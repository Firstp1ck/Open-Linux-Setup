#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_restart_wifi.sh
# ============================================================================
# Description:
#   Comprehensive WiFi restart tool that cycles network components to resolve
#   connectivity issues. Restarts network managers, reloads WiFi drivers,
#   unblocks WiFi via rfkill, and brings network interfaces down and up.
#
# What it does:
#   - Restarts NetworkManager service
#   - Restarts dhcpcd service for the wireless interface (if used)
#   - Unloads and reloads WiFi kernel drivers (iwlwifi, iwlmvm)
#   - Blocks and unblocks WiFi using rfkill
#   - Brings wireless interface down and up
#   - Identifies wireless interface automatically
#
# How to use:
#   Run with appropriate privileges:
#     ./Start_restart_wifi.sh
#     sudo ./Start_restart_wifi.sh  (if root access needed)
#   
#   Options:
#     --help, -h      Show help message
#     --dry-run       Preview actions without making changes
#
# Target:
#   - Users experiencing WiFi connectivity problems
#   - Systems with WiFi adapters that need driver reload
#   - Troubleshooting intermittent WiFi connection issues
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
    Restart WiFi by cycling NetworkManager, dhcpcd (if used), WiFi drivers,
    rfkill, and network interfaces. This can help resolve WiFi connectivity
    issues.

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
require_command "systemctl" "This script requires systemd"
require_command "ip" "Install iproute2 package"

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

msg_info "Starting WiFi restart process..."

# Restart NetworkManager
msg_info "Restarting NetworkManager..."
if systemctl is-enabled NetworkManager.service >/dev/null 2>&1; then
    if run_as_root systemctl restart NetworkManager.service; then
        msg_success "NetworkManager restarted successfully."
    else
        msg_error "Failed to restart NetworkManager."
        exit 1
    fi
else
    msg_warning "NetworkManager service is not enabled. Skipping restart."
fi

# Restart dhcpcd (if used)
msg_info "Identifying wireless interface..."
interface=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -i 'wl' | head -n1 || true)

if [ -n "$interface" ]; then
    msg_success "Wireless interface identified: $interface"
    
    # Check if dhcpcd service exists for this interface
    if systemctl list-unit-files | grep -q "dhcpcd@${interface}.service"; then
        msg_info "Restarting dhcpcd for $interface..."
        if run_as_root systemctl restart "dhcpcd@${interface}.service"; then
            msg_success "dhcpcd restarted successfully for $interface."
        else
            msg_warning "Failed to restart dhcpcd for $interface (may not be active)."
        fi
    else
        msg_info "dhcpcd service not found for $interface. Skipping."
    fi
else
    msg_warning "No wireless interface found."
fi

# Unload and reload WiFi driver
msg_info "Unloading WiFi drivers..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would execute: modprobe -r iwlmvm iwlwifi"
else
    # Try to unload drivers, but don't fail if they're not loaded
    run_as_root modprobe -r iwlmvm iwlwifi 2>/dev/null || true
fi

msg_info "Reloading WiFi drivers..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would execute: modprobe iwlwifi"
else
    run_as_root modprobe iwlwifi
fi
msg_success "WiFi drivers reloaded."

# Disable and re-enable WiFi
msg_info "Disabling WiFi..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would execute: rfkill block wifi"
else
    if command -v rfkill >/dev/null 2>&1; then
        rfkill block wifi || msg_warning "Failed to block WiFi (may require root)"
    else
        msg_warning "rfkill not found. Skipping WiFi block/unblock."
    fi
fi

msg_info "Re-enabling WiFi..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would execute: rfkill unblock wifi"
else
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi || msg_warning "Failed to unblock WiFi (may require root)"
    fi
fi
msg_success "WiFi disabled and re-enabled."

# Bring interface down and up
if [ -n "$interface" ]; then
    msg_info "Bringing $interface down..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Would execute: ip link set $interface down"
    else
        run_as_root ip link set "$interface" down
    fi
    
    msg_info "Bringing $interface up..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Would execute: ip link set $interface up"
    else
        run_as_root ip link set "$interface" up
    fi
    msg_success "Interface $interface cycled."
fi

msg_success "WiFi restart process complete."
msg_info "Please wait a moment for the connection to re-establish."

if [ "$HAS_GUM" = true ]; then
    gum input --placeholder "Press Enter to exit..." >/dev/null
else
    echo -e "\nPress Enter to exit..."
    read -r
fi

exit 0
