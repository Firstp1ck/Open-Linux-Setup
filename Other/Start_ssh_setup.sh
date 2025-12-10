#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_ssh_setup.sh
# ============================================================================
# Description:
#   Complete SSH server setup tool that detects USB devices, copies SSH keys
#   to USB for backup, installs OpenSSH server, generates SSH keypairs if
#   needed, and configures SSH service to start automatically.
#
# What it does:
#   - Detects USB storage devices automatically
#   - Mounts USB device and copies SSH private key to USB
#   - Detects Linux distribution and installs OpenSSH server accordingly
#   - Starts and enables SSH service (sshd or ssh)
#   - Generates SSH keypair (RSA 4096-bit) if it doesn't exist
#   - Copies SSH private key to Downloads folder
#   - Configures proper permissions on .ssh directory
#
# How to use:
#   Run with appropriate privileges:
#     ./Start_ssh_setup.sh
#     sudo ./Start_ssh_setup.sh  (if root access needed)
#   
#   Options:
#     --help, -h      Show help message
#     --skip-usb      Skip USB key copying step
#
# Target:
#   - Users setting up SSH server for remote access
#   - System administrators configuring SSH access
#   - Users needing SSH key backup to USB
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

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Setup SSH server by detecting USB device, copying SSH keys to USB,
    installing OpenSSH server, and configuring SSH service. Also generates
    SSH keypair if it doesn't exist.

Options:
    --help, -h          Show this help message
    --skip-usb          Skip USB key copying step

Examples:
    $(basename "$0")
    $(basename "$0") --skip-usb

Note: This script requires sudo privileges for some operations.

EOF
}

# Parse arguments
SKIP_USB=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --skip-usb)
            SKIP_USB=1
            ;;
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    shift
done

# Check dependencies
require_command "lsblk" "Install util-linux package"
require_command "systemctl" "This script requires systemd"

# Check for sudo if needed
# shellcheck disable=SC2329
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            msg_error "This script requires sudo privileges. Install sudo or run as root."
            exit 1
        fi
    fi
}

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# === Step 1: Detect USB device ===
if [ "$SKIP_USB" -eq 0 ]; then
    msg_info "Detecting USB device..."
    DEVICE=$(lsblk -pno NAME,TRAN 2>/dev/null | awk '$2=="usb"{print $1}' | head -n 1 || true)
    
    if [ -z "$DEVICE" ]; then
        msg_error "No USB device detected. Please insert a USB stick and try again."
        exit 1
    else
        msg_success "USB device detected: $DEVICE"
    fi

    # Find the first partition on the device (e.g., /dev/sdb1)
    PARTITION="${DEVICE}1"
    msg_info "Checking for partition: $PARTITION..."
    if ! lsblk | grep -q "$(basename "$PARTITION")"; then
        msg_error "Partition $PARTITION not found. Please check your USB stick."
        exit 1
    else
        msg_success "Partition found: $PARTITION"
    fi

    # === Step 2: Mount the USB partition ===
    MOUNTPOINT="/mnt/usb"
    msg_info "Mounting $PARTITION to $MOUNTPOINT..."
    run_as_root mkdir -p "$MOUNTPOINT"
    if run_as_root mount "$PARTITION" "$MOUNTPOINT"; then
        msg_success "Mounted $PARTITION at $MOUNTPOINT."
    else
        msg_error "Failed to mount $PARTITION."
        exit 1
    fi

    # === Step 3: Copy the key file ===
    KEY_FILE="$HOME/.ssh/id_rsa"
    msg_info "Checking for SSH private key at $KEY_FILE..."
    if [ ! -f "$KEY_FILE" ]; then
        msg_warning "SSH private key not found: $KEY_FILE"
        msg_info "SSH key will be generated later in the script."
    else
        msg_success "SSH private key found. Copying to USB..."
        if cp "$KEY_FILE" "$MOUNTPOINT/"; then
            msg_success "SSH private key copied to USB stick ($MOUNTPOINT)"
        else
            msg_error "Failed to copy SSH private key to USB stick."
            run_as_root umount "$MOUNTPOINT" || true
            exit 1
        fi
    fi

    # === Step 4: Optionally unmount USB after copying ===
    msg_info "Unmounting USB stick..."
    if run_as_root umount "$MOUNTPOINT"; then
        msg_success "USB stick unmounted. You can now safely remove it."
    else
        msg_warning "Failed to unmount USB stick. Please unmount manually if needed."
    fi
else
    msg_info "Skipping USB key copying step (--skip-usb specified)."
fi

# === Step 5: Detect Linux distribution and install OpenSSH server accordingly ===
if [ ! -f /etc/os-release ]; then
    msg_error "/etc/os-release not found. Cannot determine Linux distribution."
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID=$ID

INSTALL_CMD=""
SERVICE_NAME=""

case "$DISTRO_ID" in
    arch|manjaro|endeavouros|cachyos)
        INSTALL_CMD="pacman -Syu --noconfirm openssh"
        SERVICE_NAME="sshd"
        ;;
    debian|ubuntu|linuxmint|pop|mint)
        INSTALL_CMD="apt-get update && apt-get install -y openssh-server"
        SERVICE_NAME="ssh"
        ;;
    fedora|bazzite|nobara)
        INSTALL_CMD="dnf install -y openssh-server"
        SERVICE_NAME="sshd"
        ;;
    *)
        msg_error "Unsupported or unrecognized Linux distribution: $DISTRO_ID"
        exit 1
        ;;
esac

# === Step 6: Install OpenSSH server (if not already installed) ===
msg_info "Checking if OpenSSH server is installed..."
if ! command -v sshd >/dev/null 2>&1; then
    msg_info "Installing OpenSSH server..."
    if [ "$EUID" -eq 0 ]; then
        if eval "$INSTALL_CMD"; then
            msg_success "OpenSSH server installed."
        else
            msg_error "Failed to install OpenSSH server."
            exit 1
        fi
    else
        if command -v sudo >/dev/null 2>&1; then
            if sudo bash -c "$INSTALL_CMD"; then
                msg_success "OpenSSH server installed."
            else
                msg_error "Failed to install OpenSSH server."
                exit 1
            fi
        else
            msg_error "This operation requires root privileges."
            exit 1
        fi
    fi
else
    msg_success "OpenSSH server is already installed."
fi

# === Step 7: Start SSH service and enable it to start at boot ===
msg_info "Starting SSH service and enabling it to start at boot..."
run_as_root systemctl enable "$SERVICE_NAME"
if run_as_root systemctl start "$SERVICE_NAME"; then
    msg_success "SSH service started and enabled."
else
    msg_error "Failed to start SSH service."
    exit 1
fi

# === Step 8: Generate SSH keypair (defaults to ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub) ===
KEY_COMMENT="${USER}@$(hostname)"
KEY_FILE="$HOME/.ssh/id_rsa"
msg_info "Checking for existing SSH key at $KEY_FILE..."

# Ensure .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY_FILE" ]; then
    msg_success "An SSH key already exists at $KEY_FILE. Skipping generation."
else
    msg_info "Generating SSH keypair..."
    if ssh-keygen -t rsa -b 4096 -C "$KEY_COMMENT" -N "" -f "$KEY_FILE"; then
        msg_success "SSH keypair generated."
    else
        msg_error "Failed to generate SSH keypair."
        exit 1
    fi
fi

# === Step 9: Copy private key to Downloads folder ===
# Check if Downloads folder exists
DOWNLOADS_DIR="$HOME/Downloads"
msg_info "Checking for Downloads folder at $DOWNLOADS_DIR..."
if [ ! -d "$DOWNLOADS_DIR" ]; then
    msg_info "Creating Downloads folder at $DOWNLOADS_DIR..."
    if mkdir -p "$DOWNLOADS_DIR"; then
        msg_success "Downloads folder created."
    else
        msg_error "Failed to create Downloads folder."
        exit 1
    fi
fi

msg_info "Copying SSH private key to $DOWNLOADS_DIR..."
if cp "$KEY_FILE" "$DOWNLOADS_DIR/"; then
    msg_success "SSH private key copied to $DOWNLOADS_DIR/"
else
    msg_error "Failed to copy SSH private key to $DOWNLOADS_DIR/"
    exit 1
fi

msg_success "SSH server setup completed."

exit 0
