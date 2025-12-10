#!/usr/bin/env bash

set -euo pipefail

# Script: Start_bootloader_signing.sh
# Description: Sign bootloader and kernel for Secure Boot using MOK (Machine Owner Key)

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
# shellcheck disable=SC2329
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
    Sign bootloader and kernel for Secure Boot using MOK (Machine Owner Key).
    Generates signing keys, imports them into UEFI firmware, and signs GRUB
    and the Linux kernel.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

Note: This script requires root privileges and will prompt for sudo if needed.
      You will need to reboot and enroll the key in MOK manager after first run.

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

# Log all output to a file and display on terminal
LOGFILE=~/secureboot_sign.log
exec > >(tee -a "$LOGFILE") 2>&1

if [ "$HAS_GUM" = true ]; then
    gum style --border normal --margin "1 2" --padding "1 2" --foreground 63 "Secure Boot Signing Script Run: $(date)"
else
    echo "========== Secure Boot Signing Script Run: $(date) =========="
fi

# Function to print error and exit
error_exit() {
    msg_error "$1"
    exit 1
}

# Function to check if a command exists
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || error_exit "$1 is required but not installed."
}

# Check for required commands
for cmd in openssl grub efibootmgr sbsigntools mokutil pacman; do
    require_cmd "$cmd"
done

msg_info "Installing required packages (if not already installed)..."
if [ "$EUID" -eq 0 ]; then
    pacman -S --needed --noconfirm --verbose openssl grub efibootmgr sbsigntools mokutil || error_exit "Failed to install required packages."
else
    if command -v sudo >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm --verbose openssl grub efibootmgr sbsigntools mokutil || error_exit "Failed to install required packages."
    else
        error_exit "This script requires root privileges. Install sudo or run as root."
    fi
fi

msg_info "Generating Secure Boot signing keys using OpenSSL..."
mkdir -p ~/secure_boot
cd ~/secure_boot || error_exit "Failed to enter ~/secure_boot directory."

if [[ ! -f MOK.key || ! -f MOK.crt ]]; then
    openssl req -newkey rsa:2048 -nodes -keyout MOK.key -new -x509 -sha256 -days 3650 -subj "/CN=Secure Boot Key/" -out MOK.crt || error_exit "Failed to generate MOK.key and MOK.crt."
    openssl x509 -outform DER -in MOK.crt -out MOK.cer || error_exit "Failed to generate MOK.cer."
    msg_success "Signing keys generated successfully."
else
    msg_info "Signing keys already exist, skipping key generation."
fi

# Add generated public Key into UEFI firmware.
msg_warning "Importing public key into UEFI firmware (will require a reboot to enroll)..."
if [ "$EUID" -eq 0 ]; then
    mokutil --import ~/secure_boot/MOK.cer || error_exit "Failed to import MOK.cer with mokutil."
else
    if command -v sudo >/dev/null 2>&1; then
        sudo mokutil --import ~/secure_boot/MOK.cer || error_exit "Failed to import MOK.cer with mokutil."
    else
        error_exit "This operation requires root privileges."
    fi
fi

msg_warning "Please reboot and enroll the key in the MOK manager, then re-run this script to continue."
if [ "$HAS_GUM" = true ]; then
    gum input --placeholder "Press Enter to continue if you have already enrolled the key, or Ctrl+C to abort..." >/dev/null
else
    read -rp "Press Enter to continue if you have already enrolled the key, or Ctrl+C to abort..."
fi

# Configure Grub to load the signed key
msg_info "Signing GRUB EFI binary..."
if [ "$EUID" -eq 0 ]; then
    sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/boot/bootx64.efi || error_exit "Failed to sign GRUB EFI binary."
    cp /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/BOOT/bootx64.efi || error_exit "Failed to copy signed GRUB EFI binary."
else
    if command -v sudo >/dev/null 2>&1; then
        sudo sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/boot/bootx64.efi || error_exit "Failed to sign GRUB EFI binary."
        sudo cp /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/BOOT/bootx64.efi || error_exit "Failed to copy signed GRUB EFI binary."
    else
        error_exit "This operation requires root privileges."
    fi
fi
msg_success "GRUB EFI binary signed successfully."

msg_info "Signing Linux kernel..."
if [ "$EUID" -eq 0 ]; then
    sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to sign Linux kernel."
    mv /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to move signed kernel."
else
    if command -v sudo >/dev/null 2>&1; then
        sudo sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to sign Linux kernel."
        sudo mv /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to move signed kernel."
    else
        error_exit "This operation requires root privileges."
    fi
fi
msg_success "Linux kernel signed successfully."

msg_info "Regenerating GRUB configuration..."
if [ "$EUID" -eq 0 ]; then
    grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to regenerate GRUB config."
else
    if command -v sudo >/dev/null 2>&1; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to regenerate GRUB config."
    else
        error_exit "This operation requires root privileges."
    fi
fi
msg_success "GRUB configuration regenerated."

# Enable Secure Boot in UEFI (manual step)
msg_warning "Please enable Secure Boot in your UEFI/BIOS settings if not already enabled."

msg_info "Checking Secure Boot status..."
if mokutil --sb-state; then
    msg_success "Secure Boot status checked."
else
    msg_warning "Failed to check Secure Boot status (may not be enabled yet)."
fi

msg_info "Repeat signing after every kernel or GRUB update."

exit 0
