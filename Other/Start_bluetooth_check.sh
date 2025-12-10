#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_bluetooth_check.sh
# ============================================================================
# Description:
#   Diagnostic and repair tool for Bluetooth connectivity issues. Checks
#   Bluetooth module status, loads drivers if needed, unblocks Bluetooth if
#   blocked, and ensures the Bluetooth service is running.
#
# What it does:
#   - Checks if btusb kernel module is loaded, loads it if missing
#   - Installs bluez-hid2hci package if needed for certain Bluetooth devices
#   - Checks and unblocks Bluetooth if blocked by rfkill
#   - Verifies and restarts Bluetooth service (bluetooth.service)
#   - Provides diagnostic information about Bluetooth status
#
# How to use:
#   Run with appropriate privileges:
#     ./Start_bluetooth_check.sh
#     sudo ./Start_bluetooth_check.sh  (if root access needed)
#   
#   Options:
#     --help, -h      Show help message
#     --dry-run       Preview actions without making changes
#
# Target:
#   - Users experiencing Bluetooth connectivity problems
#   - Systems with Bluetooth adapters not being detected
#   - Troubleshooting Bluetooth device pairing issues
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
    Check Bluetooth module (btusb) status, load it if needed, check for
    bluez-hid2hci, unblock Bluetooth if blocked, and ensure Bluetooth service
    is running.

Options:
    --help, -h          Show this help message
    --dry-run           Show what would be done without making changes

Examples:
    $(basename "$0")
    $(basename "$0") --dry-run

EOF
}

# Parse arguments
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            msg_info "Running in DRY RUN mode: No changes will be made."
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
require_command "lsmod" "This script requires Linux kernel modules support"
require_command "systemctl" "This script requires systemd"

# Check for sudo if needed
# shellcheck disable=SC2329
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            msg_error "This script requires root privileges. Install sudo or run as root."
            exit 1
        fi
    fi
}

run_as_root() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Would execute: $*"
    elif [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

msg_info "Checking for btusb module..."
if ! lsmod | grep -q btusb; then
    msg_warning "btusb not loaded. Loading..."
    run_as_root modprobe btusb
    sleep 1
fi

msg_info "Rechecking for btusb module..."
if ! lsmod | grep -q btusb; then
    msg_warning "btusb still not loaded. Checking for bluez-hid2hci..."
    if ! command -v pacman >/dev/null 2>&1; then
        msg_error "pacman not found. Cannot check for bluez-hid2hci package."
        exit 1
    fi
    
    if ! pacman -Q bluez-hid2hci &>/dev/null; then
        msg_info "bluez-hid2hci not installed. Installing..."
        run_as_root pacman -S --noconfirm bluez-hid2hci
    else
        msg_info "bluez-hid2hci is installed. Running hciconfig..."
        if command -v hciconfig >/dev/null 2>&1; then
            hciconfig -a
        else
            msg_warning "hciconfig not found. Install bluez-utils to use hciconfig."
        fi
    fi
else
    msg_success "btusb module loaded."
fi

msg_info "Checking for Bluetooth block status..."
if ! command -v rfkill >/dev/null 2>&1; then
    msg_warning "rfkill not found. Cannot check Bluetooth block status."
else
    blocked=$(rfkill list bluetooth 2>/dev/null | grep -i "blocked: yes" || true)
    if [[ -n "$blocked" ]]; then
        msg_warning "Bluetooth is blocked. Unblocking..."
        run_as_root rfkill unblock bluetooth
        sleep 1
        msg_info "Rechecking block status..."
        rfkill list bluetooth
    else
        msg_success "Bluetooth is not blocked."
    fi
fi

msg_info "Checking Bluetooth service status..."
status=$(systemctl is-active bluetooth.service 2>/dev/null || echo "inactive")
if [[ "$status" != "active" ]]; then
    msg_warning "Bluetooth service not running. Restarting..."
    run_as_root systemctl restart bluetooth.service
    sleep 1
    status=$(systemctl is-active bluetooth.service 2>/dev/null || echo "inactive")
    if [[ "$status" == "active" ]]; then
        msg_success "Bluetooth service is now running."
    else
        msg_error "Failed to start Bluetooth service."
        exit 1
    fi
else
    msg_success "Bluetooth service is running."
fi

msg_success "Bluetooth check completed."

exit 0
