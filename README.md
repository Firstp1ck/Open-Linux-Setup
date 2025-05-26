# Open-Linux-Setup
A Collection of Functions to Setup Linux (Tested for Arch Linux)

## Table of Contents
- [Overview](#overview)
- [Installation Guide](#installation-guide)
- [How to Use](#how-to-use)
    - [Setting Variables](#setting-variables)
    - [Running the Main Setup](#main-setup)
- [Scripts](#scripts)
- [Dependencies](#dependencies)
- [Contributing](#contributing)
- [License](#license)

## Overview
This project provides a collection of scripts to automate the setup of a Linux system, primarily tested on Arch Linux. It aims to streamline the post-installation configuration process by offering functions for various setup tasks.

## Installation Guide
To get started with Open-Linux-Setup:

1. **Clone the repository:**
   ```bash
   git clone YOUR_REPOSITORY_URL_HERE
   ```
   (Please replace `YOUR_REPOSITORY_URL_HERE` with the actual URL of your repository.)
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

## Dependencies
This setup may depend on or integrate with other projects. A notable dependency is:

-   **Hyprland_Simple_Setup**: This project is designed with compatibility in mind for users who may also be using or integrating with my `Hyprland_Simple_Setup` repository:
    - The Functions: `configure_hyprlock_wallpaper` and `configure_dotfiles` depend on this repository.

Please ensure any external dependencies are met before running the function of the main script.

## Contributing
Contributions are welcome! If you'd like to contribute to this project, please feel free to fork the repository, make your changes, and submit a pull request.

## License
This project is licensed under the terms of the [LICENSE](LICENSE) file.
