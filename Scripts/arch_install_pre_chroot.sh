#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}=== $1 ===${NC}\n"
}

# Function to execute command and check status
execute_command() {
    echo -e "${YELLOW}Command to execute: $1${NC}"
    read -rp "Do you want to execute this command? (Y/n): " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        echo -e "${RED}Command skipped.${NC}"
    else
        eval "$1"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Command failed. Please check the error and try again.${NC}"
            exit 1
        fi
    fi
}

# Initial Setup
print_section "Initial Setup"

echo "Available keyboard layouts:"
execute_command "localectl list-keymaps"
read -rp "Enter your keyboard layout (e.g., de_CH-latin1): " keyboard_layout
execute_command "loadkeys $keyboard_layout"

execute_command "timedatectl"
execute_command "cat /sys/firmware/efi/fw_platform_size"
execute_command "ping -c 3 archlinux.org"
execute_command "fdisk -l"

# Disk Partitioning
print_section "Disk Partitioning"

read -rp "Enter the disk to partition (e.g., /dev/vda): " disk
echo "Starting disk partitioning. You will need to manually create partitions using fdisk."
echo "Recommended partition layout:"
echo "1. EFI System Partition (1GB) - Type: EFI System"
echo "2. Swap Partition (4GB) - Type: Linux Swap"
echo "3. Root Partition (remaining space) - Linux Filesystem"
echo "Use the following commands:"
echo "1. 'g' for creating a GPT Partitionstable"
echo "2. 'n' to create new Partition each"
echo "3. 't' to choose the File System Type"
echo "4. 'w' save and exit fdisk"
execute_command "fdisk $disk"

execute_command "lsblk"

# Filesystem Setup
print_section "Filesystem Setup"

read -rp "Enter root partition (e.g., /dev/vda3): " root_partition
read -rp "Enter boot partition (e.g., /dev/vda1): " boot_partition
read -rp "Enter swap partition (e.g., /dev/vda2): " swap_partition

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
execute_command "pacstrap -K /mnt base linux linux-firmware base-devel sudo pam grub efibootmgr curl git fish neovim man-db man-pages terminus-font networkmanager qemu-guest-agent sddm hyprland xdg-desktop-portal-hyprland xdg-user-dirs intel-ucode mesa vulkan-icd-loader sof-firmware lib32-mesa lib32-vulkan-icd-loader pipewire pipewire-pulse wireplumber kitty wofi falkon dolphin polkit"
execute_command "genfstab -U /mnt >> /mnt/etc/fstab"

# Copy the chroot script to the new system
print_section "Preparing for Chroot"
execute_command "cp arch_install_chroot.sh /mnt/root/"
execute_command "chmod +x /mnt/root/arch_install_chroot.sh"

echo -e "${GREEN}Pre-chroot setup completed!${NC}"
echo "Now you can enter the chroot environment and run the chroot script:"
echo "1. arch-chroot /mnt"
echo "2. /root/arch_install_chroot.sh" 