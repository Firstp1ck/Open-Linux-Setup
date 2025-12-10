#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_network_check.sh
# ============================================================================
# Description:
#   Comprehensive Wi-Fi diagnostic tool that runs automatic checks and
#   reports results with PASS/FAIL indicators. Tests network managers,
#   RFKill blocks, system logs, drivers, MTU settings, DHCP, and more.
#
# What it does:
#   - Checks for conflicting network managers (NetworkManager, systemd-networkd)
#   - Tests RFKill block status (hard/soft blocks)
#   - Analyzes Wi-Fi logs from journalctl for errors
#   - Checks NetworkManager Wi-Fi specific logs
#   - Verifies journald persistent logging configuration
#   - Identifies Wi-Fi driver and adapter via lspci
#   - Analyzes dmesg for driver errors (ath9k, wlan0)
#   - Checks MTU settings on wireless interface
#   - Tests path MTU with fragmentation ping
#   - Verifies regulatory domain configuration
#   - Checks DHCP logs (dhcpcd, dhclient)
#   - Tests NetworkManager service status
#   - Checks Wi-Fi power management settings
#   - Analyzes iptables FORWARD chain
#   - Checks ath9k driver configuration
#   - Provides summary with pass/warn/fail counts
#
# How to use:
#   Run with appropriate privileges:
#     ./Start_network_check.sh
#     sudo ./Start_network_check.sh  (recommended for full diagnostics)
#   
#   Options:
#     --help, -h      Show help message
#
#   Requirements: gum, systemctl, iw, rfkill
#
# Target:
#   - Users experiencing Wi-Fi connectivity issues
#   - Network administrators troubleshooting wireless problems
#   - System administrators diagnosing network configuration
# ============================================================================

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Comprehensive Wi-Fi diagnostic script that checks network managers, RFKill
    blocks, logs, drivers, MTU settings, DHCP, and more. Runs all checks
    automatically and prints concise PASS/FAIL results with reasons.

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
            echo "[ERROR] Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
    esac
    # shellcheck disable=SC2317
    shift
done

# --- Prerequisites & Notices ---
if ! command -v gum >/dev/null 2>&1; then
    echo "[ERROR] This script requires 'gum'. Install it (e.g., 'pacman -S gum' or 'brew install gum') and rerun." >&2
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        gum style --foreground 196 "[ERROR] sudo is not installed. Install sudo or run as root."
        exit 1
    fi
    gum style --foreground 214 "[WARNING] Some checks require superuser privileges."
    if gum confirm "Re-run this script with sudo now?" --default=true; then
        sudo -k
        exec sudo -E -- "$0" "$@"
    else
        gum style --foreground 214 "[INFO] Continuing without sudo; some checks may be limited."
    fi
fi

gum style --foreground 42 --bold "Starting Wi-Fi diagnostic checks (non-interactive)..."

# --- Helpers ---
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

style_pass() { gum style --foreground 42 --bold "$1"; }
style_fail() { gum style --foreground 196 --bold "$1"; }
style_info() { gum style --foreground 63 "$1"; }
style_warn() { gum style --foreground 214 --bold "$1"; }

# Detect Wi-Fi interface name dynamically
get_wifi_interface() {
    iw dev | awk '$1=="Interface"{print $2}' | head -n1
}

print_result() {
    local title="$1"; shift
    local status="$1"; shift # "PASS" or "FAIL"
    local info="$*"
    if [ "$status" = "PASS" ]; then
        style_pass "[PASS] $title"; [ -n "$info" ] && style_info "  - $info"
        PASS_COUNT=$((PASS_COUNT+1))
    elif [ "$status" = "WARN" ]; then
        style_warn "[WARN] $title"; [ -n "$info" ] && style_info "  - $info"
        WARN_COUNT=$((WARN_COUNT+1))
    else
        style_fail "[FAIL] $title"; [ -n "$info" ] && echo "  - reason: $info"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# --- Checks ---
check_network_managers() {
    local primary_network_managers=("NetworkManager.service" "systemd-networkd.service")
    local enabled_network_managers=()
    for service in "${primary_network_managers[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            enabled_network_managers+=("$service")
        fi
    done
    local num_enabled=${#enabled_network_managers[@]}
    if [ "$num_enabled" -le 1 ]; then
        print_result "Primary Network Managers" "PASS" "Enabled: ${enabled_network_managers[*]:-none}"
    else
        print_result "Primary Network Managers" "FAIL" "Multiple enabled: ${enabled_network_managers[*]}"
    fi
}

check_rfkill() {
    local rfkill_output
    rfkill_output=$(rfkill list all 2>&1)
    if echo "$rfkill_output" | grep -q "Hard blocked: yes\|Soft blocked: yes"; then
        local lines
        lines=$(echo "$rfkill_output" | grep -E "(Hard|Soft) blocked: yes" | tr '\n' '; ')
        print_result "RFKill blocks" "FAIL" "$lines"
    else
        print_result "RFKill blocks" "PASS" "No hard/soft blocks detected"
    fi
}

check_wifi_logs_boot() {
    local suspicious_regex='fail|error|timed out|timeout|disconnect|denied|deauth|unreachable|no carrier|link down'
    local lines
    lines=$(journalctl -b 2>/dev/null | grep -i "wifi" | grep -Eai "$suspicious_regex" | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "Wi-Fi logs (boot)" "FAIL" "Suspicious entries: ${lines} ..."
    else
        print_result "Wi-Fi logs (boot)" "PASS" "No suspicious Wi-Fi entries"
    fi
}

check_nm_wifi_logs_boot() {
    # Only flag warnings/errors, and only Wi-Fi related entries to reduce false positives
    local lines
    lines=$(journalctl -u NetworkManager -b -p warning..alert 2>/dev/null | \
        grep -Eai 'wifi|wlan|wpa|supplicant|802\.1x|auth' | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "NetworkManager Wi-Fi logs (boot)" "FAIL" "Warnings/Errors: ${lines} ..."
    else
        print_result "NetworkManager Wi-Fi logs (boot)" "PASS" "No Wi-Fi warnings/errors in NM logs"
    fi
}

check_journald_persistent() {
    local journald_conf="/etc/systemd/journald.conf"
    if grep -Eq "^Storage=persistent" "$journald_conf"; then
        print_result "Journald persistent logs" "PASS" "Storage=persistent configured"
    else
        print_result "Journald persistent logs" "FAIL" "Persistent logs disabled; logs may be lost on reboot"
    fi
}

check_wifi_driver_info() {
    local lspci_output
    lspci_output=$(lspci -k | grep -A3 Network)
    if [ -n "$lspci_output" ]; then
        local model
        model=$(echo "$lspci_output" | head -n1 | sed 's/^.*: //')
        print_result "Wi-Fi driver info (lspci)" "PASS" "$model"
    else
        print_result "Wi-Fi driver info (lspci)" "FAIL" "No Wi-Fi adapter found via lspci"
    fi
}

check_dmesg_ath9k() {
    local suspicious_regex='fail|error|timeout|timed out|reset|firmware|hang'
    local lines
    lines=$(dmesg 2>/dev/null | grep -i ath9k | grep -Eai "$suspicious_regex" | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "dmesg: ath9k" "FAIL" "Suspicious entries: ${lines} ..."
    else
        print_result "dmesg: ath9k" "PASS" "No suspicious ath9k messages"
    fi
}

check_dmesg_wlan0() {
    local suspicious_regex='fail|error|timeout|timed out|reset|firmware|disconnect|deauth|link down'
    local lines
    lines=$(dmesg 2>/dev/null | grep -i wlan0 | grep -Eai "$suspicious_regex" | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "dmesg: wlan0" "FAIL" "Suspicious entries: ${lines} ..."
    else
        print_result "dmesg: wlan0" "PASS" "No suspicious wlan0 messages"
    fi
}

check_mtu() {
    local wifi_if
    wifi_if=$(get_wifi_interface)
    local mtu
    mtu=$(ip -o link 2>/dev/null | awk -v iface="$wifi_if" -F': ' '$2==iface{print $3}' | sed -n 's/.*mtu \([0-9]\+\).*/\1/p')
    if [ -n "$wifi_if" ] && [ -n "$mtu" ]; then
        print_result "MTU settings" "PASS" "$wifi_if mtu=$mtu"
    else
        print_result "MTU settings" "PASS" "See: ip link (interface not found or MTU unreadable)"
    fi
}

check_fragmentation_ping() {
    local ping_test
    ping_test=$(ping -c 4 -M "do" -s 1472 8.8.8.8 2>&1)
    if ping -c 4 -M "do" -s 1472 8.8.8.8 >/dev/null 2>&1; then
        print_result "Fragmentation test (ping 8.8.8.8)" "PASS" "Path MTU OK"
    else
        local summary
        summary=$(echo "$ping_test" | tail -n 3 | tr '\n' ' ')
        print_result "Fragmentation test (ping 8.8.8.8)" "FAIL" "$summary"
    fi
}

check_regdom() {
    local reg
    reg=$(iw reg get 2>/dev/null | grep -E "country [A-Z]{2}")
    if [ -n "$reg" ]; then
        print_result "Regulatory domain" "PASS" "$(echo "$reg" | head -n1 | xargs)"
    else
        # Not strictly a failure; warn user it's advisable to set a country code
        print_result "Regulatory domain" "WARN" "No country code configured"
    fi
}

check_dhcpcd_logs() {
    local suspicious_regex='fail|error|timeout|timed out|nack|decline|no lease|expired'
    local lines
    lines=$(journalctl -u dhcpcd -b 2>/dev/null | grep -Eai "$suspicious_regex" | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "DHCP logs: dhcpcd" "FAIL" "Suspicious entries: ${lines} ..."
    else
        print_result "DHCP logs: dhcpcd" "PASS" "No suspicious entries"
    fi
}

check_dhclient_logs() {
    local suspicious_regex='fail|error|timeout|timed out|nack|decline|no lease|expired'
    local lines
    lines=$(journalctl -u dhclient@wlan0 -b 2>/dev/null | grep -Eai "$suspicious_regex" | head -n 5)
    if [ -n "$lines" ]; then
        lines=$(echo "$lines" | tr '\n' ' ')
        print_result "DHCP logs: dhclient@wlan0" "FAIL" "Suspicious entries: ${lines} ..."
    else
        print_result "DHCP logs: dhclient@wlan0" "PASS" "No suspicious entries or service not used"
    fi
}

check_nm_status() {
    if systemctl is-active --quiet NetworkManager.service; then
        print_result "NetworkManager service" "PASS" "Active"
    else
        local status
        status=$(systemctl status NetworkManager.service --no-pager 2>&1 | sed -n '1,5p' | tr '\n' ' ')
        print_result "NetworkManager service" "FAIL" "$status"
    fi
}

check_wifi_power_save() {
    local wifi_interface
    wifi_interface=$(get_wifi_interface)
    if [ -n "$wifi_interface" ]; then
        local powersave_status
        if powersave_status=$(iw dev "$wifi_interface" get power_save 2>&1); then
            local mode
            mode=$(echo "$powersave_status" | awk '{print $NF}')
            print_result "Wi-Fi power management" "PASS" "$wifi_interface power_save=$mode"
        else
            print_result "Wi-Fi power management" "FAIL" "Could not read power save for $wifi_interface"
        fi
    else
        print_result "Wi-Fi power management" "FAIL" "No Wi-Fi interface found"
    fi
}

check_iptables_forward() {
    # Informational; treat as PASS with brief summary of counts
    local line
    line=$(iptables -L FORWARD -v -n 2>/dev/null | sed -n '2p')
    if [ -n "$line" ]; then
        print_result "iptables FORWARD chain" "PASS" "$(echo "$line" | xargs)"
    else
        print_result "iptables FORWARD chain" "PASS" "No rules or iptables unavailable"
    fi
}

check_ath9k_conf() {
    local modprobe_conf="/etc/modprobe.d/ath9k.conf"
    if [ -f "$modprobe_conf" ]; then
        local first
        first=$(head -n 1 "$modprobe_conf" | xargs)
        print_result "ath9k driver config" "PASS" "Found $modprobe_conf: ${first:-non-empty}"
    else
        print_result "ath9k driver config" "PASS" "No custom config present"
    fi
}

run_automatic() {
    check_network_managers
    check_rfkill
    check_wifi_logs_boot
    check_nm_wifi_logs_boot
    check_journald_persistent
    check_wifi_driver_info
    check_dmesg_ath9k
    check_dmesg_wlan0
    check_mtu
    check_fragmentation_ping
    check_regdom
    check_dhcpcd_logs
    check_dhclient_logs
    check_nm_status
    check_wifi_power_save
    check_iptables_forward
    check_ath9k_conf

    echo
    gum style --bold "Summary: $(style_pass \"$PASS_COUNT pass\") / $(style_warn \"$WARN_COUNT warn\") / $(style_fail \"$FAIL_COUNT fail\")"
}

run_automatic

gum style --foreground 42 --bold "Wi-Fi diagnostic session finished."
exit 0