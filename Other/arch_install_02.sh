#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: arch_install_02.sh
# ============================================================================
# Description:
#   Interactive Arch Linux installation script for chroot configuration phase.
#   Configures system settings, bootloader, user accounts, and desktop
#   environment after entering the chroot environment.
#
# What it does:
#   - Configures keyboard layout and timezone
#   - Sets up locale (UTF-8 and ISO-8859-1)
#   - Configures hostname
#   - Enables NetworkManager and NTP
#   - Sets root password
#   - Installs and configures GRUB bootloader
#   - Creates user account with wheel group
#   - Configures sudo access
#   - Sets up Hyprland desktop configuration
#   - Enables SDDM display manager
#
# How to use:
#   Run as root inside chroot environment:
#     arch-chroot /mnt
#     /root/Open-Linux-Setup/Other/arch_install_02.sh
#   
#   Options:
#     --help, -h      Show help message
#
#   Must be run after arch_install_01.sh completes
#
# Target:
#   - Users completing Arch Linux installation
#   - System administrators configuring new Arch systems
#   - Users setting up Hyprland desktop environment
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
    Interactive Arch Linux installation script for chroot configuration.
    Configures system settings, bootloader, user accounts, and Hyprland desktop.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

Note: This script must be run inside chroot environment as root.

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
require_command "systemctl" "This script requires systemd"
require_command "grub-install" "Install grub package"
require_command "localectl" "Install systemd package"

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}${BOLD}=== $1 ===${NC}\n"
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

# Function to get non-empty input
get_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    read -rp "$prompt [Default: $default]: " input
    echo "${input:-$default}"
}

# System Configuration
print_section "System Configuration"

show_keyboard_layouts=$(get_input "Do you want to see a list of available keyboard layouts? (y/N)" "N")
if [[ "$show_keyboard_layouts" =~ ^[Yy]$ ]]; then
    execute_command "localectl list-keymaps"
fi
keyboard_layout=$(get_input "Enter your keyboard layout" "de_CH-latin1")

show_timezones=$(get_input "Do you want to see a list of available timezones? (y/N)" "N")
if [[ "$show_timezones" =~ ^[Yy]$ ]]; then
    execute_command "timedatectl list-timezones"
fi
timezone=$(get_input "Enter your timezone" "Europe/Zurich")
execute_command "ln -sf /usr/share/zoneinfo/$timezone /etc/localtime"
execute_command "hwclock --systohc"

show_locale_gen=$(get_input "Do you want to see the relevant lines from /etc/locale.gen? (y/N)" "N")
if [[ "$show_locale_gen" =~ ^[Yy]$ ]]; then
    execute_command "grep 'UTF-8' /etc/locale.gen | cat"
fi
locale_utf8=$(get_input "Enter your desired UTF-8 locale from the list above" "de_CH.UTF-8 UTF-8")

if [[ "$show_locale_gen" =~ ^[Yy]$ ]]; then
    execute_command "grep 'ISO-8859-1' /etc/locale.gen | cat"
fi
locale_iso=$(get_input "Enter your desired ISO-8859-1 locale from the list above" "de_CH ISO-8859-1")
execute_command "sed -i \"s/#${locale_utf8}/${locale_utf8}/g\" /etc/locale.gen"
execute_command "sed -i \"s/#${locale_iso}/${locale_iso}/g\" /etc/locale.gen"
execute_command "locale-gen"
execute_command "echo 'LANG=de_CH.UTF-8' > /etc/locale.conf"

execute_command "echo 'KEYMAP=$keyboard_layout' > /etc/vconsole.conf"

hostname=$(get_input "Enter hostname" "archlinux")
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

username=$(get_input "Enter username" "user")
execute_command "useradd -m -G wheel -s /bin/bash $username"
execute_command "passwd $username"

execute_command "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
execute_command "sed -i 's/# %sudo ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) ALL/' /etc/sudoers"

execute_command "systemctl enable sddm"

# Hyprland Configuration
print_section "Hyprland Configuration"

execute_command "mkdir -p /home/$username/.config/hypr"
execute_command "cp /root/Open-Linux-Setup/System_files/hyprland.conf.bak /home/$username/.config/hypr/hyprland.conf"
execute_command "mkdir -p /home/$username/.config/waybar"
execute_command "cp -r /root/Open-Linux-Setup/System_files/waybar/* /home/$username/.config/waybar/"
execute_command "chown -R $username:$username /home/$username/.config"

# Final Steps
print_section "Final Steps"
msg_success "Chroot installation completed!"
msg_info "Please follow these final steps:"
echo "1. Exit chroot environment: type 'exit' or Ctrl+D"
echo "2. Reboot the system: reboot"
echo "3. Log in with your user account"
echo "4. Start configuring your desktop environment"

exit 0
