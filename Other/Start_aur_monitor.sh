#!/usr/bin/env bash

# Requires: libnotify (notify-send) and netcat
# sudo pacman -S libnotify gnu-netcat

HOST="aur.archlinux.org"
PORT=22
APP_NAME="port-watch"

last_state=""
while true; do
    if nc -z -w3 "$HOST" "$PORT"; then
        current_state="up"
        if [ "$last_state" = "down" ]; then
            notify-send -u normal -i network-server -a "$APP_NAME" "AUR SSH is UP" "$HOST:$PORT is accepting connections"
            echo "$(date) - AUR SSH is UP"
        fi
    else
        current_state="down"
        if [ "$last_state" != "down" ]; then
            notify-send -u critical -i network-error -a "$APP_NAME" "AUR SSH is DOWN" "$HOST:$PORT is not accepting connections"
            echo "$(date) - AUR SSH is DOWN"
        fi
    fi
    last_state="$current_state"
    sleep 60
done