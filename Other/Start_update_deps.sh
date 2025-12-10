#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_update_deps.sh
# ============================================================================
# Description:
#   Package update analyzer that shows available updates and their reverse
#   dependencies. Helps users understand which packages depend on updated
#   packages before performing system updates.
#
# What it does:
#   - Uses checkupdates to find packages with available updates
#   - For each updatable package, shows what other packages depend on it
#   - Displays "Required By" (Benötigt von) information from pacman
#   - Provides a summary of all packages with pending updates
#
# How to use:
#   Run directly:
#     ./Start_update_deps.sh
#   
#   Options:
#     --help, -h      Show help message
#
# Target:
#   - Arch Linux users planning system updates
#   - System administrators reviewing update impact
#   - Users wanting to understand package dependencies before updating
# ============================================================================

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
    Check which packages have updates available and show what depends on them.
    Uses checkupdates to find available updates and pacman to show dependencies.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

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

# Check dependencies
require_command "checkupdates" "Install pacman-contrib package"
require_command "pacman" "This script requires Arch Linux with pacman"

msg_info "Checking for available updates and their dependencies..."

if [ "$HAS_GUM" = true ]; then
    gum style --border normal --margin "1 2" --padding "1 2" --foreground 63 "Update Check"
else
    echo "======================================================="
fi
echo

# Get list of packages that have updates available
updates=$(checkupdates 2>/dev/null || true)

# Check if checkupdates returned any results
if [ -z "$updates" ]; then
    msg_success "No updates available."
    exit 0
fi

# Process each package that has an update
update_count=0
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Extract package name from checkupdates output (format: "package old_version -> new_version")
    package_name=$(echo "$line" | awk '{print $1}')
    
    if [ -n "$package_name" ]; then
        update_count=$((update_count + 1))
        if [ "$HAS_GUM" = true ]; then
            gum style --foreground 63 "Package: $package_name"
        else
            echo "Package: $package_name"
        fi
        echo "Update: $line"
        
        # Get package info and grep for "Benötigt von" (Required By in German)
        # Also check for English "Required By"
        required_by=$(pacman -Qi "$package_name" 2>/dev/null | grep -E "(Benötigt von|Required By)" || true)
        
        if [ -n "$required_by" ]; then
            echo "$required_by"
        else
            if [ "$HAS_GUM" = true ]; then
                gum style --foreground 244 "Benötigt von        : Keine"
            else
                echo "Benötigt von        : Keine"
            fi
        fi
        echo "---"
    fi
done <<< "$updates"

echo
if [ "$HAS_GUM" = true ]; then
    gum style --foreground 42 "Found $update_count package(s) with available updates."
else
    msg_info "Script completed. Found $update_count package(s) with available updates."
fi

exit 0
