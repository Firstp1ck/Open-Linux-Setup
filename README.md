# Open-Linux-Setup
A Collection of Functions to Setup Linux (Tested for Arch Linux)

## Table of Contents
- [Overview](#overview)
- [Installation Guide](#installation-guide)
- [How to Use](#how-to-use)
    - [Setting Variables](#setting-variables)
    - [Running the Main Setup](#main-setup)
- [Scripts](#scripts)
- [Available Functions](#available-functions)
- [Dependencies](#dependencies)
- [Contributing](#contributing)
- [License](#license)

## Overview
This project provides a collection of scripts to automate the setup of a Linux system, primarily tested on Arch Linux. It aims to streamline the post-installation configuration process by offering functions for various setup tasks.

## Installation Guide
To get started with Open-Linux-Setup:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Firstp1ck/Open-Linux-Setup.git
   ```
2. **Navigate to the directory:**
   ```bash
   cd Open-Linux-Setup
   ```
3. **\[Optional\] Make scripts executable:**
   You might need to make the scripts executable:
   ```bash
   chmod +x *.sh main/*.sh Other/*.sh # Adjust path if needed
   ```

## How to Use

### Setting Variables
Before running the main system setup script, you **must** configure the necessary variables using the `Start_set_variable.sh` script. This script will guide you through setting up paths, preferences, and other variables that `Start_System_setup.sh` relies on.

To run the script:
```bash
cd Path/to/Script
./Start_set_variable.sh
```
Follow the prompts to set your desired configuration.

### Main Setup 
Once you have set the variables using `Start_set_variable.sh`, you can execute the main system setup script `Start_System_setup.sh`. This script will then use the variables you configured to perform the system setup tasks.

To run the main setup script:
```bash
cd Path/to/Script
./Start_System_setup.sh
```
The script will proceed with the automated setup based on your configuration.

## Scripts
This repository includes several scripts to assist with your Linux setup. Here's a brief overview:

-   `system_variables.sh`: This script contains variables related to system and user variables used by the setup scripts.
-   `Start_set_variables.sh`: This interactive script is used to set environment variables and configuration options, as detailed in the "How to Use" section.
-   `Start_System_setup.sh`: This is the primary script that orchestrates the execution of various system setup tasks based on the variables set.
-   `Start_ssh_server.sh`: This script starts or manages SSH server.
-   `Start_pihole_check.sh`: This script checks the status of a Pi-hole.
-   `Start_restart_wifi.sh`: This script is used to restart the Wi-Fi connection.
-   `Start_server_status.sh`: This script checks and reports the status of a server setup with Nginx/Docker and other services to add.
-   `Start_user_editor.sh`: This script is used to set up and manage users.
-   `Start_network_check.sh`: This script performs various network connectivity or configuration checks.

## Available Functions

Functions in the `Start_System_setup.sh` Script

### Update Functions

- `update_eos_mirrors`: Update EndeavourOS mirrors
- `update_arch_mirrors`: Update Arch Linux mirrors
- `update_pacman`: Update pacman packages
- `update_yay`: Update AUR packages
- `update_debian`: Update Debian packages
- `update_fedora`: Update Fedora packages
- `update_firmware`: Check and install firmware updates
- `remove_cache`: Remove pacman cache

### Install Functions
- `install_packages`: Install pacman and AUR packages
- `install_drivers`: Install graphics drivers

### Debug Functions

- `Debug_ntfs_drives`: Fix and mount NTFS USB drives

### Configuration Functions

- `configure_drives`: Mounts unmounted drives not yet added to fstab
- `configure_pacman_color`: Ensure pacman Color and ILoveCandy are set
- `configure_fish`: Set fish as default shell and add fzf as file management
- `configure_bluetooth`: Setup Bluetooth
- `configure_ssh`: Configure SSH keys and connection
- `configure_git`: Setup Git configuration
- `configure_environment`: Set up environment variables for Librewolf and Neovim
- `configure_dotfiles`: Setup dotfiles
- `configure_virtual_env`: Setup Virtual Machines
- `configure_ollama`: Configure Ollama AI
- `configure_razer`: Setup Open-Razer
- `configure_input_remapper`: Setup Input-Remapper
- `configure_fingerprint`: Setup fingerprint reader
- `configure_grub`: Configure GRUB bootloader
- `configure_timeshift`: Setup Timeshift backups
- `configure_grub_btrfsd`: Configure GRUB BTRFS
- `configure_network_manager`: Configure NetworkManager
- `configure_wifi`: Configure WiFi settings
- `configure_rust`: Configure Rust, if installed
- `configure_gnome_keyring`: Setup GNOME Keyring
- `configure_filepicker`: Configure file picker
- `configure_monitor`: Configure monitor settings
- `configure_onedrive`: Setup OneDrive
- `configure_onedrive_rclone`: Setup OneDrive (rclone)
- `sync_arch_to_nas`: Sync Arch to NAS
- `configure_nas_sync`: Setup NAS Sync for Onedrive
- `configure_wallpaper_path`: Configure wallpaper path
- `configure_hyprlock_wallpaper`: Configure Hyprlock wallpaper
- `configure_notification`: Configure Dunst Notification Daemon
- `configure_waydroid`: Configure Waydroid
- `configure_torbrowser`: Configure Tor Network/Browser

## Dependencies
This setup may depend on or integrate with other projects. A notable dependency is:

-   **Hyprland-Simple-Setup**: This project is designed with compatibility in mind for users who may also be using or integrating with my `Hyprland-Simple-Setup` repository:
    - The Functions: `configure_hyprlock_wallpaper` and `configure_dotfiles` depend on this repository.

Please ensure any external dependencies are met before running the function of the main script.

## Contributing
Contributions are welcome! If you'd like to contribute to this project, please feel free to fork the repository, make your changes, and submit a pull request.

## License
This project is licensed under the terms of the [LICENSE](LICENSE) file.
