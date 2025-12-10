#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_notify_test.sh
# ============================================================================
# Description:
#   Notification system tester that sends test notifications with different
#   priority levels to verify the desktop notification daemon is working
#   correctly.
#
# What it does:
#   - Sends low priority notification
#   - Sends normal priority notification
#   - Sends critical priority notification
#   - Verifies each notification was sent successfully
#   - Reports completion status
#
# How to use:
#   Run directly:
#     ./Start_notify_test.sh
#   
#   Options:
#     --help, -h      Show help message
#
#   Requirements: notify-send (libnotify package)
#
# Target:
#   - Users testing desktop notification functionality
#   - System administrators verifying notification daemon setup
#   - Troubleshooting notification system issues
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
    Test notification system by sending notifications with different priority
    levels: low, normal, and critical.

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
require_command "notify-send" "Install libnotify package (or notification-daemon)"

msg_info "Testing notification system..."

# Low priority notification
msg_info "Sending low priority notification..."
if notify-send -u low "Low Priority" "This is a low priority test message"; then
    msg_success "Low priority notification sent."
else
    msg_error "Failed to send low priority notification."
    exit 1
fi

sleep 1

# Normal priority notification
msg_info "Sending normal priority notification..."
if notify-send -u normal "Normal Priority" "This is a normal priority test message"; then
    msg_success "Normal priority notification sent."
else
    msg_error "Failed to send normal priority notification."
    exit 1
fi

sleep 1

# Critical priority notification
msg_info "Sending critical priority notification..."
if notify-send -u critical "Critical Priority" "This is a critical priority test message"; then
    msg_success "Critical priority notification sent."
else
    msg_error "Failed to send critical priority notification."
    exit 1
fi

msg_success "All notification tests completed successfully."

exit 0
