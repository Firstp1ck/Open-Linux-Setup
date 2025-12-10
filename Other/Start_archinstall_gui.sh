#!/usr/bin/env bash

set -euo pipefail

# Script: Start_archinstall_gui.sh
# Description: Prepare Arch Linux installation environment with GUI components

# Gum detection
HAS_GUM=false
if command -v gum >/dev/null 2>&1; then
    HAS_GUM=true
fi

# Standard message functions
msg_info() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 63 "[INFO] $1"
    else
        echo "[INFO] $1"
    fi
}

msg_success() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 42 "[SUCCESS] $1"
    else
        echo "[SUCCESS] $1"
    fi
}

msg_error() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 196 "[ERROR] $1" >&2
    else
        echo "[ERROR] $1" >&2
    fi
}

msg_warning() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 214 "[WARNING] $1"
    else
        echo "[WARNING] $1"
    fi
}

# Dependency checking
require_command() {
    local cmd="$1"
    local install_hint="${2:-Install it via your package manager}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        msg_error "'$cmd' is required but not installed."
        echo "Hint: $install_hint" >&2
        exit 1
    fi
}

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Prepare Arch Linux installation environment with GUI components (Xorg, XFCE,
    Ly display manager, and Calamares installer). Checks disk space and installs
    necessary packages.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

Note: This script must be run as root during Arch Linux installation.

EOF
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    # shellcheck disable=SC2317
    shift
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    msg_error "This script must be run as root."
    exit 1
fi

# Check dependencies
require_command "pacman" "This script requires Arch Linux with pacman"
require_command "df" "This script requires coreutils"
require_command "systemctl" "This script requires systemd"

# Minimum required free space in KiB (500 MiB = 512000 KiB)
MINSPACE=512000

FREESPACE=$(df --output=avail / | tail -1)

if [ "$FREESPACE" -lt "$MINSPACE" ]; then
    msg_warning "Not enough free space on /. Attempting to remount /run/archiso/cowspace to 1 GiB..."
    if mount -o remount,size=1G /run/archiso/cowspace; then
        FREESPACE=$(df --output=avail / | tail -1)
        if [ "$FREESPACE" -lt "$MINSPACE" ]; then
            msg_error "Still less than 500 MiB available after remount. Only $((FREESPACE / 1024)) MiB free. Aborting."
            exit 1
        else
            msg_success "Remount successful. $((FREESPACE / 1024)) MiB available."
        fi
    else
        msg_error "Failed to remount /run/archiso/cowspace"
        exit 1
    fi
fi

# Refresh package database
msg_info "Refreshing package database..."
pacman -Syy --noconfirm

# Install essential Xorg components, XFCE, Ly, Calamares
msg_info "Installing GUI components (Xorg, XFCE, Ly, Calamares)..."
pacman -S --noconfirm xorg-server xorg-xinit xf86-input-libinput mesa xf86-video-intel xfce4 ly calamares

# Prompt for new user name
msg_info "Creating new user..."
if [ "$HAS_GUM" = true ]; then
    NEWUSER=$(gum input --prompt "Enter the name for the new user: " || true)
else
    read -rp "Enter the name for the new user: " NEWUSER
fi

if [ -z "$NEWUSER" ]; then
    msg_error "Username cannot be empty"
    exit 1
fi

if id "$NEWUSER" &>/dev/null; then
    msg_warning "User '$NEWUSER' already exists. Skipping user creation."
else
    useradd -m -G wheel "$NEWUSER"
    msg_info "Set password for $NEWUSER:"
    passwd "$NEWUSER"
fi

# Prompt for root password
msg_info "Set password for root:"
passwd root

# Grant wheel group sudo access by updating /etc/sudoers
msg_info "Configuring sudo access for wheel group..."
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers
    msg_success "Enabled sudo access for wheel group."
else
    msg_info "Sudo access for wheel group already configured."
fi

# Make XFCE default session for the user
msg_info "Configuring XFCE as default session..."
if [ -d "/home/$NEWUSER" ]; then
    echo "exec startxfce4" > "/home/$NEWUSER/.xinitrc"
    chown "$NEWUSER:$NEWUSER" "/home/$NEWUSER/.xinitrc"
    msg_success "XFCE configured as default session for $NEWUSER."
else
    msg_warning "Home directory for $NEWUSER not found. Skipping .xinitrc configuration."
fi

# Enable and start Ly immediately
msg_info "Enabling and starting Ly display manager..."
if systemctl enable --now ly.service; then
    msg_success "Ly display manager started."
    msg_info "Log in as $NEWUSER, then launch 'calamares' in XFCE to begin installation."
else
    msg_error "Failed to start Ly display manager."
    exit 1
fi

exit 0
