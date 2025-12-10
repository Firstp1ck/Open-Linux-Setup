#!/usr/bin/env bash

set -euo pipefail

# Script: Start_ssh_server.sh
# Description: Connect to SSH server using configuration from system_variables.sh

# Gum detection
HAS_GUM=false
if command -v gum >/dev/null 2>&1; then
    HAS_GUM=true
fi

# Standard message functions
msg_info() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 63 "[INFO] $1"
    else
        echo "[INFO] $1"
    fi
}

# shellcheck disable=SC2329
msg_success() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 42 "[SUCCESS] $1"
    else
        echo "[SUCCESS] $1"
    fi
}

msg_error() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 196 "[ERROR] $1" >&2
    else
        echo "[ERROR] $1" >&2
    fi
}

# shellcheck disable=SC2329
msg_warning() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 214 "[WARNING] $1"
    else
        echo "[WARNING] $1"
    fi
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
    Connect to SSH server using configuration from system_variables.sh.
    Prompts for the path to system_variables.sh if not found in default location.

Options:
    --help, -h          Show this help message
    --path PATH         Specify path to system_variables.sh directly

Examples:
    $(basename "$0")
    $(basename "$0") --path /path/to/system_variables.sh

EOF
}

# Parse arguments
SYSTEM_VARS_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --path)
            SYSTEM_VARS_PATH="$2"
            shift
            ;;
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    shift
done

# Check dependencies
require_command "ssh" "Install openssh package"

# Validate file path
validate_file_path() {
    local path="$1"
    if [[ "$path" != /* ]] && [[ "$path" != "$HOME"/* ]]; then
        msg_error "Invalid path format" "Path must be absolute or relative to HOME"
        return 1
    fi
    if [ ! -f "$path" ]; then
        msg_error "File not found" "Path: $path"
        return 1
    fi
    return 0
}

# Get system_variables.sh path
if [ -z "$SYSTEM_VARS_PATH" ]; then
    if [ "$HAS_GUM" = true ]; then
        echo "$HOME/ * /Open-Linux-Setup"
        SYSTEM_VARS_PATH=$(gum input --prompt "Enter the full path to system_variables.sh or just the directory replacing *: " || true)
    else
        echo "$HOME/ * /Open-Linux-Setup"
        read -rp "Enter the full path to system_variables.sh or just the directory replacing *: " SYSTEM_VARS_PATH
    fi
fi

if [[ "$SYSTEM_VARS_PATH" == /* ]] || [[ "$SYSTEM_VARS_PATH" == "$HOME"/* ]]; then
    full_path="$SYSTEM_VARS_PATH"
else
    full_path="$HOME/$SYSTEM_VARS_PATH/Open-Linux-Setup/main/system_variables.sh"
fi

msg_info "Using source path: $full_path"

if ! validate_file_path "$full_path"; then
    exit 1
fi

# Source the system variables
# shellcheck disable=SC1090
if ! source "$full_path"; then
    msg_error "Failed to source system_variables.sh"
    exit 1
fi

# Check if required variables are set
if [ -z "${SSH_SERVER_IP:-}" ] || [ -z "${SSH_USER:-}" ]; then
    msg_error "Required variables not set" "SSH_SERVER_IP and SSH_USER must be defined in system_variables.sh"
    exit 1
fi

msg_info "Connecting to SSH server..."
msg_info "Server: $SSH_SERVER_IP"
msg_info "User: $SSH_USER"

connect_ssh() {
    local host=$SSH_SERVER_IP
    local user=$SSH_USER
    
    if [ "$TERM" = "xterm-kitty" ] && command -v kitty >/dev/null 2>&1; then
        kitty +kitten ssh "$user@$host"
    else
        ssh "$user@$host"
    fi
}

connect_ssh

if [ "$HAS_GUM" = true ]; then
    gum input --placeholder "Press Enter to exit..." >/dev/null
else
    echo -e "\nPress Enter to exit..."
    read -r
fi

exit 0
