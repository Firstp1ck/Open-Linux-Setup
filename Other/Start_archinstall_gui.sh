#!/usr/bin/env bash

set -e

# Minimum required free space in KiB (500 MiB = 512000 KiB)
MINSPACE=512000

FREESPACE=$(df --output=avail / | tail -1)

if [ "$FREESPACE" -lt "$MINSPACE" ]; then
  echo "Not enough free space on /. Attempting to remount /run/archiso/cowspace to 1 GiB..."
  mount -o remount,size=1G /run/archiso/cowspace

  FREESPACE=$(df --output=avail / | tail -1)
  if [ "$FREESPACE" -lt "$MINSPACE" ]; then
    echo "Error: Still less than 500 MiB available after remount. Only $(($FREESPACE / 1024)) MiB free. Aborting."
    exit 1
  else
    echo "Remount successful. $(($FREESPACE / 1024)) MiB available."
  fi
fi

# Refresh package database
pacman -Syy --noconfirm

# Install essential Xorg components, XFCE, Ly, Calamares (swap xf86-video-intel if needed)
pacman -S --noconfirm xorg-server xorg-xinit xf86-input-libinput mesa xf86-video-intel xfce4 ly calamares

# Prompt for new user name
read -p "Enter the name for the new user: " NEWUSER
useradd -m -G wheel "$NEWUSER"
echo "Set password for $NEWUSER:"
passwd "$NEWUSER"

# Prompt for root password
echo "Set password for root:"
passwd root

# Grant wheel group sudo access by updating /etc/sudoers
sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers

# Make XFCE default session for the user
echo "exec startxfce4" > /home/$NEWUSER/.xinitrc
chown $NEWUSER:$NEWUSER /home/$NEWUSER/.xinitrc

# Enable and start Ly immediately
systemctl enable --now ly.service

echo "Ly started. Log in as $NEWUSER, then launch 'calamares' in XFCE to begin installation."
