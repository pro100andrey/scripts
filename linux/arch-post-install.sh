#!/bin/bash

# Arch Linux Post-Installation Script
#
# This script automates the post-installation setup of an Arch Linux system.
# It performs the following tasks:
# - System Configuration:
#   - Updates mirrorlist using reflector
#   - Configures Pacman (parallel downloads, color, multilib)
#   - Optimizes Makepkg (parallel compilation)
#   - Updates system packages
# - Package Management:
#   - Installs essential packages (development, utilities, fonts, applications)
#   - Installs and configures 'yay' AUR helper
#   - Installs AUR packages
#   - Removes unnecessary packages
# - Shell & Environment:
#   - Installs and configures Zsh with Oh My Zsh
#   - Installs Zsh plugins (autosuggestions, syntax-highlighting)
#   - Configures aliases and environment variables (eza, fzf)
# - Development Setup:
#   - Installs Flutter SDK
#   - Configures Docker
#   - Configures Git
# - System Services & Hardware:
#   - Enables essential services (fstrim, network, time, bluetooth, firewall)
#   - Configures wireless regulatory domain
#   - Configures bootloader (systemd-boot)
#
# Usage:
#   Run as root (sudo):
#   sudo ./arch-post-install.sh
#
#   One-liner:
#   curl -fsSL https://raw.githubusercontent.com/pro100andrey/scripts/main/linux/arch-post-install.sh | sudo bash

# Exit on error, treat unset variables as error, fail on pipe errors
set -euo pipefail

# Trap errors and cleanup
trap 'echo "Error occurred at line $LINENO. Exit code: $?"; exit 1' ERR

#==============================================================================
# Configuration
#==============================================================================

MAIN_PACKAGES=(
    # Development tools
    clang
    cmake
    ninja
    git
    docker
    docker-compose
    
    # Shell and utilities
    stress-ng
    zsh
    unzip
    zip
    less
    tree
    eza
    fzf
    bat
    fd
    ripgrep
    reflector
    btop
    fastfetch
    pacman-contrib
    
    # System
    ufw
    bluez
    bluez-utils
    wireless-regdb
    
    # System monitoring
    nvtop
    hyperfine
    
    # Fonts
    ttf-jetbrains-mono-nerd
    ttf-hack-nerd
    noto-fonts-cjk
    
    # Applications
    audacity
    vlc
    transmission-qt
    yakuake
    filelight
    obsidian
    telegram-desktop
    gwenview
    gimp
    inkscape
    okular
    zed

    # Games
    lutris
    lib32-vulkan-utility-libraries
)

CLEANUP_PACKAGES=(
    # System utilities
    vim
    # Applications
    kate
)

AUR_PACKAGES=(
    #Utils
    wrk
    #Applications
    google-chrome
    onlyoffice-bin
    android-studio
    lmstudio
    visual-studio-code-bin
)

#==============================================================================
# Logging functions
#==============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

#==============================================================================
# Utility functions
#==============================================================================

# Internal function for key-value updates
_handle_kv_update() {
    local file="$1"
    local key="$2"
    local value="$3"
    local log_message="$4"

    # Check if key is already set (uncommented)
    if grep -q "^${key}=" "$file"; then
        local current_value
        current_value=$(grep "^${key}=" "$file" | cut -d= -f2-)
        
        if [[ "$current_value" == "$value" ]]; then
            log "$key is already set to correct value"
            return 0
        fi
        
        echo "Configuration mismatch for $key in $file"
        echo "  Current: $current_value"
        echo "  New:     $value"
        
        # Ask user for confirmation
        read -p "Do you want to replace the current value? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping update for $key"
            return 0
        fi
        
        # Escape special chars for sed
        local sed_value="${value//|/\\|}"
        sed_value="${sed_value//&/\\&}"
        
        sed -i "s|^${key}=.*|${key}=${sed_value}|" "$file"
        log "$log_message"
        
    elif grep -q "^#${key}=" "$file"; then
        # Commented out - uncomment and set
        local sed_value="${value//|/\\|}"
        sed_value="${sed_value//&/\\&}"
        
        sed -i "s|^#${key}=.*|${key}=${sed_value}|" "$file"
        log "$log_message"
    else
        # Not found - append
        echo "${key}=${value}" >> "$file"
        log "$log_message (appended)"
    fi
}

# Internal function for uncommenting lines
_handle_uncomment() {
    local file="$1"
    local pattern="$2"
    local end_pattern="$3"
    local log_message="$4"

    # Remove ^# prefix from pattern for checking if already uncommented
    local check_pattern="${pattern#^#}"
    
    # Check if already uncommented
    if grep -q "^${check_pattern#^}" "$file" 2>/dev/null; then
        log "Configuration already active in $file"
        return 0
    fi
    
    log "$log_message in $file..."
    
    # Escape slashes in patterns to prevent sed syntax errors
    local sed_pattern="${pattern//\//\\/}"
    local sed_end_pattern="${end_pattern//\//\\/}"
    
    # Uncomment lines
    if [[ -n "$end_pattern" ]]; then
        # Uncomment range
        if ! sed -i "/${sed_pattern}/,/${sed_end_pattern}/ s/^#[[:space:]]*//" "$file"; then
            log_error "Failed to uncomment lines in $file"
            return 3
        fi
    else
        # Uncomment single line
        if ! sed -i "/${sed_pattern}/ s/^#[[:space:]]*//" "$file"; then
            log_error "Failed to uncomment lines in $file"
            return 3
        fi
    fi
    
    log "Configuration enabled successfully"
}

# Update or uncomment configuration in a file
# Usage: update_config FILE PATTERN [OPTIONS]
# Options:
#   -v, --value VALUE       Set specific value (key=value format)
#   -e, --end PATTERN       End pattern for range uncommenting
#   -m, --msg MESSAGE       Log message
# Examples:
#   update_config /etc/file.conf "^#Option" --msg "Enabling Option"
#   update_config /etc/file.conf "KEY" --value "new_value" --msg "Updating KEY"
update_config() {
    local file="$1"
    local pattern="$2"
    shift 2

    local value=""
    local end_pattern=""
    local log_message="Updating configuration"
    local set_value=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--value)
                value="$2"
                set_value=true
                shift 2
                ;;
            -e|--end)
                end_pattern="$2"
                shift 2
                ;;
            -m|--msg|--message)
                log_message="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    if [[ "$set_value" == "true" ]]; then
        _handle_kv_update "$file" "$pattern" "$value" "$log_message"
    else
        _handle_uncomment "$file" "$pattern" "$end_pattern" "$log_message"
    fi
    
    return 0
}

#==============================================================================
# Validation functions
#==============================================================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root. Please run with: sudo ./arch-post-install.sh"
        exit 1
    fi
}

check_sudo_user() {
    if [[ -z "${SUDO_USER:-}" ]]; then
        log_error "Cannot run commands as non-root user: must run with sudo"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/arch-release ]]; then
        log_error "This script is designed for Arch Linux only"
        exit 1
    fi
}

check_internet() {
    log "Checking internet connection..."
    if ! ping -c 1 archlinux.org &> /dev/null; then
        log_error "No internet connection. Please connect to the internet and try again."
        exit 1
    fi
}

# Helper function to run commands as SUDO_USER
run_as_user() {
    sudo -u "$SUDO_USER" "$@"
}

#==============================================================================
# System configuration functions
#==============================================================================

update_mirrors() {
    log "Updating mirrorlist with reflector..."
    # Save current mirrorlist
    if [[ ! -f /etc/pacman.d/mirrorlist.bak ]]; then
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    fi
    
    # Get 20 latest mirrors, sort by rate, and keep top 10
    if ! reflector --latest 20 --number 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
        log_error "Failed to update mirrorlist"
        # Restore backup if failed
        cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
        return 1
    fi
    log "Mirrorlist updated successfully"
}

pacman_configure() {
    log "Configuring Pacman..."
    
    # Parallel downloads
    update_config /etc/pacman.conf \
            "^#ParallelDownloads" \
            --msg "Enabling parallel downloads"
            
    # Color output
    update_config /etc/pacman.conf \
            "^#Color" \
            --msg "Enabling Color"
            
    # Verbose package lists
    update_config /etc/pacman.conf \
            "^#VerbosePkgLists" \
            --msg "Enabling VerbosePkgLists"
            
    # Easter egg: ILoveCandy (Pac-Man eating dots)
    if ! grep -q "ILoveCandy" /etc/pacman.conf; then
        sed -i "/^Color/a ILoveCandy" /etc/pacman.conf
        log "Enabled ILoveCandy"
    fi
}

configure_makepkg() {
    log "Optimizing makepkg build flags..."
    local makepkg_conf="/etc/makepkg.conf"
    local cores=$(nproc)
    
    # Set MAKEFLAGS to use all cores
    update_config "$makepkg_conf" "MAKEFLAGS" --value "\"-j$cores\"" --msg "MAKEFLAGS set to -j$cores"

    # Enable multi-threaded compression
    update_config "$makepkg_conf" "COMPRESSXZ" --value "(xz -c -z - --threads=0)" --msg "Enabled multi-threaded compression for packages"
}

pacman_enable_multilib() {
    log "Checking multilib repository..."
    update_config /etc/pacman.conf \
            "^#\[multilib\]" \
            --end "^#Include = /etc/pacman.d/mirrorlist" \
            --msg "Enabling multilib repository" || {
        log_error "Failed to enable multilib repository"
        exit 1
    }
}

pacman_update_system() {
    log "Updating system..."
    if ! pacman -Syu --noconfirm; then
        log_error "System update failed"
        exit 1
    fi
    log "System updated successfully"
}

#==============================================================================
# Package installation functions
#==============================================================================

pacman_install_main_packages() {
    log "Installing main packages..."
    
    if ! pacman -S --needed --noconfirm "${MAIN_PACKAGES[@]}"; then
        log_error "Failed to install main packages"
        exit 1
    fi
    
    log "Main packages installed successfully"
}

pacman_cleanup_packages() {
    log "Uninstalling unnecessary packages..."
    
    if ! pacman -Rns --noconfirm "${CLEANUP_PACKAGES[@]}"; then
        log_error "Failed to uninstall some packages (this may be non-critical)"
        # Don't exit, some packages may be already removed
    else
        log "Unnecessary packages uninstalled successfully"
    fi
}


install_yay() {
    log "Checking for yay AUR helper..."
    
    if command -v yay &> /dev/null; then
        log "yay is already installed."
        return 0
    fi
    
    check_sudo_user
    
    log "Installing yay AUR helper..."
    local yay_tmp_dir=$(mktemp -d)
    
    # Setup cleanup trap
    cleanup_yay() {
        [[ -d "$yay_tmp_dir" ]] && rm -rf "$yay_tmp_dir"
    }
    trap cleanup_yay RETURN
    
    git clone https://aur.archlinux.org/yay.git "$yay_tmp_dir" || {
        log_error "Failed to clone yay repository"
        return 1
    }
    
    (cd "$yay_tmp_dir" && run_as_user makepkg -si --noconfirm) || {
        log_error "Failed to build yay"
        return 1
    }
    
    log "yay installed successfully."
}

install_aur_packages() {
    log "Installing AUR packages..."
    
    check_sudo_user
    
    if ! sudo -u "$SUDO_USER" yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"; then
        log_error "Failed to install some AUR packages (this may be non-critical)"
        # Don't exit, some packages may be unavailable
    else
        log "AUR packages installed successfully"
    fi
}

configure_git() {
    log "Configuring Git..."
    run_as_user git config --global init.defaultBranch main
    run_as_user git config --global user.name "Andrii Ivanov"
    run_as_user git config --global user.email "this.andrey@gmail.com"
    run_as_user git config --global core.editor "code"
    log "Git configured"
}

configure_bootloader() {
    log "Configuring bootloader..."
    local loader_conf="/boot/loader/loader.conf"
    
    if [[ -f "$loader_conf" ]]; then
        if grep -q "^console-mode" "$loader_conf"; then
            sed -i 's/^console-mode.*/console-mode max/' "$loader_conf"
        else
            echo "console-mode max" >> "$loader_conf"
        fi
        log "Bootloader console-mode set to max"
    else
        log "Bootloader config not found at $loader_conf, skipping"
    fi
}

configure_wireless() {
    log "Configuring wireless regulatory domain..."
    update_config "/etc/conf.d/wireless-regdom" \
        "^#WIRELESS_REGDOM=\\\"UA\\\"" \
        --msg "Setting wireless regulatory domain to UA"
}

configure_system_services() {
    log "Enabling system services..."
    # Enable fstrim for SSD longevity
    systemctl enable --now fstrim.timer
    
    # Network optimization
    log "Configuring systemd-resolved..."
    systemctl enable --now systemd-resolved.service
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    
    log "Masking NetworkManager-wait-online..."
    systemctl mask NetworkManager-wait-online.service
    
    # Time synchronization
    log "Configuring time synchronization..."
    systemctl enable --now systemd-timesyncd.service
    
    # Automatic mirror updates
    log "Enabling automatic mirror updates..."
    systemctl enable --now reflector.timer

    # Bluetooth
    log "Configuring Bluetooth..."
    systemctl enable --now bluetooth.service
    
    # Firewall
    log "Configuring Firewall (UFW)..."
    systemctl enable --now ufw.service
    ufw default deny incoming
    ufw default allow outgoing
    # Allow SSH if needed, otherwise comment out
    # ufw allow ssh
    ufw --force enable
    
    log "System services enabled"
}

configure_docker() {
    log "Configuring Docker..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    log "Enabling and starting Docker service..."
    systemctl enable --now docker.service
    
    log "Adding user $SUDO_USER to docker group..."
    if ! usermod -aG docker "$SUDO_USER"; then
        log_error "Failed to add user to docker group"
        return 1
    fi
    
    log "Docker configured successfully"
}

install_ohmyzsh() {
    log "Installing Oh My Zsh..."
    check_sudo_user

    # Get user's home directory
    local user_home
    user_home=$(eval echo "~$SUDO_USER")
    
    if [[ -d "$user_home/.oh-my-zsh" ]]; then
        log "Oh My Zsh is already installed."
    else
        log "Installing Oh My Zsh for $SUDO_USER..."
        sudo -u "$SUDO_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log "Oh My Zsh installed successfully."
    fi
    
    # Install Oh My Zsh plugins
    log "Installing Oh My Zsh plugins..."
    
    local zsh_custom="$user_home/.oh-my-zsh/custom"
    local -A plugins=(
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions.git"
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    )
    
    for plugin in "${!plugins[@]}"; do
        if [[ ! -d "$zsh_custom/plugins/$plugin" ]]; then
            log "Installing $plugin..."
            run_as_user git clone "${plugins[$plugin]}" "$zsh_custom/plugins/$plugin"
            log "$plugin installed."
        else
            log "$plugin already installed."
        fi
    done
    
    # Configure plugins in .zshrc
    log "Configuring Oh My Zsh plugins in .zshrc..."
    local zshrc="$user_home/.zshrc"
    
    if [[ ! -f "$zshrc" ]]; then
        log_error ".zshrc not found at $zshrc"
        return 1
    fi
    
    if grep -q "^plugins=(" "$zshrc"; then
        run_as_user sed -i 's/^plugins=(.*/plugins=(z fzf git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc"
        log "Plugins configured in .zshrc"
    else
        log_error "Could not find plugins line in .zshrc"
    fi
    
    log "Oh My Zsh plugins installed successfully."

    # Set Zsh as default shell
    if [[ "$(getent passwd "$SUDO_USER" | cut -d: -f7)" != "/usr/bin/zsh" ]]; then
        log "Setting Zsh as default shell for $SUDO_USER..."
        chsh -s /usr/bin/zsh "$SUDO_USER"
        log "Default shell changed to Zsh."
    else
        log "Zsh is already the default shell."
    fi
}

install_flutter() {
    log "Installing Flutter SDK..."
    check_sudo_user
    
    local user_home
    user_home=$(eval echo "~$SUDO_USER")
    local flutter_dir="$user_home/Projects/dart/flutter"
    
    if [[ -d "$flutter_dir" ]]; then
        log "Flutter already installed at $flutter_dir"
        return 0
    fi
    
    log "Creating Flutter directory structure..."
    run_as_user mkdir -p "$user_home/Projects/dart"
    
    log "Cloning Flutter SDK..."
    run_as_user git clone https://github.com/flutter/flutter.git -b stable "$flutter_dir" || {
        log_error "Failed to clone Flutter repository"
        return 1
    }
    
    log "Running Flutter initial setup..."
    run_as_user "$flutter_dir/bin/flutter" --version || {
        log_error "Failed to initialize Flutter"
        return 1
    }
    
    log "Flutter SDK installed successfully at $flutter_dir"
}

configure_zshrc() {
    log "Configuring .zshrc with eza and fzf settings..."
    check_sudo_user
    
    local user_home
    user_home=$(eval echo "~$SUDO_USER")
    local zshrc="$user_home/.zshrc"
    local custom_config="$user_home/.zsh_custom_config"
    
    if [[ ! -f "$zshrc" ]]; then
        log_error ".zshrc not found at $zshrc"
        return 1
    fi

    # Create custom config file
    log "Creating custom zsh config at $custom_config..."
    run_as_user tee "$custom_config" > /dev/null << 'EOF'
# eza alias
alias ls='eza --icons=always'
alias l='eza -1 --icons=always'
alias ll='eza -l --icons=always'
alias la='eza -la --icons=always'
alias lt='eza --tree --icons=always'
alias llt='eza -l --tree --level=2 --icons=always'
alias lh='eza -lh --header --icons=always'
alias lg='eza -la --git --icons=always'
alias lS='eza -1 --icons=always --sort=size'
alias lM='eza -1 --icons=always --sort=modified'
alias tre='eza --tree --icons=always --level=3 --git-ignore'

# fzf configuration
export FZF_DEFAULT_OPTS=" \
  --layout=reverse \
  --info=inline \
  --height=40% \
  --border \
  --preview-window=right:60% \
"

export FZF_CTRL_R_OPTS=" \
  --preview 'echo {}' \
  --preview-window=down:3:wrap \
  --sort \
"

if command -v fd &> /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
else
  export FZF_DEFAULT_COMMAND='find . -prune -o -type f -print -o -type l -print 2> /dev/null | sed '\''s/^\.\///'\'''
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='find . -prune -o -type d -print 2> /dev/null | sed '\''s/^\.\///'\'''
fi

export FZF_CTRL_T_OPTS=" \
  --preview 'bat --color=always --style=numbers --line-range :500 {}' \
  --bind '?:toggle-preview' \
"

export FZF_ALT_C_OPTS=" \
  --preview 'tree -C {} | head -200' \
  --bind '?:toggle-preview' \
"

# Environment variables
export PATH=$HOME/Projects/dart/flutter/bin:$PATH
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
export PATH="$PATH":"$HOME/.pub-cache/bin"
export GOPATH=$HOME/.go
EOF

    # Source the custom config in .zshrc if not already there
    if ! grep -q "source $custom_config" "$zshrc"; then
        log "Adding source command to .zshrc..."
        run_as_user tee -a "$zshrc" > /dev/null << EOF

# Custom configuration
if [[ -f "$custom_config" ]]; then
    source "$custom_config"
fi
EOF
    else
        log "Custom config already sourced in .zshrc"
    fi
    
    log ".zshrc configured successfully"
}

cleanup_cache() {
    log "Cleaning up package cache..."
    
    # Clean pacman cache
    if pacman -Scc --noconfirm; then
        log "Pacman cache cleaned"
    else
        log_error "Failed to clean pacman cache"
    fi
    
    # Clean yay cache if installed
    if command -v yay &> /dev/null; then
        check_sudo_user
        if sudo -u "$SUDO_USER" yay -Scc --noconfirm; then
            log "Yay cache cleaned"
        else
            log_error "Failed to clean yay cache"
        fi
    fi
    
    # Remove unused packages (orphans)
    if pacman -Qtdq &> /dev/null; then
        log "Removing orphaned packages..."
        pacman -Rns --noconfirm $(pacman -Qtdq)
        log "Orphaned packages removed"
    else
        log "No orphaned packages found"
    fi

    # Clean system journals
    log "Cleaning system journals..."
    journalctl --rotate
    if journalctl --vacuum-time=1s; then
        log "System journals cleaned"
    else
        log_error "Failed to clean system journals"
    fi
}

#==============================================================================
# Main function
#==============================================================================

main() {
    local start_time=$(date +%s)
    
    log "Starting Arch Linux post-installation setup..."
    
    # Validation
    check_root
    check_sudo_user
    # check_os
    check_internet
    
    # System configuration
    pacman_configure
    configure_makepkg
    pacman_enable_multilib
    update_mirrors
    pacman_update_system
    
    # Package management
    pacman_cleanup_packages
    pacman_install_main_packages
    
    # AUR setup
    install_yay
    install_aur_packages
    
    # Shell configuration (after git and zsh are installed)
    install_ohmyzsh
    configure_zshrc
    
    # Development tools
    install_flutter
    configure_docker
    configure_git
    configure_bootloader
    configure_system_services
    configure_wireless
    
    # Cleanup
    cleanup_cache
    
    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log ""
    log "=========================================="
    log "Post-installation completed successfully!"
    log "Total time: ${duration}s"
    log "=========================================="
    log ""
}

# Script entry point
main "$@"