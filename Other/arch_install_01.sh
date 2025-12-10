#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: arch_install_01.sh
# ============================================================================
# Description:
#   Interactive Arch Linux installation script for pre-chroot setup phase.
#   Guides users through initial system setup, disk partitioning, filesystem
#   creation, and base system installation before entering chroot environment.
#
# What it does:
#   - Sets keyboard layout
#   - Checks system time and EFI firmware
#   - Tests network connectivity
#   - Guides disk partitioning with fdisk
#   - Creates filesystems (Btrfs for root, FAT32 for boot, swap)
#   - Mounts partitions
#   - Enables multilib repository
#   - Installs base system with Hyprland desktop and essential packages
#   - Generates fstab
#   - Copies repository to new system for chroot script
#
# How to use:
#   Run as root from Arch Linux installation media:
#     sudo ./arch_install_01.sh
#   
#   Options:
#     --help, -h      Show help message
#
#   After completion, enter chroot and run arch_install_02.sh
#
# Target:
#   - Users performing fresh Arch Linux installations
#   - System administrators setting up Arch Linux systems
#   - Users wanting automated installation with Hyprland desktop
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Standard message functions
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# shellcheck disable=SC2329
msg_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
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
    Interactive Arch Linux installation script for pre-chroot setup.
    Guides through initial setup, disk partitioning, filesystem creation,
    and system installation.

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
require_command "localectl" "Install systemd package"
require_command "fdisk" "Install util-linux package"
require_command "pacstrap" "Install arch-install-scripts package"

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}${BOLD}=== $1 ===${NC}\n"
}

# Function to get non-empty input
get_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    read -rp "$prompt [Default: $default]: " input
    echo "${input:-$default}"
}

# Function to execute command and check status
# Note: Uses eval for interactive user confirmation - be careful with input
execute_command() {
    local cmd="$1"
    
    echo -e "${YELLOW}Command to execute: $cmd${NC}"
    read -rp "Do you want to execute this command? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${RED}Command skipped.${NC}"
    else
        if eval "$cmd"; then
            msg_success "Command executed successfully."
        else
            msg_error "Command failed. Please check the error and try again."
            exit 1
        fi
    fi
}

# Initial Setup
print_section "Initial Setup"

read -rp "Do you want to see the list of keyboard layouts? (y/N): " show_keymaps_confirm
if [[ ! "$show_keymaps_confirm" =~ ^[Yy]$ ]]; then
    msg_info "Skipping keyboard layout listing."
else
    execute_command "localectl list-keymaps"
fi

keyboard_layout=$(get_input "Enter your keyboard layout" "de_CH-latin1")
execute_command "loadkeys $keyboard_layout"

execute_command "timedatectl"
execute_command "cat /sys/firmware/efi/fw_platform_size"
execute_command "ping -c 3 archlinux.org"
execute_command "fdisk -l"

# Disk Partitioning
print_section "Disk Partitioning"

disk=$(get_input "Enter the disk to partition" "/dev/vda")
msg_info "Starting disk partitioning. You will need to manually create partitions using fdisk."
echo "Recommended partition layout:"
echo "1. EFI System Partition (1GB) - Type: EFI System"
echo "2. Swap Partition (4GB) - Type: Linux Swap"
echo "3. Root Partition (remaining space) - Linux Filesystem"
echo "Use the following commands:"
echo "1. 'g' for creating a GPT Partitionstable"
echo "2. 'n' to create new Partition each"
echo "2.a.  Use +1g (Boot) resp +4g (Swap) for 'Last Sector'"
echo "3. 't' to choose the File System Type"
echo "  a.  Use '1' for EFI System (Boot)"
echo "  b.  Use '19' for Swap System (Swap)"
echo "  c.  Skip Root Partition, already set to Linux Filesystem (20)"
echo "4. 'w' save and exit fdisk"
execute_command "fdisk $disk"

execute_command "lsblk"

# Filesystem Setup
print_section "Filesystem Setup"

root_partition=$(get_input "Enter root partition" "/dev/vda3")
boot_partition=$(get_input "Enter boot partition" "/dev/vda1")
swap_partition=$(get_input "Enter swap partition" "/dev/vda2")

execute_command "mkfs.btrfs $root_partition"
execute_command "mkfs.fat -F 32 $boot_partition"
execute_command "mkswap $swap_partition"

execute_command "mount $root_partition /mnt"
execute_command "mount --mkdir $boot_partition /mnt/boot"
execute_command "swapon $swap_partition"

# System Installation
print_section "System Installation"

execute_command "sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf"
execute_command "pacman -Sy"
execute_command "pacstrap -K /mnt base linux linux-firmware base-devel sudo pam grub efibootmgr curl git fish neovim man-db man-pages terminus-font networkmanager qemu-guest-agent sddm hyprland xdg-desktop-portal-hyprland xdg-user-dirs intel-ucode mesa vulkan-icd-loader sof-firmware lib32-mesa lib32-vulkan-icd-loader pipewire pipewire-pulse wireplumber kitty wofi dolphin hyprpaper waybar otf-font-awesome pavucontrol power-profiles-daemon libappindicator-gtk3 python-psutil python-pydbus python-gobject firefox network-manager-applet polkit gedit"
execute_command "genfstab -U /mnt >> /mnt/etc/fstab"

# Copy the chroot script to the new system
print_section "Preparing for Chroot"

# Get the directory where the script is located
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
current_dir="$(pwd)"

# If we're not in the script directory, change to it
if [ "$current_dir" != "$script_dir" ]; then
    msg_info "Changing to script directory: $script_dir"
    cd "$script_dir" || exit 1
fi

# Copy the entire repository to the new system
execute_command "cp -r ../ /mnt/root/Open-Linux-Setup"
execute_command "chmod +x /mnt/root/Open-Linux-Setup/Other/arch_install_02.sh"

msg_success "Pre-chroot setup completed!"
msg_info "Now you can enter the chroot environment and run the chroot script:"
echo "1. arch-chroot /mnt"
echo "2. /root/Open-Linux-Setup/Other/arch_install_02.sh"

exit 0
