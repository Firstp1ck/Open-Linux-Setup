#!/bin/bash

# Wi-Fi Diagnostic Script
# This script performs a series of checks to diagnose Wi-Fi connectivity issues.
# It does not alter any system configurations.

# Function Definitions for Informative Output
echo_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

echo_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

echo_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

echo_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Ensure the script is run with necessary privileges
if [ "$EUID" -ne 0 ]; then
    echo_warning "Some checks might require superuser privileges. Consider running the script with sudo."
fi

echo_success "Starting Wi-Fi diagnostic checks..."

# 1. Check for Multiple Network Managers
echo_info "1. Checking for active primary Network Managers..."

# Define primary network managers to check
declare -a primary_network_managers=("NetworkManager.service" "systemd-networkd.service")

# Initialize an array to hold enabled primary network managers
enabled_network_managers=()

# Iterate over each primary network manager and check if it's enabled
for service in "${primary_network_managers[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        enabled_network_managers+=("$service")
    fi
done

# Determine the number of enabled primary network managers
num_enabled=${#enabled_network_managers[@]}

if [ "$num_enabled" -le 1 ]; then
    echo_success "Only one primary Network Manager is enabled."
else
    echo_warning "Multiple primary Network Managers are enabled:"
    for svc in "${enabled_network_managers[@]}"; do
        echo "  - $svc"
    done
fi
echo ""

# 2. Check Hardware Issues with RFKill
echo_info "2. Checking for hardware or software blocks using rfkill..."
rfkill_output=$(rfkill list all)
echo "$rfkill_output"
if echo "$rfkill_output" | grep -q "Hard blocked: yes\|Soft blocked: yes"; then
    echo_warning "There are hardware or software blocks on your Wi-Fi device."
else
    echo_success "No hardware or software blocks detected."
fi
echo ""

# 3. Check Wi-Fi Related Logs
echo_info "3. Checking Wi-Fi related logs from the current boot..."
if journalctl -b | grep -iq "wifi" | sort | uniq -f 6; then
    journalctl -b | grep -i "wifi" | sort | uniq -f 6
else
    echo_success "No Wi-Fi related logs found for the current boot."
fi
echo ""

echo_info "   Checking NetworkManager logs from the current boot..."
if journalctl -u NetworkManager -b | grep -iq "wifi" | sort | uniq -f 6; then
    journalctl -u NetworkManager -b | grep -i "wifi" | sort | uniq -f 6
else
    echo_success "No Wi-Fi related logs found in NetworkManager logs for the current boot."
fi
echo ""

# 4. Check if Persistent Logs are Enabled
echo_info "4. Checking if persistent logs are enabled in systemd-journald..."
journald_conf="/etc/systemd/journald.conf"
if grep -Eq "^Storage=persistent" "$journald_conf"; then
    echo_success "Persistent logging is enabled."
else
    echo_warning "Persistent logging is not enabled. Logs may not be saved after reboot."
fi
echo ""

# 5. Check Wi-Fi Driver Information
echo_info "5. Checking Wi-Fi driver information..."
lspci_output=$(lspci -k | grep -A3 Network)
if [ -n "$lspci_output" ]; then
    echo "$lspci_output"
    echo_success "Retrieved Wi-Fi adapter information."
else
    echo_warning "No Wi-Fi adapter information found using lspci."
fi
echo ""

echo_info "   Checking dmesg for ath9k driver messages..."
dmesg_ath9k=$(dmesg | grep ath9k)
if [ -n "$dmesg_ath9k" ]; then
    echo "$dmesg_ath9k"
else
    echo_success "No ath9k driver messages found in dmesg."
fi
echo ""

echo_info "   Checking dmesg for wlan0 interface messages..."
dmesg_wlan0=$(dmesg | grep wlan0 | sort | uniq -f 2)
if [ -n "$dmesg_wlan0" ]; then
    echo "$dmesg_wlan0"
else
    echo_success "No wlan0 interface messages found in dmesg."
fi
echo ""

# 6. Check MTU Settings
echo_info "6. Checking MTU settings on network interfaces..."
ip link
echo ""

# 7. Check Fragmentation Issues with Ping
echo_info "7. Checking for fragmentation issues using ping (pinging 8.8.8.8 with packet size 1472)..."
ping_test=$(ping -c 4 -M do -s 1472 8.8.8.8 2>/dev/null)
if [ $? -eq 0 ]; then
    echo_success "No fragmentation issues detected."
    echo "$ping_test"
else
    echo_warning "Fragmentation issues detected or ping failed."
    echo "$ping_test"
fi
echo ""

# 8. Check Regulatory Domains
echo_info "8. Checking current regulatory domain settings..."
iw reg get
echo ""

# 9. Verify DHCP Configuration
echo_info "9. Checking DHCP client logs for dhcpcd..."
dhcpcd_logs=$(journalctl -u dhcpcd -b)
if [ -n "$dhcpcd_logs" ]; then
    echo "$dhcpcd_logs"
else
    echo_success "No dhcpcd logs found for the current boot."
fi
echo ""

echo_info "   Checking DHCP client logs for dhclient@wlan0..."
dhclient_logs=$(journalctl -u dhclient@wlan0 -b)
if [ -n "$dhclient_logs" ]; then
    echo "$dhclient_logs"
else
    echo_success "No dhclient@wlan0 logs found for the current boot."
fi
echo ""

# 10. Display NetworkManager Service Status
echo_info "10. Checking NetworkManager service status..."
systemctl status NetworkManager.service --no-pager
echo ""

# 11. Check Power Management Settings for Wi-Fi
echo_info "11. Checking Wi-Fi power management settings..."
# Determine the Wi-Fi interface name dynamically
wifi_interface=$(iw dev | awk '$1=="Interface"{print $2}' | head -n1)
if [ -n "$wifi_interface" ]; then
    powersave_status=$(iw dev "$wifi_interface" get power_save 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$powersave_status"
    else
        echo_warning "Could not retrieve power save status for $wifi_interface. Ensure the interface name is correct."
    fi
else
    echo_warning "No Wi-Fi interface found."
fi
echo ""

# 12. Check iptables FORWARD Chain Logging
echo_info "12. Checking iptables FORWARD chain for logging rules..."
iptables -L FORWARD -v -n
echo ""

# 13. Check ath9k Driver Configuration
echo_info "13. Checking ath9k driver configuration..."
modprobe_conf="/etc/modprobe.d/ath9k.conf"
if [ -f "$modprobe_conf" ]; then
    echo "Contents of $modprobe_conf:"
    cat "$modprobe_conf"
else
    echo_success "$modprobe_conf does not exist. No custom ath9k configurations found."
fi
echo ""

echo_success "Wi-Fi diagnostic checks completed."
echo ""

# 14. Prompt to Open Journal Log
echo_info "14. Would you like to open the full journal log for the current boot? (y/n)"
read -r -p "Open journal log? [y/N]: " choice

case "$choice" in
    y|Y )
        echo_info "Opening journal log... Press 'q' to exit."
        journalctl -b -g 'wifi|network|wlan'
        ;;
    * )
        echo_info "Skipping opening the journal log."
        ;;
esac

echo_success "Script execution finished."

echo -e "\nPress Enter to exit..."
read -r

exit 0