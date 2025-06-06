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

# Function to prompt user and wait for confirmation
prompt_continue() {
    echo -e "${YELLOW}$1${NC}"
    read -p "Press Enter to continue..."
}

# Function to execute command and check status
execute_command() {
    echo -e "${YELLOW}Executing: $1${NC}"
    eval "$1"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Command failed. Please check the error and try again.${NC}"
        exit 1
    fi
}

# Initial Setup
print_section "Initial Setup"

echo "Available keyboard layouts:"
execute_command "localectl list-keymaps"
read -p "Enter your keyboard layout (e.g., de_CH-latin1): " keyboard_layout
execute_command "loadkeys $keyboard_layout"

prompt_continue "Verifying system time..."
execute_command "timedatectl"

prompt_continue "Verifying boot mode..."
execute_command "cat /sys/firmware/efi/fw_platform_size"

prompt_continue "Checking internet connection..."
execute_command "ping -c 3 archlinux.org"

prompt_continue "Listing available disks..."
execute_command "fdisk -l"

# Disk Partitioning
print_section "Disk Partitioning"

read -p "Enter the disk to partition (e.g., /dev/vda): " disk
prompt_continue "Starting disk partitioning. You will need to manually create partitions using fdisk."
echo "Recommended partition layout:"
echo "1. EFI System Partition (1GB)"
echo "2. Swap Partition (4GB)"
echo "3. Root Partition (remaining space)"
execute_command "fdisk $disk"

prompt_continue "Verifying partition layout..."
execute_command "lsblk"

# Filesystem Setup
print_section "Filesystem Setup"

read -p "Enter root partition (e.g., /dev/vda3): " root_partition
read -p "Enter boot partition (e.g., /dev/vda1): " boot_partition
read -p "Enter swap partition (e.g., /dev/vda2): " swap_partition

execute_command "mkfs.btrfs $root_partition"
execute_command "mkfs.fat -F 32 $boot_partition"
execute_command "mkswap $swap_partition"

execute_command "mount $root_partition /mnt"
execute_command "mount --mkdir $boot_partition /mnt/boot"
execute_command "swapon $swap_partition"

# System Installation
print_section "System Installation"

prompt_continue "Adding multilib repository..."
execute_command "sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf"

prompt_continue "Updating package database..."
execute_command "pacman -Sy"

prompt_continue "Installing base system and packages..."
execute_command "pacstrap -K /mnt base linux linux-firmware base-devel sudo pam grub efibootmgr curl git fish neovim man-db man-pages terminus-font networkmanager qemu-guest-agent sddm hyprland xdg-desktop-portal-hyprland xdg-user-dirs intel-ucode mesa vulkan-icd-loader sof-firmware lib32-mesa lib32-vulkan-icd-loader pipewire pipewire-pulse wireplumber kitty wofi falkon dolphin polkit"

prompt_continue "Generating fstab..."
execute_command "genfstab -U /mnt >> /mnt/etc/fstab"

# System Configuration
print_section "System Configuration"

prompt_continue "Entering chroot environment..."
execute_command "arch-chroot /mnt"

read -p "Enter your timezone (e.g., Europe/Zurich): " timezone
execute_command "ln -sf /usr/share/zoneinfo/$timezone /etc/localtime"
execute_command "hwclock --systohc"

prompt_continue "Configuring locale..."
execute_command "sed -i 's/#de_CH.UTF-8 UTF-8/de_CH.UTF-8 UTF-8/' /etc/locale.gen"
execute_command "sed -i 's/#de_CH ISO-8859-1/de_CH ISO-8859-1/' /etc/locale.gen"
execute_command "locale-gen"
execute_command "echo 'LANG=de_CH.UTF-8' > /etc/locale.conf"

execute_command "echo 'KEYMAP=$keyboard_layout' > /etc/vconsole.conf"

read -p "Enter hostname: " hostname
execute_command "echo $hostname > /etc/hostname"

execute_command "systemctl enable NetworkManager"
execute_command "timedatectl set-ntp true"

prompt_continue "Setting root password..."
execute_command "passwd"

# Bootloader Setup
print_section "Bootloader Setup"

execute_command "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
execute_command "grub-mkconfig -o /boot/grub/grub.cfg"

# User Setup
print_section "User Setup"

read -p "Enter username: " username
execute_command "useradd -m -G wheel -s /bin/bash $username"
execute_command "passwd $username"

prompt_continue "Configuring sudo..."
execute_command "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
execute_command "sed -i 's/# %sudo ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) ALL/' /etc/sudoers"

execute_command "systemctl enable --now sddm"

# Hyprland Configuration
print_section "Hyprland Configuration"

execute_command "mkdir -p /home/$username/.config/hypr"
execute_command "echo 'kb_layout = ch' > /home/$username/.config/hypr/hyprland.conf"
execute_command "chown -R $username:$username /home/$username/.config"

# Final Steps
print_section "Final Steps"
echo -e "${GREEN}Installation completed!${NC}"
echo "Please follow these final steps:"
echo "1. Exit chroot environment: type 'exit'"
echo "2. Unmount all partitions: umount -R /mnt"
echo "3. Reboot the system: reboot"
echo "4. Log in with your user account"
echo "5. Start configuring your desktop environment"

prompt_continue "Press Enter to exit chroot environment..."
exit 