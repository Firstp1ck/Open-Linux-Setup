#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_user_editor.sh
# ============================================================================
# Description:
#   Interactive user and access management tool with TUI (Terminal User Interface).
#   Provides a menu-driven interface for creating, deleting, and modifying user
#   accounts, passwords, and group memberships.
#
# What it does:
#   - Creates new users with password, home directory, and group assignments
#   - Deletes users and optionally removes their home directories
#   - Modifies usernames (renames user, home directory, and primary group)
#   - Changes user passwords
#   - Manages user group memberships
#   - Checks for scripts referencing old usernames when renaming
#   - Configures sudo access for wheel group
#
# How to use:
#   Run as root:
#     sudo ./Start_user_editor.sh
#   
#   Options:
#     --help, -h      Show help message
#
# Target:
#   - System administrators managing user accounts
#   - Users needing to rename accounts or manage access
#   - Multi-user systems requiring user management
# ============================================================================

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Interactive user and access management tool. Create users, delete users,
    modify usernames and passwords, and manage user groups.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

Note: This script must be run as root.

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
            echo "Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
    esac
    # shellcheck disable=SC2317
    shift
done

require_gum() {
    if ! command -v gum >/dev/null 2>&1; then
        echo "This script requires 'gum' (TUI)." >&2
        if command -v pacman >/dev/null 2>&1; then
            echo "Install it with: sudo pacman -S gum" >&2
        else
            echo "Install 'gum' via your package manager and re-run." >&2
        fi
        exit 1
    fi
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        gum style --foreground 196 "Please run as root."
        exit 1
    fi
}

list_non_system_users() {
    getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }'
}

check_scripts_for_old_username() {
    local home_dir="$1"
    local old_username="$2"
    grep -rl --exclude-dir={.cache,.config,.local} -E '\.(sh|bash)$' "$home_dir" 2>/dev/null | xargs -r grep -l "$old_username" 2>/dev/null || true
}

create_user() {
    gum style --bold --foreground 212 "Create User"

    local username
    while true; do
        username=$(gum input --prompt "Username: " --placeholder "new username" || true)
        [ -z "${username:-}" ] && return 0
        if id "$username" &>/dev/null; then
            gum style --foreground 196 "User '$username' already exists."
            continue
        fi
        if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            gum style --foreground 196 "Invalid username. Use lowercase letters, digits, '_' or '-'."
            continue
        fi
        break
    done

    local password password_confirm
    while true; do
        password=$(gum input --password --prompt "Password: " || true)
        [ -z "${password:-}" ] && gum style --foreground 196 "Password cannot be empty." && continue
        password_confirm=$(gum input --password --prompt "Confirm: " || true)
        if [ "$password" != "$password_confirm" ]; then
            gum style --foreground 196 "Passwords do not match. Try again."
            continue
        fi
        break
    done

    useradd -m -G wheel -s /bin/bash "$username"
    echo "$username:$password" | chpasswd

    if visudo -cf /etc/sudoers &>/dev/null; then
        if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
            sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
            gum style --foreground 121 "Enabled sudo for wheel group in /etc/sudoers."
        fi
    fi

    if gum confirm "Copy groups from existing user?"; then
        local source_user
        source_user=$(list_non_system_users | gum choose --no-limit=false --header "Choose source user" || true)
        if [ -n "${source_user:-}" ]; then
            if ! id "$source_user" &>/dev/null; then
                gum style --foreground 196 "User '$source_user' does not exist. Skipping group copy."
            else
                local groups
                groups=$(id -nG "$source_user" | tr ' ' '\n' | grep -v "^$source_user$" | paste -sd, -)
                if [ -n "$groups" ]; then
                    usermod -aG "$groups" "$username"
                    gum style --foreground 121 "Added $username to groups: $(echo "$groups" | tr ',' ' ')"
                fi
            fi
        fi
    fi

    gum style --foreground 121 "User '$username' created successfully."
}

user_management() {
    while true; do
        local action
        action=$(gum choose "Delete User" "Modify Username" "Modify Password" "Back" --header "User Management" || true)
        [ -z "${action:-}" ] && return 0
        [ "$action" = "Back" ] && return 0

        local username
        username=$(list_non_system_users | gum choose --header "Select user" || true)
        [ -z "${username:-}" ] && continue
        if ! id "$username" &>/dev/null; then
            gum style --foreground 196 "User '$username' does not exist."
            continue
        fi

        case "$action" in
            "Delete User")
                if gum confirm "Delete '$username' and remove home directory?"; then
                    if userdel -r "$username"; then
                        gum style --foreground 121 "Deleted '$username'"
                    else
                        gum style --foreground 196 "Deletion failed"
                    fi
                fi
                ;;

            "Modify Username")
                local new_username
                while true; do
                    new_username=$(gum input --prompt "New username: " --placeholder "e.g. johndoe" || true)
                    [ -z "${new_username:-}" ] && break
                    if id "$new_username" &>/dev/null; then
                        gum style --foreground 196 "User '$new_username' already exists."
                        continue
                    fi
                    if [[ ! "$new_username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                        gum style --foreground 196 "Invalid username. Use lowercase letters, digits, '_' or '-'."
                        continue
                    fi
                    break
                done
                [ -z "${new_username:-}" ] && continue

                local old_home new_home
                old_home=$(eval echo ~"$username")
                new_home="/home/$new_username"

                local affected_files
                affected_files=$(check_scripts_for_old_username "$old_home" "$username" || true)
                if [ -n "${affected_files:-}" ]; then
                    printf "%s\n" "The following files reference '$username':" | gum style --foreground 214
                    echo "$affected_files" | gum pager --soft-wrap
                else
                    gum style --foreground 244 "No scripts contain the old username."
                fi

                if usermod -l "$new_username" -d "$new_home" -m "$username"; then
                    if getent group "$username" >/dev/null 2>&1; then
                        groupmod -n "$new_username" "$username" || true
                    fi
                    gum style --foreground 121 "Renamed $username → $new_username"
                else
                    gum style --foreground 196 "Renaming failed"
                fi
                ;;

            "Modify Password")
                local password
                password=$(gum input --password --prompt "New password: " || true)
                [ -z "${password:-}" ] && continue
                if echo "$username:$password" | chpasswd; then
                    gum style --foreground 121 "Password updated for '$username'"
                else
                    gum style --foreground 196 "Password change failed"
                fi
                ;;
        esac
    done
}

main() {
    require_gum
    require_root

    while true; do
        local opt
        opt=$(gum choose "Create User" "User Management" "Exit" --header "User & Access Management" || true)
        [ -z "${opt:-}" ] && exit 0
        case "$opt" in
            "Create User")
                create_user
                ;;
            "User Management")
                user_management
                ;;
            "Exit")
                gum style --foreground 244 "Exiting."
                break
                ;;
        esac
    done
}

main "$@"

exit 0