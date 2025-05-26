#!/usr/bin/bash

create_user() {
    # Prompt for new username
    read -rp "Enter new username: " username
    if id "$username" &>/dev/null; then
        echo "Error: User $username already exists." >&2
        return 1
    fi

    # Create user with home and wheel group
    sudo useradd -m -G wheel -s /bin/bash "$username"

    # Set password securely with confirmation
    while true; do
        read -rsp "Enter password for $username: " password
        echo
        read -rsp "Confirm password: " password_confirm
        echo
        if [ "$password" = "$password_confirm" ]; then
            echo "$username:$password" | sudo chpasswd
            break
        else
            echo "Passwords do not match. Try again."
        fi
    done

    # Enable wheel group in sudoers if not already
    sudo visudo -cf /etc/sudoers &>/dev/null || return 1
    if ! sudo grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
        sudo sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        echo "Enabled sudo for wheel group in /etc/sudoers."
    fi

    # Optionally copy groups from another user
    read -rp "Copy groups from existing user? (y/n): " choice
    if [[ $choice =~ ^[Yy] ]]; then
        read -rp "Enter source username for groups: " source_user
        if ! id "$source_user" &>/dev/null; then
            echo "Error: User $source_user does not exist." >&2
            return 1
        fi
        # Get group list, excluding the source username
        groups=$(id -nG "$source_user" | tr ' ' ',')
        if [ -n "$groups" ]; then
            sudo usermod -aG "$groups" "$username"
            echo "Added $username to groups: ${groups//,/ }"
        fi
    fi

    echo "User $username created successfully."
}

user_management() {
    # Function to list non-system users
    list_users() {
        echo "Available users:"
        getent passwd {1000..60000} | cut -d: -f1
    }

    # Function to check for bash scripts with old username
    check_scripts_for_old_username() {
        local home_dir="$1"
        local old_username="$2"
        echo "Checking for bash scripts containing '$old_username' in $home_dir..."
        grep -rl --exclude-dir={.cache,.config,.local} -E '\.sh$|\.bash$' "$home_dir" 2>/dev/null | xargs grep -l "$old_username" 2>/dev/null
    }

    while true; do
        # Main menu
        echo "Select action:"
        select action in "Delete User" "Modify Username" "Modify Password" "Exit"; do
            case $action in
                "Delete User"|"Modify Username"|"Modify Password")
                    list_users
                    read -rp "Enter username: " username
                    if ! id "$username" &>/dev/null; then
                        echo "Error: User $username does not exist." >&2
                        break
                    fi
                    ;;
                "Exit")
                    echo "Exiting."
                    return 0
                    ;;
                *)
                    echo "Invalid selection." >&2
                    continue
                    ;;
            esac
            
            case $action in
                "Delete User")
                    sudo userdel -r "$username" && echo "Deleted $username" || echo "Deletion failed" >&2
                    break
                    ;;
                
                "Modify Username")
                    read -rp "Enter new username: " new_username
                    if id "$new_username" &>/dev/null; then
                        echo "Error: $new_username already exists." >&2
                        break
                    fi
                    
                    # Get old home dir
                    old_home=$(eval echo ~"$username")
                    new_home="/home/$new_username"
                    
                    # Check for scripts with old username
                    affected_files=$(check_scripts_for_old_username "$old_home" "$username")
                    if [ -n "$affected_files" ]; then
                        echo "Files needing updates:"
                        echo "$affected_files"
                    else
                        echo "No scripts contain the old username."
                    fi
                    
                    # Rename user and move home dir
                    sudo usermod -l "$new_username" -d "$new_home" -m "$username" && \
                    sudo groupmod -n "$new_username" "$username" && \
                    echo "Renamed $username → $new_username" || echo "Renaming failed" >&2
                    break
                    ;;
                
                "Modify Password")
                    read -rsp "Enter new password: " password
                    echo
                    echo "$username:$password" | sudo chpasswd && echo "Password updated" || echo "Password change failed" >&2
                    break
                    ;;
            esac
        done
    done
}

main() {
    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root." >&2
        exit 1
    fi

    # Main menu
    PS3="Select an option: "
    options=("Create User" "User Management" "Exit")
    select opt in "${options[@]}"; do
        case $opt in
            "Create User")
                create_user
                ;;
            "User Management")
                user_management
                ;;
            "Exit")
                echo "Exiting."
                break
                ;;
            *)
                echo "Invalid option." >&2
                ;;
        esac
    done
}

# Run the main function
main

echo -e "\nPress Enter to exit..."
read -r

exit 0