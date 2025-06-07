#!/usr/bin/env bash

############################################################## Disabled Shellcheck Messages ##############################################################

# shellcheck disable=SC2317 
# Command appears to be unreachable. Check usage (or ignore if invoked indirectly).

# shellcheck disable=SC2012
# Use find instead of ls to better handle non-alphanumeric filenames.

# shellcheck disable=SC2010
# Don't use ls | grep. Use a glob or a for loop with a condition to allow non-alphanumeric filenames.

# shellcheck disable=SC2011
# Use 'find .. -print0 | xargs -0 ..' or 'find .. -exec .. +' to allow non-alphanumeric filenames.

# shellcheck disable=SC1091
# Not following: /etc/os-release: openBinaryFile: does not exist (No such file or directory)

############################################################## Color and Symbol Definitions ##############################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CHECK_MARK=$'\e[1;32m\u2714\e[0m'
CROSS_MARK=$'\e[1;31m\u2718\e[0m'
CIRCLE=$'\u25CB'

############################################################## System Specific Variables ##############################################################

source ./system_variables.sh

LOG_FILE="$HOME/Linux-Setup.log"
NAS_LOG="/var/log/rsync_onedrive.log"

GOPRELOAD_DIR="/usr/share/gopreload"
REPO_CONFIG="/etc/pacman.conf"
FSTAB_CONFIG="/etc/fstab"

############################################################## Array Declaration ##############################################################

# Arrays to store update statuses
mirror_updates=()
package_updates=()
aur_updates=()
failed_packages=()
config_statuses=()

declare -a FILTERED_FUNCTIONS
declare -a FILTERED_DESCRIPTIONS
declare -a DRY_RUN_OPERATIONS=()

declare -a essential_tools=(
                            # Pacman packages
                            "lib32-gnutls" "lsscsi" "netctl" "ntp" "pavucontrol" "satty" "rclone" "dysk" "calcurse" "wev" "qalculate-gtk" "zoxide" "duf" "ark" "7zip" "gwenview" "lshw" "ntfs-3g" "dos2unix" "usbutils" "dolphin" "haruna" "gparted" "fzf" "fd" "sl" "bitwarden"
                            "xorg-apps" "xorg" "firewalld" "git" "gitui" "github-cli" "glab" "stow" "fish" "yazi" "filezilla" "kitty" "konsole" "neovim" "zellij"
                            "fastfetch" "onefetch" "btop" "nvtop" "iw" "openssh" "network-manager-applet" "networkmanager" "nm-connection-editor" "dnsutils" "bat" "lsd"
                            "tldr" "rsync" "timeshift" "grub-btrfs" "inotify-tools" "arch-wiki-docs" "vivaldi" "vivaldi-ffmpeg-codecs" "ffmpeg" "partitionmanager"
                            "noto-fonts" "ttf-nerd-fonts-symbols" "ttf-nerd-fonts-symbols-common" "ttf-nerd-fonts-symbols-mono" "ttf-opensans"
                            # AUR packages
                            "downgrade" "balena-etcher" "github-desktop-bin" "visual-studio-code-bin" "superfile-bin" "waypaper-git" "lsplug" "masterpdfeditor")

############################################################## Function Lists ##############################################################

# All available step functions
declare -A STEP_MAP=(
    [update_eos_mirrors]="Update EndeavourOS mirrors"
    [update_arch_mirrors]="Update Arch Linux mirrors"
    [update_pacman]="Update pacman packages"
    [update_yay]="Update AUR packages"
    [update_debian]="Update Debian packages"
    [update_fedora]="Update Fedora packages"
    [remove_cache]="Remove pacman cache"
    [configure_pacman_color]="Ensure pacman Color and ILoveCandy are set"
    [install_packages]="Install pacman and AUR packages"
    [install_drivers]="Install graphics drivers"
    [update_firmware]="Check and install firmware updates"
    [configure_drives]="Mounts unmounted drives not yet added to fstab"
    [Debug_ntfs_drives]="Fix and mount NTFS USB drives"
    [configure_fish]="Set fish as default shell and add fzf as file management"
    [configure_bluetooth]="Setup Bluetooth"
    [configure_ssh]="Configure SSH keys and connection"
    [configure_git]="Setup Git configuration"
    [configure_environment]="Set up environment variables for Librewolf and Neovim"
    [configure_dotfiles]="Setup dotfiles"
    [configure_virtual_env]="Setup Virtual Machines"
    [configure_ollama]="Configure Ollama AI"
    [configure_razer]="Setup Open-Razer"
    [configure_input_remapper]="Setup Input-Remapper"
    [configure_fingerprint]="Setup fingerprint reader"
    [configure_grub]="Configure GRUB bootloader"
    [configure_timeshift]="Setup Timeshift backups"
    [configure_grub_btrfsd]="Configure GRUB BTRFS"
    [configure_network_manager]="Configure NetworkManager"
    [configure_wifi]="Configure WiFi settings"
    [configure_rust]="Configure Rust, if installed"
    [configure_gnome_keyring]="Setup GNOME Keyring"
    [configure_filepicker]="Configure file picker"
    [configure_monitor]="Configure monitor settings"
    [configure_onedrive]="Setup OneDrive"
    [configure_onedrive_rclone]="Setup OneDrive (rclone)"
    [sync_arch_to_nas]="Sync Arch to NAS"
    [configure_nas_sync]="Setup NAS Sync for Onedrive"
    [configure_wallpaper_path]="Configure wallpaper path"
    [configure_hyprlock_wallpaper]="Configure Hyprlock wallpaper"
    [configure_notification]="Configure Dunst Notification Daemon"
    [configure_waydroid]="Configure Waydroid"
    [configure_torbrowser]="Configure Tor Network/Browser"
)

list_functions() {
    echo "Available functions:"
    echo "System Update and Maintenance:"
    echo "  update_eos_mirrors        - Update EndeavourOS mirrors"
    echo "  update_arch_mirrors       - Update Arch Linux mirrors"
    echo "  update_pacman             - Update pacman packages"
    echo "  update_yay                - Update AUR packages"
    echo "  update_debian             - Update Debian packages"
    echo "  update_fedora             - Update Fedora packages"
    echo "  remove_cache              - Remove pacman cache"
    echo "  update_arch               - Full update: mirrors, packages, AUR, and cache (Arch/EndeavourOS)"
    echo "  install_packages          - Install Pacman and AUR packages"
    echo "  install_drivers           - Install graphics drivers"
    echo "  update_firmware           - Check and install firmware updates"
    echo "  configure_drives          - Mount drives that are not yet in fstab"
    echo "  update_specific_package   - Update single or multiple Packages (Pacman/AUR)"
    echo "  system_backup             - Backup system files"
    echo "  restore_system_backup     - Restore system files from backup"
    echo "  verify_installed_packages - Verify all packages from the package lists are installed"
    echo "  Debug_ntfs_drives         - Fix and mount NTFS USB drives"

    echo -e "\nConfiguration Functions:"
    echo "  configure_fish            - Set fish as default shell and add fzf file management"
    echo "  configure_ssh             - Configure SSH keys and connection"
    echo "  configure_git             - Setup Git configuration"
    echo "  configure_environment     - Set up environment variables for Librewolf and Neovim"
    echo "  configure_dotfiles        - Setup dotfiles"
    echo "  configure_ollama          - Configure Ollama AI"
    echo "  configure_virtual_env     - Setup Virtual Machines"
    echo "  configure_razer           - Setup Open-Razer"
    echo "  configure_input_remapper  - Setup Input-Remapper"
    echo "  configure_grub            - Configure GRUB bootloader"
    echo "  configure_pacman_colors   - Configure pacman colors"
    echo "  configure_timeshift       - Setup Timeshift backups"
    echo "  configure_grub_btrfsd     - Configure GRUB BTRFS"
    echo "  configure_network_manager - Configure NetworkManager"
    echo "  configure_wifi            - Configure WiFi settings"
    echo "  configure_rust            - Configure Rust, if installed"
    echo "  configure_waydroid        - Setup Waydroid"
    echo "  configure_torbrowser      - Configures the Tor-Network to use with Tor Browser"
    echo "  configure_onedrive        - Setup OneDrive"
    echo "  configure_onedrive_rclone - Setup OneDrive (rclone)"
    echo "  sync_arch_to_nas          - Sync Arch to NAS"
    echo "  configure_nas_sync        - Setup NAS Sync for Onedrive"
    echo "  configure_fingerprint     - Setup fingerprint reader"

    echo -e "\nHyprland Specific:"
    echo "  configure_bluetooth       - Setup Bluetooth"
    echo "  configure_hyprpaper       - Configure Hyprpaper"
    echo "  configure_wallpaper_path  - Configure wallpaper path"
    echo "  configure_hyprlock_wallpaper - Configure Hyprlock wallpaper"
    echo "  configure_gnome_keyring   - Setup GNOME Keyring"
    echo "  configure_filepicker      - Configure file picker"
    echo "  configure_monitor         - Configure monitor settings"
    echo "  configure_notification    - Configure dunst with systemd"

    echo -e "\nOptional Functions:"
    echo "  install_essential_tools - Install essential packages"

    #TODO Functions not working yet
    # echo "  endeavouros_package_manager - Add EOS Package Manager for Arch"
    # echo "  install_cachyos    - Add CachyOS Kernel, Chaotic AUR and CachyOS repos"
    # echo "  configure_numpad          - Configure ASUS NumberPad Driver"
    # echo "  configure_preload         - Setup Preloading Programs at startup"
    # echo "  configure_cooler          - Setup CPU Cooler Status Viewer"
}

# Define your setup sequence
setup_sequence=(
    "update_arch_mirrors"
    "update_eos_mirrors"
    "update_pacman"
    "update_yay"
    "update_debian"
    "update_fedora"
    "remove_cache"
    "update_firmware"
    "configure_pacman_color"
    "install_essential_tools"
    "endeavouros_package_manager"
    "install_packages"
    "install_drivers"
    "install_cachyos"
    "configure_environment"
    "configure_fish"
    "configure_ssh"
    "configure_git"
    "configure_rust"
    "configure_network_manager"
    "configure_wifi"
    "configure_drives"
    "configure_timeshift"
    "configure_grub_btrfsd"
    "configure_grub"
    "configure_gnome_keyring"
    "configure_filepicker"
    "configure_monitor"
    "configure_notification"
    "configure_wallpaper_path"
    "configure_hyprlock_wallpaper"
    "configure_bluetooth"
    "configure_fingerprint"
    "configure_input_remapper"
    "configure_razer"
    "configure_numpad"
    "configure_ollama"
    "configure_virtual_env"
    "configure_onedrive"
    "configure_onedrive_rclone"
    "sync_arch_to_nas"
    "configure_nas_sync"
    "configure_waydroid"
    "configure_torbrowser"
    "configure_preload"
    "configure_dotfiles"
    "Debug_ntfs_drives"
)

# Default steps to run in --default mode (order matters)
default_steps=(
    "update_arch_mirrors"
    "update_pacman"
    "update_yay"
    "remove_cache"
    "configure_pacman_color"
    "install_essential_tools"
    "configure_drives"
    "configure_fish"
    "configure_environment"
    "configure_dotfiles"
    "configure_timeshift"
    "configure_grub_btrfsd"
    "configure_network_manager"
    "configure_wifi"
)

# Core functions always included in menu selection
core_functions=(
    "configure_drives"
    "Debug_ntfs_drives"
    "configure_ssh"
    "configure_git"
    "configure_environment"
    "configure_fish"
    "configure_network_manager"
    "configure_wifi"
    "configure_fingerprint"
    "configure_onedrive"
    "configure_onedrive_rclone"
    "sync_arch_to_nas"
    "configure_nas_sync"
    "configure_dotfiles"
)

# Functions specific to Arch/EndeavourOS
arch_functions=(
    "update_pacman"
    "update_arch_mirrors"
    "update_yay"
    "install_packages"
    "install_drivers"
    "update_firmware"
    "configure_grub"
    "configure_grub_btrfsd"
    "configure_timeshift"
    "configure_ollama"
    "configure_virtual_env"
    "configure_input_remapper"
    "configure_razer"
)
# EndeavourOS only:
eos_functions=(
    "update_eos_mirrors"
)

# Functions specific to Hyprland
hyprland_functions=(
    "configure_bluetooth"
    "configure_hyprpaper"
    "configure_hyprlock_wallpaper"
    "configure_wallpaper_path"
    "configure_gnome_keyring"
    "configure_filepicker"
    "configure_notification"
    "configure_torbrowser"
    "configure_monitor"
)

# Functions specific to GNOME
gnome_functions=(
    "configure_gnome_keyring"
)

# Functions specific to KDE Plasma
kde_functions=(
    # Add KDE-specific functions here if needed
)

xfce_functions=(
    # Add XFCE-specific functions here if needed
)

# Functions specific to Debian-based distros
debian_functions=(
    "update_debian"
)

# Functions specific to Fedora/RHEL-based distros
fedora_functions=(
    "update_fedora"
)

############################################################## Helper Functions ##############################################################

is_windows() {
    case "$(uname -s)" in
        *CYGWIN*|*MINGW*|*MSYS*|*Windows_NT*) return 0 ;;
        *) return 1 ;;
    esac
}

is_dry_run() {
if is_windows; then
        print_warning "Running on Windows - forcing dry-run mode"
        return 0
    fi
    [[ "$DRY_RUN" == "true" ]]
}

log_dry_run_operation() {
    local function_name="$1"
    local operation="$2"
    DRY_RUN_OPERATIONS+=("[$function_name] $operation")
}

execute_command() {
    local cmd="$1"
    local description="$2"
    local caller_function="${FUNCNAME[1]}"

    print_verbose "About to execute: $cmd (Description: $description)"

    # Regular command handling
    if is_dry_run; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
        echo -e "${YELLOW}[DRY-RUN]${NC} Description: $description"
        log_dry_run_operation "$caller_function" "$description"
        return 0
    else
        bash -c "$cmd"
        local exit_code=$?
        print_verbose "Command executed: $cmd (Exit code: $exit_code)"
        if [ $exit_code -ne 0 ]; then
            print_warning "Command for '$description' failed."
        fi
        return $exit_code
    fi
}

prompt_yes_no() {
    local prompt="$1"
    while true; do
        read -rp "$prompt (y/n): " yn
        # Default to 'Yy' if nothing is entered
        if [[ -z "$yn" ]]; then
            yn="y"
        fi
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

announce_step() {
    local step="$1"
    echo -e "\n${GREEN}=== $step ===${NC}\n"
}

extended_announce_step() {
    local step="$1"
    echo -e "\n${GREEN}========= $step =========${NC}\n"
}

print_dry_run_summary() {
    if [ ${#DRY_RUN_OPERATIONS[@]} -eq 0 ]; then
        echo -e "\n${YELLOW}[DRY-RUN SUMMARY]${NC} No operations were recorded."
        return
    fi

    echo -e "\n${YELLOW}[DRY-RUN SUMMARY]${NC} The following operations would have been performed:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local current_function=""
    local count=0

    for operation in "${DRY_RUN_OPERATIONS[@]}"; do
        # Extract function name from the operation string
        local function_name
        function_name=$(echo "$operation" | cut -d']' -f1 | sed 's/\[//')

        local op_description
        op_description=$(echo "$operation" | cut -d']' -f2- | sed 's/^ //')

        # Print function header when we move to a new function
        if [[ "$function_name" != "$current_function" ]]; then
            if [[ -n "$current_function" ]]; then
                echo "  Total: $count operation(s)"
                echo ""
            fi
            echo -e "${GREEN}▶ $function_name${NC}"
            current_function="$function_name"
            count=0
        fi

        # Print the operation description
        echo "  • $op_description"
        ((count++))
    done

    # Print the count for the last function
    if [[ -n "$current_function" ]]; then
        echo "  Total: $count operation(s)"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}[DRY-RUN]${NC} No actual changes were made to your system."
}

distro_install() {
    local -a packages
    packages=("$@")
    case "$DISTRO" in
        debian|ubuntu)
            execute_command "sudo apt install -y ${packages[*]}" "Install packages: ${packages[*]}"
            ;;
        fedora)
            execute_command "sudo dnf install -y ${packages[*]}" "Install packages: ${packages[*]}"
            ;;
        arch|endeavouros)
            if ! execute_command "sudo pacman -S --needed --noconfirm ${packages[*]}" "Install packages: ${packages[*]}"; then
                print_warning "pacman failed, trying yay as fallback for: ${packages[*]}"
                if execute_command "yay -S --needed --noconfirm ${packages[*]}" "Install packages with yay: ${packages[*]}"; then
                    print_message "yay fallback install succeeded for: ${packages[*]}"
                    return 0
                else
                    print_error "Both pacman and yay failed to install: ${packages[*]}"
                    return 1
                fi
            else
                print_message "pacman install succeeded for: ${packages[*]}"
                return 0
            fi
            ;;
        *)
            print_warning "Distro '$DISTRO' not supported for package installation."
            return 1
            ;;
    esac
}

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]
or set alias and add to environment path in your shell configuration file (e.g. ~/.bashrc or ~/.zshrc) to use as 'setup':

Fish Example for alias:
    alias setup='Start_System_setup.sh'

EOF
    cat <<'EOF'
Fish example for setting environment path: 
    set -x SCRIPTS_DIR "$SETUP_DIR/Scripts"
    set -x PATH "$PATH:$SCRIPTS_DIR"

Fish example for automatically making scripts executable in the set path:
    if test -d "$SCRIPTS_DIR"
        find "$SCRIPTS_DIR" -type f \( -name "*.sh" -o -name "*.desktop" \) -exec chmod +x {} \;
    end

EOF
    cat <<EOF
Options:
  --dry-run         Simulate actions without making changes
  --function NAME   Run only the specified function
  --list            List all available functions
  --default         Run the default set of steps
  --verbose         Enable verbose output
  --help            Show this help message

Examples:
  $0 --dry-run
  $0 --function configure_dotfiles
  $0 --default

EOF
}

# Function to filter steps based on desktop environment and distro
filter_available_steps() {
    local detected_de
    detected_de=$(check_desktop_environment)
    print_message "Detected desktop environment: $detected_de"

    # Build a list of applicable steps as "function_name|description"
    local -a step_pairs=()

    for function_name in "${!STEP_MAP[@]}"; do
        local add_function=false

        # First check if it's a core function
        if [[ " ${core_functions[*]} " =~ ${function_name} ]]; then
            add_function=true
        else
            # Distribution-specific functions
            case "$DISTRO" in
                arch|endeavouros)
                    if [[ " ${arch_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    if [[ "$DISTRO" == "endeavouros" && " ${eos_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
                debian|ubuntu)
                    if [[ " ${debian_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
                fedora|centos|rhel)
                    if [[ " ${fedora_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
            esac

            # Desktop environment specific functions
            case "$detected_de" in
                Hyprland|hyprland)
                    if [[ " ${hyprland_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
                KDE|kde|plasma|PLASMA)
                    if [[ " ${kde_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
                GNOME|gnome)
                    if [[ " ${gnome_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
                XFCE|xfce)
                    if [[ " ${xfce_functions[*]} " =~ ${function_name} ]]; then
                        add_function=true
                    fi
                    ;;
            esac
        fi

        if $add_function && [[ -n "${STEP_MAP[$function_name]}" ]]; then
            step_pairs+=("$function_name|${STEP_MAP[$function_name]}")
        fi
    done

    # Sort step_pairs by description (after the |)
    mapfile -t sorted_pairs < <(printf '%s\n' "${step_pairs[@]}" | sort -t'|' -k2,2)
    unset IFS

    FILTERED_FUNCTIONS=()
    FILTERED_DESCRIPTIONS=()
    for pair in "${sorted_pairs[@]}"; do
        FILTERED_FUNCTIONS+=("${pair%%|*}")
        FILTERED_DESCRIPTIONS+=("${pair#*|}")
    done
}

# Replace the show_menu function to use the filtered arrays
show_menu() {
    echo -e "\n${YELLOW}System Setup Menu:${NC}"
    local i=1
    for ((i=0; i<${#FILTERED_FUNCTIONS[@]}; i++)); do
        echo "  $((i+1))) ${FILTERED_DESCRIPTIONS[$i]}"
    done
    echo "  a) All applicable steps"
    echo "  e) All steps with exceptions"
    echo "  d) Default (run all without interaction)"
    echo "  m) Select multiple steps by number (e.g., 1 5 7)"
    echo "  q) Quit"
}

# Function to select exceptions from the available steps
select_exceptions() {
    local exceptions=()
    echo -e "\n${YELLOW}Select steps to EXCLUDE (e.g. 1 3 5 or 'q' to finish):${NC}"
    local i=1
    for ((i=0; i<${#FILTERED_FUNCTIONS[@]}; i++)); do
        echo "  $((i+1))) ${FILTERED_DESCRIPTIONS[$i]}"
    done
    echo "  q) Done selecting exceptions"

    while true; do
        read -rp "> " choices
        if [[ "$choices" == "q" ]]; then
            break
        fi

        # Process multiple selections
        for choice in $choices; do
            if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice > 0)) && ((choice <= ${#FILTERED_FUNCTIONS[@]})); then
                local step="${FILTERED_FUNCTIONS[$((choice-1))]}"
                if [[ ! " ${exceptions[*]} " =~ ${step} ]]; then
                    exceptions+=("$step")
                    echo "Added to exceptions: ${FILTERED_DESCRIPTIONS[$((choice-1))]}"
                else
                    echo "Already in exceptions list: ${FILTERED_DESCRIPTIONS[$((choice-1))]}"
                fi
            elif [[ "$choice" != "q" ]]; then
                echo "Invalid choice: $choice"
            fi
        done
    done

    # Create array of all steps minus exceptions
    local all_steps=("${FILTERED_FUNCTIONS[@]}")
    for exception in "${exceptions[@]}"; do
        all_steps=("${all_steps[@]/$exception}")
    done
    # Remove empty elements
    mapfile -t all_steps < <(printf '%s\n' "${all_steps[@]}" | grep -v '^$')

    echo -e "\n${GREEN}You have selected to run all steps EXCEPT:${NC}"
    for exception in "${exceptions[@]}"; do
        for i in "${!FILTERED_FUNCTIONS[@]}"; do
            if [[ "${FILTERED_FUNCTIONS[$i]}" = "${exception}" ]]; then
                echo "  - ${FILTERED_DESCRIPTIONS[$i]}"
                break
            fi
        done
    done
    echo
    if ! prompt_yes_no "Proceed?"; then
        echo "Aborted."
        handle_error
    fi
}

# Function to run all steps without interaction
run_default() {
    announce_step "Running in default mode - executing predefined set of steps without interaction"

    # Use the default_steps array from the top of the script
    local steps=("${default_steps[@]}")
    if [[ "$DISTRO" == "endeavouros" ]]; then
        steps=("update_eos_mirrors" "${steps[@]}")
    fi

    # Filter the steps based on what's actually available
    SELECTED_STEPS=()
    for step in "${steps[@]}"; do
        if declare -f "$step" > /dev/null; then
            SELECTED_STEPS+=("$step")
        else
            print_warning "Default step '$step' not found in available functions"
        fi
    done

    echo -e "\n${GREEN}Default steps to be executed:${NC}"
    for step in "${SELECTED_STEPS[@]}"; do
        for i in "${!FILTERED_FUNCTIONS[@]}"; do
            if [[ "${FILTERED_FUNCTIONS[$i]}" = "$step" ]]; then
                echo "  - ${FILTERED_DESCRIPTIONS[$i]}"
                break
            fi
        done
        if [[ "$step" == "install_essential_tools" ]]; then
            echo "  - Install essential pacman packages (non-interactive)"
        elif [[ "$step" == "install_aur_essential_tools" ]]; then
            echo "  - Install essential AUR packages (non-interactive)"
        fi
    done
    echo

    return 0
}

# Update the get_user_choices function to use the filtered arrays
get_user_choices() {
    # First detect the distro if not already done
    if [ -z "$DISTRO" ]; then
        check_distro
    fi

    # Filter available steps based on environment
    filter_available_steps

    # Sort the FILTERED_FUNCTIONS array based on the setup_sequence order
    local -a sorted_functions=()
    local -a sorted_descriptions=()
    
    # First add functions that exist in setup_sequence
    for func in "${setup_sequence[@]}"; do
        for i in "${!FILTERED_FUNCTIONS[@]}"; do
            if [[ "${FILTERED_FUNCTIONS[$i]}" == "$func" ]]; then
                sorted_functions+=("$func")
                sorted_descriptions+=("${FILTERED_DESCRIPTIONS[$i]}")
                break
            fi
        done
    done

    # Then add any remaining functions that weren't in setup_sequence
    for i in "${!FILTERED_FUNCTIONS[@]}"; do
        if [[ ! " ${sorted_functions[*]} " =~ ${FILTERED_FUNCTIONS[$i]} ]]; then
            sorted_functions+=("${FILTERED_FUNCTIONS[$i]}")
            sorted_descriptions+=("${FILTERED_DESCRIPTIONS[$i]}")
        fi
    done

    # Replace the original arrays with sorted ones
    FILTERED_FUNCTIONS=("${sorted_functions[@]}")
    FILTERED_DESCRIPTIONS=("${sorted_descriptions[@]}")

    while true; do
        show_menu

        read -rp "> " choice

        case "$choice" in
            [0-9]*)
                if [ "$choice" -ge 1 ] && [ "$choice" -le "${#FILTERED_FUNCTIONS[@]}" ]; then
                    SELECTED_STEPS=("${FILTERED_FUNCTIONS[$((choice-1))]}")
                else
                    print_warning "Invalid choice: $choice"
                    continue
                fi
                break
                ;;
            a)
                SELECTED_STEPS=("${FILTERED_FUNCTIONS[@]}")
                break
                ;;
            e)
                local exceptions=()
                echo -e "\n${YELLOW}Select steps to EXCLUDE (e.g. 1 3 5 or 'q' to finish):${NC}"
                local i=1
                for ((i=0; i<${#FILTERED_FUNCTIONS[@]}; i++)); do
                    echo "  $((i+1))) ${FILTERED_DESCRIPTIONS[$i]}"
                done
                echo "  q) Done selecting exceptions"

                while true; do
                    read -rp "> " choices
                    if [[ "$choices" == "q" ]]; then
                        break
                    fi

                    # Process multiple selections
                    for choice in $choices; do
                        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice > 0)) && ((choice <= ${#FILTERED_FUNCTIONS[@]})); then
                            local step="${FILTERED_FUNCTIONS[$((choice-1))]}"
                            if [[ ! " ${exceptions[*]} " =~ ${step} ]]; then
                                exceptions+=("$step")
                                echo "Added to exceptions: ${FILTERED_DESCRIPTIONS[$((choice-1))]}"
                            else
                                echo "Already in exceptions list: ${FILTERED_DESCRIPTIONS[$((choice-1))]}"
                            fi
                        elif [[ "$choice" != "q" ]]; then
                            echo "Invalid choice: $choice"
                        fi
                    done
                done

                # Create array of all steps minus exceptions
                SELECTED_STEPS=("${FILTERED_FUNCTIONS[@]}")
                for exception in "${exceptions[@]}"; do
                    SELECTED_STEPS=("${SELECTED_STEPS[@]/$exception}")
                done
                # Remove empty elements
                mapfile -t SELECTED_STEPS < <(printf '%s\n' "${SELECTED_STEPS[@]}" | grep -v '^$')

                echo -e "\n${GREEN}You have selected to run all steps EXCEPT:${NC}"
                for exception in "${exceptions[@]}"; do
                    for i in "${!FILTERED_FUNCTIONS[@]}"; do
                        if [[ "${FILTERED_FUNCTIONS[$i]}" = "${exception}" ]]; then
                            echo "  - ${FILTERED_DESCRIPTIONS[$i]}"
                            break
                        fi
                    done
                done
                echo
                if ! prompt_yes_no "Proceed?"; then
                    echo "Aborted."
                    handle_error
                fi
                break
                ;;
            d)
                if run_default; then
                    break
                fi
                ;;
            m) # Handle multiple selection by number
                local selected_indices=()
                SELECTED_STEPS=() # Clear previous selection

                echo -e "\n${YELLOW}Enter step numbers to INCLUDE (space-separated, e.g., 1 5 7):${NC}"
                local i=1
                for ((i=0; i<${#FILTERED_FUNCTIONS[@]}; i++)); do
                    echo "  $((i+1))) ${FILTERED_DESCRIPTIONS[$i]}"
                done
                read -rp "> " choices_list

                read -ra selected_indices <<< "$choices_list"
                local valid=true
                for index_str in "${selected_indices[@]}"; do
                    if [[ "$index_str" =~ ^[0-9]+$ ]]; then
                        local index=$((index_str-1))
                        if [ "$index" -ge 0 ] && [ "$index" -lt "${#FILTERED_FUNCTIONS[@]}" ]; then
                            SELECTED_STEPS+=("${FILTERED_FUNCTIONS[$index]}")
                        else
                            print_warning "Invalid step number: $index_str. Skipping."
                            valid=false
                        fi
                    else
                        print_warning "Invalid input: '$index_str'. Skipping."
                        valid=false
                    fi
                done

                if [ ${#SELECTED_STEPS[@]} -eq 0 ]; then
                    print_warning "No valid steps selected. Returning to menu."
                    continue # Go back to the main menu
                fi

                echo -e "\n${GREEN}You have selected:${NC}"
                for step in "${SELECTED_STEPS[@]}"; do
                    for i in "${!FILTERED_FUNCTIONS[@]}"; do
                        if [[ "${FILTERED_FUNCTIONS[$i]}" = "$step" ]]; then
                            echo "  - ${FILTERED_DESCRIPTIONS[$i]}"
                            break
                        fi
                    done
                done
                echo
                if ! prompt_yes_no "Proceed with selected steps?"; then
                    echo "Aborted."
                    handle_error
                fi
                break # Exit the while loop after processing multiple choices
                ;;
            q)
                echo "Exiting."
                exit 0
                ;;
            *)
                print_warning "Invalid choice. Please try again."
                ;;
        esac
    done

    if [[ ${#SELECTED_STEPS[@]} -eq 0 ]]; then
        handle_error "No steps selected. Exiting script."
    fi

    if [ "$choice" != "d" ]; then
        echo -e "\n${GREEN}You have selected:${NC}"
        for step in "${SELECTED_STEPS[@]}"; do
            for i in "${!FILTERED_FUNCTIONS[@]}"; do
                if [[ "${FILTERED_FUNCTIONS[$i]}" = "$step" ]]; then
                    echo "  - ${FILTERED_DESCRIPTIONS[$i]}"
                    break
                fi
            done
        done
        echo
        if ! prompt_yes_no "Proceed?"; then
            echo "Aborted."
            handle_error
        fi
    fi
}

############################################################## Verbosity and Error Handling Functions ##############################################################

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}[VERBOSE]${NC} $1"
    fi
}

handle_error() {
    local msg="$1"
    log_message "ERROR" "$msg"
    echo -e "${RED}[ERROR]${NC} $msg"
    exit 1
}

log_message() {
    local log_level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %T")
    echo "[$timestamp] [$log_level] $message" >> "$LOG_FILE"
}
# Function to print colored messages
print_message() {
    log_message "DEBUG" "$1"  # Log the debug message
    echo -e "${GREEN}[*] $1${NC}"
}

print_warning() {
    log_message "WARNING" "$1"  # Log the warning message
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    log_message "ERROR" "$1"  # Log the error message
    echo -e "${RED}[ERROR] $1${NC}"
}

print_status_summary() {
    echo -e "\n${GREEN}========= INSTALLATION SUMMARY =========${NC}"
    echo "Log file: $LOG_FILE"

    # Package installation results
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo -e "${RED}Failed packages:${NC}"
        for pkg in "${failed_packages[@]}"; do
            echo "  - $pkg"
        done
    else
        echo -e "${GREEN}All packages installed successfully!${NC}"
    fi

    # Configuration results
    if [ ${#config_statuses[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Configuration Status:${NC}"
        for status in "${config_statuses[@]}"; do
            echo -e "  $status"
        done
        # Count failed configurations
        local failed_count=0
        for status in "${config_statuses[@]}"; do
            if [[ "$status" == *"$CROSS_MARK"* ]]; then
                ((failed_count++))
            fi
        done
        if [ "$failed_count" -gt 0 ]; then
            print_warning "Total failed configurations: $failed_count"
        else
            print_message "All configurations completed successfully!"
        fi
    else
        print_message "No configurations were processed"
    fi

    # Package verification
    echo -e "\n${GREEN}Package Verification:${NC}"
    verify_installed_packages

    echo -e "\n${GREEN}========================================${NC}\n"
}

track_config_status() {
    local config_name="$1"
    local status="$2"
    config_statuses+=("$config_name: $status")
}

list_packages() {
    announce_step "Generating Package Lists (user-installed and AUR packages)..."
    local date_suffix packages_file aur_file is_endeavouros is_debian_based
    date_suffix=$(date +%Y-%m-%d)
    packages_file="$HOME/user_installed_packages_${date_suffix}.txt"
    aur_file="$HOME/aur_packages_${date_suffix}.txt"
    is_endeavouros=false
    is_debian_based=false

    if command -v eos-packagelist &> /dev/null && grep -q "EndeavourOS" /etc/os-release; then
        is_endeavouros=true
        print_message "EndeavourOS detected - will exclude default EndeavourOS packages."
    elif command -v apt &> /dev/null && (grep -q "Debian\\|Ubuntu\\|Mint" /etc/os-release || [ -f /etc/debian_version ]); then
        is_debian_based=true
        print_message "Debian-based system detected - will list manually installed packages."
    else
        print_message "Arch Linux detected - will list all explicitly installed packages."
    fi

    print_message "This utility will generate:"
    print_message "  1. A list of manually installed packages"
    if [ "$is_endeavouros" = true ]; then
        print_message "     (excluding EndeavourOS default packages)"
    elif [ "$is_debian_based" = true ]; then
        print_message "     (using apt-mark showmanual)"
    fi
    print_message "  2. A separate list of AUR packages"
    if [ "$is_debian_based" = true ]; then
        print_message "     (not applicable on Debian-based systems)"
    fi

    print_message "Generating package lists..."
    if [ "$is_endeavouros" = true ]; then
        echo -e "# User installed packages (excluding EndeavourOS defaults)" > "$packages_file"
    elif [ "$is_debian_based" = true ]; then
        echo -e "# Manually installed packages on Debian-based system" > "$packages_file"
    else
        echo -e "# User installed packages on Arch Linux" > "$packages_file"
    fi
    echo -e "# Generated on: $(date)\n" >> "$packages_file"

    if [ "$is_debian_based" = false ]; then
        echo -e "# AUR packages installed on the system" > "$aur_file"
        echo -e "# Generated on: $(date)\n" >> "$aur_file"
    fi

    print_message "Processing main package list..."
    if [ "$is_endeavouros" = true ]; then
        execute_command "comm -23 <(pacman -Qqet | sort) <(eos-packagelist KDE-Desktop 'EndeavourOS applications' 'Recommended applications selection' 'Spell Checker and language package' 'Firewall' 'LTS kernel in addition' 'Printing support' 'HP printer/scanner support' | sort) >> '$packages_file'" "List user packages (EndeavourOS)"
    elif [ "$is_debian_based" = true ]; then
        execute_command "apt-mark showmanual >> '$packages_file'" "List manually installed packages (Debian)"
    else
        execute_command "pacman -Qqet >> '$packages_file'" "List explicitly installed packages (Arch)"
    fi
    print_message "Main package list done."

    if [ "$is_debian_based" = false ]; then
        print_message "Processing AUR package list..."
        execute_command "pacman -Qqm >> '$aur_file'" "List AUR packages"
        print_message "AUR package list done."
    fi

    print_message "Package lists have been saved to:"
    print_message "  Main package list: $packages_file"
    print_message "  AUR package list: $aur_file"
    print_message "Total packages found: $(grep -v '^#' "$packages_file" | wc -l)"
    print_message "Total AUR packages found: $(grep -v '^#' "$aur_file" | wc -l)"
    print_message "Thank you for using the Package Installation History Utility!"
}

verify_installed_packages() {
    extended_announce_step "VERIFYING INSTALLED PACKAGES"

    # Find the newest package list files
    local user_pkg_file
    user_pkg_file=$(ls -t "$HOME"/user_installed_packages_* 2>/dev/null | head -n1)
    local aur_pkg_file
    aur_pkg_file=$(ls -t "$HOME"/aur_packages_* 2>/dev/null | head -n1)

    if [ -z "$user_pkg_file" ] && [ -z "$aur_pkg_file" ]; then
        print_warning "No package list files found in $HOME. Generating new package lists..."
        list_packages
        # Re-find the files after generation
        user_pkg_file=$(ls -t "$HOME"/user_installed_packages_* 2>/dev/null | head -n1)
        aur_pkg_file=$(ls -t "$HOME"/aur_packages_* 2>/dev/null | head -n1)
        if [ -z "$user_pkg_file" ] && [ -z "$aur_pkg_file" ]; then
            print_error "Failed to generate package list files."
            track_config_status "Package Verification" "$CROSS_MARK"
            return 1
        fi
    fi

    local missing_packages=()
    local total_checked=0
    local total_missing=0

    # Check standard packages
    if [ -n "$user_pkg_file" ]; then
        print_message "Checking packages from: $(basename "$user_pkg_file")"
        while IFS= read -r package; do
            # Skip empty lines and comments
            [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue

            ((total_checked++))
            if ! pacman -Qi "$package" &>/dev/null; then
                missing_packages+=("$package (Pacman)")
                ((total_missing++))
            fi
        done < "$user_pkg_file"
    fi

    # Check AUR packages
    if [ -n "$aur_pkg_file" ]; then
        print_message "Checking packages from: $(basename "$aur_pkg_file")"
        while IFS= read -r package; do
            # Skip empty lines and comments
            [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue

            ((total_checked++))
            if ! pacman -Qi "$package" &>/dev/null; then
                missing_packages+=("$package (AUR)")
                ((total_missing++))
            fi
        done < "$aur_pkg_file"
    fi

    # Report results
    if [ ${#missing_packages[@]} -eq 0 ]; then
        print_message "All packages from the lists are installed! ✅"
        print_message "Total packages checked: $total_checked"
        track_config_status "Package Verification" "$CHECK_MARK"
    else
        print_warning "Missing packages ($total_missing out of $total_checked total packages):"
        printf '\n%s\n' "Missing Packages:"
        printf '=====================================\n'
        printf '%s\n' "${missing_packages[@]}" | column
        printf '=====================================\n'
        track_config_status "Package Verification" "$CROSS_MARK"
    fi
}

############################################################## Check Functions ##############################################################

check_bootloader() {
    local bootloader="Unknown"

    if [ -d /sys/firmware/efi ]; then
        print_message "System is booted in UEFI mode."
    else
        print_message "System is booted in legacy BIOS mode."
    fi

    if [ -f /boot/grub/grub.cfg ] || [ -f /boot/grub2/grub.cfg ] || command -v grub-install &>/dev/null; then
        bootloader="GRUB"
    elif [ -d /boot/loader ] || [ -f /boot/loader/loader.conf ] || command -v bootctl &>/dev/null; then
        bootloader="systemd-boot"
    elif [ -d /EFI/refind ] || [ -f /boot/EFI/refind/refind.conf ] || command -v refind-install &>/dev/null; then
        bootloader="rEFInd"
    elif [ -f /boot/syslinux/syslinux.cfg ] || command -v syslinux &>/dev/null; then
        bootloader="Syslinux"
    fi

    print_message "Detected bootloader: $bootloader"
    export BOOTLOADER="$bootloader"
}

check_yay() {
    if ! command -v yay &> /dev/null; then
        print_message "yay is not installed. Installing yay..."

        if is_windows; then
            print_message "Running on Windows - skipping yay installation"
            return 0
        fi

        # Make sure git is installed
        if ! command -v git &> /dev/null; then
            print_message "Installing git and base-devel"
            distro_install "git base-devel"
        fi

        # Clone the yay repo and build it
        execute_command "git clone https://aur.archlinux.org/yay.git /tmp/yay" "Clone yay repository"
        cd /tmp/yay > /dev/null || return 
        execute_command "makepkg -si --noconfirm" "Build and install yay"

        # Verify installation was successful
        if ! command -v yay &> /dev/null; then
            handle_error "'yay' installation failed. Please install yay manually and re-run the script."
        else
            print_message "yay installed successfully!"
        fi
    else
        print_message "yay is already installed."
    fi
}

check_disk_space() {
    local required_space=10000000  # 10GB in KB
    local available_space
    available_space=$(df /usr | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$required_space" ]; then
        handle_error "Insufficient disk space. At least 10GB required in /usr."
    else
        print_message "Sufficient disk space available: $((available_space / 1024)) MB"
    fi
}

check_dependencies() {
    local deps=("git" "curl" "wget" "sudo" "reflector")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            handle_error "Dependency '$dep' is missing. Please install '$dep' and re-run the script."
        else
            print_message "Dependency '$dep' is installed."
        fi
    done

    # Check if running on an Arch-based distribution
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$ID" == "arch" || "$ID" == "endeavouros" || "$ID" == "chachyos" ]]; then
            # Special check for base-devel package group
            if ! pacman -Q base-devel &> /dev/null; then
                handle_error "Package group 'base-devel' is missing. Please install it using 'sudo pacman -S base-devel' and re-run the script."
            else
                print_message "Package group 'base-devel' is installed."
            fi
        fi
    fi
}

check_distro() {
    if is_windows; then
        print_message "Running on Windows in dry-run mode. Simulating Arch Linux environment."
        DISTRO="arch"
        return 0
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_message "Detected distro: $ID"
        DISTRO=$ID
    else
        handle_error "Could not detect Linux distribution. Ensure /etc/os-release exists and is readable."
    fi
}

# Function to detect the current desktop environment
check_desktop_environment() {
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP"
    elif [ -n "$DESKTOP_SESSION" ]; then
        echo "$DESKTOP_SESSION"
    elif execute_command "pgrep -x plasmashell > /dev/null"; then
        echo "KDE"
    elif execute_command "pgrep -x Hyprland > /dev/null" || [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        echo "Hyprland"
    elif execute_command "pgrep -x gnome-shell > /dev/null"; then
        echo "GNOME"
    elif execute_command "pgrep -x xfce4-session > /dev/null"; then
        echo "XFCE"
    else
        echo "Unknown"
    fi
}

check_hyprland() {
    print_message "Checking if Hyprland is running"
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
        return 0
    else
        return 1
    fi
}

check_environment() {
    local required_vars=("HOME" "USER" "SHELL" "PATH" "LANG" "PWD")
    local missing_vars=()

    # Check required environment variables
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        handle_error "Missing required environment variables: ${missing_vars[*]}"
    fi

    # Check if running with correct permissions
    if [ "$(id -u)" -eq 0 ]; then
        handle_error "Script is being run as root. Please run as a regular user with sudo privileges."
    fi

    # Check if sudo is available and user has sudo rights
    if ! command -v sudo >/dev/null; then
        handle_error "'sudo' is not installed. Please install sudo and re-run the script."
    elif ! sudo -l &>/dev/null; then
        handle_error "Current user does not have sudo privileges. Please add your user to the sudoers file."
    fi

    # Validate log directory and permissions
    local logdir
    logdir=$(dirname "$LOG_FILE")
    if [ ! -d "$logdir" ]; then
        mkdir -p "$logdir" || { handle_error "Cannot create log directory: $logdir. Check permissions."; }
    fi
    if [ ! -w "$logdir" ]; then
        handle_error "Log directory $logdir is not writable. Check permissions."
    fi

    print_message "Environment validation successful"
}

check_directories() {
    local directories=(
        "$HOME/.config"
        "$HOME/.local/share"
        "$HOME/.local/bin"
        "$HOME/.cache"
        "$HOME/$DOWNLOADS_DIR"
        "$HOME/$DOCUMENTS_DIR"
        "$HOME/.ssh"
    )
    local failed=0

    # Check existence and permissions of critical directories
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            print_message "Creating directory: $dir"
            mkdir -p "$dir" || {
                print_error "Failed to create directory: $dir"
                ((failed++))
                continue
            }
        fi

        # Check directory permissions
        if [ ! -w "$dir" ]; then
            print_error "Directory not writable: $dir"
            ((failed++))
        fi
    done

    # Check disk space in critical directories
    local min_space=1048576  # 1GB in KB
    for dir in "$HOME" "/tmp" "/var"; do
        local available
        available=$(df -k "$dir" | awk 'NR==2 {print $4}')
        if [ "$available" -lt "$min_space" ]; then
            print_error "Insufficient space in $dir: $((available/1024))MB available, minimum 1GB required"
            ((failed++))
        fi
    done

    # Check if we're on supported filesystem types
    local root_fs
    root_fs=$(df -T "$HOME" | awk 'NR==2 {print $2}')
    case "$root_fs" in
        ext4|btrfs|xfs)
            print_message "Filesystem type $root_fs is supported"
            ;;
        *)
            print_warning "Unsupported filesystem type: $root_fs"
            ;;
    esac

    if [ "$failed" -gt 0 ]; then
        handle_error "Directory validation failed with $failed errors. See above for details."
    fi

    print_message "Directory validation successful"
}

check_time_settings() {
    # Function to check and set time settings
    local timezone_file="/usr/share/zoneinfo/$TIMEZONE"
    local localtime_link="/etc/localtime"
    local ntp_enabled
    local timezone_set=false
    local ntp_was_set=false

    # Check if timezone file exists
    if [ ! -e "$timezone_file" ]; then
        handle_error "Timezone file $timezone_file does not exist. Please provide a valid timezone. $TIMEZONE"
    fi

    print_verbose "Checking and setting timezone to $TIMEZONE..."
    if [ ! -e "$localtime_link" ] || ! cmp -s "$localtime_link" "$timezone_file"; then
        if execute_command "sudo ln -sf $timezone_file $localtime_link" "Set timezone to $TIMEZONE"; then
            timezone_set=true
        else
            handle_error "Could not set timezone to $TIMEZONE"
        fi
    else
        print_verbose "Timezone already set to $TIMEZONE."
    fi

    print_verbose "Checking NTP status..."
    ntp_enabled=$(timedatectl show -p NTP --value 2>/dev/null)
    if [ "$ntp_enabled" != "yes" ]; then
        if execute_command "sudo timedatectl set-ntp true" "Enable NTP"; then
            ntp_was_set=true
        else
            handle_error "Could not enable NTP service"
        fi
    else
        print_verbose "NTP is already enabled."
    fi

    if ($timezone_set || $ntp_was_set); then
        print_verbose "Syncing hardware clock to system time..."
        if ! execute_command "sudo hwclock --systohc" "Sync hardware clock to system time"; then
            handle_error "Could not synchronize hardware clock with system time"
        fi
    fi

    print_verbose "Current time status:"
    print_verbose "$(timedatectl status | grep -E 'Local time:|Time zone:|NTP enabled:')" 

    # Success message if all steps completed
    if { [ -e "$localtime_link" ] && cmp -s "$localtime_link" "$timezone_file"; } && \
       [ "$(timedatectl show -p NTP --value 2>/dev/null)" = "yes" ]; then
        print_message "Time settings successfully checked and configured."
    fi
}

############################################################## Update Functions ##############################################################

update_eos_mirrors() {
    announce_step "Updating EOS mirrors"
    if execute_command "eos-rankmirrors" "Update EndeavourOS mirrors"; then
        mirror_updates+=("EOS Mirrors: $CHECK_MARK")
    else
        mirror_updates+=("EOS Mirrors: $CROSS_MARK")
    fi
}

update_arch_mirrors() {
    announce_step "Updating Arch mirrors"
        if ! command -v reflector &> /dev/null; then
        print_message "Reflector not installed. Installing reflector..."
        if ! distro_install "reflector"; then
            print_error "Reflector installation failed. Aborting mirror update."
            return 1
        fi
    fi
    if execute_command "sudo reflector --verbose --country DE,CH,AT --protocol https --sort rate --latest 20 --download-timeout 6 --save /etc/pacman.d/mirrorlist" "Update Arch mirrors"; then
        mirror_updates+=("Arch Mirrors: $CHECK_MARK")
    else
        mirror_updates+=("Arch Mirrors: $CROSS_MARK")
    fi
}

update_pacman() {
    announce_step "Updating pacman packages"
    if execute_command "sudo pacman -Syu --noconfirm" "Update pacman packages"; then
        package_updates+=("Pacman Packages: $CHECK_MARK")
    else
        package_updates+=("Pacman Packages: $CROSS_MARK")
    fi
}

update_yay() {
    announce_step "Updating AUR packages"
    check_yay
    if execute_command "yay -Sua --noconfirm" "Update AUR packages"; then
        aur_updates+=("AUR Packages: $CHECK_MARK")
    else
        aur_updates+=("AUR Packages: $CROSS_MARK")
    fi
}

update_debian() {
    announce_step "Updating Debian-based packages"
    if execute_command "sudo apt update && sudo apt upgrade -y" "Update Debian packages"; then
        package_updates+=("Debian Packages: $CHECK_MARK")
    else
        package_updates+=("Debian Packages: $CROSS_MARK")
    fi
}

update_fedora() {
    announce_step "Updating Fedora-based packages"
    if execute_command "sudo dnf upgrade --refresh -y" "Update Fedora packages"; then
        package_updates+=("Fedora Packages: $CHECK_MARK")
    else
        package_updates+=("Fedora Packages: $CROSS_MARK")
    fi
}

remove_cache() {
    announce_step "Removing pacman cache"
    if [[ "$DISTRO" == "endeavouros" ]]; then
        execute_command "sudo paccache -r && sudo pacman -Sc --noconfirm && yay -Sc --noconfirm" "Remove pacman/aur cache (EndeavourOS)"
    elif [[ "$DISTRO" == "arch" ]]; then
        execute_command "sudo pacman -Sc --noconfirm && yay -Sc --noconfirm" "Remove pacman/aur cache (Arch Linux)"
    else
        execute_command "sudo pacman -Sc --noconfirm && yay -Sc --noconfirm" "Remove pacman/aur cache"
    fi
    print_message "Pacman cache removed."
}

update_arch() {
    announce_step "Starting full Arch/EndeavourOS update sequence"

    # Only run update_eos_mirrors if on EndeavourOS
    if [[ "$DISTRO" == "endeavouros" ]]; then
        update_eos_mirrors
    fi

    update_arch_mirrors
    update_pacman
    update_yay
    remove_cache

    print_message "Arch/EndeavourOS update sequence completed."
}

update_firmware() {
    announce_step "Updating Firmware"
    echo "Checking for firmware updates..."

    # Check if fwupd is installed
    if ! command -v fwupdmgr &>/dev/null; then
        print_warning "fwupd is not installed. Installing..."
        if ! distro_install "fwupd"; then
            print_error "Failed to install fwupd"
            track_config_status "Firmware Update" "$CROSS_MARK"
            return 1
        fi
    fi

    # Refresh firmware metadata
    print_message "Refreshing firmware metadata..."
    if ! execute_command "sudo fwupdmgr refresh --force" "Refresh firmware metadata"; then
        print_error "Failed to refresh firmware metadata"
        track_config_status "Firmware Update" "$CROSS_MARK"
        return 1
    fi

    # Check for updates
    local update_check
    update_check=$(fwupdmgr get-updates 2>&1)
    if [ $? -eq 0 ] && echo "$update_check" | grep -q "Updates available"; then
        print_message "Firmware updates found. Installing..."
        if execute_command "sudo fwupdmgr update -y" "Install firmware updates"; then
            print_message "Firmware updates installed successfully"
            track_config_status "Firmware Update" "$CHECK_MARK"
        else
            print_error "Failed to install firmware updates"
            track_config_status "Firmware Update" "$CROSS_MARK"
            return 1
        fi
    else
        print_message "No firmware updates available"
        track_config_status "Firmware Update" "$CHECK_MARK (No updates needed)"
    fi
}

contains_element() {
    local element
    for element in "${@:2}"; do
        [[ "$element" == "$1" ]] && return 0
    done
    return 1
}

update_specific_package() {
    print_message "Updating Mirrors..."
    update_eos_mirrors
    update_arch_mirrors
    
    local aur_helper="yay"
    if ! command -v "$aur_helper" &>/dev/null; then
        print_error "$aur_helper is required for this function."
        return 1
    fi

    # Get updates from both repos
    local all_updates
    mapfile -t all_updates < <((checkupdates 2>/dev/null; "$aur_helper" -Qua 2>/dev/null) | awk '{print $1}' | sort -u)
    local remaining=("${all_updates[@]}")

    if [[ ${#all_updates[@]} -eq 0 ]]; then
        print_message "System up to date!"
        return 0
    fi

    local updated_packages=()

    while [[ ${#remaining[@]} -gt 0 ]]; do
        clear
        print_message "Available Updates (${#remaining[@]} remaining):"
        printf '%s\n' "${remaining[@]}" | nl | pr -T -w 120 -4

        read -rp "Enter package numbers (space-separated), 'a' for all, 'q' to quit: " choice

        case "$choice" in
            a)
                print_message "Updating all remaining packages..."
                execute_command "$aur_helper -Syu --needed --noconfirm ${remaining[*]}" "Update all packages"
                updated_packages+=("${remaining[@]}")
                break
                ;;
            q)
                print_warning "Exiting with remaining updates:"
                printf '%s\n' "${remaining[@]}"
                return 0
                ;;
            *)
                # Validate input and extract packages
                read -ra indexes <<< "$choice"
                indexes=("$(printf '%s\n' "${indexes[@]}" | grep -E '^[0-9]+$')")
                local valid=true
                local to_update=()

                for i in "${indexes[@]}"; do
                    if [[ ! "$i" =~ ^[0-9]+$ || "$i" -lt 1 || "$i" -gt ${#remaining[@]} ]]; then
                        print_error "Invalid selection: $i"
                        valid=false
                        break
                    fi
                    to_update+=("${remaining[$((i-1))]}")
                done

                $valid || { sleep 1; continue; }

                print_message "Updating: ${to_update[*]}..."
                if execute_command "$aur_helper -S --needed --noconfirm ${to_update[*]}" "Update selected packages"; then
                    updated_packages+=("${to_update[@]}")
                    # Remove updated packages
                    local new_remaining=()
                    for pkg in "${remaining[@]}"; do
                        if ! contains_element "$pkg" "${to_update[@]}"; then
                            new_remaining+=("$pkg")
                        fi
                    done
                    remaining=("${new_remaining[@]}")
                    # If there are still remaining packages, ask the user if they want to continue
                    if [[ ${#remaining[@]} -gt 0 ]]; then
                        if ! prompt_yes_no "There are still updates remaining. Do you want to continue? (y/n): "; then
                            print_warning "Exiting with remaining updates:"
                            printf '%s\n' "${remaining[@]}"
                            break
                        fi
                    fi
                else
                    print_warning "Update failed for some packages. Check dependencies."
                    sleep 2
                    # If there are still remaining packages, ask the user if they want to continue
                    if [[ ${#remaining[@]} -gt 0 ]]; then
                        if ! prompt_yes_no "There are still updates remaining (some failed). Do you want to continue? (y/n): "; then
                            print_warning "Exiting with remaining updates:"
                            printf '%s\n' "${remaining[@]}"
                            break
                        fi
                    fi
                fi
                ;;
        esac
    done

    if [[ ${#remaining[@]} -eq 0 ]]; then
        print_message "All updates completed!"
    else
        print_warning "Remaining updates:"
        printf '%s\n' "${remaining[@]}"
    fi

    # Print summary of updated packages
    if [[ ${#updated_packages[@]} -gt 0 ]]; then
        print_message "\nSummary of updated packages in this session:"
        printf '  - %s\n' "${updated_packages[@]}"
    else
        print_message "No packages were updated in this session."
    fi
}

############################################################## Install Functions ##############################################################

endeavouros_package_manager() {
    announce_step "Installing EndeavourOS Repository"
    # Check if EndeavourOS repository is already configured
    if [[ "$DISTRO" != "endeavouros" ]]; then
        print_message "Adding EndeavourOS repository configuration..."
        
        # Check if mirrorlist already exists
        if [ -f "/etc/pacman.d/endeavouros-mirrorlist" ]; then
            print_message "EndeavourOS mirrorlist already exists"
        else
            # Download and set up mirrorlist
            print_message "Setting up EndeavourOS mirrorlist..."
            if ! execute_command "sudo curl -o /etc/pacman.d/endeavouros-mirrorlist https://raw.githubusercontent.com/endeavouros-team/PKGBUILDS/refs/heads/master/endeavouros-mirrorlist/endeavouros-mirrorlist" "Download EndeavourOS mirrorlist"; then
                print_error "Failed to download EndeavourOS mirrorlist"
                return 1
            fi
            
            # Set proper permissions for the mirrorlist
            execute_command "sudo chmod 644 /etc/pacman.d/endeavouros-mirrorlist" "Set mirrorlist permissions"
        fi

        local repo_config="[endeavouros]
SigLevel = PackageRequired
Include = /etc/pacman.d/endeavouros-mirrorlist"

        if ! grep -q "\[endeavouros\]" "$REPO_CONFIG"; then
            echo "$repo_config" | sudo tee -a "$REPO_CONFIG" > /dev/null
            print_message "EndeavourOS repository configuration added."
        else
            print_message "EndeavourOS repository already configured."
        fi

        # Install required dependencies after repo configuration
        local deps=("eos-rankmirrors" "endeavouros-keyring")
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &>/dev/null || ! pacman -Qi "$dep" &>/dev/null; then
                print_message "Installing dependency: $dep"
                if ! distro_install "$dep"; then
                    print_error "Failed to install $dep. Repository configuration may fail."
                fi
            fi
        done
    else
        print_message "Running on EndeavourOS, repository already configured."
    fi
}

install_packages() {
    announce_step "Installing Packages"
    declare -a office_apps=("thunderbird" "libreoffice-fresh" "signal-desktop")
    declare -a browsers=("librewolf-bin" "qutebrowser")
    declare -a communication_media=("telegram-desktop" "discord" "obs-studio" "imagemagick" "discord-canary" "whatsapp-for-linux")
    declare -a general_entertainment=("clipgrab" "qbittorrent" "mpc" "mpd" "rmpc" "artem")
    declare -a media_editing=("gimp" "davinci-resolve")
    declare -a gaming=(
                       # Pacman Packages
                       "lact" "winetricks" "glu" "lib32-glu" "flatpak" "prismlauncher" "steam" "lutris" "gamemode" "lib32-gamemode" "wine" "wine-mono" "wine-gecko" 
                       "vulkan-icd-loader" "lib32-vulkan-icd-loader" "mangohud" "lib32-mangohud"
                       # AUR Packages
                       "protonplus" "arch-gaming-meta" "cachyos-ananicy-rules" "heroic-games-launcher-bin" "curseforge-bin" "xpadneo-dkms-git" "gpu-screen-recorder-gtk" "protonup-qt")
    declare -a vr_gaming=("alvr-bin" "alvr-launcher-bin" "wivrn-server" "wivrn-dashboard" "openxr" "openvr" "openhmd")
    declare -a programming=("maven" "cursor-bin" "windsurf" "waydroid" "xh" "sshpass" "rustup" "tea" "zed" "go" "jdk-openjdk" 
                            "python-pip" "python-pipx" "python-ipykernel" "npm" "flawz" "shellcheck" "jdk-openjdk" "virt-manager" "libvirt" "qemu-full")
    declare -a general_customization=("spamton-shimeji" )
    declare -a kde_customization=("plasma6-applets-panel-colorizer")
    declare -a hyprland_apps=("hyprland" "waybar" "hyprpaper" "hyprcursor" "wofi" "hyprlock" "hyprlang" "hyprutils" "hypridle" "hyprpolkitagent"
                            "xdg-desktop-portal-hyprland" "xdg-desktop-portal-gtk" "xdg-desktop-portal" "dunst" "libnotify" "cava" "hyprsunset"
                            "gnome-keyring" "ttf-jetbrains-mono-nerd" "hyprpicker" "wl-clipboard" "wl-clip-persist" "hyprgraphics" "hyprland-qtutils" 
                            "hyprland-qt-support" "hyprwayland-scanner" "python-pyquery" "python-customtkinter" "python-commentjson" 
                            "hyprshot" "pyprland" "xwaylandvideobridge-git" "rose-pine-hyprcursor" "waybar-module-pacman-updates-git" "wl-clipboard-history-git")

    # Initialize final package list
    packages=()

    # Install Essential Tools without prompting the user
    packages+=( "${essential_tools[@]}" )

    if prompt_yes_no "Do you want to install Office Applications?"; then
        packages+=( "${office_apps[@]}" )
    fi

    if prompt_yes_no "Do you want to install Additional Browsers?"; then
        packages+=( "${browsers[@]}" )
    fi

    if prompt_yes_no "Do you want to install Communication, Media, and Image Editing tools?"; then
        packages+=( "${communication_media[@]}" )
    fi

    if prompt_yes_no "Do you want to install Entertainment packages?"; then
        packages+=( "${general_entertainment[@]}" )
    fi

    if prompt_yes_no "Do you want to install additional Media Editing packages?"; then
        packages+=( "${media_editing[@]}" )
    fi

    if prompt_yes_no "Do you want to install Gaming packages?"; then
        packages+=( "${gaming[@]}" )
    fi

    if prompt_yes_no "Do you want to install VR packages?"; then
        packages+=( "${vr_gaming[@]}" )
    fi

    if prompt_yes_no "Do you want to install additional Programming/Virtualization packages?"; then
        packages+=( "${programming[@]}" )
    fi

    if prompt_yes_no "Do you want to install General Customization?"; then
        packages+=( "${general_customization[@]}" )
    fi

    if prompt_yes_no "Do you want to install KDE Desktop Environment Customization?"; then
        packages+=( "${kde_customization[@]}" )
    fi

    if prompt_yes_no "Do you want to install Hyprland related packages?"; then
        packages+=( "${hyprland_apps[@]}" )
    fi

    print_message "Installing pacman packages..."
    for package in "${packages[@]}"; do
        print_message "Installing $package..."
        if ! distro_install "$package"; then
            print_warning "Failed to install $package. Retrying..."
            if ! distro_install "$package"; then
                print_error "Failed to install $package after retry. Please install manually."
                failed_packages+=("$package")
            fi
        fi
    done
}

# Install only essential pacman packages (non-interactive)
install_essential_tools() {
    announce_step "Installing Essential Packages"
    print_message "Installing essential packages (non-interactive)..."
    for package in "${essential_tools[@]}"; do
        print_message "Installing $package..."
        if ! distro_install "$package"; then
            print_warning "Failed to install $package. Retrying..."
            if ! distro_install "$package"; then
                print_error "Failed to install $package after retry. Please install manually."
                failed_packages+=("$package")
            fi
        fi
    done
}

# Function to install drivers and utilities
install_drivers() {
    announce_step "Installing Drivers and Utilities"
    # Check for installed graphics card
    execute_command "lspci | grep -E 'VGA|3D'" "Detecting graphics card..."
    print_message "Updating system and installing drivers and utilities..."
    if ! distro_install "mesa mesa-demos"; then
        print_warning "Failed to install mesa/mesa-demos."
    fi
    if execute_command "lspci | grep -E 'NVIDIA'" "Searching Nvidia Drivers"; then
        # Check if any NVIDIA drivers are already installed
        if execute_command "pacman -Q | grep -E '^nvidia|^nouveau' &>/dev/null" "Checking for NVIDIA drivers"; then
            print_message "NVIDIA driver(s) already installed. Skipping NVIDIA driver installation."
        else
            # Extract PCI device ID for identification of GPU model
            pci_entry=$(lspci -n | grep -i 'VGA\|3D' | grep -i nvidia | head -n1 | awk '{print $3}')
            device_id_hex=${pci_entry#*:}  # part after colon

            # Convert hex to decimal
            device_id_dec=$((16#$device_id_hex))

            # Select driver based on device ID
            if (( device_id_dec >= 0x2500 )); then
                driver="nvidia-open"
                if ! distro_install "nvidia-open nvidia-open-dkms nvidia-utils nvidia-container-toolkit nvidia-open-lts lib32-nvidia-utils"; then
                    print_warning "Failed to install modern NVIDIA open drivers."
                fi
            elif (( device_id_dec >= 0x1000 )); then
                driver="nvidia"
                if ! distro_install "nvidia nvidia-utils nvidia-settings"; then
                    print_warning "Failed to install modern NVIDIA drivers."
                fi
            elif (( device_id_dec >= 0x0C00 )); then
                driver="nvidia-470xx"
                if ! distro_install "nvidia-470xx nvidia-470xx-utils"; then
                    print_warning "Failed to install legacy NVIDIA 470xx drivers."
                fi
            elif (( device_id_dec >= 0x0600 )); then
                driver="nvidia-390xx"
                if ! distro_install "nvidia-390xx nvidia-390xx-utils"; then
                    print_warning "Failed to install legacy NVIDIA 390xx drivers."
                fi
            elif (( device_id_dec >= 0x0300 )); then
                driver="nvidia-340xx"
                if ! distro_install "nvidia-340xx nvidia-340xx-utils"; then
                    print_warning "Failed to install legacy NVIDIA 340xx drivers."
                fi
            else
                driver="nouveau"
                if ! distro_install "xf86-video-nouveau"; then
                    print_warning "Failed to install Nouveau drivers."
                fi
            fi
            print_message "Selected NVIDIA driver: $driver"
        fi
    elif execute_command "lspci | grep -E 'AMD'" "Searching AMD Driver"; then
        if ! distro_install "mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu amd-ucode"; then
            print_warning "Failed to install AMD drivers."
        fi
    elif execute_command "lspci | grep -E 'Intel'" "Searching Intel Driver"; then
        if ! distro_install "xf86-video-intel"; then
            print_warning "Failed to install Intel drivers."
        fi
    else
        print_message "No supported graphics card detected."
    fi
}

install_cachyos() {
  set -e

  # Import CachyOS signing key
  print_message "Importing CachyOS signing key..."
  execute_command "sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com"
  execute_command "sudo pacman-key --lsign-key F3B607488DB35A47"

  # Install CachyOS keyring and mirrorlist
  execute_command "sudo pacman -U --noconfirm \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst'" "Installing CachyOS keyring and mirrorlist..."

  # Add CachyOS repo to pacman.conf if not already present
  if ! grep -q "\[cachyos\]" "$REPO_CONFIG"; then
    print_message "Adding CachyOS repository to pacman.conf..."
    echo -e "\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist" | execute_command "sudo tee -a $REPO_CONFIG"
  fi

  # Update package database
  execute_command "sudo pacman -Sy" "Updating package database..."

  # Install CachyOS kernel and headers
  execute_command "sudo pacman -S --noconfirm linux-cachyos linux-cachyos-headers" "Installing CachyOS kernel and headers..."

  # Regenerate initramfs
  execute_command "sudo mkinitcpio -P" "Regenerating initramfs..."

  # Update GRUB bootloader (if installed)
  if [ -x /usr/bin/grub-mkconfig ]; then
    execute_command "sudo grub-mkconfig -o /boot/grub/grub.cfg" "Update GRUB configuration"
  else
    print_warning "WARNING: GRUB not found. Please update your bootloader configuration manually."
  fi

  print_message "CachyOS kernel installation complete! Please reboot your system."
}

############################################################## Backup functions ##############################################################

system_backup() {
    announce_step "Setting up and running system backup..."

    # Validate backup destination exists
    if [ ! -d "$(dirname "$BACKUP_DIR")" ]; then
        print_warning "Destination directory $(dirname "$BACKUP_DIR") doesn't exist. Please choose another location."
        read -rp "Enter backup destination path (e.g., /mnt/External/Backups/): " user_backup_dir
        BACKUP_DIR="${user_backup_dir%/}/System_BackUp/"
    fi

    # Create backup directory if it doesn't exist
    if [ ! -d "$BACKUP_DIR" ]; then
        if ! execute_command "sudo mkdir -p \"$BACKUP_DIR\"" "Create backup directory"; then
            print_error "Failed to create backup directory: $BACKUP_DIR"
            track_config_status "System Backup" "$CROSS_MARK"
            return 1
        fi
    fi

    local DATE
    DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    local BACKUP_PATH="${BACKUP_DIR}/${DATE}"
    local LATEST_LINK="${BACKUP_DIR}/latest"

    # Extended exclude list
    local EXCLUDES=(
        --exclude='/dev/*'
        --exclude='/proc/*'
        --exclude='/sys/*'
        --exclude='/tmp/*'
        --exclude='/run/*'
        --exclude='/mnt/*'
        --exclude='/media/*'
        --exclude='/lost+found'
        --exclude='/home/*/.cache/*'
        --exclude='/home/*/.trash/*'
        --exclude='/var/cache'
        --exclude='/var/tmp'
        --exclude='/var/log'
        --exclude='/home/*/.local/share/Trash'
        --exclude="/home/*/$DOCUMENTS_DIR/GitHub/*"
        --exclude="/home/*/$DOCUMENTS_DIR/GitLab/*"
    )

    print_message "Starting system backup to: $BACKUP_PATH"
    print_message "This may take a while depending on your system size..."

    # Perform the backup
    if execute_command "sudo rsync -aAXvhP --delete ${EXCLUDES[*]} --link-dest \"${LATEST_LINK}\" / \"${BACKUP_PATH}\"" "Perform system backup"; then
        # Update symlink only if backup succeeded
        if execute_command "sudo ln -sfn \"${BACKUP_PATH}\" \"${LATEST_LINK}\"" "Update latest backup symlink"; then
            # Create log entry
            execute_command "echo \"Backup completed on ${DATE}\" >> \"${BACKUP_DIR}/backup.log\"" "Create backup log entry"
            print_message "System backup completed successfully!"
            track_config_status "System Backup" "$CHECK_MARK"
            return 0
        fi
    fi

    print_error "System backup failed"
    track_config_status "System Backup" "$CROSS_MARK"
    return 1
}

restore_system_backup() {
    announce_step "Restoring from system backup..."

    # Checking if we're running in a terminal that supports the restore UI
    if ! is_dry_run && [ "$TERM" != "xterm-kitty" ]; then
        print_message "For best experience, this should run in kitty terminal"
        if ! prompt_yes_no "Continue anyway?"; then
            print_message "Launching in kitty terminal..."
            # We can't directly exec because we're inside a function
            # Instead, relaunch script with specific function
            if command -v kitty &> /dev/null; then
                kitty -- "$0" --function=restore_system_backup
                return $?
            else
                print_warning "kitty terminal not found, continuing in current terminal"
            fi
        fi
    fi

    # Validate backup source exists
    local LATEST_LINK="${BACKUP_DIR}/latest"

    if [ ! -d "$BACKUP_DIR" ]; then
        print_warning "Backup directory $BACKUP_DIR doesn't exist."
        read -rp "Enter backup source path: " user_backup_dir
        BACKUP_DIR="${user_backup_dir%/}/"
        LATEST_LINK="${BACKUP_DIR}/latest"

        if [ ! -d "$BACKUP_DIR" ]; then
            print_error "Specified backup directory doesn't exist: $BACKUP_DIR"
            track_config_status "System Restore" "$CROSS_MARK"
            return 1
        fi
    fi

    # Show available backups
    print_message "Available backups:"

    if is_dry_run; then
        print_message "[DRY-RUN] Would list backups from: $BACKUP_DIR"
    else
        ls -la "${BACKUP_DIR}" | grep -v "latest\|backup.log" | grep "^d"

        if [ -L "$LATEST_LINK" ] && [ -d "$LATEST_LINK" ]; then
            echo "latest -> $(readlink -f "${LATEST_LINK}")"
        fi
    fi

    # User selects backup
    print_message "Options:"
    echo "1. Restore from latest backup"
    echo "2. Select a specific backup"
    read -rp "Enter your choice (1 or 2): " choice

    local SELECTED_BACKUP=""

    if [ "$choice" = "1" ]; then
        if [ -L "$LATEST_LINK" ] && [ -d "$LATEST_LINK" ]; then
            SELECTED_BACKUP="${LATEST_LINK}"
            print_message "Selected backup: latest -> $(readlink -f "${LATEST_LINK}")"
        else
            print_error "Latest backup link does not exist or is not valid"
            track_config_status "System Restore" "$CROSS_MARK"
            return 1
        fi
    elif [ "$choice" = "2" ]; then
        read -rp "Enter the backup date (format YYYY-MM-DD_HH-MM-SS): " backup_date
        SELECTED_BACKUP="${BACKUP_DIR}/${backup_date}"

        # Check if specified backup exists
        if [ ! -d "${SELECTED_BACKUP}" ]; then
            print_error "Error: Backup '${backup_date}' does not exist."
            track_config_status "System Restore" "$CROSS_MARK"
            return 1
        fi
        print_message "Selected backup: ${SELECTED_BACKUP}"
    else
        print_error "Invalid choice."
        track_config_status "System Restore" "$CROSS_MARK"
        return 1
    fi

    # Warning and confirmation
    print_warning "WARNING: This will restore your system from the backup at:"
    print_warning "${SELECTED_BACKUP}"
    print_warning "This operation will overwrite files on your system."

    read -rp "Are you sure you want to proceed? (Type 'yes' to confirm): " confirm

    if [ "${confirm}" != "yes" ]; then
        print_message "Restore cancelled by user."
        return 0
    fi

    # Execute restore
    print_message "Starting restore process..."

    if is_dry_run; then
        if execute_command "sudo rsync -aAXvhn --delete \"${SELECTED_BACKUP}/\" /" "Preview files to be restored (dry run)"; then
            print_message "[DRY-RUN] System restore simulation completed successfully"
            track_config_status "System Restore Preview" "$CHECK_MARK"
            return 0
        else
            print_error "[DRY-RUN] System restore simulation failed"
            track_config_status "System Restore Preview" "$CROSS_MARK"
            return 1
        fi
    else
        if execute_command "sudo rsync -aAXvh --delete \"${SELECTED_BACKUP}/\" /" "Restore system from backup"; then
            print_message "System restore completed successfully!"
            print_message "It's recommended to reboot your system now."
            track_config_status "System Restore" "$CHECK_MARK"
            return 0
        else
            print_error "System restore failed"
            track_config_status "System Restore" "$CROSS_MARK"
            return 1
        fi
    fi
}

############################################################## Configuration Functions ##############################################################

configure_fish() {
    announce_step "Setting default shell to fish"
    if execute_command "sudo chsh -s /usr/bin/fish" "Set fish as default shell"; then
        track_config_status "Default Shell (fish)" "$CHECK_MARK"
    else
        track_config_status "Default Shell (fish)" "$CROSS_MARK"
    fi

    print_message "Download fzf Repository for fzf file management integration in fish"
    if [ -d "$HOME/.fzf" ]; then
        print_message "fzf repository already exists at $HOME/.fzf, skipping clone."
    else
        execute_command "git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf" "Download fzf Github Repo"
    fi

    # Run fzf install script non-interactively for fish only
    if [ -f "$HOME/.fzf/install" ]; then
        execute_command "\"$HOME/.fzf/install\" --all --no-bash --no-zsh --no-update-rc" "Execute fzf Installation (non-interactive for fish)"
    else
        print_warning "fzf install script not found at $HOME/.fzf/install"
    fi
}

configure_ssh() {
    announce_step "Configuring SSH"

    # Check if SSH key already exists
    if [ -f "$HOME"/.ssh/id_ed25519 ]; then
        print_message "SSH key already exists, skipping generation"
    else
        execute_command "ssh-keygen -t ed25519 -C $SSH_EMAIL" "Generate SSH key"
    fi

    # Enable SSH and add key to agent
    if execute_command "sudo systemctl enable --now sshd" "Enable and start SSH" &&
       execute_command "eval \$(ssh-agent -s)" "Start SSH agent" &&
       execute_command "ssh-add $HOME/.ssh/id_ed25519" "Add SSH key to agent"; then
        # Copy SSH key to remote host
        if execute_command "ssh-copy-id $SSH_USER@$SSH_SERVER_IP" "Copy SSH key to remote host"; then
            # Test SSH connection
            if execute_command "ssh $SSH_USER@$SSH_SERVER_IP 'exit'" "Test SSH connection to remote host"; then
                track_config_status "SSH Setup" "$CHECK_MARK"
            else
                print_warning "SSH connection test failed."
                track_config_status "SSH Setup" "$CROSS_MARK"
            fi
        else
            print_warning "ssh-copy-id failed."
            track_config_status "SSH Setup" "$CROSS_MARK"
        fi
    else
        track_config_status "SSH Setup" "$CROSS_MARK"
    fi
}

configure_git() {
    announce_step "Configuring Git"

    # Check and set git user.name
    local current_name
    current_name=$(git config --global user.name || echo "")
    if [[ -z "$current_name" ]]; then
        execute_command "git config --global user.name '$GIT_USER'" "Set Git user name"
    else
        print_message "Git user.name is already set to '$current_name'"
    fi

    # Check and set git user.email
    local current_email
    current_email=$(git config --global user.email || echo "")
    if [[ -z "$current_email" ]]; then
        execute_command "git config --global user.email '$GIT_EMAIL'" "Set Git user email"
    else
        print_message "Git user.email is already set to '$current_email'"
    fi

    # Check if GitHub CLI is authenticated
    if ! gh auth status &>/dev/null; then
        execute_command "gh auth login" "Login to GitHub CLI"
        execute_command "gh auth setup-git" "Setup GitHub CLI"
        track_config_status "Git Configuration" "$CHECK_MARK"
    else
        print_message "GitHub CLI already authenticated."
        track_config_status "Git Configuration" "$CHECK_MARK"
    fi

    # Set default branch to main if not already set
    local current_default_branch
    current_default_branch=$(git config --global init.defaultBranch || echo "")
    if [[ "$current_default_branch" != "main" ]]; then
        execute_command "git config --global init.defaultBranch main" "Set default git branch to main"
    else
        print_message "Git init.defaultBranch is already set to 'main'"
    fi
}

configure_environment() {
    announce_step "Configuring Environment"
    # Check if librewolf is installed
    if ! command -v librewolf &>/dev/null; then
        print_message "Librewolf is not installed. Installing..."
        if ! distro_install "librewolf-bin"; then
            print_error "Failed to install Librewolf. Please install it manually."
            echo "Configuration failed."
            return 1
        fi
    fi

    # Set BROWSER environment variable
    if ! execute_command "systemctl --user set-environment BROWSER=librewolf" "Set BROWSER environment variable to librewolf"; then
        print_error "Failed to set BROWSER environment variable."
        echo "Configuration failed."
        return 1
    fi

    # Check if nvim is installed
    if ! command -v nvim &>/dev/null; then
        print_message "Neovim is not installed. Installing..."
        if ! distro_install "neovim"; then
            print_error "Failed to install Neovim. Please install it manually."
            echo "Configuration failed."
            return 1
        fi
    fi

    # Set EDITOR environment variable
    if ! execute_command "systemctl --user set-environment EDITOR=nvim" "Set EDITOR environment variable to nvim"; then
        print_error "Failed to set EDITOR environment variable."
        echo "Configuration failed."
        return 1
    fi

    echo "Configuration completed successfully."
}

switch_dotfiles_branch() {
    print_message "Switching dotfiles branch"
    local repo_dir="$HOME/.dotfiles"
    local branch_name=""

    # Check for desktop environment
    if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ] || pgrep -x "Hyprland" > /dev/null; then
        branch_name="EndeavourOS_Hyprland"
    elif [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_CURRENT_DESKTOP" = "plasma" ] || pgrep -x "plasmashell" > /dev/null; then
        branch_name="EndeavourOS_KDE-Plasma6"
    else
        print_warning "Neither Hyprland nor KDE Plasma detected. Please select a branch:"
        select choice in "EndeavourOS_Hyprland" "EndeavourOS_KDE-Plasma6"; do
            if [ -n "$choice" ]; then
                branch_name="$choice"
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
    fi

    # Navigate to repository
    if [ ! -d "$repo_dir" ]; then
        print_error "$repo_dir directory not found"
        return 1
    fi

    cd "$repo_dir" || { print_error "Failed to navigate to $repo_dir"; return 1; }

    # Check if branch exists locally
    if git show-ref --quiet "refs/heads/$branch_name"; then
        print_message "Switching to existing branch: $branch_name"
        if ! git switch "$branch_name"; then
            print_error "Conflict detected! Use git stash to save changes first."
            return 2
        fi
    else
        # Check if branch exists remotely
        git fetch --quiet origin "$branch_name" 2>/dev/null
        if git show-ref --quiet "refs/remotes/origin/$branch_name"; then
            print_message "Creating local tracking branch for remote $branch_name"
            if ! git switch -c "$branch_name" "origin/$branch_name"; then
                return 3
            fi
        else
            print_message "Creating new branch: $branch_name"
            if ! git switch -c "$branch_name"; then
                return 4
            fi
        fi
    fi

    print_message "Successfully switched to $branch_name"
}

configure_dotfiles() {
    announce_step "Configuring dotfiles"
    cd "$HOME" || {
        print_error "Failed to change to home directory"
        track_config_status "Dotfiles Setup" "$CROSS_MARK"
        return 1
    }
    if [ -d ".dotfiles" ]; then
        print_message ".dotfiles already exists."
            track_config_status "Dotfiles Setup" "$CROSS_MARK"
            return 1
    else
        if execute_command "git clone $GIT_DOTFILES" "Clone dotfiles repository"; then
            cd .dotfiles || {
                print_error "Failed to change to .dotfiles directory"
                track_config_status "Dotfiles Setup" "$CROSS_MARK"
                return 1
            }
            print_message "Dotfiles repository cloned"
        else
            track_config_status "Dotfiles Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Check if sources directory already exists
    if [ -d "$HYPR_SCRIPTS/sources" ]; then
        print_message ".config/hypr/sources directory already exists, keeping existing configuration"
    # Check if sources_example exists and copy it to sources if it does
    elif [ -d "$HYPR_SCRIPTS/sources_example" ]; then
        print_message "Creating .config/hypr/sources from sources_example template..."
        if ! execute_command "cp -r $HYPR_SCRIPTS/sources_example $HYPR_SCRIPTS/sources" "Copy sources_example directory"; then
            print_error "Failed to copy sources_example directory"
            track_config_status "Dotfiles Setup" "$CROSS_MARK"
            return 1
        fi
    else
        print_message "sources_example directory not found, continuing with existing configuration"
    fi

    if cd "$HOME"/.dotfiles/.local/scripts; then
        if execute_command "./Start_stow_solve.sh" "Run stow script" &&
           execute_command "fish -c 'source $HOME/.config/fish/config.fish'" "Source fish config"; then
            track_config_status "Dotfiles Setup" "$CHECK_MARK"
            return 0
        fi
    fi
    track_config_status "Dotfiles Setup" "$CROSS_MARK"
    return 1
}

configure_pacman_color() {
    announce_step "Configuring Pacman Color"
    local pacman_conf="$REPO_CONFIG"
    local tmp_conf="/tmp/pacman.conf.$$"
    local color_found=false
    local candy_found=false
    local color_line_num=0
    local line_num=0

    # Read through the file and process
    while IFS= read -r line; do
        ((line_num++))
        # Check for Color (commented or not)
        if [[ "$line" =~ ^#?Color$ ]]; then
            color_found=true
            color_line_num=$line_num
            # Uncomment if commented
            echo "Color" >> "$tmp_conf"
        # Check for ILoveCandy (commented or not)
        elif [[ "$line" =~ ^#?ILoveCandy$ ]]; then
            candy_found=true
            echo "ILoveCandy" >> "$tmp_conf"
        else
            echo "$line" >> "$tmp_conf"
        fi
    done < "$pacman_conf"

    # If Color was not found, add it after [options]
    if ! $color_found; then
        awk '/^\[options\]/{print;print "Color";next}1' "$tmp_conf" > "${tmp_conf}.new" && mv "${tmp_conf}.new" "$tmp_conf"
        color_found=true
        color_line_num=$(awk '/^Color$/{print NR; exit}' "$tmp_conf")
    fi

    # If ILoveCandy is not found, add it just below Color
    if ! $candy_found && $color_found; then
        awk -v cline="$color_line_num" '{print; if(NR==cline) print "ILoveCandy"}' "$tmp_conf" > "${tmp_conf}.new" && mv "${tmp_conf}.new" "$tmp_conf"
    fi

    # Only replace the original if changes were made
    if ! cmp -s "$pacman_conf" "$tmp_conf"; then
        sudo cp "$pacman_conf" "${pacman_conf}.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp "$tmp_conf" "$pacman_conf"
        print_message "Updated $pacman_conf: ensured 'Color' is uncommented and 'ILoveCandy' is present."
    else
        print_message "$pacman_conf already has 'Color' and 'ILoveCandy' set correctly."
    fi
    rm -f "$tmp_conf"
}

configure_virtual_env() {
    # Check if qemu is installed and ask user
    if command -v qemu-system-x86_64 &>/dev/null; then
        print_message "QEMU is already installed."
    else
        if prompt_yes_no "Do you want to install QEMU?"; then
            print_message "Installing QEMU..."
            # Install and enable on startup
            if distro_install "qemu-full libvirtd virt-manager"; then
                print_message "QEMU installed successfully."
                # Enable libvirt service
                if execute_command "sudo systemctl enable --now libvirtd" "Enable libvirt service"; then
                    print_message "Libvirt service enabled successfully."
                else
                    print_error "Failed to enable libvirt service."
                    return 1
                fi
                print_error "Failed to install QEMU. Please install it manually."
                return 1
            fi
        else
            print_warning "Skipping QEMU installation."
        fi
    fi

}

configure_ollama() {
    announce_step "Setting up Ollama"
    if prompt_yes_no "Do you want to install/reinstall/update AI Tools (Ollama)?"; then
        print_message "Installing Ollama via alternative method..."
        execute_command "curl -fsSL https://ollama.com/install.sh | sh" "Install Ollama"
    fi
    # Check if Ollama is installed; if not, skip configuration.
    if ! command -v ollama &>/dev/null; then
        print_warning "Ollama is not installed. Skipping Ollama configuration."
        track_config_status "Ollama Setup" "$CIRCLE (Not installed)"
        return 0
    fi

    local new_path="$SSD_MNT/Ollama/"
    local drive_exists=true

    # Check if mount point exists; if not, skip drive-specific setup.
    if [ ! -d "$SSD_MNT" ]; then
        print_warning "Mount point $SSD_MNT does not exist. Skipping drive-specific setup."
        drive_exists=false
    fi

    if $drive_exists; then
        if [ ! -d "$new_path" ]; then
            if ! execute_command "sudo mkdir -p $new_path" "Create Ollama models directory"; then
                print_warning "Failed to create Ollama directory. Skipping drive-specific configuration."
                drive_exists=false
            fi
        fi
    fi

    if $drive_exists; then
        if ! execute_command "sudo mkdir -p /etc/systemd/system/ollama.service.d/" "Create systemd override directory"; then
            print_warning "Failed to create systemd override directory. Skipping drive-specific configuration."
            drive_exists=false
        fi
    fi

    if $drive_exists; then
        # Check if override file already exists with the required content
        local override_file="/etc/systemd/system/ollama.service.d/override.conf"
        local needs_update=true

        if [ -f "$override_file" ]; then
            # Check if all required settings are already in the file
            if grep -q "OLLAMA_USE_GPU=1" "$override_file" && \
               grep -q "OLLAMA_MAX_LOADED_MODELS=2" "$override_file" && \
               grep -q "OLLAMA_NUM_PARALLEL=4" "$override_file" && \
               grep -q "OLLAMA_MAX_QUEUE=512" "$override_file" && \
               grep -q "OLLAMA_MODELS=$new_path" "$override_file" && \
               grep -q "HSA_OVERRIDE_GFX_VERSION=11.0.1" "$override_file" && \
               grep -q "HIP_VISIBLE_DEVICES=0" "$override_file" && \
               grep -q "OLLAMA_HOST=0.0.0.0" "$override_file" && \
               grep -q "HSA_ENABLE_SDMA=0" "$override_file" && \
               grep -q "GPU_MAX_HW_QUEUES=2" "$override_file"; then
                print_message "Ollama override.conf already contains all required settings"
                needs_update=false
            else
                print_message "Ollama override.conf exists but needs updating"
            fi
        fi

        if $needs_update; then
            if ! execute_command "sudo bash -c 'cat > $override_file << EOF
[Service]
Environment=\"OLLAMA_USE_GPU=1\"
Environment=\"OLLAMA_MAX_LOADED_MODELS=2\"
Environment=\"OLLAMA_NUM_PARALLEL=4\"
Environment=\"OLLAMA_MAX_QUEUE=512\"
Environment=\"OLLAMA_MODELS=$new_path\"
Environment=\"HSA_OVERRIDE_GFX_VERSION=11.0.1\"
Environment=\"HIP_VISIBLE_DEVICES=0\"
Environment=\"OLLAMA_HOST=0.0.0.0\"
Environment=\"HSA_ENABLE_SDMA=0\"
Environment=\"GPU_MAX_HW_QUEUES=2\"
EOF'" "Configure Ollama settings"; then
                print_warning "Failed to create Ollama configuration override. Skipping drive-specific configuration."
            else
                print_message "Ollama override.conf created/updated successfully"
            fi
        fi
    fi

    # Check if FirewallD is already active and set
    if systemctl is-active --quiet firewalld; then
        print_message "FirewallD is already running"
        # Check if port is already open
        if sudo firewall-cmd --list-ports | grep -q "11434/tcp"; then
            print_message "Port 11434 is already open in firewall"
        else
            # Configure firewall
            if ! execute_command "sudo firewall-cmd --permanent --add-port=11434/tcp" "Configure firewall" || \
               ! execute_command "sudo firewall-cmd --reload" "Reload firewall"; then
                print_error "Failed to configure firewall"
                track_config_status "Ollama Setup" "$CROSS_MARK"
                return 1
            fi
        fi
    else
        # Start and enable FirewallD service
        if ! execute_command "sudo systemctl enable --now firewalld" "Enable and start FirewallD"; then
            print_error "Failed to start FirewallD"
            track_config_status "Ollama Setup" "$CROSS_MARK"
            return 1
        fi

        # Configure firewall
        if ! execute_command "sudo firewall-cmd --permanent --add-port=11434/tcp" "Configure firewall" || \
           ! execute_command "sudo firewall-cmd --reload" "Reload firewall"; then
            print_error "Failed to configure firewall"
            track_config_status "Ollama Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Start service
    if ! execute_command "sudo systemctl daemon-reload" "Reload systemd" || \
       ! execute_command "sudo systemctl enable ollama" "Enable Ollama" || \
       ! execute_command "sudo systemctl restart ollama" "Restart Ollama"; then
        print_error "Failed to start Ollama service"
        track_config_status "Ollama Setup" "$CROSS_MARK"
        return 1
    fi

    # Detect AMD GPU and only then run ROCm setup
    if lspci | grep -qi "AMD" > /dev/null; then
        print_message  "AMD GPU detected → configuring ROCm support"
        if ! configure_rocm; then
            print_warning "ROCm configuration failed"
        fi
    elif lspci | grep -qi "NVIDIA" > /dev/null; then
        print_message  "NVIDIA GPU detected → configuring CUDA support"
        if ! configure_cuda; then
            print_warning "CUDA configuration failed"
        fi
    else
        print_message "No AMD or NVIDA GPU found; skipping setup"
    fi

    # Verify Ollama is running
    if ! systemctl is-active --quiet ollama; then
        print_error "Ollama service failed to start"
        track_config_status "Ollama Setup" "$CROSS_MARK"
        return 1
    fi

    track_config_status "Ollama Setup" "$CHECK_MARK"
    return 0
}

configure_razer() {
    announce_step "Setting up Open-Razer"

    # Check if any Razer devices are connected
    print_message "Checking for connected Razer devices..."
    if ! execute_command "lsusb | grep -i 'Razer'" "Check for Razer devices" >/dev/null 2>&1; then
        print_warning "No Razer devices detected. Skipping Open-Razer setup."
        track_config_status "Open-Razer Setup" "$CIRCLE (No devices detected)"
        return 0
    fi

    print_message "Razer device(s) detected, proceeding with setup..."

    # Check if packages are installed using pacman query
    local openrazer_installed=false
    local polychromatic_installed=false

    if pacman -Qi openrazer-meta-git &>/dev/null; then
        openrazer_installed=true
        print_message "openrazer-meta-git is already installed"
    fi

    if pacman -Qi polychromatic &>/dev/null; then
        polychromatic_installed=true
        print_message "polychromatic is already installed"
    fi

    if ! $openrazer_installed || ! $polychromatic_installed; then
        print_warning "Some Razer packages are missing. Installing..."

        if ! $openrazer_installed; then
            if ! distro_install "openrazer-meta-git" "Install Open-Razer"; then
                return 0
            fi
        fi

        if ! $polychromatic_installed; then
            print_message "Installing Polychromatic..."
            if ! distro_install "polychromatic"; then
                return 0
            fi
        fi
    fi

    # Install razer-cli if not already installed
    if ! command -v razer-cli &>/dev/null; then
        print_message "Installing razer-cli (AUR CLI for Razer devices)..."
        if ! distro_install "razer-cli" "Install razer-cli"; then
            print_warning "Failed to install razer-cli. You may need to install it manually if you want CLI control of Razer devices."
        fi
    else
        print_message "razer-cli is already installed."
    fi

    if execute_command "sudo gpasswd -a $USER plugdev" "Add user to plugdev group" &&
       execute_command "sudo modprobe razerkbd razermouse razeraccessory" "Load Razer modules"; then
        track_config_status "Open-Razer Setup" "$CHECK_MARK"
    else
        track_config_status "Open-Razer Setup" "$CROSS_MARK"
    fi
}

configure_input_remapper() {
    announce_step "Setting up Input-Remapper"

    # Check if any Razer devices are connected
    print_message "Checking for connected Razer devices..."
    if ! execute_command "lsusb | grep -i 'Razer'" "Check for Razer devices" >/dev/null 2>&1; then
        print_warning "No Razer devices detected. Skipping Input-Remapper setup."
        track_config_status "Input-Remapper Setup" "$CIRCLE (No devices detected)"
        return 0
    fi

    print_message "Razer device(s) detected, proceeding with setup..."

    if ! command -v input-remapper-control &>/dev/null; then
        print_message "Input-Remapper is not installed. Installing automatically..."
        if ! distro_install "input-remapper-git"; then
            print_warning "Failed to install Input-Remapper. Skipping configuration."
            track_config_status "Input-Remapper Setup" "$CIRCLE (Installation failed)"
            return 0
        fi
    fi

    # Proceed with configuration if installed
    if execute_command "sudo systemctl restart input-remapper" "Restart Input-Remapper" &&
       execute_command "sudo systemctl enable input-remapper" "Enable Input-Remapper"; then
        track_config_status "Input-Remapper Setup" "$CHECK_MARK"
    else
        track_config_status "Input-Remapper Setup" "$CROSS_MARK"
    fi
}

configure_fingerprint() {
    announce_step "Setting up fingerprint reader"
    # Check if fingerprint sensor is available using lsusb
    print_message "Checking for fingerprint sensor..."
    if ! lsusb | grep -iE "fingerprint|fprint|synaptics|authentec|validity" >/dev/null; then
        print_warning "No fingerprint sensor detected."
        track_config_status "Fingerprint Reader Setup" "$CIRCLE (No sensor detected)"
        return 0
    fi

    print_message "Fingerprint sensor detected: $(lsusb | grep -iE "fingerprint|fprint|synaptics|authentec|validity")"

    # Ask user if they want to proceed with fingerprint setup
    if ! prompt_yes_no "Would you like to proceed with fingerprint setup?"; then
        print_message "Fingerprint setup skipped by user."
        track_config_status "Fingerprint Reader Setup" "$CIRCLE (Skipped by user)"
        return 0
    fi

    # Install required packages if not present
    local required_packages=("fprintd" "libfprint" "pambase")
    for pkg in "${required_packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            if ! distro_install "$pkg"; then
                print_error "Failed to install $pkg"
                track_config_status "Fingerprint Reader Setup" "$CROSS_MARK"
                return 1
            fi
        fi
    done

    # Create or update udev rules for fingerprint device
    local udev_rule_file="/etc/udev/rules.d/70-fingerprint.rules"
    if [ ! -f "$udev_rule_file" ]; then
        print_message "Creating udev rules for fingerprint device..."
        echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="*", ATTRS{idProduct}=="*", GROUP="plugdev", MODE="0660"' | sudo tee "$udev_rule_file"
        execute_command "sudo udevadm control --reload-rules && sudo udevadm trigger" "Reload udev rules"
    fi

    # Create plugdev group if it doesn't exist
    if ! getent group plugdev >/dev/null; then
        print_message "Creating plugdev group..."
        if ! execute_command "sudo groupadd plugdev" "Create plugdev group"; then
            print_error "Failed to create plugdev group"
            track_config_status "Fingerprint Reader Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Add user to required groups
    for group in "plugdev" "input"; do
        if ! groups "$USER" | grep -q "\b$group\b"; then
            print_message "Adding user to $group group..."
            if ! execute_command "sudo usermod -aG $group $USER" "Add user to $group group"; then
                print_error "Failed to add user to $group group"
                track_config_status "Fingerprint Reader Setup" "$CROSS_MARK"
                return 1
            fi
        fi
    done

    # Start and enable fprintd service
    print_message "Enabling fprintd service..."
    if ! execute_command "sudo systemctl enable --now fprintd.service" "Enable fprintd service"; then
        print_error "Failed to enable fprintd service"
        track_config_status "Fingerprint Reader Setup" "$CROSS_MARK"
        return 1
    fi

    # Clear any existing fingerprint data
    print_message "Clearing existing fingerprint data..."
    execute_command "fprintd-delete $USER" "Clear existing fingerprint data"

    # Enroll fingerprint with multiple attempts
    print_message "Starting fingerprint enrollment. Please follow the instructions carefully."
    print_message "You will need to scan your finger multiple times for a successful enrollment."

    local max_enrollment_attempts=3
    local enrollment_success=false

    for ((attempt=1; attempt<=max_enrollment_attempts; attempt++)); do
        print_message "Enrollment attempt $attempt of $max_enrollment_attempts..."
        if execute_command "fprintd-enroll $USER" "Enroll fingerprint"; then
            enrollment_success=true
            break
        else
            print_warning "Enrollment attempt $attempt failed. Please try again."
            sleep 2
        fi
    done

    if ! $enrollment_success; then
        print_error "Failed to enroll fingerprint after $max_enrollment_attempts attempts."
        track_config_status "Fingerprint Reader Setup" "$CROSS_MARK"
        return 1
    fi

    # Configure PAM
    local pam_files=("/etc/pam.d/system-local-login" "/etc/pam.d/sudo")
    for pam_file in "${pam_files[@]}"; do
        if [ -f "$pam_file" ]; then
            print_message "Configuring PAM for $pam_file..."
            # Create backup
            execute_command "sudo cp $pam_file ${pam_file}.backup" "Backup PAM file"

            # Add fingerprint authentication if not already present
            if ! grep -q "^auth.*sufficient.*pam_fprintd.so" "$pam_file"; then
                execute_command "sudo sed -i '1i auth sufficient pam_fprintd.so' $pam_file" "Add fingerprint authentication to $pam_file"
            fi
        fi
    done

    print_message "Fingerprint setup completed. Please log out and log back in for changes to take effect."
    track_config_status "Fingerprint Reader Setup" "$CHECK_MARK"
}

configure_numpad() {
    announce_step "Configuring ASUS NumberPad Driver"

    # Check if activatable numpad is available using lshw
    if ! execute_command "sudo lshw -C input" | grep -q "ASUE140D:00 04F3:31B9 Touchpad" >/dev/null 2>&1; then
        print_warning "No ASUS NumberPad device detected."
        track_config_status "NumberPad Setup" "$CIRCLE (No device detected)"
        return 0
    fi

    print_message "ASUS NumberPad device detected"

    # Check if driver is installed
    if ! execute_command "pacman -Qq asus-numberpad-driver-up5401ea-git &>/dev/null"; then
        print_message "ASUS NumberPad driver is not installed."
        if prompt_yes_no "Would you like to install the ASUS NumberPad driver?"; then
            if ! distro_install "asus-numberpad-driver-up5401ea-git"; then
                print_error "Failed to install ASUS NumberPad driver"
                track_config_status "NumberPad Setup" "$CROSS_MARK"
                return 1
            fi
        else
            print_message "Skipping NumberPad configuration."
            track_config_status "NumberPad Setup" "$CIRCLE (Skipped by user)"
            return 0
        fi
    fi

    # Install system-wide Python dependencies using pacman
    print_message "Installing required Python packages..."
    if ! execute_command "sudo pacman -S --needed --noconfirm python-evdev python-systemd i2c-tools" "Install Python dependencies"; then
        print_error "Failed to install Python dependencies"
        track_config_status "NumberPad Setup" "$CROSS_MARK"
        return 1
    fi

    # Load required kernel modules
    print_message "Loading required kernel modules..."
    execute_command "sudo modprobe i2c-dev" "Load i2c-dev module"
    execute_command "sudo modprobe i2c_hid" "Load i2c_hid module"

    # Add user to i2c group
    if ! groups "$USER" | grep -q "\bi2c\b"; then
        print_message "Adding user to i2c group..."
        execute_command "sudo groupadd -f i2c" "Create i2c group if it doesn't exist"
        execute_command "sudo usermod -aG i2c $USER" "Add user to i2c group"
    fi

    # Set up udev rules for I2C access
    local udev_rule_file="/etc/udev/rules.d/99-i2c.rules"
    print_message "Setting up udev rules for I2C access..."
    execute_command "echo 'KERNEL==\"i2c-[0-9]*\", GROUP=\"i2c\", MODE=\"0660\"' | sudo tee $udev_rule_file" "Create udev rules"
    execute_command "sudo udevadm control --reload-rules && sudo udevadm trigger" "Reload udev rules"

    # Create systemd user service directory if it doesn't exist
    mkdir -p "${HOME}/.config/systemd/user"

    # Create service file
    local SERVICE_NAME="asus_numberpad_driver@"
    local SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}${USER}.service"

    print_message "Creating service file..."
    if ! execute_command "cat > ${SERVICE_FILE} << EOF
[Unit]
Description=Asus NumberPad Driver
StartLimitBurst=20
StartLimitIntervalSec=300

[Service]
Type=simple
Environment=PYTHONPATH=/usr/share/asus-numberpad-driver
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/python3 /usr/share/asus-numberpad-driver/numberpad.py up5401ea /usr/share/asus-numberpad-driver/config
TimeoutSec=5
Restart=on-failure
RestartSec=1
StandardOutput=journal
StandardError=journal
Environment=DISPLAY=\${DISPLAY}
Environment=WAYLAND_DISPLAY=\${WAYLAND_DISPLAY}
Environment=DBUS_SESSION_BUS_ADDRESS=\${DBUS_SESSION_BUS_ADDRESS}
Environment=XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR}
Environment=XDG_SESSION_TYPE=\${XDG_SESSION_TYPE}

[Install]
WantedBy=default.target
EOF" "Create NumberPad service file"; then
        print_error "Failed to create service file"
        track_config_status "NumberPad Setup" "$CROSS_MARK"
        return 1
    fi

    # Set proper permissions
    if ! execute_command "chmod 644 ${SERVICE_FILE}" "Set service file permissions"; then
        print_error "Failed to set service file permissions"
        track_config_status "NumberPad Setup" "$CROSS_MARK"
        return 1
    fi

    # Load modules at boot
    print_message "Configuring modules to load at boot..."
    if ! grep -q "i2c[-_]dev" /etc/modules-load.d/i2c.conf 2>/dev/null; then
        execute_command "echo 'i2c-dev' | sudo tee -a /etc/modules-load.d/i2c.conf" "Add i2c-dev to modules"
    fi
    if ! grep -q "i2c[-_]hid" /etc/modules-load.d/i2c.conf 2>/dev/null; then
        execute_command "echo 'i2c_hid' | sudo tee -a /etc/modules-load.d/i2c.conf" "Add i2c_hid to modules"
    fi

    # Stop any existing service instance and clean up
    print_message "Stopping existing service and cleaning up..."
    execute_command "systemctl --user stop ${SERVICE_NAME}${USER}.service" "Stop existing service" || true
    execute_command "systemctl --user disable ${SERVICE_NAME}${USER}.service" "Disable existing service" || true
    execute_command "systemctl --user daemon-reload" "Reload systemd daemon"

    # Start and enable the service
    print_message "Starting and enabling service..."
    if ! execute_command "systemctl --user enable --now ${SERVICE_NAME}${USER}.service" "Enable and start NumberPad service"; then
        print_error "Failed to enable/start NumberPad service"
        track_config_status "NumberPad Setup" "$CROSS_MARK"
        return 1
    fi

    print_warning "You may need to log out and log back in for group changes to take effect."

    # Wait a moment for the service to start
    sleep 5

    # Check service status and show logs
    print_message "Checking service status and logs..."
    execute_command "systemctl --user status ${SERVICE_NAME}.service --no-pager" "Check service status" || true
    execute_command "journalctl --user -u ${SERVICE_NAME}.service --no-pager -n 20" "Show recent logs"

    # Verify if the service is actually running
    if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
        print_message "NumberPad service is running successfully"
        track_config_status "NumberPad Setup" "$CHECK_MARK"
        return 0
    else
        print_error "NumberPad service failed to start"
        track_config_status "NumberPad Setup" "$CROSS_MARK"
        return 1
    fi
}

# Add backup before GRUB modification
backup_grub_config() {
    local backup_file
    backup_file="/etc/default/grub.backup.$(date +%Y%m%d)"
    if [ ! -f "$backup_file" ]; then
        execute_command "sudo cp /etc/default/grub $backup_file" "Backup GRUB config" || {
            handle_error "Failed to create GRUB config backup at $backup_file. Check permissions."
        }
    fi
}

configure_grub() {
    announce_step "Configuring GRUB"
    # Ensure Linux-Setup folder exists
    if [ ! -d "$SETUP_DIR" ]; then
        print_warning "Linux-Setup folder not found at $SETUP_DIR. Cloning from GitHub..."
        if ! execute_command "git clone $GIT_LINUX_SETUP \"$SETUP_DIR\""; then
            print_error "Failed to clone Linux-Setup repository. Aborting GRUB configuration."
            track_config_status "GRUB Configuration" "$CROSS_MARK"
            return 1
        fi
    fi
    backup_grub_config

    # Copy theme folders
    if [ -d "$SETUP_DIR/System_files/Grub_Themes" ]; then
        # Get list of theme folders
        mapfile -t source_themes < <(ls -d "$GIT_DIR"/Linux-Setup/System_files/Grub_Themes/*/ 2>/dev/null | xargs -n 1 basename)
        for theme in "${source_themes[@]}"; do
            target_dir="/boot/grub/themes/$theme"
            if [ -d "$target_dir" ]; then
                if prompt_yes_no "Theme folder '$theme' already exists. Overwrite?"; then
                    execute_command "sudo rm -rf \"$target_dir\"" "Remove existing theme folder"
                    execute_command "sudo cp -r \"$SETUP_DIR/System_files/Grub_Themes/$theme\" /boot/grub/themes/" "Copy theme folder"
                else
                    # Find next available number
                    counter=1
                    while [ -d "${target_dir}_${counter}" ]; do
                        ((counter++))
                    done
                    new_theme_name="${theme}_${counter}"
                    execute_command "sudo cp -r \"$SETUP_DIR/System_files/Grub_Themes/$theme\" \"/boot/grub/themes/$new_theme_name\"" "Copy theme folder with new name"
                fi
            else
                execute_command "sudo cp -r \"$SETUP_DIR/System_files/Grub_Themes/$theme\" /boot/grub/themes/" "Copy theme folder"
            fi
        done

        # Get available themes after copying
        mapfile -t themes < <(ls -d /boot/grub/themes/*/ 2>/dev/null | xargs -n 1 basename)
        if [ ${#themes[@]} -eq 0 ]; then
            print_warning "No themes found in /boot/grub/themes/"
        else
            echo "Available GRUB themes:"
            for i in "${!themes[@]}"; do
                echo "$((i+1)). ${themes[i]}"
            done

            read -rp "Select theme number (1-${#themes[@]}): "  theme_num
            if [[ "$theme_num"  =~ ^[0-9]+$ ]] && [ "$theme_num" -ge 1  ] && [ "$theme_num" -le "${#themes[@]}" ]; then
                selected_theme="${themes[$((theme_num-1))]}"
                execute_command "sudo sed -i 's|^#\?GRUB_THEME=.*|GRUB_THEME=\"/boot/grub/themes/$selected_theme/theme.txt\"|' /etc/default/grub" "Set GRUB theme"
                print_message "Added GRUB theme configuration: GRUB_THEME=/boot/grub/themes/$selected_theme/theme.txt"
            else
                print_warning "Invalid selection. Skipping theme configuration."
            fi
        fi
    else
        print_warning "Theme folder not found at $SETUP_DIR/System_files/Grub_Themes"
    fi

    if execute_command "sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=4/' /etc/default/grub" "Set GRUB timeout" &&
       execute_command "sudo grub-mkconfig -o /boot/grub/grub.cfg" "Update GRUB"; then
        track_config_status "GRUB Configuration" "$CHECK_MARK"
    else
        track_config_status "GRUB Configuration" "$CROSS_MARK"
    fi
}

configure_timeshift() {
    announce_step "Setting up Timeshift"

    # Ensure Timeshift is installed
    if ! command -v timeshift &>/dev/null; then
        if ! distro_install "timeshift"; then
            track_config_status "Timeshift Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Enable the cronie service (required for scheduling snapshots)
    if ! execute_command "sudo systemctl enable --now cronie.service" "Enable Cronie for Timeshift scheduling"; then
        track_config_status "Timeshift Setup" "$CROSS_MARK"
        return 1
    fi

    # Create an initial snapshot without a .snapshot suffix
    if execute_command "sudo timeshift --create --comments 'Automated snapshot created by Linux-Setup script' --tags D" "Create initial Timeshift snapshot"; then
        track_config_status "Timeshift Setup" "$CHECK_MARK"
    else
        track_config_status "Timeshift Setup" "$CROSS_MARK"
    fi
}

configure_grub_btrfsd() {
    announce_step "Configuring grub-btrfsd"

    # Check if  Bootloader is GRUB
    if ! [ "$BOOTLOADER" == "GRUB" ]; then
        print_warning "Bootloader is not GRUB. Skipping grub-btrfsd configuration."
        track_config_status "grub-btrfsd Configuration" "$CIRCLE (Not GRUB bootloader)"
        return 0
    fi

    # Check if the root filesystem is BTRFS
    if ! mount | grep "on / type btrfs" > /dev/null; then
        print_warning "Root filesystem is not BTRFS. Skipping grub-btrfsd configuration."
        track_config_status "grub-btrfsd Configuration" "$CIRCLE (Not BTRFS filesystem)"
        return 0
    fi

    # Create systemd override directory if it doesn't exist
    if ! execute_command "sudo mkdir -p /etc/systemd/system/grub-btrfsd.service.d" "Create override directory for grub-btrfsd"; then
        track_config_status "grub-btrfsd Configuration" "$CROSS_MARK"
        return 1
    fi

    # Create (or overwrite) a drop-in override file that removes any '.snapshot' and appends '-t' to ExecStart
    if sudo bash -c "cat > /etc/systemd/system/grub-btrfsd.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=\$(grep '^ExecStart=' /etc/systemd/system/grub-btrfsd.service | sed 's/\.snapshot//g; s/\$/ -t/')
EOF"; then
        print_message "grub-btrfsd override file created."
    else
        print_error "Failed to create grub-btrfsd override file."
        track_config_status "grub-btrfsd Configuration" "$CROSS_MARK"
        return 1
    fi

    # Reload systemd daemon and enable the service
    if execute_command "sudo systemctl daemon-reload && sudo systemctl enable --now grub-btrfsd" "Enable grub-btrfsd service"; then
        track_config_status "Enable grub-btrfsd service" "$CHECK_MARK"
    else
        track_config_status "grub-btrfsd Configuration" "$CROSS_MARK"
    fi
}

configure_rocm() {
    announce_step "Setting up ROCm"

    # Add ROCm package installation to configure_rocm
    if ! distro_install "rocm-hip-sdk rocm-opencl-sdk"; then
        print_warning "Failed to install ROCm packages"
    fi

    # Add user to groups
    execute_command "sudo usermod -aG render $USER" "Add user to render group"
    execute_command "sudo usermod -aG video $USER" "Add user to video group"
    # Check if ROCm paths are already in environment
    if grep -q "/opt/rocm/bin" /etc/environment; then
        print_message "ROCm paths already in environment"
    else
        execute_command "echo 'PATH=\$PATH:/opt/rocm/bin:/opt/rocm/hipopen/bin:/opt/rocm/opencl/bin' | sudo tee -a /etc/environment > /dev/null" "Add ROCm paths to environment"
    fi

    # Check if ROCm is properly installed
    if command -v rocminfo &> /dev/null; then
        track_config_status "ROCm Setup" "$CHECK_MARK"
    else
        track_config_status "ROCm Setup" "$CROSS_MARK"
    fi
}

configure_cuda() {
    announce_step "Setting up CUDA"

    # Add CUDA package installation to configure_cuda
    if ! distro_install "cuda cuda-tools"; then
        print_warning "Failed to install CUDA packages"
    fi

    # Add user to groups
    execute_command "sudo usermod -aG render $USER" "Add user to render group"
    execute_command "sudo usermod -aG video $USER" "Add user to video group"
    # Check if CUDA paths are already in environment
    if grep -q "/opt/cuda/bin" /etc/environment; then
        print_message "CUDA paths already in environment"
    else
        print_warning "Failed to find CUDA environment"
    fi

    # Check if CUDA is properly installed
    if command -v cuda &> /dev/null; then
        track_config_status "CUDA Setup" "$CHECK_MARK"
    else
        track_config_status "CUDA Setup" "$CROSS_MARK"
    fi
}

configure_onedrive() {
    announce_step "Setting up OneDrive"
    mkdir -p "$ONEDRIVE_CONFIG_DIR"
    # Copy backup config file if it exists
    if [ -f "$ONEDRIVE_CONFIG_DIR/.config.backup" ]; then
        cp "$ONEDRIVE_CONFIG_DIR/.config.backup" "$ONEDRIVE_CONFIG_DIR/config"
    fi
    local config_file="$ONEDRIVE_CONFIG_DIR/config"
    # Prompt for user input to set the sync directory path and update the config file
    read -rp "Enter sync directory path for OneDrive (Default to: $HOME/Onedrive): " user_sync_dir
    ONEDRIVE_SYNC_DIR="$user_sync_dir"  # Store globally for later use

    # If the folder name is not "onedrive" (case-insensitive), create the folder first if it doesn't exist
    user_basename=$(basename "$user_sync_dir")
    if [[ "${user_basename,,}" != "onedrive" ]]; then
        if [ ! -d "$user_sync_dir" ]; then
            execute_command "mkdir -p \"$user_sync_dir\"" "Create sync directory as it is not named onedrive"
        fi
    fi

    execute_command "sed -i 's|^sync_dir *= *\".*\"|sync_dir = \"$user_sync_dir\"|' \"$config_file\"" "Update sync directory in config file"

    # Install onedrive-abraunegg if not already installed
    if ! command -v onedrive &>/dev/null; then
        print_message "Installing Onedrive..."
        distro_install "onedrive-abraunegg"
    fi

    # Enable and start OneDrive service
    execute_command "systemctl --user enable --now onedrive" "Enable and Start OneDrive"

    # Check OneDrive configuration for sync location
    if [ -f "$config_file" ]; then
        local sync_dir
        sync_dir=$(grep "^sync_dir" "$config_file" | cut -d'"' -f2)
        if [ -n "$sync_dir" ]; then
            print_message "OneDrive configured to sync to: $sync_dir"
            if [ -d "$sync_dir" ]; then
                print_message "Sync directory exists, performing resync"
                if ! execute_command "onedrive --monitor" "Monitor OneDrive"; then
                    print_warning "'onedrive --monitor' failed, attempting 'onedrive --resync'..."
                    execute_command "onedrive --monitor --resync" "Resync OneDrive"
                fi
            else
                print_message "Sync directory does not exist, performing initial sync"
                execute_command "onedrive -s" "Sync OneDrive"
            fi
            track_config_status "OneDrive Setup" "$CHECK_MARK"
        else
            print_message "No sync directory configured, using default"
            execute_command "onedrive -s" "Sync OneDrive"
            track_config_status "OneDrive Setup" "$CHECK_MARK"
        fi
    else
        print_message "OneDrive config not found, performing initial setup"
        if execute_command "onedrive -s" "Sync OneDrive"; then
            track_config_status "OneDrive Setup" "$CHECK_MARK"
        else
            track_config_status "OneDrive Setup" "$CROSS_MARK"
        fi
    fi
}

configure_onedrive_rclone() {
    announce_step "Setting up OneDrive (rclone)"
    
    local SERVICE_FILE="/etc/systemd/system/rclone-onedrive.service"
    RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
    local RCLONE_REMOTE="onedrive:"
    local CACHE_DIR=$HOME/.cache
    local USER_NAME
    USER_NAME=$(whoami)

    # Check if rclone config exists
    if [ ! -f "$RCLONE_CONFIG" ]; then
        print_warning "rclone config not found at $RCLONE_CONFIG."
        read -rp "Do you want to start the rclone config process with 'rclone ls onedrive:'? (y/n): " yn
        case $yn in
            [Yy]* )
                rclone ls onedrive:
                ;;
            * )
                echo "Skipping OneDrive rclone configuration."
                return
                ;;
        esac
    fi

    # Ensure /etc/fuse.conf has user_allow_other enabled (only uncomment '#user_allow_other' with no trailing text)
    if grep -q '^#user_allow_other$' /etc/fuse.conf; then
        print_message "Uncommenting 'user_allow_other' in /etc/fuse.conf"
        execute_command "sudo sed -i 's/^#user_allow_other$/user_allow_other/' /etc/fuse.conf" "Uncomment user_allow_other in /etc/fuse.conf"
    elif ! grep -q '^user_allow_other$' /etc/fuse.conf; then
        print_message "Adding 'user_allow_other' to /etc/fuse.conf"
        execute_command "echo 'user_allow_other' | sudo tee -a /etc/fuse.conf" "Add user_allow_other to /etc/fuse.conf"
    else
        print_message "'user_allow_other' already enabled in /etc/fuse.conf"
    fi

    # Check if mount directory is already mounted
    if mountpoint -q "$RCLONE_ONEDRIVE_DIR"; then
        print_message "$RCLONE_ONEDRIVE_DIR is already mounted. Skipping permission setting and mounting."
    else
        print_message "Create Mount Directory and set Permissions"
        execute_command "sudo mkdir -p $RCLONE_ONEDRIVE_DIR" "Creating Mount Directory" && execute_command "sudo chown $USER_NAME:$USER_NAME $RCLONE_ONEDRIVE_DIR" "Set Permissions for Directory"
    fi

    # Create systemd service file
    if [ ! -f "$SERVICE_FILE" ]; then
        read -rsp "Enter Config Password: " RCLONE_CONFIG_PASS
        execute_command "sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Rclone Mount for OneDrive
After=network-online.target
Wants=network-online.target
AssertPathIsDirectory=$RCLONE_ONEDRIVE_DIR

[Service]
Type=notify
User=$USER_NAME
Group=$USER_NAME
Environment='RCLONE_CONFIG_PASS=$RCLONE_CONFIG_PASS'
ExecStart=/usr/bin/rclone mount $RCLONE_REMOTE $RCLONE_ONEDRIVE_DIR
    --config=$RCLONE_CONFIG
    --allow-other
    --vfs-cache-mode=full
    --cache-dir=$CACHE_DIR
    --vfs-cache-max-size=10G
ExecStop=/bin/fusermount -uz $RCLONE_ONEDRIVE_DIR
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF" "Creating Service File"

        print_message "Created service file: $SERVICE_FILE"
        execute_command "sudo systemctl daemon-reload" "Reload Daemon"
        execute_command "sudo systemctl enable --now rclone-onedrive" "Enable (at startup) and Start Rclone"
        print_message "Service enabled and started!"
    else
        print_message "Service already exists."
    fi
}

configure_network_manager() {
    announce_step "Configuring NetworkManager"
    if command -v nm-connection-editor >/dev/null || command -v nm-applet >/dev/null || command -v nmcli >/dev/null; then
        if execute_command "sudo systemctl enable --now NetworkManager" "Enable NetworkManager"; then
            track_config_status "NetworkManager Setup" "$CHECK_MARK"
        else
            track_config_status "NetworkManager Setup" "$CROSS_MARK"
        fi
    else
        print_warning "Network Manager tools not found. Skipping NetworkManager setup."
        track_config_status "NetworkManager Setup" "$CIRCLE (Not installed)"
    fi
}

configure_wifi() {
    announce_step "Configuring WiFi"
    if execute_command "sudo iw dev wlan0 set power_save off" "Disable WiFi power save"; then
        track_config_status "WiFi Configuration" "$CHECK_MARK"
    else
        track_config_status "WiFi Configuration" "$CROSS_MARK"
    fi
}

configure_waydroid() {
    announce_step "Setting up Waydroid"

    # Check if Waydroid is already installed
    if ! command -v waydroid &>/dev/null; then
        print_message "Waydroid is not installed. Installing..."
        if ! distro_install "waydroid"; then
            print_error "Failed to install Waydroid"
            track_config_status "Waydroid Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Install additional packages
    print_message "Installing additional required packages..."
    for pkg in "binder_linux-dkms" "python-pyclip"; do
        print_message "Installing $pkg..."
        if ! distro_install "$pkg"; then
            print_error "Failed to install $pkg"
            track_config_status "Waydroid Setup" "$CROSS_MARK"
            return 1
        fi
    done

    # Load binder_linux module
    print_message "Loading binder_linux module..."
    if ! execute_command "sudo modprobe -a binder_linux" "Load binder_linux module"; then
        print_error "Failed to load binder_linux module"
        track_config_status "Waydroid Setup" "$CROSS_MARK"
        return 1
    fi

    # Setup binderfs mount point
    print_message "Setting up binderfs mount point..."
    if ! execute_command "sudo mkdir -p /dev/binderfs" "Create binderfs directory"; then
        print_error "Failed to create binderfs directory"
        track_config_status "Waydroid Setup" "$CROSS_MARK"
        return 1
    fi

    if ! execute_command "sudo mount -t binder none /dev/binderfs" "Mount binderfs"; then
        print_error "Failed to mount binderfs"
        track_config_status "Waydroid Setup" "$CROSS_MARK"
        return 1
    fi

    # Add persistent mount to fstab if not already present
    if ! grep -q "/dev/binderfs" "$FSTAB_CONFIG"; then
        print_message "Adding binderfs to $FSTAB_CONFIG..."
        echo "none /dev/binderfs binder nofail 0 0" | sudo tee -a "$FSTAB_CONFIG"
    fi

    # Initialize Waydroid with GAPPS
    print_message "Initializing Waydroid with GAPPS..."
    if ! execute_command "sudo waydroid init -s GAPPS" "Initialize Waydroid"; then
        print_error "Failed to initialize Waydroid"
        track_config_status "Waydroid Setup" "$CROSS_MARK"
        return 1
    fi

    # Enable and start Waydroid container
    print_message "Starting Waydroid container..."
    if ! execute_command "sudo systemctl enable --now waydroid-container" "Enable Waydroid container"; then
        print_error "Failed to enable Waydroid container"
        track_config_status "Waydroid Setup" "$CROSS_MARK"
        return 1
    fi

    # Configure Waydroid properties
    print_message "Configuring Waydroid properties..."
    execute_command "waydroid prop set persist.waydroid.fake_wifi com.android.vending" "Set Waydroid properties"

    # Restart Waydroid services
    print_message "Restarting Waydroid services..."
    execute_command "sudo systemctl restart waydroid-container" "Restart Waydroid container"
    execute_command "waydroid session stop" "Stop Waydroid session"
    execute_command "waydroid session start" "Start Waydroid session"

    # Configure networking
    print_message "Configuring networking..."
    execute_command "sudo sysctl -w net.ipv4.ip_forward=1" "Enable IP forwarding"
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

    # Configure firewall
    print_message "Configuring firewall..."
    execute_command "sudo firewall-cmd --zone=trusted --add-port=67/udp" "Configure firewall UDP port 67"
    execute_command "sudo firewall-cmd --zone=trusted --add-port=53/udp" "Configure firewall UDP port 53"
    execute_command "sudo firewall-cmd --zone=trusted --add-forward" "Enable firewall forwarding"
    execute_command "sudo firewall-cmd --zone=trusted --add-interface=waydroid0" "Add waydroid0 interface"
    execute_command "sudo firewall-cmd --runtime-to-permanent" "Make firewall changes permanent"

    # Show Android ID for Google Play Services
    print_message "Retrieving Android ID..."
    execute_command "sudo waydroid shell \"ANDROID_RUNTIME_ROOT=/apex/com.android.runtime sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \\\"select * from main where name = 'android_id';\\\"\"" "Get Android ID"

    # Launch Waydroid UI
    print_message "Launching Waydroid UI..."
    execute_command "waydroid show-full-ui" "Launch Waydroid UI"

    track_config_status "Waydroid Setup" "$CHECK_MARK"
    print_message "Waydroid setup completed successfully!"
}

# Function to list currently preloaded programs
list_preloaded_programs() {
    echo -e "\n${GREEN}Currently preloaded programs:${NC}"
    if [ -d "$GOPRELOAD_DIR/enabled" ]; then
        if [ "$(ls -A "$GOPRELOAD_DIR"/enabled 2>/dev/null)" ]; then
            for prog in "$GOPRELOAD_DIR"/enabled/*; do
                echo "  - $(basename "$prog")"
            done
        else
            echo "  None"
        fi
    else
        echo "  Preload directory not found"
    fi
    
    echo -e "\n${YELLOW}Disabled preloaded programs:${NC}"
    if [ -d "$GOPRELOAD_DIR/disabled" ]; then
        if [ "$(ls -A "$GOPRELOAD_DIR"/disabled 2>/dev/null)" ]; then
            for prog in "$GOPRELOAD_DIR"/disabled/*; do
                echo "  - $(basename "$prog")"
            done
        else
            echo "  None"
        fi
    else
        echo "  Preload directory not found"
    fi
}

configure_preload() {
    announce_step "Configuring Preload Applications"
    
    # Check if gopreload is installed
    if ! command -v gopreload-prepare >/dev/null 2>&1; then
        print_message "gopreload-prepare is not installed. Installing..."
        if ! distro_install "gopreload-git"; then
            print_error "Failed to install gopreload-git"
            track_config_status "Preload Setup" "$CROSS_MARK"
            return 1
        fi
    fi
    
    # Start and enable preload service immediately after installation
    print_message "Enabling and starting gopreload service..."
    if execute_command "sudo systemctl enable --now gopreload.service" "Enable and start gopreload service"; then
        print_message "Successfully enabled and started gopreload service"
    else
        print_error "Failed to enable and start gopreload service"
    fi
    
    # Ensure directories exist and have correct permissions
    execute_command "sudo mkdir -p $GOPRELOAD_DIR/enabled $GOPRELOAD_DIR/disabled" "Create gopreload directories if they don't exist"
    execute_command "sudo chown $USER:users $GOPRELOAD_DIR/enabled $GOPRELOAD_DIR/disabled" "Set permissions for gopreload directories"
    
    # Choose operation
    PS3="Select operation: "
    options=("Add program to preload" "Remove program from preload" "Refresh preload list" "View preloaded programs" "Enable/Disable preloaded program" "Quit")
    select opt in "${options[@]}"; do
        case $opt in
            "Add program to preload")
                read -rp "Enter the program name to preload: " program_name
                if command -v "$program_name" >/dev/null 2>&1; then
                    print_message "Preparing to preload $program_name..."
                    print_message "Please wait for the program to fully load, then press Enter"
                    if execute_command "gopreload-prepare $program_name" "Prepare $program_name for preloading"; then
                        print_message "Successfully added $program_name to preload list"
                    else
                        print_error "Failed to add $program_name to preload list"
                    fi
                else
                    print_error "Program '$program_name' not found. Make sure it's installed and in your PATH"
                fi
                list_preloaded_programs
                break
                ;;
            "Remove program from preload")
                list_preloaded_programs
                read -rp "Enter the program name to remove from preload: " program_name
                if [ -f "$GOPRELOAD_DIR/enabled/$program_name" ]; then
                    if execute_command "rm -f $GOPRELOAD_DIR/enabled/$program_name" "Remove $program_name from preload"; then
                        print_message "Successfully removed $program_name from preload list"
                    else
                        print_error "Failed to remove $program_name from preload list"
                    fi
                elif [ -f "$GOPRELOAD_DIR/disabled/$program_name" ]; then
                    if execute_command "rm -f $GOPRELOAD_DIR/disabled/$program_name" "Remove disabled $program_name from preload"; then
                        print_message "Successfully removed disabled $program_name from preload list"
                    else
                        print_error "Failed to remove disabled $program_name from preload list"
                    fi
                else
                    print_error "Program '$program_name' not found in preload lists"
                fi
                list_preloaded_programs
                break
                ;;
            "Refresh preload list")
                print_message "Refreshing all preloaded programs..."
                print_message "This might take a while. Please don't use the system during refresh."
                if execute_command "gopreload-batch-refresh.sh" "Refresh all preload lists"; then
                    print_message "Successfully refreshed all preload lists"
                else
                    print_error "Failed to refresh preload lists"
                fi
                break
                ;;
            "View preloaded programs")
                list_preloaded_programs
                break
                ;;
            "Enable/Disable preloaded program")
                list_preloaded_programs
                read -rp "Enter the program name to toggle (enable/disable): " program_name
                
                if [ -f "$GOPRELOAD_DIR/enabled/$program_name" ]; then
                    # Disable: move from enabled to disabled
                    if execute_command "mv $GOPRELOAD_DIR/enabled/$program_name $GOPRELOAD_DIR/disabled/" "Disable $program_name preloading"; then
                        print_message "Successfully disabled preloading for $program_name"
                    else
                        print_error "Failed to disable preloading for $program_name"
                    fi
                elif [ -f "$GOPRELOAD_DIR/disabled/$program_name" ]; then
                    # Enable: move from disabled to enabled
                    if execute_command "mv $GOPRELOAD_DIR/disabled/$program_name $GOPRELOAD_DIR/enabled/" "Enable $program_name preloading"; then
                        print_message "Successfully enabled preloading for $program_name"
                    else
                        print_error "Failed to enable preloading for $program_name"
                    fi
                else
                    print_error "Program '$program_name' not found in preload lists"
                fi
                list_preloaded_programs
                break
                ;;
            "Quit")
                break
                ;;
            *) 
                print_error "Invalid option" 
                ;;
        esac
    done
    
    # Display final status
    if systemctl is-active --quiet gopreload.service; then
        track_config_status "Preload Setup" "$CHECK_MARK"
    else
        track_config_status "Preload Setup" "$CIRCLE (Service not active)"
    fi
}

configure_rust() {
    announce_step "Configuring Rust (skipping install if not present)"

    # Only proceed if rustup or cargo is already installed
    if ! command -v rustup &>/dev/null && ! command -v cargo &>/dev/null; then
        print_warning "Rust is not installed. Skipping Rust setup."
        track_config_status "Rust Setup" "$CIRCLE (Rust not installed)"
        return 0
    fi

    # Ensure cargo is in PATH
    if ! command -v cargo &>/dev/null && [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # Set default toolchain to stable (if rustup is available)
    if command -v rustup &>/dev/null; then
        if ! rustup default stable; then
            print_error "Failed to set default Rust toolchain to stable."
            track_config_status "Rust Setup" "$CROSS_MARK"
            return 1
        fi

        # Install common developer components
        print_message "Installing common Rust developer components (clippy, rustfmt)..."
        rustup component add clippy rustfmt
    fi

    # Optionally install useful global cargo tools
    if command -v cargo &>/dev/null; then
        local tools=("cargo-edit" "cargo-watch" "cargo-audit" "cargo-outdated")
        for tool in "${tools[@]}"; do
            if ! cargo install --locked "$tool"; then
                print_warning "Failed to install $tool (may already be installed or not needed)."
            fi
        done
    fi

    print_message "Rust setup complete!"
    track_config_status "Rust Setup" "$CHECK_MARK"
}

configure_torbrowser() {
    announce_step "Configuring Tor Browser"

    # Install required packages
    local packages=("tor" "nyx" "torsocks" "torbrowser-launcher")
    for pkg in "${packages[@]}"; do
        if ! pacman -Qq "$pkg" &>/dev/null; then
            print_message "Installing missing package: $pkg"
            if ! distro_install "$pkg"; then
                print_error "Failed to install $pkg. Aborting Tor configuration."
                track_config_status "Tor Browser Setup" "$CROSS_MARK"
                return 1
            fi
        fi
    done

    # Ensure sudoers entry for passwordless tor start
    local sudoers_line="$TOR_USER ALL=(tor) NOPASSWD: /usr/bin/tor"
    local sudoers_file="/etc/sudoers.d/99-tor-nopasswd"
    if ! sudo grep -q "$sudoers_line" "$sudoers_file" 2>/dev/null; then
        print_message "Adding sudoers entry for passwordless Tor start..."
        echo "$sudoers_line" | sudo tee "$sudoers_file" > /dev/null
        sudo chmod 440 "$sudoers_file"
    else
        print_message "Sudoers entry for passwordless Tor already present."
    fi

    # Configure /etc/tor/torrc
    local torrc="/etc/tor/torrc"
    local torrc_bak
    torrc_bak="/etc/tor/torrc.bak.$(date +%Y%m%d%H%M%S)"
    if [ -f "$torrc" ]; then
        execute_command "sudo cp $torrc $torrc_bak" "Backup torrc"
    fi

    # Prompt for password and generate hash
    set +o history
    read -rsp "Input your new Tor password (will not echo): " your_password
    echo
    set -o history
    local hash
    hash=$(tor --hash-password "$your_password" 2>/dev/null | grep '^16:' || true)
    if [ -z "$hash" ]; then
        print_error "Failed to generate Tor hashed password"
        track_config_status "Tor Browser Setup" "$CROSS_MARK"
        return 1
    fi

    # Write torrc config
    if ! execute_command "sudo bash -c 'cat > $torrc <<EOF
ControlPort 9051
CookieAuthentication 1
CookieAuthFile /var/lib/tor/control_auth_cookie
CookieAuthFileGroupReadable 1
DataDirectoryGroupReadable 1
HashedControlPassword $hash
ControlSocket /var/lib/tor/control_socket
ControlSocketsGroupWritable 1
EOF
'" "Write Tor configuration"; then
        print_error "Failed to write torrc"
        track_config_status "Tor Browser Setup" "$CROSS_MARK"
        return 1
    fi

    # Ensure /var/lib/tor permissions are correct
    print_message "Ensuring /var/lib/tor is owned by tor:tor and has 700 permissions..."
    execute_command "sudo chown -R tor:tor /var/lib/tor" "Set ownership of /var/lib/tor"
    execute_command "sudo chmod 700 /var/lib/tor" "Set permissions of /var/lib/tor"

    # Check if Tor is running (by port 9050)
    if ss -nlt | grep -q ':9050'; then
        print_message "Tor is already running (port 9050 open)."
    else
        print_message "Tor is not running. Starting Tor as background process..."
        # Start Tor as tor user (background)
        execute_command "sudo -u tor /usr/bin/tor -f /etc/tor/torrc & disown" "Start Tor as tor user"
        sleep 3
        if ss -nlt | grep -q ':9050'; then
            print_message "Tor started successfully."
        else
            print_error "Failed to start Tor."
            track_config_status "Tor Browser Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Add user to tor group (optional, for control port access)
    if ! groups "$TOR_USER" | grep -qw tor; then
        execute_command "sudo usermod -a -G tor $TOR_USER" "Add user to tor group"
        print_warning "You have been added to the 'tor' group. Please log out and log in again for group changes to take effect."
    fi

    # Print status and test
    print_message "Verifying Tor port (should show 9050):"
    execute_command "ss -nlt | grep 9050" "Check Tor port"

    print_message "Launching Tor Browser Launcher for first run (you may need to complete setup manually)..."
    execute_command "torbrowser-launcher" "Launch Tor Browser"

    print_message "Visit https://check.torproject.org to verify Tor is working."

    track_config_status "Tor Browser Setup" "$CHECK_MARK"
}

configure_drives() {
    announce_step "Auto-mounting internal drives (SSD/HDD/NVMe) to $FSTAB_CONFIG"

    # Scan all disks and partitions (not just partitions)
    local devices=()
    local summary=()
    local added_any=0

    print_message "Scanning for internal disks and partitions (excluding USB and loop devices)..."
    while IFS= read -r line; do
        local dev_name dev_type tran
        dev_name="$(echo "$line" | awk '{print $1}')"
        dev_type="$(echo "$line" | awk '{print $2}')"
        tran="$(udevadm info --query=property --name=/dev/"$dev_name" 2>/dev/null | grep '^ID_BUS=' | cut -d'=' -f2)"
        local dev_path="/dev/$dev_name"
        local mountpoint
        mountpoint=$(lsblk -nr -o MOUNTPOINT "$dev_path" | awk 'NF{print; exit}')
        print_verbose "Found device: $dev_path (type: $dev_type, bus: $tran)"
        if [[ ("$dev_type" == "part" || "$dev_type" == "disk") && "$tran" != "usb" ]]; then
            if [[ -n "$mountpoint" ]]; then
                print_verbose "  -> $dev_path is already mounted at $mountpoint, skipping."
                summary+=("$dev_path|$dev_type|$mountpoint|already mounted")
            else
                devices+=("$dev_path")
                print_verbose "  -> Added $dev_path to candidate list."
                summary+=("$dev_path|$dev_type|--|candidate")
            fi
        else
            print_verbose "  -> Skipped $dev_path (not internal disk/partition or is USB)"
            summary+=("$dev_path|$dev_type|--|skipped (not internal or is USB)")
        fi
    done < <(lsblk -nr -o NAME,TYPE)   # now lists both disks and partitions

    if [ ${#devices[@]} -eq 0 ]; then
        print_warning "No internal disks or partitions found to add to $FSTAB_CONFIG."
    fi

    for dev in "${devices[@]}"; do
        print_message "\nProcessing: $dev"
        # Get UUID and filesystem
        local uuid fstype
        uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null)
        fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
        print_verbose "  -> UUID: $uuid, Filesystem: $fstype"
        if [[ -z "$uuid" || -z "$fstype" ]]; then
            print_warning "  -> Skipping $dev (missing UUID or filesystem type)"
            continue
        fi
        # Check if already in fstab
        if grep -q "UUID=$uuid" "$FSTAB_CONFIG"; then
            print_message "  -> $dev (UUID=$uuid) already in $FSTAB_CONFIG, skipping."
            continue
        fi
        # Suggest a mount point
        local label mount_point
        label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
        if [[ -z "$label" ]]; then
            label=$(basename "$dev")
        fi
        mount_point="/mnt/$label"
        print_verbose "  -> Proposed mount point: $mount_point"
        # Create mount point if it doesn't exist
        if [ ! -d "$mount_point" ]; then
            print_message "  -> Creating mount point: $mount_point"
            execute_command "sudo mkdir -p '$mount_point'" "Create mount point $mount_point"
        else
            print_verbose "  -> Mount point $mount_point already exists."
        fi
        # Add to fstab
        local fstab_entry
        fstab_entry="UUID=$uuid $mount_point $fstype defaults,nofail 0 0"
        print_message "  -> Adding to $FSTAB_CONFIG: $fstab_entry"
        execute_command "echo '$fstab_entry' | sudo tee -a $FSTAB_CONFIG" "Add $dev to $FSTAB_CONFIG"
        added_any=1
    done

    # Print summary table
    echo -e "\n${YELLOW}Device Summary:${NC}"
    printf '%-18s %-10s %-20s %-30s\n' "Device" "Type" "Mountpoint" "Status"
    printf '%-18s %-10s %-20s %-30s\n' "------" "----" "----------" "------"
    for entry in "${summary[@]}"; do
        IFS='|' read -r dev type mnt status <<< "$entry"
        printf '%-18s %-10s %-20s %-30s\n' "$dev" "$type" "$mnt" "$status"
    done
    print_message "\nDrive auto-mounting complete."

    if [[ "$added_any" -eq 1 ]]; then
        print_message "Updating GRUB configuration..."
        execute_command "grub-update" "Update GRUB config"
    else 
        print_message "No drives mounted"
    fi
}

configure_sensor() {
    announce_step "Setting up hardware sensors (lm_sensors, psensor)"

    # Check and install lm_sensors
    if ! command -v sensors &>/dev/null; then
        print_message "lm_sensors is not installed. Installing..."
        if ! distro_install "lm_sensors"; then
            print_error "Failed to install lm_sensors"
            track_config_status "Sensor Setup" "$CROSS_MARK"
            return 1
        fi
    else
        print_message "lm_sensors is already installed."
    fi

    # Check and install psensor
    if ! command -v psensor &>/dev/null; then
        print_message "psensor is not installed. Installing..."
        if ! distro_install "psensor"; then
            print_error "Failed to install psensor"
            track_config_status "Sensor Setup" "$CROSS_MARK"
            return 1
        fi
    else
        print_message "psensor is already installed."
    fi

    # Ask user if they want to run sensors-detect
    if prompt_yes_no "Would you like to start sensor scans with 'sudo sensors-detect'?"; then
        print_message "Starting sensors-detect. Please follow the prompts in the terminal."
        if ! execute_command "sudo sensors-detect" "Run sensors-detect"; then
            print_warning "sensors-detect did not complete successfully."
            track_config_status "Sensor Setup" "$CIRCLE (sensors-detect failed)"
            return 1
        fi
    else
        print_message "Skipping sensors-detect as per user request."
    fi

    print_message "Sensor setup completed."
    track_config_status "Sensor Setup" "$CHECK_MARK"
}

configure_cooler() {
    announce_step "Starting cooler configuration"
    
    # Check if liquidctl is installed
    print_message "Checking if liquidctl is installed..."
    if ! pacman -Q liquidctl &>/dev/null; then
        print_message "liquidctl not found. Installing..."
        if ! distro_install "liquidctl"; then
            print_error "Failed to install liquidctl."
            return 1
        fi
        print_message "liquidctl installed successfully."
    else
        print_message "liquidctl is already installed."
    fi

    # Check for Coolers
    print_message "Checking for compatible cooling devices..."
    if ! execute_command "sudo liquidctl status" "Checking for Devices"; then
        print_message "No devices found or permission issues detected. Setting up udev rules..."
        
        # Download the udev rules file
        print_message "Downloading udev rules file..."
        if ! execute_command "sudo curl -o /etc/udev/rules.d/71-liquidctl.rules https://raw.githubusercontent.com/liquidctl/liquidctl/refs/heads/main/extra/linux/71-liquidctl.rules" "Download and install udev rules"; then
            print_error "Failed to download udev rules. Please check your internet connection."
            return 1
        fi
        
        # Verify the rules file was downloaded
        if [ ! -f "/etc/udev/rules.d/71-liquidctl.rules" ]; then
            print_error "udev rules file was not created properly."
            return 1
        fi
        
        print_message "Reloading udev rules..."
        if ! execute_command "sudo udevadm control --reload-rules" "Reload Rules"; then
            print_error "Failed to reload udev rules."
            return 1
        fi
        
        print_message "Triggering udev rules..."
        if ! execute_command "sudo udevadm trigger" "Create trigger"; then
            print_error "Failed to trigger udev rules."
            return 1
        fi
        
        print_warning "Setup complete. Please reboot your device and run 'configure_cooler' again to verify the configuration."
        return 0
    else
        print_message "Cooling devices detected successfully."
        
        # Additional verification step
        print_message "Verifying device access..."
        if ! execute_command "sudo liquidctl status" "Verify device access"; then
            print_error "Device detected but unable to access. Please check permissions."
            return 1
        fi
        
        print_message "Cooler configuration completed successfully."
    fi
}

############################################################## Hyprland Configurations ##############################################################

configure_bluetooth() {
    announce_step "Configuring Bluetooth"
    for pkg in bluez bluez-utils blueman; do
        if ! pacman -Qq "$pkg" &>/dev/null; then
            print_message "Installing missing package: $pkg"
            if ! distro_install "$pkg"; then
                print_error "Failed to install $pkg. Aborting Bluetooth configuration."
                return 1
            fi
        fi
    done

    print_message "Enabling Bluetooth..."
    if execute_command "sudo systemctl enable --now bluetooth" "Enable and start Bluetooth"; then
        track_config_status "Bluetooth Setup" "$CHECK_MARK"
    else
        track_config_status "Bluetooth Setup" "$CROSS_MARK"
    fi
}

configure_notification() {
    announce_step "Configuring Dunst Notification Daemon"

    # Check if running in Hyprland
    if [[ "$XDG_CURRENT_DESKTOP" != *Hyprland* ]] && [[ "$DESKTOP_SESSION" != *hyprland* ]]; then
        print_warning "Not running in Hyprland environment. Skipping notification configuration."
        track_config_status "Notification Setup" "$CIRCLE (Not Hyprland)"
        return 0
    fi

    local SERVICE_NAME="dunst.service"
    local USER_SYSTEMD_DIR="/usr/lib/systemd/user/"
    local SERVICE_PATH="$USER_SYSTEMD_DIR/$SERVICE_NAME"
    local DUNST_RUNNING=false

    # Check if dunst is installed
    if ! command -v dunst &>/dev/null; then
        print_message "Dunst is not installed. Installing..."
        if ! distro_install "dunst"; then
            print_error "Failed to install dunst."
            track_config_status "Notification Setup" "$CROSS_MARK"
            return 1
        fi
    fi

    # Check if Dunst is running
    if pgrep -x "dunst" >/dev/null; then
        DUNST_RUNNING=true
        print_message "Dunst notification daemon is currently running."
    fi

    # Function to verify service file contents
    verify_service_file() {
        if [ ! -f "$SERVICE_PATH" ]; then
            return 1
        fi
        if ! grep -q "Description=Dunst notification daemon" "$SERVICE_PATH" || \
           ! grep -q "ExecStart=/usr/bin/dunst" "$SERVICE_PATH" || \
           ! grep -q "WantedBy=default.target" "$SERVICE_PATH" || \
           ! grep -q "Type=dbus" "$SERVICE_PATH" || \
           ! grep -q "BusName=org.freedesktop.Notifications" "$SERVICE_PATH"; then
            return 1
        fi
        return 0
    }

    # Function to create correct service file
    create_service_file() {
        mkdir -p "$USER_SYSTEMD_DIR"
        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Dunst notification daemon
Documentation=man:dunst(1)
PartOf=graphical-session.target
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/bin/dunst
Restart=on-failure
RestartSec=3
Environment="DISPLAY=:0"
Environment="WAYLAND_DISPLAY=wayland-0"
Slice=session.slice

[Install]
WantedBy=default.target
EOF
    }

    # Check if service file exists and is correct
    if verify_service_file; then
        print_message "Service file exists and is correctly configured."
    else
        print_message "Service file is missing or incorrect. Creating correct service file..."
        
        # Stop Dunst if it's running
        if $DUNST_RUNNING; then
            print_message "Stopping running Dunst instance..."
            pkill dunst
            sleep 1
        fi

        # Create correct service file
        create_service_file
        
        # Verify the new service file
        if ! verify_service_file; then
            print_error "Failed to create correct service file."
            track_config_status "Notification Setup" "$CROSS_MARK"
            return 1
        fi

        execute_command "systemctl --user daemon-reload" "Reload user systemd daemon"
        execute_command "systemctl --user enable --now $SERVICE_NAME" "Enable and start Dunst service"
        print_message "Dunst service file corrected and service restarted."
    fi

    # Start the service if not running
    if ! systemctl --user is-active --quiet "$SERVICE_NAME"; then
        execute_command "systemctl --user start $SERVICE_NAME" "Start Dunst service"
        print_message "Dunst service started."
    fi

    # Send test notification
    if command -v notify-send >/dev/null 2>&1; then
        execute_command "notify-send 'Test Notification' 'Dunst is configured and running!'" "Send test notification"
        print_message "Test notification sent."
        track_config_status "Notification Setup" "$CHECK_MARK"
    else
        print_warning "notify-send not found. Please install libnotify."
        track_config_status "Notification Setup" "$CIRCLE (notify-send missing)"
    fi
}

configure_wallpaper_path() {
    announce_step "Configuring Wallpaper Path"
    # If OneDrive directory is not already configured, try to find it automatically.
    if [ -z "$ONEDRIVE_SYNC_DIR" ]; then
        # Check in /home (only immediate subdirectories)
        for d in /home/*; do
            if [ -d "$d" ] && [[ "$(basename "$d")" =~ [Oo]nedrive ]]; then
                ONEDRIVE_SYNC_DIR="$d"
                break
            fi
        done
        # If not found in /home, search in /mnt (recursively, up to 2 levels deep)
        if [ -z "$ONEDRIVE_SYNC_DIR" ]; then
            ONEDRIVE_SYNC_DIR=$(find /mnt -maxdepth 2 -type d -iname "*onedrive*" 2>/dev/null | head -n 1)
        fi
        # If still not found, prompt the user.
        if [ -z "$ONEDRIVE_SYNC_DIR" ]; then
            read -rp "OneDrive is not configured. Enter the path to your OneDrive directory (e.g., ~/Onedrive): " onedrive_input
            ONEDRIVE_SYNC_DIR="$onedrive_input"
        fi
    fi

    local onedrive_base="$ONEDRIVE_SYNC_DIR"
    local wallpaper_dir="${onedrive_base}/$PICTURE_DIR/WallPaper"
    local config_file="${HOME}/.config/hypr/sources/change_wallpaper.conf"

    # Check if configuration file exists, otherwise skip
    if [ ! -f "$config_file" ]; then
        print_warning "Configuration file not found: $config_file. Skipping wallpaper configuration."
        return 0
    fi

    if [ -d "$onedrive_base" ]; then
        if [ -d "$wallpaper_dir" ]; then
            if grep -q "^WALLPAPER_DIR=" "$config_file"; then
                sed -i "s|^WALLPAPER_DIR=.*|WALLPAPER_DIR=\"$wallpaper_dir\"|" "$config_file"
            else
                echo "WALLPAPER_DIR=\"$wallpaper_dir\"" >> "$config_file"
            fi
            print_message "Wallpaper path configured to: $wallpaper_dir"
        else
            print_warning "Wallpaper directory not found at: $wallpaper_dir"
        fi
    else
        print_warning "OneDrive directory not found at: $onedrive_base"
    fi
}

configure_hyprlock_wallpaper() {
    announce_step "Configuring Hyprlock wallpaper"
    local default_wallpaper="$GIT_DIR/Hyprland-Simple-Setup/Wallpaper/Forest_01.png"
    local config_file="${HOME}/.config/hypr/sources/app_variables.conf"
    local repo_url="https://github.com/Firstp1ck/Hyprland-Simple-Setup.git"
    local repo_path="$GIT_DIR/Hyprland-Simple-Setup"
    local wallpaper_path=""

    # Check if default wallpaper exists
    if [ -f "${default_wallpaper/#\~/$HOME}" ]; then
        wallpaper_path="$default_wallpaper"
    else
        # Check if repo exists
        if [ ! -d "$repo_path" ]; then
            print_message "Cloning Hyprland setup repository..."
            if ! execute_command "git clone $repo_url $repo_path" "Clone Hyprland setup repository"; then
                print_error "Failed to clone repository"
                return 1
            fi
        fi

        # Check for Forest_01.png in the cloned repo
        if [ -f "$repo_path/Wallpaper/Forest_01.png" ]; then
            wallpaper_path="$GIT_DIR/Hyprland-Simple-Setup/Wallpaper/Forest_01.png"
        else
            # Get first wallpaper from the Wallpaper directory
            local first_wallpaper
            first_wallpaper=$(find "$repo_path/Wallpaper" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) | head -n 1)
            if [ -n "$first_wallpaper" ]; then
                wallpaper_path="$HOME${first_wallpaper#"$HOME"}"
            else
                print_error "No wallpapers found in repository"
                return 1
            fi
        fi
    fi

    # Update or add wallpaper path to config file
    if [ -n "$wallpaper_path" ]; then
        if [ -f "$config_file" ]; then
            if grep -q "^\$lockscreen_wallpaper=" "$config_file"; then
                execute_command "sed -i 's|^\$lockscreen_wallpaper=.*|\$lockscreen_wallpaper=\"$wallpaper_path\"|' \"$config_file\"" "Update lockscreen wallpaper path"
            else
                execute_command "echo '\$lockscreen_wallpaper=\"$wallpaper_path\"' >> \"$config_file\"" "Add lockscreen wallpaper path"
            fi
            print_message "Hyprlock wallpaper configured: $wallpaper_path"
            track_config_status "Hyprlock Wallpaper" "$CHECK_MARK"
        else
            print_error "Configuration file not found: $config_file"
            track_config_status "Hyprlock Wallpaper" "$CROSS_MARK"
            return 1
        fi
    else
        print_error "No valid wallpaper found"
        track_config_status "Hyprlock Wallpaper" "$CROSS_MARK"
        return 1
    fi
}

configure_gnome_keyring() {
    announce_step "Configuring gnome-keyring"

    if [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || [ "$XDG_CURRENT_DESKTOP" = "plasma" ] || pgrep -x "plasmashell" > /dev/null; then
        print_message "KDE environment detected. Skipping gnome-keyring configuration."
        track_config_status "Gnome-keyring Setup" "$CIRCLE (Not needed in KDE)"
        return 0
    fi

    if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
        print_warning "gnome-keyring is not installed. Installing..."
        distro_install "gnome-keyring"
    else
        print_message "gnome-keyring is already installed."
    fi

    if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/login; then
        print_message "Adding PAM configurations for gnome-keyring to /etc/pam.d/login..."
        echo "auth optional pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/login > /dev/null
        echo "session optional pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/login > /dev/null
    else
        print_message "PAM configuration for gnome-keyring already exists in /etc/pam.d/login."
    fi

    print_message "Starting gnome-keyring-daemon..."
    if pgrep -f gnome-keyring-daemon >/dev/null; then
        print_message "gnome-keyring-daemon already running."
    else
        /usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets,ssh &>/dev/null &
        print_message "gnome-keyring-daemon is set..."
    fi

    track_config_status "Gnome-keyring Setup" "$CHECK_MARK"
}

configure_filepicker() {
    announce_step "Configuring filepicker"

    if ! check_hyprland; then
        print_message "Not running in Hyprland. Skipping filepicker configuration."
        track_config_status "Filepicker Setup" "$CIRCLE (Not in Hyprland)"
        return 0
    fi

    local conf_dir="${HOME}/.config/xdg-desktop-portal"
    local conf_file="${conf_dir}/hyprland-portals.conf"
    local desired_content="[preferred]
default = hyprland;gtk
org.freedesktop.impl.portal.FileChooser = kde"
    mkdir -p "$conf_dir"
    if [ -f "$conf_file" ]; then
        if grep -q "default = hyprland;gtk" "$conf_file" && grep -q "org.freedesktop.impl.portal.FileChooser = kde" "$conf_file"; then
            print_message "Filepicker configuration already set."
        else
            print_message "Updating filepicker configuration..."
            execute_command "echo \"$desired_content\" > \"$conf_file\"" "Update filepicker configuration"
        fi
    else
        print_message "Creating filepicker configuration..."
        execute_command "echo \"$desired_content\" > \"$conf_file\"" "Create filepicker configuration"
    fi

    if [ ! -L "/etc/xdg/menus/applications.menu" ]; then
        sudo ln -s /etc/xdg/menus/plasma-applications.menu /etc/xdg/menus/applications.menu
    else
        print_message "Symlink for applications.menu already exists."
    fi

    track_config_status "Filepicker Setup" "$CHECK_MARK"
}

configure_monitor() {
    announce_step "Configuring monitor"

    # Ask user if they want to proceed with monitor setup
    if ! prompt_yes_no "Would you like to configure your monitor settings?"; then
        print_message "Monitor setup skipped by user."
        track_config_status "Monitor Setup" "$CIRCLE (Skipped by user)"
        return 0
    fi

    if check_hyprland; then
        local monitor_output
        monitor_output=$(hyprctl monitors 2>&1)
        print_message "Hyprland monitor configuration:"
        echo "$monitor_output"
        local monitor_count
        monitor_count=$(echo "$monitor_output" | grep -E -c "^Monitor")
        print_message "Detected $monitor_count monitor(s) on Hyprland."
        if [ "$monitor_count" -eq 0 ]; then
            print_warning "No monitors detected via hyprctl monitors."
            return
        fi

        local monitor_names=()
        while IFS= read -r line; do
            monitor_names+=("$(echo "$line" | awk '{print $2}')")
        done < <(echo "$monitor_output" | grep "^Monitor")

        local primary_monitor=""
        local primary_width=""

        while true; do
            print_message "Available monitors:"
            local i=0
            for name in "${monitor_names[@]}"; do
                print_message "$i: $name"
                ((i++))
            done
            read -rp "Select monitor number: " monitor_index
            chosen_monitor="${monitor_names[$monitor_index]}"

            local modes_lines mode_line
            modes_lines=$(echo "$monitor_output" | grep "availableModes:")
            if [ -n "$modes_lines" ]; then
                declare -A ratio_modes
                gcd() {
                    local a=$1
                    local b=$2
                    while [ "$b" -ne 0 ]; do
                        local temp=$b
                        b=$(( a % b ))
                        a=$temp
                    done
                    echo "$a"
                }
                for mode_line in $modes_lines; do
                    local modes_str
                    modes_str=${mode_line#*availableModes: }
                    for mode in $modes_str; do
                        if [[ "$mode" != *x* ]]; then
                            continue
                        fi
                        local res=${mode%%@*}
                        local width=${res%%x*}
                        local height=${res#*x}
                        if ! [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]; then
                            continue
                        fi
                        local div
                        div=$(gcd "$width" "$height")
                        local simple_width=$(( width / div ))
                        local simple_height=$(( height / div ))
                        local ratio="${simple_width}:${simple_height}"
                        if [[ ! " ${ratio_modes[$ratio]} " =~ ${mode} ]]; then
                            ratio_modes["$ratio"]+="$mode "
                        fi
                    done
                done
                print_message "Available ratios:"
                ratios=("${!ratio_modes[@]}")
                PS3="Select ratio number: "
                select selected_ratio in "${ratios[@]}"; do
                    if [ -n "$selected_ratio" ]; then
                        chosen_ratio="$selected_ratio"
                        break
                    else
                        print_message "Invalid selection. Try again."
                    fi
                done
                read -ra resolutions <<< "${ratio_modes[$chosen_ratio]}"
                print_message "Choose a resolution for ratio $chosen_ratio:"
                PS3="Select resolution number: "
                select chosen_resolution in "${resolutions[@]}"; do
                    if [ -n "$chosen_resolution" ]; then
                        break
                    else
                        print_message "Invalid selection. Try again."
                    fi
                done

                if [ -z "$primary_monitor" ]; then
                    primary_monitor="$chosen_monitor"
                    primary_width="${chosen_resolution%%x*}"
                    offset="0x0"
                else
                    if [ "$chosen_monitor" = "$primary_monitor" ]; then
                        offset="0x0"
                    else
                        offset="${primary_width}x0"
                    fi
                fi

                read -rp "Enter scale for monitor ${chosen_monitor} (1.0 - 2.0): " scale

                local monitors_conf_file="${HOME}/.config/hypr/sources/monitors.conf"
                if grep -q "^monitor=${chosen_monitor}," "$monitors_conf_file"; then
                    sed -i "s|^monitor=${chosen_monitor},.*|monitor=${chosen_monitor},${chosen_resolution},${offset},${scale}|g" "$monitors_conf_file"
                else
                    sed -i "1i monitor=${chosen_monitor},${chosen_resolution},${offset},${scale}" "$monitors_conf_file"
                fi
            fi
            if prompt_yes_no "Configure another monitor?"; then
                : # continue loop
            else
                break
            fi
        done

        local monitors_conf_file="${HOME}/.config/hypr/sources/monitors.conf"
        mapfile -t configured < <(grep "^monitor=" "$monitors_conf_file" | awk -F',' '{print $1}' | sed 's/monitor=//')
        primary="${configured[0]}"
        if [ "${#configured[@]}" -gt 1 ]; then
            secondary="${configured[1]}"
        else
            secondary="$primary"
        fi
        awk -F, -v p="$primary" -v s="$secondary" 'BEGIN { OFS="," }
            /^workspace=/ {
                split($1, arr, "=");
                ws=arr[2];
                if (ws % 2 == 1) { $2="monitor:" s } else { $2="monitor:" p }
                print
            }
            !/^workspace=/ { print }
        ' "$monitors_conf_file" > "${monitors_conf_file}.tmp" && mv "${monitors_conf_file}.tmp" "$monitors_conf_file"

        local wallpaper_conf="${HOME}/.config/hypr/sources/change_wallpaper.conf"
        if [ -f "$wallpaper_conf" ]; then
            monitors_str=""
            for m in "${configured[@]}"; do
                monitors_str+="\"$m\" "
            done
            monitors_str=$(echo "$monitors_str")
            if grep -q "^MONITORS=" "$wallpaper_conf"; then
                sed -i "s|^MONITORS=.*|MONITORS=($monitors_str)|" "$wallpaper_conf"
            else
                print_message "MONITORS=($monitors_str)" >> "$wallpaper_conf"
            fi
            print_message "Updated MONITORS in change_wallpaper.conf: MONITORS=($monitors_str)"
        else
            print_warning "Wallpaper configuration file not found: $wallpaper_conf"
        fi

    elif command -v kscreen-doctor &>/dev/null; then
        local monitor_output
        monitor_output=$(kscreen-doctor -o 2>&1)
        print_message "KDE Plasma monitor configuration:"
        echo "$monitor_output"
        local monitor_count
        monitor_count=$(echo "$monitor_output" | grep -E -c "^Monitor")
        print_message "Detected $monitor_count monitor(s) on KDE Plasma."
        if [ "$monitor_count" -eq 0 ]; then
            print_warning "No monitors detected via kscreen-doctor."
            return
        fi
    else
        print_warning "No supported monitor configuration tool found (hyprctl or kscreen-doctor)."
    fi
}

sync_arch_to_nas() {
    announce_step "Syncing Arch Onedrive to NAS"
    local nas_password_file="$HOME/.local/nas_credentials"
    local nas_password=""

    # Function to read password from file
    read_password() {
        if [ ! -f "$nas_password_file" ]; then
            print_error "Password file not found at: $nas_password_file"
            return 1
        fi
        
        # Check file permissions
        local file_perms
        file_perms=$(stat -c "%a" "$nas_password_file")
        if [ "$file_perms" != "600" ]; then
            print_warning "Insecure file permissions on password file. Fixing..."
            chmod 600 "$nas_password_file"
        fi
        
        # Read password from file
        nas_password=$(cat "$nas_password_file")
        if [ -z "$nas_password" ]; then
            print_error "Password file is empty"
            return 1
        fi
        return 0
    }

    # Check if rsync is installed
    if ! command -v rsync &>/dev/null; then
        print_message "rsync not found. Installing..."
        if ! distro_install "rsync"; then
            print_error "Failed to install rsync"
            return 1
        fi
    fi

    # Check for SSH key, create if missing
    if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
        print_message "SSH key not found. Generating one..."
        if ! execute_command "ssh-keygen -t ed25519 -N \"\" -f \"$HOME/.ssh/id_ed25519\"" "Generate SSH key"; then
            print_error "SSH keygen failed"
            return 1
        fi
    fi

    # Run rsync to sync the directory
    print_message "Starting rsync..."
        
    # Read password from file
    if ! read_password; then
        return 1
    fi

    # Install sshpass if needed
    if ! command -v sshpass &>/dev/null; then
        print_message "sshpass not found. Installing..."
        if ! distro_install "sshpass"; then
            print_error "Failed to install sshpass"
            return 1
        fi
    fi

    if is_dry_run; then
        # For dry run, use a masked command that doesn't show the password
        if execute_command "rsync -avzn --delete -e \"ssh -p $NAS_PORT\" \"$ONEDRIVE_SOURCE\" \"$NAS_USER@$NAS_IP:$NAS_ONEDRIVE_DEST\"" "Preview files to be synced (dry run)"; then
            print_message "[DRY-RUN] Sync simulation completed successfully"
            track_config_status "NAS Sync Preview" "$CHECK_MARK"
            return 0
        else
            print_error "[DRY-RUN] Sync simulation failed"
            track_config_status "NAS Sync Preview" "$CROSS_MARK"
            return 1
        fi
    else
        # For actual sync, use sshpass with the password
        if execute_command "sshpass -p \"$nas_password\" rsync -avz --delete -e \"ssh -p $NAS_PORT\" \"$ONEDRIVE_SOURCE\" \"$NAS_USER@$NAS_IP:$NAS_ONEDRIVE_DEST\"" "Sync Onedrive to NAS"; then
            print_message "Sync completed successfully."
            execute_command "date '+%Y-%m-%d %H:%M:%S' > /tmp/rsync_success" "Write sync success timestamp"
        else
            print_error "Sync failed."
            nas_password=""  # Clear password
            return 1
        fi
    fi

    # Clear the password variable for security
    nas_password=""
}

configure_nas_sync() {
    announce_step "Configuring NAS Sync with rsync"

    # Check if source directory exists
    if [ ! -d "$ONEDRIVE_SOURCE" ]; then
        print_warning "Source directory $ONEDRIVE_SOURCE does not exist. Skipping NAS sync configuration."
        return 0
    fi

    # Check/install rsync
    if ! command -v rsync &> /dev/null; then
        print_message "Installing rsync..."
        if ! distro_install "rsync"; then
            print_error "Failed to install rsync"
            return 1
        fi
    fi

    # SSH key setup
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        print_message "Generating SSH key..."
        if ! execute_command "ssh-keygen -t ed25519 -f \"$HOME/.ssh/id_ed25519\" -N \"\"" "Generate SSH key"; then
            print_error "SSH key generation failed"
            return 1
        fi
    fi

    # Copy SSH key to NAS (with retry logic)
    if ! execute_command "ssh -p \"$NAS_PORT\" -o PasswordAuthentication=no \"$NAS_USER@$NAS_IP\" exit" "Test SSH connection to NAS"; then
        print_message "Copying SSH key to NAS..."
        local success=0
        for i in {1..3}; do
            if execute_command "ssh-copy-id -p \"$NAS_PORT\" -i \"$HOME/.ssh/id_ed25519.pub\" \"$NAS_USER@$NAS_IP\"" "Copy SSH key to NAS"; then
                success=1
                break
            fi
            sleep 5
        done
        if [ "$success" -eq 0 ]; then
            print_error "SSH key copy failed after 3 attempts"
            return 1
        fi
    fi

    # Initial rsync test: create destination directory if missing
    if ! execute_command "ssh -p \"$NAS_PORT\" \"$NAS_USER@$NAS_IP\" \"test -d $NAS_ONEDRIVE_DEST\"" "Check NAS destination directory"; then
        print_message "Creating destination directory on NAS..."
        if ! execute_command "ssh -p \"$NAS_PORT\" \"$NAS_USER@$NAS_IP\" \"mkdir -p $NAS_ONEDRIVE_DEST\"" "Create NAS destination directory"; then
            print_error "Failed to create NAS directory"
            return 1
        fi
    fi

    # Perform initial sync
    print_message "Starting initial rsync..."
    if ! execute_command "rsync -avz --delete -e \"ssh -p $NAS_PORT\" \"$ONEDRIVE_SOURCE\" \"$NAS_USER@$NAS_IP:$NAS_ONEDRIVE_DEST\"" "Initial rsync to NAS"; then
        print_error "Initial rsync failed"
        return 1
    fi

    # Configure cron job
    local CRON_JOB="0 2 * * * rsync -avz --delete -e \"ssh -p $NAS_PORT\" $ONEDRIVE_SOURCE $NAS_USER@$NAS_IP:\"$NAS_ONEDRIVE_DEST\" >> $NAS_LOG 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "$NAS_ONEDRIVE_DEST"; then
        print_message "Adding cron job for daily sync at 2 AM..."
        if ! execute_command "(crontab -l 2>/dev/null; echo \"$CRON_JOB\") | crontab -" "Add cron job for NAS sync"; then
            print_error "Failed to add cron job"
            return 1
        fi
    fi

    # Log rotation setup
    if ! execute_command "sudo touch \"$NAS_LOG\"" "Create log file"; then
        print_warning "Could not create log file: $NAS_LOG"
    else
        execute_command "sudo chown \"$NAS_USER\" \"$NAS_LOG\"" "Set log file ownership"
    fi

    print_message "Setup complete. Daily sync scheduled at 2 AM."
    print_message "Log file: $NAS_LOG"
}

############################################################## Degub Functions ##############################################################

Debug_ntfs_drives() {
    announce_step "Fixing NTFS drives"
    print_message "Checking for unmounted NTFS USB drives..."

    local unmounted_drives=()
    while read -r device; do
        if grep -q "^$device " /proc/mounts; then
            continue
        fi

        if blkid "$device" | grep -q "ntfs"; then
            unmounted_drives+=("$device")
        fi
    done < <(lsblk -pno NAME | grep -E "sd[a-z][0-9]|nvme[0-9]n[0-9]p[0-9]")

    if [ ${#unmounted_drives[@]} -eq 0 ]; then
        print_warning "No unmounted NTFS USB drives found."
        return 0
    fi

    print_message "Found ${#unmounted_drives[@]} unmounted NTFS drives."

    echo "Available unmounted NTFS drives:"
    for i in "${!unmounted_drives[@]}"; do
        local drive="${unmounted_drives[$i]}"

        local label
        label=$(blkid -o value -s LABEL "$drive" 2>/dev/null || echo "Unknown")

        local size
        size=$(lsblk -no SIZE "$drive" 2>/dev/null || echo "Unknown")

        echo "[$i] $drive ($label, $size)"
    done

    read -rp "Select a drive to fix (number) or 'a' for all: " selection

    local drives_to_fix=()
    if [[ "$selection" == "a" ]]; then
        drives_to_fix=("${unmounted_drives[@]}")
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -lt "${#unmounted_drives[@]}" ]; then
        drives_to_fix=("${unmounted_drives[$selection]}")
    else
        print_error "Invalid selection. Exiting."
        return 1
    fi

    for drive in "${drives_to_fix[@]}"; do
        print_message "Processing drive: $drive"

        print_message "Checking for NTFS errors on $drive..."
        local error_check
        error_check=$(ntfsinfo "$drive" 2>&1)
        if [ $? -ne 0 ]; then
            print_warning "Error detected on $drive:"
            echo "$error_check"

            if prompt_yes_no "Attempt to fix errors on $drive? This will use ntfsfix."; then
                print_message "Fixing NTFS errors on $drive..."
                if execute_command "sudo ntfsfix $drive" "Fix NTFS errors on $drive"; then
                    print_message "NTFS fix completed successfully."
                else
                    print_error "Failed to fix NTFS errors on $drive."
                    continue
                fi
            else
                print_message "Skipping fix for $drive."
                continue
            fi
        else
            print_message "No immediate errors detected on $drive."
        fi

        local mount_dir
        mount_dir="/media/ntfs_fix_$(basename "$drive")"
        print_message "Creating mount point: $mount_dir"
        if ! execute_command "sudo mkdir -p $mount_dir" "Create mount point"; then
            print_error "Failed to create mount point $mount_dir"
            continue
        fi

        print_message "Mounting $drive to $mount_dir..."
        if execute_command "sudo mount -t ntfs-3g -o rw $drive $mount_dir" "Mount drive"; then
            print_message "Successfully mounted $drive to $mount_dir"

            if grep -q "$drive $mount_dir" /proc/mounts; then
                if execute_command "sudo touch \"$mount_dir/test_file\" && sudo rm \"$mount_dir/test_file\"" "Test write access"; then
                    print_message "✅ Drive $drive is mounted correctly and is writable."
                else
                    print_warning "⚠️ Drive $drive is mounted but may be read-only."
                fi
            else
                print_error "❌ Failed to verify mount for $drive."
            fi
        else
            print_error "Failed to mount $drive. You may need to check the drive on a Windows system."
        fi
    done

    print_message "NTFS fix process completed."
}

############################################################## Main Execution ##############################################################

main() {
    if is_windows; then
        print_warning "Running on Windows - This script can only be run in dry-run mode"
        DRY_RUN=true
    fi

    # Run checks first, regardless of mode
    check_distro
    check_disk_space
    if ! is_windows; then
        check_dependencies
        check_bootloader
        check_environment
        check_directories
        check_time_settings "$@"
    fi

    # Initialize empty array for selected steps
    SELECTED_STEPS=()

    # If a specific function was requested, run only that
    if [ -n "$FUNCTION_TO_RUN" ]; then
        if declare -f "$FUNCTION_TO_RUN" > /dev/null; then
            if is_dry_run; then
                echo -e "\n${YELLOW}[DRY-RUN]${NC} Would execute function: $FUNCTION_TO_RUN"
                log_dry_run_operation "main" "Execute function: $FUNCTION_TO_RUN"
                "$FUNCTION_TO_RUN"
                print_dry_run_summary
            else
                echo -e "\n${GREEN}Running: $FUNCTION_TO_RUN${NC}"
                log_message "INFO" "Starting task: $FUNCTION_TO_RUN"
                "$FUNCTION_TO_RUN"
                log_message "INFO" "Completed task: $FUNCTION_TO_RUN"
            fi
        else
            list_functions
            handle_error "Function '$FUNCTION_TO_RUN' not found!"
        fi
        echo
        if is_dry_run; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Dry run completed. No changes were made."
        else
            print_message "Function execution completed!"
            print_status_summary
        fi
        return
    fi

    # Check if default mode is requested via command line
    if [[ $PASSTHRU_DEFAULT -eq 1 ]]; then
        get_user_choices "d"
    else
        get_user_choices
    fi

    if is_dry_run; then
        echo -e "\n${YELLOW}[DRY-RUN]${NC} The following steps would be executed:"
        for step in "${SELECTED_STEPS[@]}"; do
            echo -e "${YELLOW}[DRY-RUN]${NC} - $step"
            # Find description for the selected step
            for i in "${!FILTERED_FUNCTIONS[@]}"; do
                if [[ "${FILTERED_FUNCTIONS[$i]}" = "${step}" ]]; then
                    echo -e "${YELLOW}[DRY-RUN]${NC}   Description: ${FILTERED_DESCRIPTIONS[$i]}"
                    break
                fi
            done
        done

        echo -e "\n${YELLOW}[DRY-RUN]${NC} Executing dry run of selected functions..."

        for step in "${SELECTED_STEPS[@]}"; do
            if declare -f "$step" > /dev/null; then
                echo -e "\n${YELLOW}[DRY-RUN]${NC} Processing: $step"
                "$step"
            else
                print_error "Function for step '$step' not found!"
            fi
        done

        print_dry_run_summary
        return
    fi
    
    for step in "${SELECTED_STEPS[@]}"; do
        if declare -f "$step" > /dev/null; then
            echo -e "\n${GREEN}Running: $step${NC}"
            log_message "INFO" "Starting task: $step"
            "$step"
            log_message "INFO" "Completed task: $step"
        else
            print_error "Function for step '$step' not found!"
            log_message "ERROR" "Function not found: $step"
        fi
        echo
    done

    print_message "All selected steps completed!"
    print_status_summary
}

# Add cleanup function
cleanup() {
    print_message "Cleaning up temporary files..."
    rm -rf /tmp/yay 2>/dev/null
    # Add other cleanup tasks as needed
    print_message "Cleanup completed."
}

# Register cleanup function to run on script exit
trap cleanup EXIT

# Add command line argument handling
PASSTHRU_DEFAULT=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run | -dry)
            DRY_RUN=true
            ;;
        --function=*)
            FUNCTION_TO_RUN="${1#*=}"
            ;;
        --function | -f)
            if [[ -z "$2" ]]; then
                print_error "Error: --function/-f requires a value"
                exit 1
            fi
            FUNCTION_TO_RUN="$2"
            shift
            ;;
        --list | -l)
            list_functions
            exit 0
            ;;
        --default | -d)
            PASSTHRU_DEFAULT=1
            ;;
        --verbose)
            VERBOSE=true
            ;;
        --help | -h)
            show_help
            exit 0
            ;;
        *)
            handle_error "Unknown parameter: $1"
            ;;
    esac
    shift
done

if [[ $PASSTHRU_DEFAULT -eq 1 ]]; then
    main --default
else
    main
fi

echo -e "\nPress Enter to exit..."
read -r
exit 0