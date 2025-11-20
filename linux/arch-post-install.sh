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


#==============================================================================
# Logging functions
#==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*${NC}"
}

log_error() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${RED}ERROR: $*${NC}" >&2
}

#==============================================================================
# Exit handler
#==============================================================================

START_TIME=$(date +%s)

on_exit() {
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo "=========================================="
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}Post-installation completed successfully!${NC}"
    else
        echo -e "${RED}Post-installation failed with exit code $exit_code.${NC}"
    fi
    echo -e "${GREEN}Took: ${duration}s${NC}"
    echo "=========================================="
}

# Trap errors and cleanup
trap 'echo "Error occurred at line $LINENO. Exit code: $?"; exit 1' ERR
trap on_exit EXIT

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

BG_WALLPAPERS=(
    abstract-flower-5120x2880-17713.png
    astronauts-7680x4320-15413.png
    colorful-fish-ripple-purple-background-girly-backgrounds-4000x3000-7591.png
    dark-abstract-3840x2160-18134.png
    dark-background-abstract-background-network-3d-background-7680x4320-8324.png
    gradient-shapes-8k-7680x4320-22806.png
    microsoft-surface-3840x2638-9238.png
    samsung-galaxy-s21-stock-amoled-particles-magenta-red-black-3200x3200-3961.png
    translucent-3840x2160-22795.png
    windows-11-abstract-3840x2160-20724.png
    windows-11-waves-3840x2400-20750.png
)

#==============================================================================
# Utility functions
#==============================================================================

# Internal function for key-value updates
_handle_kv_update() {
    local file="$1"
    local key="$2"
    local value="$3"
    local log_message="$4"
    local delimiter="${5:-=}"
    local run_cmd="${6:-}"
    local insert_after="${7:-}"

    # Check if key is already set (uncommented)
    if $run_cmd grep -q "^${key}${delimiter}" "$file"; then
        local current_value
        current_value=$($run_cmd grep "^${key}${delimiter}" "$file" | cut -d"${delimiter}" -f2-)
        
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
        
        $run_cmd sed -i "s|^${key}${delimiter}.*|${key}${delimiter}${sed_value}|" "$file"
        log "$log_message"
        
    elif $run_cmd grep -q "^#${key}${delimiter}" "$file"; then
        # Commented out - uncomment and set
        local sed_value="${value//|/\\|}"
        sed_value="${sed_value//&/\\&}"
        
        $run_cmd sed -i "s|^#${key}${delimiter}.*|${key}${delimiter}${sed_value}|" "$file"
        log "$log_message"
    else
        # Not found - append or insert
        local line="${key}${delimiter}${value}"
        if [[ -n "$insert_after" ]]; then
             # Escape insert_after for sed
             local sed_insert="${insert_after//\//\\/}"
             if $run_cmd grep -q "$insert_after" "$file"; then
                 $run_cmd sed -i "/$sed_insert/a $line" "$file"
                 log "$log_message (inserted)"
                 return 0
             fi
             # Fallback to append if pattern not found
             log "Pattern '$insert_after' not found, appending instead."
        fi

        if [[ -n "$run_cmd" ]]; then
             echo "$line" | $run_cmd tee -a "$file" > /dev/null
        else
             echo "$line" >> "$file"
        fi
        log "$log_message (appended)"
    fi
}

# Internal function for uncommenting lines
_handle_uncomment() {
    local file="$1"
    local pattern="$2"
    local end_pattern="$3"
    local log_message="$4"
    local run_cmd="${5:-}"
    local insert_after="${6:-}"

    # Remove ^# prefix from pattern for checking if already uncommented
    local check_pattern="${pattern#^#}"
    
    # Check if already uncommented
    if $run_cmd grep -q "^${check_pattern#^}" "$file" 2>/dev/null; then
        log "Configuration already active in $file"
        return 0
    fi
    
    # Escape slashes in patterns to prevent sed syntax errors
    local sed_pattern="${pattern//\//\\/}"
    local sed_end_pattern="${end_pattern//\//\\/}"
    
    # Check if commented out (simple check)
    # If pattern is "Option", we look for "#Option" or "# Option"
    # If pattern is "^#Option", we look for "^#Option"
    local is_commented=false
    if [[ "$pattern" == ^#* ]]; then
         if $run_cmd grep -q "$pattern" "$file"; then is_commented=true; fi
    else
         if $run_cmd grep -q "#[[:space:]]*$pattern" "$file"; then is_commented=true; fi
    fi

    if [[ "$is_commented" == "true" ]]; then
        log "$log_message in $file..."
        # Uncomment lines
        if [[ -n "$end_pattern" ]]; then
            # Uncomment range
            if ! $run_cmd sed -i "/${sed_pattern}/,/${sed_end_pattern}/ s/^#[[:space:]]*//" "$file"; then
                log_error "Failed to uncomment lines in $file"
                return 3
            fi
        else
            # Uncomment single line
            if ! $run_cmd sed -i "/${sed_pattern}/ s/^#[[:space:]]*//" "$file"; then
                log_error "Failed to uncomment lines in $file"
                return 3
            fi
        fi
        log "Configuration enabled successfully"
        return 0
    fi

    # Not found - insert if requested
    if [[ -n "$insert_after" ]]; then
        log "$log_message (inserting)..."
        local sed_insert="${insert_after//\//\\/}"
        if $run_cmd grep -q "$insert_after" "$file"; then
            $run_cmd sed -i "/$sed_insert/a $check_pattern" "$file"
            log "Configuration inserted successfully"
            return 0
        else
            log_error "Insert pattern '$insert_after' not found in $file"
            return 1
        fi
    fi
    
    # Not found and no insert instruction
    log "Configuration '$pattern' not found in $file (and no insert location provided)"
    return 1
}

# Update or uncomment configuration in a file
# Usage: update_config FILE PATTERN [OPTIONS]
# Options:
#   -v, --value VALUE       Set specific value (key=value format)
#   -e, --end PATTERN       End pattern for range uncommenting
#   -m, --msg MESSAGE       Log message
#   -d, --delimiter DELIM   Delimiter between key and value (default: =)
#   -a, --after PATTERN     Insert after this pattern if not found
#   --user                  Run as SUDO_USER
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
    local delimiter="="
    local run_as_user=false
    local run_cmd=""
    local insert_after=""

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
            -d|--delimiter)
                delimiter="$2"
                shift 2
                ;;
            -a|--after)
                insert_after="$2"
                shift 2
                ;;
            --user)
                run_as_user=true
                shift 1
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    if [[ "$run_as_user" == "true" ]]; then
        run_cmd="sudo -u $SUDO_USER"
    fi
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    if [[ "$set_value" == "true" ]]; then
        _handle_kv_update "$file" "$pattern" "$value" "$log_message" "$delimiter" "$run_cmd" "$insert_after"
    else
        _handle_uncomment "$file" "$pattern" "$end_pattern" "$log_message" "$run_cmd" "$insert_after"
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
    
    # Ensure reflector is installed
    if ! command -v reflector &> /dev/null; then
        log "Reflector not found. Installing..."
        pacman -Sy --noconfirm reflector
    fi

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

    # Set to 15 parallel downloads
    update_config /etc/pacman.conf \
            "^ParallelDownloads" \
            --value "15" \
            --msg "Set parallel downloads to 15"
            
    # Color output
    update_config /etc/pacman.conf \
            "^#Color" \
            --msg "Enabling Color"
            
    # Verbose package lists
    update_config /etc/pacman.conf \
            "^#VerbosePkgLists" \
            --msg "Enabling VerbosePkgLists"
            
    # Easter egg: ILoveCandy (Pac-Man eating dots)
    update_config /etc/pacman.conf "ILoveCandy" \
        --after "^Color" \
        --msg "Enabled ILoveCandy"
}

configure_makepkg() {
    log "Optimizing makepkg build flags..."
    local makepkg_conf="/etc/makepkg.conf"
    local cores=$(nproc)
    
    # Set MAKEFLAGS to use all cores
    update_config \
        "$makepkg_conf" \
        "MAKEFLAGS" --value "\"-j$cores\""\
        --msg "MAKEFLAGS set to -j$cores"

    # Enable multi-threaded compression
    update_config "$makepkg_conf" \
        "COMPRESSXZ" --value "(xz -c -z - --threads=0)" \
        --msg "Enabled multi-threaded compression for packages"
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
    # Fix permissions so SUDO_USER can access and write to it
    chown "$SUDO_USER" "$yay_tmp_dir"
    
    # Setup cleanup trap
    cleanup_yay() {
        [[ -d "${yay_tmp_dir:-}" ]] && rm -rf "${yay_tmp_dir:-}"
    }
    trap cleanup_yay RETURN
    
    run_as_user git clone https://aur.archlinux.org/yay.git "$yay_tmp_dir" || {
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
    
    if ! sudo -u "$SUDO_USER" yay --sudoloop -S --needed --noconfirm "${AUR_PACKAGES[@]}"; then
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

    # SSH Key generation
    local user_home
    user_home=$(eval echo "~$SUDO_USER")
    local ssh_key="$user_home/.ssh/id_ed25519"

    if [[ ! -f "$ssh_key" ]]; then
        log "Generating SSH key (ed25519)..."
        # Ensure .ssh directory exists with correct permissions
        run_as_user mkdir -p "$user_home/.ssh"
        run_as_user chmod 700 "$user_home/.ssh"
        
        run_as_user ssh-keygen -t ed25519 -C "this.andrey@gmail.com" -f "$ssh_key" -N ""
        log "SSH key generated."
    else
        log "SSH key already exists at $ssh_key"
    fi

    log "Git configured"
}

configure_bootloader() {
    log "Configuring bootloader..."
    local loader_conf="/boot/loader/loader.conf"
    
    if [[ -f "$loader_conf" ]]; then
        update_config "$loader_conf" "console-mode" \
            --value "max" \
            --delimiter " " \
            --msg "Bootloader console-mode set to max"
    else
        log "Bootloader config not found at $loader_conf, skipping"
    fi
}

configure_wireless() {
    log "Configuring wireless regulatory domain..."
    update_config "/etc/conf.d/wireless-regdom" \
        '^#WIRELESS_REGDOM="UA"' \
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

apply_theme() {
    download_bg() {
    local url="$1"
    local dest="$2"
    local max_attempts=5
    local attempt=1
    local exit_code=0
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt of $max_attempts to download $url"
        local http_code=$(curl -fsSL -w "%{http_code}" "$url" -o "$dest")
        exit_code=$?
        
        if [ $exit_code -eq 0 ] && [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            return 0
        fi
        if [ "$http_code" == "429" ] || [ $exit_code -ne 0 ]; then
            log_error "Download failed (HTTP $http_code, curl exit $exit_code). Retrying in $attempt seconds..."
            if [ $attempt -eq $max_attempts ]; then
                break
            fi
            sleep $attempt 
            attempt=$((attempt + 1))
        else
            log_error "Fatal download error (HTTP $http_code). Aborting retries for this file."
            return 1
        fi
    done

    log_error "Failed to download wallpaper from $url after $max_attempts attempts."
    return 1
}

    log "Downloading and applying wallpapers..."   
    local user_home=$(eval echo "~$SUDO_USER")
    local wallpapers_dir="$user_home/Pictures/Wallpapers"
    # run_as_user mkdir -p "$wallpapers_dir"

    local base_url="https://4kwallpapers.com/images/wallpapers/"
    for wallpaper in "${BG_WALLPAPERS[@]}"; do
        local url="${base_url}${wallpaper}"
        local dest="${wallpapers_dir}/${wallpaper}"
        if download_bg "$url" "$dest"; then
            log "Downloaded wallpaper: $wallpaper"
        else
            log_error "Failed to download wallpaper: $wallpaper"
        fi
    done

    log "Applying system theme..."
    
    # Get user's display and Wayland/X11 session info
    local user_id=$(id -u "$SUDO_USER")
    local display=$(who | grep "$SUDO_USER" | grep -oP ':\d+' | head -1)
    local wayland_display=$(ls -1 /run/user/$user_id/ 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
    
    # Build environment variables for the command
    local env_vars="XDG_RUNTIME_DIR=/run/user/$user_id DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus"
    
    if [[ -n "$wayland_display" ]]; then
        env_vars="$env_vars WAYLAND_DISPLAY=$wayland_display"
    elif [[ -n "$display" ]]; then
        env_vars="$env_vars DISPLAY=$display"
    fi
    
    # Apply theme as user with proper environment
    sudo -u "$SUDO_USER" env $env_vars \
        plasma-apply-desktoptheme breeze-dark || {
        log_error "Failed to apply desktop theme. You may need to run this manually after login:"
        log_error "  plasma-apply-desktoptheme breeze-dark"
    }
    
    sudo -u "$SUDO_USER" env $env_vars \
        plasma-apply-colorscheme BreezeDark || {
        log_error "Failed to apply color scheme"
    }
    
    sudo -u "$SUDO_USER" env $env_vars \
        plasma-apply-wallpaperimage "$wallpapers_dir/dark-background-abstract-background-network-3d-background-7680x4320-8324.png" || {
        log_error "Failed to apply wallpaper"
    }

    log "System theme applied"
}

#==============================================================================
# Main function
#==============================================================================

main() {
    log "Starting Arch Linux post-installation setup..."
    
    # Validation
    check_root
    check_sudo_user
    check_os
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
    
    # Common tools configuration
    configure_docker
    configure_git
    configure_bootloader
    configure_system_services
    configure_wireless
    
    # Development tools
    install_flutter
    
    # Cleanup
    cleanup_cache

    # Apply theme
    apply_theme
}

# Script entry point
main "$@"