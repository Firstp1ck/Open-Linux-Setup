#!/bin/env/bash

set -euo pipefail

# Log all output to a file and display on terminal
LOGFILE=~/secureboot_sign.log
exec > >(tee -a "$LOGFILE") 2>&1

echo "========== Secure Boot Signing Script Run: $(date) =========="

# Function to print error and exit
error_exit() {
    echo "[ERROR] $1" >&2
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

echo "[INFO] Installing required packages (if not already installed)..."
sudo pacman -S --needed --noconfirm --verbose openssl grub efibootmgr sbsigntools mokutil || error_exit "Failed to install required packages."

echo "[INFO] Generating Secure Boot signing keys using OpenSSL..."
mkdir -p ~/secure_boot
cd ~/secure_boot || error_exit "Failed to enter ~/secure_boot directory."
if [[ ! -f MOK.key || ! -f MOK.crt ]]; then
    openssl req -newkey rsa:2048 -nodes -keyout MOK.key -new -x509 -sha256 -days 3650 -subj "/CN=Secure Boot Key/" -out MOK.crt || error_exit "Failed to generate MOK.key and MOK.crt."
    openssl x509 -outform DER -in MOK.crt -out MOK.cer || error_exit "Failed to generate MOK.cer."
else
    echo "[INFO] Signing keys already exist, skipping key generation."
fi

# Add generated public Key into UEFI firmware.
echo "[INFO] Importing public key into UEFI firmware (will require a reboot to enroll)..."
sudo mokutil --import ~/secure_boot/MOK.cer || error_exit "Failed to import MOK.cer with mokutil."

echo "[INFO] Please reboot and enroll the key in the MOK manager, then re-run this script to continue."
read -rp "Press Enter to continue if you have already enrolled the key, or Ctrl+C to abort..."

# Configure Grub to load the signed key
echo "[INFO] Signing GRUB EFI binary..."
sudo sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/boot/bootx64.efi || error_exit "Failed to sign GRUB EFI binary."
sudo cp /boot/efi/EFI/boot/bootx64.efi /boot/efi/EFI/BOOT/bootx64.efi || error_exit "Failed to copy signed GRUB EFI binary."

echo "[INFO] Signing Linux kernel..."
sudo sbsign --key ~/secure_boot/MOK.key --cert ~/secure_boot/MOK.crt --output /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to sign Linux kernel."
sudo mv /boot/vmlinuz-linux.signed /boot/vmlinuz-linux || error_exit "Failed to move signed kernel."

echo "[INFO] Regenerating GRUB configuration..."
sudo grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to regenerate GRUB config."

# Enable Secure Boot in UEFI (manual step)
echo "[INFO] Please enable Secure Boot in your UEFI/BIOS settings if not already enabled."

echo "[INFO] Checking Secure Boot status..."
mokutil --sb-state || error_exit "Failed to check Secure Boot status."

echo "[INFO] Repeat signing after every kernel or GRUB update."