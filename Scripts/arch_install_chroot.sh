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

# System Configuration
print_section "System Configuration"

read -rp "Enter your keyboard layout (e.g., de_CH-latin1): " keyboard_layout
read -rp "Enter your timezone (e.g., Europe/Zurich): " timezone
execute_command "ln -sf /usr/share/zoneinfo/$timezone /etc/localtime"
execute_command "hwclock --systohc"

execute_command "sed -i 's/#de_CH.UTF-8 UTF-8/de_CH.UTF-8 UTF-8/' /etc/locale.gen"
execute_command "sed -i 's/#de_CH ISO-8859-1/de_CH ISO-8859-1/' /etc/locale.gen"
execute_command "locale-gen"
execute_command "echo 'LANG=de_CH.UTF-8' > /etc/locale.conf"

execute_command "echo 'KEYMAP=$keyboard_layout' > /etc/vconsole.conf"

read -rp "Enter hostname: " hostname
execute_command "echo $hostname > /etc/hostname"

execute_command "systemctl enable NetworkManager"
execute_command "timedatectl set-ntp true"

execute_command "passwd"

# Bootloader Setup
print_section "Bootloader Setup"

execute_command "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
execute_command "grub-mkconfig -o /boot/grub/grub.cfg"

# User Setup
print_section "User Setup"

read -rp "Enter username: " username
execute_command "useradd -m -G wheel -s /bin/bash $username"
execute_command "passwd $username"

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
echo -e "${GREEN}Chroot installation completed!${NC}"
echo "Please follow these final steps:"
echo "1. Exit chroot environment: type 'exit'"
echo "2. Reboot the system: reboot"
echo "3. Log in with your user account"
echo "4. Start configuring your desktop environment" 