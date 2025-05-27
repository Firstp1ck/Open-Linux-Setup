#!/usr/bin/env bash

# This script prompts the user for system-specific variables
# and outputs them in a format that can be sourced by another script.

echo "Please provide values for the system-specific variables."
echo "Press Enter to accept default values where provided."

# Define default values
DEFAULT_DOCUMENTS_DIR="Dokumente"
DEFAULT_PICTURE_DIR="Bilder"
DEFAULT_DOWNLOADS_DIR="Downloads"
DEFAULT_NAS_PORT="9222"
DEFAULT_ONEDRIVE_SYNC_DIR="$HOME/Onedrive"
DEFAULT_TIMEZONE="Europe/Zurich"

# Define default output file path
DEFAULT_OUTPUT_FILE="./system_variables.sh"

# Flag to indicate if default values should be used
USE_DEFAULTS=false

# Check for --default option
if [[ "$1" == "--default" || "$1" == "-d" ]]; then
    USE_DEFAULTS=true
    echo "Using default values."
fi

# Prompt for each variable or use defaults
if [ "$USE_DEFAULTS" == false ]; then

    read -rp "Enter your Timezone (default: $DEFAULT_TIMEZONE): " TIMEZONE
    TIMEZONE=${TIMEZONE:-$DEFAULT_TIMEZONE} # Use default if input is empty

    read -rp "Enter the mount point for your SSD/NVMe (e.g., /mnt/SSD_NVME_4TB): " SSD_MNT
    read -rp "Enter your Documents directory name (default: $DEFAULT_DOCUMENTS_DIR): " DOCUMENTS_DIR
    DOCUMENTS_DIR=${DOCUMENTS_DIR:-$DEFAULT_DOCUMENTS_DIR} # Use default if input is empty

    read -rp "Enter your Pictures directory name (default: $DEFAULT_PICTURE_DIR): " PICTURE_DIR
    PICTURE_DIR=${PICTURE_DIR:-$DEFAULT_PICTURE_DIR} # Use default if input is empty

    read -rp "Enter your Downloads directory name (default: $DEFAULT_DOWNLOADS_DIR): " DOWNLOADS_DIR
    DOWNLOADS_DIR=${DOWNLOADS_DIR:-$DEFAULT_DOWNLOADS_DIR} # Use default if input is empty

    read -rp "Enter your SSH email address: " SSH_EMAIL
    read -rp "Enter your SSH server IP address: " SSH_SERVER_IP
    read -rp "Enter your SSH username: " SSH_USER

    read -rp "Enter your Git username: " GIT_USER
    read -rp "Enter your Git email address: " GIT_EMAIL

    # Prompt for Git Dotfiles URL
    read -rp "Enter your Git dotfiles repository URL (e.g., https://github.com/your_username/.dotfiles.git): " GIT_DOTFILES

    read -rp "Enter your username for Tor (if applicable): " TOR_USER

    read -rp "Enter your NAS IP address: " NAS_IP
    read -rp "Enter your NAS SSH port (default: $DEFAULT_NAS_PORT): " NAS_PORT
    NAS_PORT=${NAS_PORT:-$DEFAULT_NAS_PORT} # Use default if input is empty

    read -rp "Enter your NAS username: " NAS_USER
    read -rp "Enter the destination path on your NAS (e.g., /Volume1/public/Onedrive): " NAS_DEST

    read -rp "Enter the sync directory path for OneDrive (Defaults to $DEFAULT_ONEDRIVE_SYNC_DIR): " ONEDRIVE_SYNC_DIR
    ONEDRIVE_SYNC_DIR=${ONEDRIVE_SYNC_DIR:-$DEFAULT_ONEDRIVE_SYNC_DIR}
    # Resolve potential ~ in ONEDRIVE_SYNC_DIR
    if [[ "$ONEDRIVE_SYNC_DIR" == "~"* ]]; then
        ONEDRIVE_SYNC_DIR="${HOME}${ONEDRIVE_SYNC_DIR:1}"
    fi

    # Prompt for the output file path
    read -rp "Enter the desired output file path for variables (default: $DEFAULT_OUTPUT_FILE): " OUTPUT_FILE
    OUTPUT_FILE=${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE} # Use default if input is empty
else
    # Set variables to default values or empty if --default is used
    SSD_MNT=""
    DOCUMENTS_DIR="$DEFAULT_DOCUMENTS_DIR"
    PICTURE_DIR="$DEFAULT_PICTURE_DIR"
    DOWNLOADS_DIR="$DEFAULT_DOWNLOADS_DIR"
    SSH_EMAIL=""
    SSH_SERVER_IP=""
    SSH_USER=""
    GIT_USER=""
    GIT_EMAIL=""
    GIT_DOTFILES=""
    TOR_USER=""
    NAS_IP=""
    NAS_PORT="$DEFAULT_NAS_PORT"
    NAS_USER=""
    NAS_DEST=""
    ONEDRIVE_SYNC_DIR="$DEFAULT_ONEDRIVE_SYNC_DIR"
    TIMEZONE=$DEFAULT_TIMEZONE

    # Use the default output file path
    OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
fi


# --- Derived variables (calculated based on user input or defaults) ---
# Ensure derived variables are calculated AFTER prompts/defaults are set
BACKUP_DIR="$SSD_MNT/System_BackUp/"
GIT_DIR="$HOME/$DOCUMENTS_DIR/GitHub"
# Assuming .dotfiles is directly in $HOME
HYPR_SCRIPTS="$HOME/.dotfiles/.config/hypr"
ONEDRIVE_CONFIG_DIR="$HOME/.config/onedrive"
RCLONE_ONEDRIVE_DIR="$SSD_MNT/Onedrive_rclone"
SETUP_DIR="$GIT_DIR/Open-Linux-Setup"

# Note: ONEDRIVE_SOURCE might still need clarification based on how you use it.
# In your script, it's "$SSD_MNT/Onedrive/", which might not match ONEDRIVE_SYNC_DIR
# if the user enters a path not under SSD_MNT. Consider using ONEDRIVE_SYNC_DIR
# consistently or prompting for ONEDRIVE_SOURCE separately if it MUST be under SSD_MNT.
# For now, keeping the original definition:
ONEDRIVE_SOURCE="$SSD_MNT/Onedrive/"

# Output the variables to the specified file
{
echo "#!/usr/bin/env bash"
echo "# Auto-generated variables from Start_set_variables.sh"

echo ""
echo "SSD_MNT=\"$SSD_MNT\""
echo "BACKUP_DIR=\"$BACKUP_DIR\""
echo "DOCUMENTS_DIR=\"$DOCUMENTS_DIR\""
echo "PICTURE_DIR=\"$PICTURE_DIR\""
echo "DOWNLOADS_DIR=\"$DOWNLOADS_DIR\""
echo "GIT_DIR=\"$GIT_DIR\""
echo "GIT_DOTFILES=\"$GIT_DOTFILES\""
echo "GIT_LINUX_SETUP=\"https://github.com/Firstp1ck/Open-Linux-Setup.git\""
echo "SETUP_DIR=\"$SETUP_DIR\"" # Derived
echo "HYPR_SCRIPTS=\"$HYPR_SCRIPTS\"" # Derived
echo "SSH_EMAIL=\"$SSH_EMAIL\""
echo "SSH_SERVER_IP=\"$SSH_SERVER_IP\""
echo "SSH_USER=\"$SSH_USER\""
echo "GIT_USER=\"$GIT_USER\""
echo "GIT_EMAIL=\"$GIT_EMAIL\""
echo "TOR_USER=\"$TOR_USER\""
echo "NAS_IP=\"$NAS_IP\""
echo "NAS_PORT=\"$NAS_PORT\""
echo "NAS_USER=\"$NAS_USER\""
echo "NAS_DEST=\"$NAS_DEST\""
echo "ONEDRIVE_SYNC_DIR=\"$ONEDRIVE_SYNC_DIR\""
echo "ONEDRIVE_CONFIG_DIR=\"$ONEDRIVE_CONFIG_DIR\"" # Derived
echo "ONEDRIVE_SOURCE=\"$ONEDRIVE_SOURCE\"" # Derived based on SSD_MNT
echo "RCLONE_ONEDRIVE_DIR=\"$RCLONE_ONEDRIVE_DIR\"" # Derived based on SSD_MNT
echo "TIMEZONE=\"$TIMEZONE\""
} > "$OUTPUT_FILE"

echo ""
echo "System variables saved to $OUTPUT_FILE"