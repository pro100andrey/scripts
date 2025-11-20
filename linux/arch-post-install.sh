#!/bin/bash

# This script performs post-installation steps for the Linux setup.

# Exit on error, treat unset variables as error, fail on pipe errors
set -euo pipefail

# Trap errors and cleanup
trap 'echo "Error occurred at line $LINENO. Exit code: $?"; exit 1' ERR

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

# Uncomment lines in a configuration file
# Usage: uncomment_config_lines FILE PATTERN [END_PATTERN] [LOG_MESSAGE]
# Examples:
#   uncomment_config_lines /etc/file.conf "^\[section\]"
#   uncomment_config_lines /etc/file.conf "^\[section\]" "^Include" "Enabling section"
# Returns:
#   0 - success or already uncommented
#   1 - file not found
#   2 - backup failed
#   3 - sed operation failed
uncomment_config_lines() {
    local file="$1"
    local start_pattern="$2"
    local end_pattern="${3:-}"
    local log_message="${4:-Uncommenting configuration}"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Remove ^# prefix from pattern for checking if already uncommented
    local check_pattern="${start_pattern#^#}"
    
    # Check if already uncommented
    if grep -q "^${check_pattern#^}" "$file" 2>/dev/null; then
        log "Configuration already active in $file"
        return 0
    fi
    
    log "$log_message in $file..."
    
    # Create backup
    if ! cp "$file" "${file}.bak"; then
        log_error "Failed to create backup of $file"
        return 2
    fi
    
    # Uncomment lines
    if [[ -n "$end_pattern" ]]; then
        # Uncomment range from start_pattern to end_pattern
        if ! sed -i "/${start_pattern}/,/${end_pattern}/ s/^#//" "$file"; then
            log_error "Failed to uncomment lines in $file"
            return 3
        fi
    else
        # Uncomment only lines matching start_pattern
        if ! sed -i "/${start_pattern}/ s/^#//" "$file"; then
            log_error "Failed to uncomment lines in $file"
            return 3
        fi
    fi
    
    log "Configuration enabled successfully"
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
    if ! command -v sudo &> /dev/null || [[ -z "${SUDO_USER:-}" ]]; then
        log_error "Cannot run commands as non-root user: must run with sudo"
        exit 1
    fi
}

#==============================================================================
# System configuration functions
#==============================================================================

pacman_enable_multilib() {
    log "Checking multilib repository..."
    uncomment_config_lines /etc/pacman.conf \
            "^#\[multilib\]" \
            "^#Include = /etc/pacman.d/mirrorlist" \
            "Enabling multilib repository" || {
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
    
    local packages=(
        # Development tools
        clang
        cmake
        ninja
        git
        
        # Shell and utilities
        zsh
        unzip
        zip
        less
        tree
        eza
        fzf
        
        # System monitoring
        nvtop
        hyperfine
        
        # Fonts
        ttf-jetbrains-mono-nerd
        ttf-hack-nerd
        noto-fonts-cjk
        
        # Applications
        transmission-qt
        yakuake
        filelight
        rssguard
        obsidian
        telegram-desktop
        gwenview
        gimp
        inkscape
        okular
        zed
    )
    
    if ! pacman -S --noconfirm "${packages[@]}"; then
        log_error "Failed to install main packages"
        exit 1
    fi
    
    log "Main packages installed successfully"
}

pacman_cleanup_packages() {
    log "Uninstalling unnecessary packages..."

    check_sudo_user
    
    local packages=(
        # System utilities
        vim

        # Applications
        kate
    )
    
    if ! pacman -Rns --noconfirm "${packages[@]}"; then
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
    
    trap cleanup_yay_temp EXIT
    
    if ! git clone https://aur.archlinux.org/yay.git "$yay_tmp_dir"; then
        log_error "Failed to clone yay repository"
        exit 1
    fi
    
    pushd "$yay_tmp_dir" > /dev/null || exit 1
    
    log "Building yay as $SUDO_USER..."
    if ! sudo -u "$SUDO_USER" makepkg -si --noconfirm; then
        log_error "Failed to build yay"
        popd > /dev/null
        exit 1
    fi
    
    popd > /dev/null || exit 1
    trap - EXIT
    # Cleanup temporary directory
    if [[ -n "${yay_tmp_dir:-}" ]] && [[ -d "$yay_tmp_dir" ]]; then
        log "Cleaning up temporary directory..."
        rm -rf "$yay_tmp_dir"
    fi
    
    log "yay installed successfully."
}

install_aur_packages() {
    log "Installing AUR packages..."
    
    check_sudo_user
    
    local aur_packages=(
        google-chrome
        onlyoffice-bin
        android-studio
        lmstudio
        visual-studio-code-bin
    )
    
    if ! sudo -u "$SUDO_USER" yay -S --noconfirm "${aur_packages[@]}"; then
        log_error "Failed to install some AUR packages (this may be non-critical)"
        # Don't exit, some packages may be unavailable
    else
        log "AUR packages installed successfully"
    fi
}

install_ohmyzsh() {
    log "Installing Oh My Zsh..."
    check_sudo_user

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

# Main function
main() {
    log "Starting Arch Linux post-installation setup..."

    local tooktime_start=$(date +%s)
    
    check_root
    pacman_enable_multilib
    pacman_update_system
    pacman_cleanup_packages
    pacman_install_main_packages
    install_yay
    install_aur_packages
    
    log "Post-installation completed successfully!"
    local tooktime_end=$(date +%s)
    local tooktime_duration=$((tooktime_end - tooktime_start))
    log "Total time taken: ${tooktime_duration} seconds"
}

# Script entry point
main "$@"