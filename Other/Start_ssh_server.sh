#!/bin/bash

echo "$HOME/ * /Open-Linux-Setup"
read -rp "Enter the full path to system_variables.sh or just the directory replacing *: " user_input

if [[ "$user_input" == /* ]] || [[ "$user_input" == $HOME/* ]]; then
    full_path="$user_input"
else
    full_path="$HOME/$user_input/Open-Linux-Setup/main/system_variables.sh"
fi

echo "Using source path: $full_path"

if [ ! -f "$full_path" ]; then
    echo "Error: Source file not found at $full_path"
    exit 1
fi

# shellcheck disable=SC1090
source "$full_path"

connect_ssh() {
    local host=$SSH_SERVER_IP
    local user=$SSH_USER
    
    if [ "$TERM" = "xterm-kitty" ]; then
        kitty +kitten ssh "$user@$host"
    else
        ssh "$user@$host"
    fi
}

connect_ssh

echo -e "\nPress Enter to exit..."
read -r

exit 0