#!/usr/bin/env bash

echo "Checking for btusb module..."
if ! lsmod | grep -q btusb; then
    echo "btusb not loaded. Loading..."
    sudo modprobe btusb
    sleep 1
fi

echo "Rechecking for btusb module..."
if ! lsmod | grep -q btusb; then
    echo "btusb still not loaded. Checking for bluez-hid2hci..."
    if ! pacman -Q bluez-hid2hci &>/dev/null; then
        echo "bluez-hid2hci not installed. Installing..."
        sudo pacman -S --noconfirm bluez-hid2hci
    else
        echo "bluez-hid2hci is installed. Running hciconfig..."
        hciconfig -a
    fi
else
    echo "btusb module loaded."
fi

echo "Checking for Bluetooth block status..."
blocked=$(rfkill list bluetooth | grep -i "blocked: yes")
if [[ -n "$blocked" ]]; then
    echo "Bluetooth is blocked. Unblocking..."
    sudo rfkill unblock bluetooth
    sleep 1
    echo "Rechecking block status..."
    rfkill list bluetooth
else
    echo "Bluetooth is not blocked."
fi

echo "Checking Bluetooth service status..."
status=$(systemctl is-active bluetooth.service)
if [[ "$status" != "active" ]]; then
    echo "Bluetooth service not running. Restarting..."
    sudo systemctl restart bluetooth.service
else
    echo "Bluetooth service is running."
fi
