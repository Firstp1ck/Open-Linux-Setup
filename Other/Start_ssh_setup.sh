#!/usr/bin/env bash

# === Step 1: Detect USB device ===
echo "[INFO] Detecting USB device..."
DEVICE=$(lsblk -pno NAME,TRAN | awk '$2=="usb"{print $1}' | head -n 1)
if [ -z "$DEVICE" ]; then
  echo "[ERROR] No USB device detected. Please insert a USB stick and try again."
  exit 1
else
  echo "[OK] USB device detected: $DEVICE"
fi

# Find the first partition on the device (e.g., /dev/sdb1)
PARTITION="${DEVICE}1"
echo "[INFO] Checking for partition: $PARTITION..."
if ! lsblk | grep -q "$(basename "$PARTITION")"; then
  echo "[ERROR] Partition $PARTITION not found. Please check your USB stick."
  exit 1
else
  echo "[OK] Partition found: $PARTITION"
fi

# === Step 2: Mount the USB partition ===
MOUNTPOINT="/mnt/usb"
echo "[INFO] Mounting $PARTITION to $MOUNTPOINT..."
sudo mkdir -p "$MOUNTPOINT"
if sudo mount "$PARTITION" "$MOUNTPOINT"; then
  echo "[OK] Mounted $PARTITION at $MOUNTPOINT."
else
  echo "[ERROR] Failed to mount $PARTITION."
  exit 1
fi

# === Step 3: Copy the key file ===
KEY_FILE="$HOME/.ssh/id_rsa"
echo "[INFO] Checking for SSH private key at $KEY_FILE..."
if [ ! -f "$KEY_FILE" ]; then
  echo "[ERROR] SSH private key not found: $KEY_FILE"
  sudo umount "$MOUNTPOINT"
  exit 1
else
  echo "[OK] SSH private key found. Copying to USB..."
fi

if cp "$KEY_FILE" "$MOUNTPOINT/"; then
  echo "[OK] SSH private key copied to USB stick ($MOUNTPOINT)"
else
  echo "[ERROR] Failed to copy SSH private key to USB stick."
  sudo umount "$MOUNTPOINT"
  exit 1
fi

# === Step 4: Optionally unmount USB after copying ===
echo "[INFO] Unmounting USB stick..."
if sudo umount "$MOUNTPOINT"; then
  echo "[OK] USB stick unmounted. You can now safely remove it."
else
  echo "[WARNING] Failed to unmount USB stick. Please unmount manually if needed."
fi

# === Step 5: Detect Linux distribution and install OpenSSH server accordingly ===
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO_ID=$ID
else
  echo "[ERROR] /etc/os-release not found. Cannot determine Linux distribution."
  exit 1
fi

INSTALL_CMD=""
SERVICE_NAME=""

case "$DISTRO_ID" in
  arch|manjaro|endeavouros|cachyos)
    INSTALL_CMD="sudo pacman -Syu --noconfirm openssh"
    SERVICE_NAME="sshd"
    ;;
  debian|ubuntu|linuxmint|pop|mint)
    INSTALL_CMD="sudo apt-get update && sudo apt-get install -y openssh-server"
    SERVICE_NAME="ssh"
    ;;
  fedora|bazzite|nobara)
    INSTALL_CMD="sudo dnf install -y openssh-server"
    SERVICE_NAME="sshd"
    ;;
  *)
    echo "[ERROR] Unsupported or unrecognized Linux distribution: $DISTRO_ID"
    exit 1
    ;;
esac

# === Step 6: Install OpenSSH server (if not already installed) ===
echo "[INFO] Checking if OpenSSH server is installed..."
if ! command -v sshd >/dev/null 2>&1; then
  echo "[INFO] Installing OpenSSH server..."
  eval "$INSTALL_CMD"
  if [ $? -eq 0 ]; then
    echo "[OK] OpenSSH server installed."
  else
    echo "[ERROR] Failed to install OpenSSH server."
    exit 1
  fi
else
  echo "[OK] OpenSSH server is already installed."
fi

# === Step 7: Start SSH service and enable it to start at boot ===
echo "[INFO] Starting SSH service and enabling it to start at boot..."
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME
if [ $? -eq 0 ]; then
  echo "[OK] SSH service started and enabled."
else
  echo "[ERROR] Failed to start SSH service."
  exit 1
fi

# === Step 8: Generate SSH keypair (defaults to ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub) ===
KEY_COMMENT="${USER}@$(hostname)"
KEY_FILE="$HOME/.ssh/id_rsa"
echo "[INFO] Checking for existing SSH key at $KEY_FILE..."
if [ -f "$KEY_FILE" ]; then
  echo "[OK] An SSH key already exists at $KEY_FILE. Skipping generation."
else
  echo "[INFO] Generating SSH keypair..."
  ssh-keygen -t rsa -b 4096 -C "$KEY_COMMENT" -N "" -f "$KEY_FILE"
  if [ $? -eq 0 ]; then
    echo "[OK] SSH keypair generated."
  else
    echo "[ERROR] Failed to generate SSH keypair."
    exit 1
  fi
fi

# === Step 9: Copy private key to Downloads folder ===
# Check if Downloads folder exists
DOWNLOADS_DIR="$HOME/Downloads"
echo "[INFO] Checking for Downloads folder at $DOWNLOADS_DIR..."
if [ ! -d "$DOWNLOADS_DIR" ]; then
  echo "[WARNING] Downloads folder ($DOWNLOADS_DIR) does not exist. It will be created later if needed."
fi
if [ ! -d "$DOWNLOADS_DIR" ]; then
  echo "[INFO] Creating Downloads folder at $DOWNLOADS_DIR..."
  mkdir -p "$DOWNLOADS_DIR"
  if [ $? -eq 0 ]; then
    echo "[OK] Downloads folder created."
  else
    echo "[ERROR] Failed to create Downloads folder."
    exit 1
  fi
fi

echo "[INFO] Copying SSH private key to $DOWNLOADS_DIR..."
if cp "$KEY_FILE" "$DOWNLOADS_DIR/"; then
  echo "[OK] SSH private key copied to $DOWNLOADS_DIR/"
else
  echo "[ERROR] Failed to copy SSH private key to $DOWNLOADS_DIR/"
  exit 1
fi

echo "[SUCCESS] SSH server setup completed."
