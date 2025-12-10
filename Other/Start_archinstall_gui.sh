#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_archinstall_gui.sh
# ============================================================================
# Description:
#   Prepares an Arch Linux installation environment with GUI components.
#   Installs Xorg, XFCE desktop environment, Ly display manager, and Calamares
#   installer. Configures user accounts, sudo access, and sets up the system
#   for graphical installation.
#
# What it does:
#   - Checks disk space and remounts cowspace if needed (for live ISO)
#   - Detects and installs appropriate video drivers (Intel/NVIDIA/AMD)
#   - Installs Xorg server, XFCE desktop, Ly display manager, and Calamares
#   - Creates a new user with wheel group membership
#   - Configures sudo access for the wheel group
#   - Sets up XFCE as the default session
#   - Enables and starts the Ly display manager
#
# How to use:
#   Run as root during Arch Linux installation (from live ISO):
#     sudo ./Start_archinstall_gui.sh
#   
#   Options:
#     --help, -h      Show help message
#     --dry-run       Preview actions without making changes
#
# Target:
#   - Arch Linux installation media (live ISO)
#   - Users setting up a graphical installation environment
#   - System administrators preparing Arch Linux with GUI installer
# ============================================================================

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

# Username validation
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        msg_error "Invalid username format. Use lowercase letters, digits, '_' or '-'."
        return 1
    fi
    return 0
}

# Progress indicator for long operations
run_with_spinner() {
    local title="$1"
    shift
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] $title: $*"
        return 0
    fi
    if [ "$HAS_GUM" = true ]; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo "[...] $title"
        "$@"
    fi
}

# Detect video hardware and return appropriate driver package
detect_video_driver() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -qi "vga.*intel"; then
            echo "xf86-video-intel"
        elif lspci | grep -qi "vga.*nvidia"; then
            echo "xf86-video-nouveau"  # Use nouveau for open-source, or nvidia for proprietary
        elif lspci | grep -qi "vga.*amd\|ati"; then
            echo "xf86-video-amdgpu"
        else
            echo "xf86-video-vesa"  # Fallback generic driver
        fi
    else
        echo "xf86-video-vesa"  # Fallback if lspci not available
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
    --dry-run           Show what would be done without making changes

Examples:
    $(basename "$0")
    $(basename "$0") --dry-run

Note: This script must be run as root during Arch Linux installation.

EOF
}

# Parse arguments
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            msg_info "Running in DRY RUN mode: No changes will be made."
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
if [ "$DRY_RUN" -eq 0 ]; then
    require_command "visudo" "Install sudo package"
fi

# Minimum required free space in KiB (500 MiB = 512000 KiB)
MINSPACE=512000

FREESPACE=$(df --output=avail / | tail -1)

if [ "$FREESPACE" -lt "$MINSPACE" ]; then
    if [ ! -d "/run/archiso/cowspace" ]; then
        msg_error "Not enough free space and /run/archiso/cowspace not found."
        msg_error "This script must be run on Arch Linux installation media."
        exit 1
    fi
    msg_warning "Not enough free space on /. Attempting to remount /run/archiso/cowspace to 1 GiB..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would execute: mount -o remount,size=1G /run/archiso/cowspace"
    elif mount -o remount,size=1G /run/archiso/cowspace; then
        FREESPACE=$(df --output=avail / | tail -1)
        if [ "$FREESPACE" -lt "$MINSPACE" ]; then
            msg_error "Still less than 500 MiB available after remount. Only $((FREESPACE / 1024)) MiB free. Aborting."
            exit 1
        else
            msg_success "Remount successful. $((FREESPACE / 1024)) MiB available."
        fi
    else
        msg_error "Failed to remount /run/archiso/cowspace"
        msg_error "Possible causes:"
        msg_error "  - Not running on Arch Linux installation media"
        msg_error "  - Insufficient permissions"
        exit 1
    fi
fi

# Detect video driver
VIDEO_DRIVER=$(detect_video_driver)
msg_info "Detected video driver: $VIDEO_DRIVER"

# Refresh package database
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would execute: pacman -Syy --noconfirm"
else
    if ! run_with_spinner "Refreshing package database..." pacman -Syy --noconfirm; then
        msg_error "Failed to refresh package database"
        exit 1
    fi
fi

# Install essential Xorg components, XFCE, Ly, Calamares
PACKAGES=("xorg-server" "xorg-xinit" "xf86-input-libinput" "mesa" "$VIDEO_DRIVER" "xfce4" "ly" "calamares")
msg_info "Installing GUI components (Xorg, XFCE, Ly, Calamares)..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would execute: pacman -S --needed --noconfirm ${PACKAGES[*]}"
else
    if ! run_with_spinner "Installing GUI components..." pacman -S --needed --noconfirm "${PACKAGES[@]}"; then
        msg_error "Failed to install GUI components"
        msg_error "Packages attempted: ${PACKAGES[*]}"
        exit 1
    fi
fi

# Prompt for new user name
msg_info "Creating new user..."
if [ "$DRY_RUN" -eq 1 ]; then
    NEWUSER="dryrun_user"
    msg_info "[dry-run] Would prompt for username"
else
    if [ "$HAS_GUM" = true ]; then
        NEWUSER=$(gum input --prompt "Enter the name for the new user: " || true)
        if [ -z "${NEWUSER:-}" ]; then
            msg_warning "No username provided. Exiting."
            exit 0
        fi
    else
        read -rp "Enter the name for the new user: " NEWUSER
        if [ -z "${NEWUSER:-}" ]; then
            msg_error "Username cannot be empty"
            exit 1
        fi
    fi
fi

# Validate username format
if ! validate_username "$NEWUSER"; then
    exit 1
fi

if id "$NEWUSER" &>/dev/null; then
    msg_warning "User '$NEWUSER' already exists. Skipping user creation."
else
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would execute: useradd -m -G wheel -s /bin/bash $NEWUSER"
    else
        if ! useradd -m -G wheel -s /bin/bash "$NEWUSER"; then
            msg_error "Failed to create user '$NEWUSER'"
            exit 1
        fi
        msg_info "Set password for $NEWUSER:"
        if ! passwd "$NEWUSER"; then
            msg_error "Failed to set password for $NEWUSER"
            exit 1
        fi
    fi
fi

# Prompt for root password
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would prompt for root password"
else
    msg_info "Set password for root:"
    if ! passwd root; then
        msg_error "Failed to set root password"
        exit 1
    fi
fi

# Grant wheel group sudo access by updating /etc/sudoers
msg_info "Configuring sudo access for wheel group..."
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would edit /etc/sudoers to enable wheel group"
    else
        # Validate sudoers file before editing
        if ! visudo -cf /etc/sudoers &>/dev/null; then
            msg_error "sudoers file is invalid. Cannot safely edit."
            exit 1
        fi
        
        # Try to uncomment the wheel line
        sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers
        
        # Validate sudoers file after editing
        if ! visudo -cf /etc/sudoers &>/dev/null; then
            msg_error "sudoers file is invalid after edit. Restoring..."
            # Try to restore by commenting the line again
            sed -i 's/^%wheel ALL=(ALL) ALL/# %wheel ALL=(ALL) ALL/' /etc/sudoers
            exit 1
        fi
        msg_success "Enabled sudo access for wheel group."
    fi
else
    msg_info "Sudo access for wheel group already configured."
fi

# Make XFCE default session for the user
msg_info "Configuring XFCE as default session..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would configure .xinitrc for $NEWUSER"
elif [ -d "/home/$NEWUSER" ]; then
    if echo "exec startxfce4" > "/home/$NEWUSER/.xinitrc"; then
        if chown "$NEWUSER:$NEWUSER" "/home/$NEWUSER/.xinitrc"; then
            msg_success "XFCE configured as default session for $NEWUSER."
        else
            msg_error "Failed to set ownership of .xinitrc"
            exit 1
        fi
    else
        msg_error "Failed to create .xinitrc"
        exit 1
    fi
else
    msg_warning "Home directory for $NEWUSER not found. Skipping .xinitrc configuration."
fi

# Enable and start Ly immediately
msg_info "Enabling and starting Ly display manager..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would execute: systemctl enable --now ly.service"
    msg_info "[dry-run] Log in as $NEWUSER, then launch 'calamares' in XFCE to begin installation."
else
    if systemctl enable --now ly.service; then
        msg_success "Ly display manager started."
        msg_info "Log in as $NEWUSER, then launch 'calamares' in XFCE to begin installation."
    else
        msg_error "Failed to start Ly display manager."
        msg_error "Possible causes:"
        msg_error "  - Service not installed correctly"
        msg_error "  - Systemd issues"
        exit 1
    fi
fi

exit 0
