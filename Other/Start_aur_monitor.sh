#!/usr/bin/env bash

# Requires: libnotify (notify-send) and netcat
# sudo pacman -S libnotify gnu-netcat

while ! nc -z -w3 aur.archlinux.org 22; do
    date
    sleep 30
done
notify-send -u normal -i network-server -a port-watch "AUR SSH is UP" "aur.archlinux.org:22 is accepting connections"