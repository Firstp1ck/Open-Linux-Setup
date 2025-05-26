#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${2}${1}${NC}"
}

print_message "Starting WiFi restart process..." "${BLUE}"

# Restart NetworkManager
print_message "Restarting NetworkManager..." "${YELLOW}"
sudo systemctl restart NetworkManager
if [ $? -eq 0 ]; then
    print_message "NetworkManager restarted successfully." "${GREEN}"
else
    print_message "Failed to restart NetworkManager." "${RED}"
fi

# Restart dhcpcd (if used)
print_message "Identifying wireless interface..." "${YELLOW}"
interface=$(ip -o link show | awk -F': ' '{print $2}' | grep -i 'wl')
if [ -n "$interface" ]; then
    print_message "Wireless interface identified: $interface" "${GREEN}"
    print_message "Restarting dhcpcd for $interface..." "${YELLOW}"
    sudo systemctl restart dhcpcd@$interface.service
    if [ $? -eq 0 ]; then
        print_message "dhcpcd restarted successfully for $interface." "${GREEN}"
    else
        print_message "Failed to restart dhcpcd for $interface." "${RED}"
    fi
else
    print_message "No wireless interface found." "${RED}"
fi

# Unload and reload WiFi driver
print_message "Unloading WiFi drivers..." "${YELLOW}"
sudo modprobe -r iwlmvm iwlwifi
print_message "Reloading WiFi drivers..." "${YELLOW}"
sudo modprobe iwlwifi
print_message "WiFi drivers reloaded." "${GREEN}"

# Disable and re-enable WiFi
print_message "Disabling WiFi..." "${YELLOW}"
rfkill block wifi
print_message "Re-enabling WiFi..." "${YELLOW}"
rfkill unblock wifi
print_message "WiFi disabled and re-enabled." "${GREEN}"

# Bring interface down and up
if [ -n "$interface" ]; then
    print_message "Bringing $interface down..." "${YELLOW}"
    sudo ip link set $interface down
    print_message "Bringing $interface up..." "${YELLOW}"
    sudo ip link set $interface up
    print_message "Interface $interface cycled." "${GREEN}"
fi

print_message "WiFi restart process complete." "${BLUE}"
print_message "Please wait a moment for the connection to re-establish." "${GREEN}"

echo -e "\nPress Enter to exit..."
read -r

exit 0