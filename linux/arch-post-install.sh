#!/bin/bash

# This script performs post-installation steps for the Linux setup.

# Exit on error
set -e

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root. Please run with: sudo ./arch-post-install.sh"
    exit 1
fi

# Update /etc/pacman.conf to enable multilib repository
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository in /etc/pacman.conf..."
    sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    echo "Multilib repository enabled."
else
    echo "Multilib repository is already enabled."
fi

# Update package database and upgrade all packages
echo "Updating system..."
pacman -Syu --noconfirm

# Install main packages
echo "Installing main packages..."
pacman -S --noconfirm \
    clang \
    cmake \
    ninja \
    git \
    zsh \
    unzip \
    zip \
    less \
    tree \
    eza \
    fzf \
    nvtop \
    hyperfine \
    ttf-jetbrains-mono-nerd \
    ttf-hack-nerd \
    noto-fonts-cjk \
    transmission-qt \
    yakuake \
    filelight \
    rssguard \
    obsidian \
    telegram-desktop \
    gwenview \
    gimp \
    inkscape \
    okular \
    zed

# Install yay AUR helper
if ! command -v yay &> /dev/null; then
    echo "Installing yay AUR helper..."
    temp_dir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$temp_dir"
    pushd "$temp_dir" || exit
    makepkg -si --noconfirm
    popd || exit
    rm -rf "$temp_dir"
    echo "yay installed successfully."
else
    echo "yay is already installed."
fi

# Install AUR packages
echo "Installing AUR packages..."
yay -S --noconfirm \
    google-chrome \
    onlyoffice-bin \
    android-studio \
    lmstudio \
    visual-studio-code-bin

echo ""
echo "=========================================="
echo "Post-installation completed successfully!"
echo "=========================================="
echo ""