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

# Check for Bluetooth hardware detection
msg_info "Checking for Bluetooth hardware..."
bt_hardware_found=false

# Check USB Bluetooth devices
if command -v lsusb >/dev/null 2>&1; then
    usb_bt=$(lsusb | grep -i "bluetooth\|Class=Wireless" || true)
    if [[ -n "$usb_bt" ]]; then
        msg_success "USB Bluetooth device(s) detected:"
        echo "$usb_bt" | sed 's/^/  /'
        bt_hardware_found=true
    else
        msg_warning "No USB Bluetooth devices found via lsusb."
    fi
else
    msg_warning "lsusb not found. Cannot check USB devices."
fi

# Check PCI Bluetooth devices
if command -v lspci >/dev/null 2>&1; then
    pci_bt=$(lspci | grep -i "bluetooth\|network\|wireless" || true)
    if [[ -n "$pci_bt" ]]; then
        msg_info "PCI Bluetooth/Wireless device(s) found:"
        echo "$pci_bt" | sed 's/^/  /'
        bt_hardware_found=true
    fi
fi

# Check kernel messages for Bluetooth errors
msg_info "Checking kernel messages for Bluetooth-related errors..."
if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
    bt_errors=$(dmesg | grep -i "bluetooth\|btusb\|hci" | tail -20 || true)
    if [[ -n "$bt_errors" ]]; then
        msg_info "Recent Bluetooth-related kernel messages:"
        echo "$bt_errors" | sed 's/^/  /'
    fi
else
    msg_warning "Cannot check dmesg without root privileges. Run with sudo to see kernel messages."
fi

# Check for all Bluetooth-related kernel modules
msg_info "Checking for Bluetooth kernel modules..."
bt_modules=$(lsmod | grep -E "^bluetooth|^bt|^rfcomm|^bnep" || true)
if [[ -n "$bt_modules" ]]; then
    msg_info "Loaded Bluetooth-related modules:"
    echo "$bt_modules" | sed 's/^/  /'
else
    msg_warning "No Bluetooth kernel modules are loaded."
fi

# Check module dependencies
msg_info "Checking if btusb module is available..."
if modinfo btusb &>/dev/null; then
    msg_info "btusb module information:"
    modinfo btusb | grep -E "filename|depends|description" | sed 's/^/  /' || true
else
    msg_error "btusb module not found in kernel modules."
fi

# Check for power management issues (common with combo WiFi/Bluetooth chips)
msg_info "Checking for power management settings..."
if [ -d /sys/module/btusb ]; then
    if [ -f /sys/module/btusb/parameters/disable_scofix ]; then
        msg_info "btusb power management parameters found."
    fi
fi

# Check USB autosuspend settings (can affect Bluetooth on USB devices)
if [ -d /sys/bus/usb/devices ]; then
    msg_info "Checking USB autosuspend settings..."
    autosuspend_found=false
    for device in /sys/bus/usb/devices/*/power/control; do
        if [ -f "$device" ]; then
            control=$(cat "$device" 2>/dev/null || echo "unknown")
            if [[ "$control" == "auto" ]]; then
                device_path=$(dirname "$device")
                device_id=$(dirname "$device_path")
                device_id=$(basename "$device_id")
                msg_warning "USB autosuspend enabled for device: $device_id"
                msg_info "  This can cause Bluetooth issues. Consider disabling with:"
                msg_info "  echo 'on' | sudo tee $device_path/control"
                autosuspend_found=true
            fi
        fi
    done
    if [ "$autosuspend_found" = false ]; then
        msg_info "No USB autosuspend issues detected."
    fi
fi

# Check PCIe power management (for combo WiFi/Bluetooth PCIe cards)
if command -v lspci >/dev/null 2>&1; then
    pci_bt_addr=$(lspci | grep -i "bluetooth\|wireless.*realtek\|rtl.*8822" | head -1 | cut -d' ' -f1 || true)
    if [[ -n "$pci_bt_addr" ]]; then
        pci_path="/sys/bus/pci/devices/0000:${pci_bt_addr}"
        if [ -d "$pci_path" ]; then
            msg_info "Found RTL8822BE or similar combo WiFi/Bluetooth chip at ${pci_bt_addr}"
            if [ -f "${pci_path}/power/control" ]; then
                pci_power=$(cat "${pci_path}/power/control" 2>/dev/null || echo "unknown")
                msg_info "PCIe device ${pci_bt_addr} power control: $pci_power"
                if [[ "$pci_power" != "on" ]]; then
                    msg_warning "PCIe device power management is set to '$pci_power' (not 'on')."
                    msg_warning "This is a common cause of Bluetooth issues with combo chips!"
                    msg_info "  Try: echo 'on' | sudo tee ${pci_path}/power/control"
                else
                    msg_success "PCIe power control is set to 'on'."
                fi
            fi
            
            # Check for runtime PM (another power management setting)
            if [ -f "${pci_path}/power/runtime_status" ]; then
                runtime_status=$(cat "${pci_path}/power/runtime_status" 2>/dev/null || echo "unknown")
                msg_info "PCIe device runtime PM status: $runtime_status"
                if [[ "$runtime_status" == "suspended" ]]; then
                    msg_warning "Device is in suspended state. This can prevent Bluetooth from working."
                    msg_info "  Try: echo 'on' | sudo tee ${pci_path}/power/control"
                    msg_info "  Then: sudo modprobe -r btusb && sudo modprobe btusb"
                fi
            fi
        fi
    fi
fi

# Improved module check - use word boundary to avoid false matches
check_btusb_loaded() {
    lsmod | grep -wq "^btusb"
}

msg_info "Checking for btusb module..."
if ! check_btusb_loaded; then
    msg_warning "btusb not loaded. Attempting to load..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Would execute: modprobe btusb"
    else
        # Ensure bluetooth module is loaded first (dependency)
        if ! lsmod | grep -wq "^bluetooth"; then
            msg_info "Loading bluetooth module (dependency) first..."
            run_as_root modprobe bluetooth 2>&1 || true
            sleep 1
        fi
        
        if run_as_root modprobe btusb 2>&1; then
            sleep 1
            if check_btusb_loaded; then
                msg_success "btusb module loaded successfully."
            else
                msg_warning "modprobe succeeded but module not found in lsmod."
            fi
        else
            load_error=$?
            msg_error "Failed to load btusb module (exit code: $load_error)"
            msg_info "Attempting to load dependencies first..."
            run_as_root modprobe bluetooth 2>&1 || true
            sleep 1
            run_as_root modprobe btusb 2>&1 || true
            sleep 1
        fi
    fi
else
    msg_success "btusb module is already loaded."
fi

msg_info "Rechecking for btusb module..."
if ! check_btusb_loaded; then
    msg_warning "btusb still not loaded after attempts."
    
    # Additional diagnostics
    msg_info "Running extended diagnostics..."
    
    # Check if bluetooth module is loaded (dependency)
    if ! lsmod | grep -q "^bluetooth"; then
        msg_warning "bluetooth module (dependency) is not loaded. Attempting to load..."
        run_as_root modprobe bluetooth 2>&1 || true
    fi
    
    # Check for bluez-hid2hci
    if ! command -v pacman >/dev/null 2>&1; then
        msg_warning "pacman not found. Cannot check for bluez-hid2hci package."
    else
        if ! pacman -Q bluez-hid2hci &>/dev/null; then
            msg_info "bluez-hid2hci not installed. Installing..."
            run_as_root pacman -S --noconfirm bluez-hid2hci
        else
            msg_info "bluez-hid2hci is installed."
        fi
    fi
    
    # Check bluetoothctl for adapter
    if command -v bluetoothctl >/dev/null 2>&1; then
        msg_info "Checking for Bluetooth adapters via bluetoothctl..."
        adapters=$(bluetoothctl list 2>/dev/null || true)
        if [[ -n "$adapters" ]]; then
            msg_info "Bluetooth adapters found:"
            echo "$adapters" | sed 's/^/  /'
        else
            msg_warning "No Bluetooth adapters found via bluetoothctl."
        fi
    fi
    
    # Check hciconfig
    if command -v hciconfig >/dev/null 2>&1; then
        msg_info "Checking hciconfig output:"
        hciconfig -a 2>&1 | sed 's/^/  /' || true
    else
        msg_warning "hciconfig not found. Install bluez-utils to use hciconfig."
    fi
    
    # Check systemd logs
    msg_info "Checking Bluetooth service logs for errors..."
    if systemctl is-active bluetooth.service &>/dev/null; then
        journalctl_output=$(run_as_root journalctl -u bluetooth.service --no-pager -n 20 2>/dev/null | grep -i "error\|fail\|warn" || true)
        if [[ -n "$journalctl_output" ]]; then
            msg_warning "Recent errors/warnings in Bluetooth service logs:"
            echo "$journalctl_output" | sed 's/^/  /'
        fi
    fi
    
    if [ "$bt_hardware_found" = false ]; then
        msg_error "No Bluetooth hardware detected. This might indicate:"
        echo "  - Bluetooth adapter is not physically connected"
        echo "  - Bluetooth adapter is disabled in BIOS/UEFI"
        echo "  - Bluetooth adapter is not recognized by the kernel"
        echo "  - Driver issue with the specific Bluetooth chipset"
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

# Final summary and recommendations
msg_info "=== Diagnostic Summary ==="

btusb_loaded=false
bt_service_active=false
bt_blocked=false
hardware_detected=false

if check_btusb_loaded; then
    btusb_loaded=true
fi

if systemctl is-active bluetooth.service &>/dev/null; then
    bt_service_active=true
fi

if command -v rfkill >/dev/null 2>&1; then
    if ! rfkill list bluetooth 2>/dev/null | grep -qi "blocked: yes"; then
        bt_blocked=false
    else
        bt_blocked=true
    fi
fi

if command -v lsusb >/dev/null 2>&1; then
    if lsusb | grep -qi "bluetooth\|Class=Wireless"; then
        hardware_detected=true
    fi
fi

if [ "$btusb_loaded" = true ] && [ "$bt_service_active" = true ] && [ "$bt_blocked" = false ]; then
    msg_success "Bluetooth check completed. All basic checks passed."
    if [ "$hardware_detected" = false ]; then
        msg_warning "However, no Bluetooth hardware was detected. Check:"
        echo "  - Is Bluetooth enabled in BIOS/UEFI?"
        echo "  - Is the Bluetooth adapter physically connected?"
        echo "  - Try: dmesg | grep -i bluetooth (as root) for hardware detection messages"
    fi
else
    msg_warning "Bluetooth issues detected. Troubleshooting steps:"
    echo ""
    if [ "$btusb_loaded" = false ]; then
        echo "  [ ] btusb module not loaded:"
        echo "      - Check: dmesg | grep -i 'bluetooth\|btusb' (as root)"
        echo "      - Try: sudo modprobe -v btusb (check for dependency errors)"
        echo "      - Check: lsmod | grep bluetooth (dependency must be loaded first)"
        echo "      - Some systems need: sudo modprobe bluetooth && sudo modprobe btusb"
        echo ""
    fi
    if [ "$bt_service_active" = false ]; then
        echo "  [ ] Bluetooth service not active:"
        echo "      - Check: sudo systemctl status bluetooth.service"
        echo "      - Check logs: sudo journalctl -u bluetooth.service -n 50"
        echo ""
    fi
    if [ "$bt_blocked" = true ]; then
        echo "  [ ] Bluetooth is blocked:"
        echo "      - Try: sudo rfkill unblock bluetooth"
        echo "      - Check hardware switch (if present)"
        echo ""
    fi
    if [ "$hardware_detected" = false ]; then
        echo "  [ ] No Bluetooth hardware detected:"
        echo "      - Check BIOS/UEFI settings for Bluetooth"
        echo "      - Verify physical connection (USB/PCI)"
        echo "      - Check: lsusb or lspci for Bluetooth devices"
        echo "      - Some laptops: Check Fn key combinations for Bluetooth toggle"
        echo ""
    fi
    
    # Power management troubleshooting (especially for combo WiFi/Bluetooth chips)
    echo "  [ ] Power Management Issues (common with combo WiFi/Bluetooth chips):"
    echo "      For RTL8822BE and similar combo chips, power saving can disable Bluetooth:"
    echo ""
    echo "      Option 1: Disable USB autosuspend (if USB device):"
    echo "        - Find device: lsusb | grep -i bluetooth"
    echo "        - Disable: echo 'on' | sudo tee /sys/bus/usb/devices/*/power/control"
    echo ""
    echo "      Option 2: Disable PCIe power management (if PCIe device):"
    echo "        - Find device: lspci | grep -i bluetooth"
    echo "        - Get address (e.g., 06:00.0) and run:"
    echo "          echo 'on' | sudo tee /sys/bus/pci/devices/0000:06:00.0/power/control"
    echo ""
    echo "      Option 3: Disable power saving in kernel module:"
    echo "        - Create: /etc/modprobe.d/btusb_disable_powersave.conf"
    echo "        - Add: options btusb enable_autosuspend=0"
    echo "        - Reboot or: sudo modprobe -r btusb && sudo modprobe btusb"
    echo ""
    echo "      Option 4: Remove from energy network (systemd):"
    echo "        - Check: systemctl status bluetooth.service"
    echo "        - If power saving is enabled, disable with:"
    echo "          sudo systemctl mask bluetooth.service"
    echo "          sudo systemctl unmask bluetooth.service"
    echo "          sudo systemctl restart bluetooth.service"
    echo ""
    echo "  Additional commands to try:"
    echo "    - sudo bluetoothctl (interactive Bluetooth control)"
    echo "    - sudo hciconfig (if bluez-utils is installed)"
    echo "    - sudo dmesg | tail -50 (check recent kernel messages)"
    echo "    - lsmod | grep -E 'bluetooth|bt' (check all BT modules)"
    echo "    - sudo dmesg | grep -i 'rtl\|8822\|bluetooth' (check for RTL chip errors)"
fi

msg_success "Bluetooth check completed."

exit 0
