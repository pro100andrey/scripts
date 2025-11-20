#!/bin/bash

# This script performs post-installation steps for the Linux setup.

# Exit on error
set -e

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root. Please run with: sudo ./arch-post-install.sh"
    exit 1
fi

# Update /etc/pacman.config to enable multilib repository
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository in /etc/pacman.conf..."
    sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    echo "Multilib repository enabled."
else

# Update package database and upgrade all packages
pacman -Syu --noconfirm

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
    hyperfine\
    ttf-jetbrains-mono-nerd \
    ttf-hack-nerd \
    noto-fonts-cjk \
    transmission-qt \
    yakuake \
    filelight \
    rssguard \
    obsidian \
    telegram-desktop\
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
fi