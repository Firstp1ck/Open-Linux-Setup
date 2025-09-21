#!/bin/bash

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper: check if gum is available
use_gum() { command -v gum &>/dev/null; }

# gum-aware printing helpers
print_info() {
    if use_gum; then
        gum style --foreground "#3B82F6" "[INFO] $1"
    else
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

print_success() {
    if use_gum; then
        gum style --foreground "#10B981" "[SUCCESS] $1"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

print_warning() {
    if use_gum; then
        gum style --foreground "#F59E0B" "[WARNING] $1"
    else
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

print_error() {
    if use_gum; then
        gum style --foreground "#EF4444" "[ERROR] $1"
    else
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

# Unified yes/no prompt with default handling (uses gum confirm if available)
ask_yes_no() {
    # Usage: ask_yes_no "Prompt" "default"; returns 0 for yes, 1 for no
    local prompt="$1"
    local default_ans="${2:-}"
    if use_gum; then
        local args=()
        case "$default_ans" in
            y|Y) args+=(--default) ;;
        esac
        if gum confirm "${args[@]}" "$prompt"; then
            return 0
        else
            return 1
        fi
    fi
    # Fallback to read
    local hint reply
    case "$default_ans" in
        y|Y) hint="Y/n" ;;
        n|N) hint="y/N" ;;
        *)   hint="y/n" ;;
    esac
    while true; do
        read -rp "$prompt [$hint]: " reply
        reply=${reply,,}
        if [[ -z "$reply" ]]; then
            case "$default_ans" in
                y|Y) return 0 ;;
                n|N) return 1 ;;
            esac
        fi
        case "$reply" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
        esac
        print_error "Please answer 'y' or 'n'."
    done
}

# Spinner wrapper for long-running commands
run_with_spinner() {
    local title="$1"; shift
    if use_gum; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        print_info "$title"
        "$@"
    fi
}

# Keep sudo fresh: ask once and refresh timestamp while the script runs
start_sudo_keepalive() {
    # Prompt for sudo up-front
    if ! sudo -v; then
        print_error "Sudo authentication failed."
        exit 1
    fi

    # Refresh sudo timestamp every 60 seconds until script exits
    while true; do
        sleep 60
        sudo -n true || break
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!

    # Stop refresher on exit and invalidate timestamp
    trap 'if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true; fi; sudo -k' EXIT
}

# Validate platform (Arch/EndeavourOS via pacman) and optionally show detected distro
validate_platform() {
    if ! command -v pacman &>/dev/null; then
        print_error "pacman not found. This script supports Arch-based systems (Arch/EndeavourOS) only."
        exit 1
    fi
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        print_info "Detected distro: ${NAME:-Unknown} (${ID:-unknown})"
    else
        print_info "Detected pacman-based system."
    fi
}

# Ensure gum is installed (optional). If not, offer to install; otherwise continue without gum.
ensure_gum_available() {
    if use_gum; then return 0; fi
    print_warning "gum CLI not found. For a better TUI experience, you can install it now."
    if ask_yes_no "Install gum now?" y; then
        if sudo pacman -S --needed --noconfirm gum; then
            print_success "gum installed."
            return 0
        fi
        # Try via AUR if pacman package not found
        local helper
        if helper=$(find_aur_helper); then
            if run_with_spinner "Installing gum via $helper" "$helper" -S --noconfirm --needed gum-bin; then
                print_success "gum installed via $helper."
                return 0
            fi
        fi
        print_warning "Failed to install gum automatically. Continuing without gum UI."
    else
        print_info "Continuing without gum UI."
    fi
    return 1
}

# Ensure lsb-release is available or offer to install it
ensure_lsb_release_available() {
    if [[ -f /etc/lsb-release ]]; then
        return 0
    fi

    if pacman -Q lsb-release &>/dev/null; then
        print_warning "/etc/lsb-release not found, but lsb-release package is installed. Proceeding without it."
        return 1
    fi

    print_warning "/etc/lsb-release not found. Some features expect it."
    if ask_yes_no "Install 'lsb-release' package now?" n; then
        if run_with_spinner "Installing lsb-release" sudo pacman -S --noconfirm --needed lsb-release; then
            if [[ -f /etc/lsb-release ]]; then
                print_success "lsb-release installed and file present."
                return 0
            else
                print_warning "lsb-release installed but /etc/lsb-release still missing."
                return 1
            fi
        else
            print_error "Failed to install lsb-release."
            return 1
        fi
    else
        print_warning "Skipping lsb-release installation and related checks."
        return 1
    fi
}

# Helper: check if penguins-eggs is installed (via pacman or binary on PATH)
eggs_installed() {
    if pacman -Q penguins-eggs &>/dev/null; then
        return 0
    fi
    if command -v eggs &>/dev/null; then
        return 0
    fi
    return 1
}

# Helper: detect available AUR helper (yay, paru)
find_aur_helper() {
    local helper
    for helper in yay paru; do
        if command -v "$helper" &>/dev/null; then
            echo "$helper"
            return 0
        fi
    done
    return 1
}

# Helper: install yay from AUR if no helper is present
install_yay() {
    print_info "Installing yay (AUR helper)..."

    if ! command -v pacman &>/dev/null; then
        print_error "pacman not found. This script supports Arch-based systems only."
        return 1
    fi

    # Ensure prerequisites
    if ! run_with_spinner "Installing base-devel git" sudo pacman -S --needed --noconfirm base-devel git; then
        print_error "Failed to install prerequisites (base-devel, git)."
        return 1
    fi

    local workdir
    workdir=$(mktemp -d)

    # Try yay-bin first (faster), then fallback to yay
    if git clone https://aur.archlinux.org/yay-bin.git "$workdir/yay-bin" &>/dev/null; then
        if run_with_spinner "Building yay-bin" bash -lc "cd '$workdir/yay-bin' && makepkg -si --noconfirm"; then
            rm -rf "$workdir"
            if command -v yay &>/dev/null; then
                print_success "yay installed successfully"
                return 0
            fi
        else
            print_warning "Building yay-bin failed, trying yay..."
        fi
    else
        print_warning "Cloning yay-bin failed, trying yay..."
    fi

    if git clone https://aur.archlinux.org/yay.git "$workdir/yay" &>/dev/null; then
        if run_with_spinner "Building yay" bash -lc "cd '$workdir/yay' && makepkg -si --noconfirm"; then
            rm -rf "$workdir"
            if command -v yay &>/dev/null; then
                print_success "yay installed successfully"
                return 0
            fi
        else
            print_error "Building yay failed."
        fi
    else
        print_error "Cloning yay repository failed."
    fi

    rm -rf "$workdir"
    return 1
}

# Function to check if penguins-eggs is installed
check_penguins_eggs() {
    print_info "Checking if penguins-eggs is installed..."
    
    if eggs_installed; then
        print_success "penguins-eggs is already installed"
        return 0
    else
        print_warning "penguins-eggs is not installed"
        return 1
    fi
}

# Function to install penguins-eggs
install_penguins_eggs() {
    print_info "Attempting to install penguins-eggs..."

    if eggs_installed; then
        print_success "penguins-eggs is already installed"
        return 0
    fi

    local helper
    if helper=$(find_aur_helper); then
        print_info "Using AUR helper: $helper"
    else
        print_warning "No supported AUR helper found (yay or paru). Attempting to install yay..."
        if install_yay && helper=$(find_aur_helper); then
            print_info "Using AUR helper: $helper"
        else
            print_error "Failed to install or detect an AUR helper. Install yay or paru manually and re-run."
            exit 1
        fi
    fi

    if run_with_spinner "Installing penguins-eggs" "$helper" -S --noconfirm --needed penguins-eggs; then
        print_success "penguins-eggs installed successfully"
        if eggs_installed; then
            return 0
        else
            print_error "Installation verification failed"
            exit 1
        fi
    else
        print_error "Failed to install penguins-eggs with $helper"
        exit 1
    fi
}

# Function to check lsb-release file
check_lsb_release() {
    print_info "Checking /etc/lsb-release configuration..."
    
    if [[ ! -f /etc/lsb-release ]]; then
        print_warning "/etc/lsb-release file does not exist"
        return 1
    fi

    local DISTRIB_ID="" DISTRIB_RELEASE="" DISTRIB_DESCRIPTION="" DISTRIB_CODENAME=""
    # shellcheck disable=SC1091
    source /etc/lsb-release || true

    if [[ "$DISTRIB_ID" == "EndeavourOS" && \
          "$DISTRIB_RELEASE" == "rolling" && \
          "$DISTRIB_DESCRIPTION" == "EndeavourOS Linux" && \
          "$DISTRIB_CODENAME" == "rolling" ]]; then
        print_success "lsb-release is correctly configured for EndeavourOS"
        return 0
    fi

    if [[ "$DISTRIB_ID" == "Arch" && \
          "$DISTRIB_RELEASE" == "rolling" && \
          "$DISTRIB_DESCRIPTION" == "Arch Linux" ]]; then
        print_success "lsb-release is correctly configured for Arch Linux"
        return 0
    fi
    
    print_warning "lsb-release is not configured correctly (ID='$DISTRIB_ID', RELEASE='$DISTRIB_RELEASE')"
    return 1
}

# Function to configure lsb-release
configure_lsb_release() {
    print_info "Current /etc/lsb-release content:"
    if [[ -f /etc/lsb-release ]]; then
        cat /etc/lsb-release
    else
        print_warning "File does not exist"
    fi
    
    echo
    print_info "Available configurations:"

    local selection=""
    if use_gum; then
        selection=$(gum choose "EndeavourOS" "Arch Linux" "Skip")
    else
        echo "1) EndeavourOS (recommended for EndeavourOS systems)"
        echo "2) Arch Linux (generic Arch configuration)"
        echo "3) Skip configuration"
        while true; do
            read -rp "Choose configuration (1-3): " choice
            case $choice in
                1) selection="EndeavourOS"; break;;
                2) selection="Arch Linux"; break;;
                3) selection="Skip"; break;;
                *) print_error "Invalid choice. Please select 1, 2, or 3." ;;
            esac
        done
    fi

    case "$selection" in
        "EndeavourOS")
            print_info "Setting EndeavourOS configuration..."
            if [[ -f /etc/lsb-release ]]; then
                local ts
                ts=$(date +%Y%m%d%H%M%S)
                sudo cp /etc/lsb-release "/etc/lsb-release.bak.$ts"
                print_info "Backup created at /etc/lsb-release.bak.$ts"
            fi
            local tmp
            tmp=$(mktemp)
            printf '%s\n' \
"DISTRIB_ID=\"EndeavourOS\"" \
"DISTRIB_RELEASE=\"rolling\"" \
"DISTRIB_DESCRIPTION=\"EndeavourOS Linux\"" \
"DISTRIB_CODENAME=\"rolling\"" > "$tmp"
            sudo install -m 644 "$tmp" /etc/lsb-release && rm -f "$tmp"
            print_success "EndeavourOS configuration applied"
            ;;
        "Arch Linux")
            print_info "Setting Arch Linux configuration..."
            if [[ -f /etc/lsb-release ]]; then
                local ts
                ts=$(date +%Y%m%d%H%M%S)
                sudo cp /etc/lsb-release "/etc/lsb-release.bak.$ts"
                print_info "Backup created at /etc/lsb-release.bak.$ts"
            fi
            local tmp
            tmp=$(mktemp)
            printf '%s\n' \
"DISTRIB_ID=\"Arch\"" \
"DISTRIB_RELEASE=\"rolling\"" \
"DISTRIB_DESCRIPTION=\"Arch Linux\"" \
"#DISTRIB_CODENAME=rolling" > "$tmp"
            sudo install -m 644 "$tmp" /etc/lsb-release && rm -f "$tmp"
            print_success "Arch Linux configuration applied"
            ;;
        "Skip"|*)
            print_warning "Skipping lsb-release configuration"
            ;;
    esac
}

# Set up logging to a timestamped file and tee all output
setup_logging() {
    local log_dir="$HOME/eggs-logs"
    mkdir -p "$log_dir"
    local ts
    ts=$(date '+%Y-%m-%d_%H-%M-%S')
    LOG_FILE="$log_dir/eggs-iso-$ts.log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    print_info "Logging to $LOG_FILE"
}

# Preflight checks: disk space and memory
preflight_checks() {
    local build_path="/home/eggs"
    local check_path="/home"
    [[ -d "$build_path" ]] && check_path="$build_path"

    local avail_kb free_gb warn_gb min_gb
    avail_kb=$(df -Pk "$check_path" | awk 'NR==2{print $4}')
    free_gb=$((avail_kb / 1024 / 1024))
    warn_gb=20
    min_gb=15

    print_info "Free disk space on $check_path: ${free_gb} GB (recommended >= ${warn_gb} GB)"
    if (( free_gb < min_gb )); then
        print_error "Very low disk space (<${min_gb} GB). Building the ISO may fail."
        if ! ask_yes_no "Proceed anyway?" n; then
            print_error "Aborting due to insufficient disk space."
            exit 1
        fi
    elif (( free_gb < warn_gb )); then
        print_warning "Low disk space (<${warn_gb} GB). Build may be slow or fail."
        if ! ask_yes_no "Proceed anyway?" n; then
            print_error "Aborting by user choice due to low disk space."
            exit 1
        fi
    fi

    local mem_kb mem_gb mem_warn_gb
    mem_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    [[ -z "$mem_kb" ]] && mem_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_gb=$((mem_kb / 1024 / 1024))
    mem_warn_gb=4

    print_info "Available memory: ${mem_gb} GB (recommended >= ${mem_warn_gb} GB)"
    if (( mem_gb < mem_warn_gb )); then
        print_warning "Low available memory (<${mem_warn_gb} GB). Build may be slow or fail."
        if ! ask_yes_no "Proceed anyway?" n; then
            print_error "Aborting by user choice due to low memory."
            exit 1
        fi
    fi
}

# Optional size optimizations to reduce ISO size
optimize_size() {
    print_info "Optional size optimizations can reduce the resulting ISO size."
    print_info "This will: clean package caches, remove orphaned packages, and prune journal to ~100MB."
    if ask_yes_no "Run size optimizations now?" n; then
        if command -v paccache &>/dev/null; then
            print_info "Cleaning package cache with paccache..."
            sudo paccache -rk1 -ruk0 || print_warning "paccache cleanup reported issues."
        else
            print_warning "paccache not found. Attempting to install pacman-contrib..."
            if run_with_spinner "Installing pacman-contrib" sudo pacman -S --needed --noconfirm pacman-contrib; then
                print_info "Cleaning package cache with paccache..."
                sudo paccache -rk1 -ruk0 || print_warning "paccache cleanup reported issues."
            else
                print_warning "Failed to install pacman-contrib. Falling back to pacman -Sc."
                sudo pacman -Sc --noconfirm || print_warning "pacman -Sc cleanup reported issues."
            fi
        fi

        print_info "Checking for orphaned packages..."
        mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
        if (( ${#orphans[@]} > 0 )); then
            print_info "Found ${#orphans[@]} orphaned packages. Removing..."
            sudo pacman -Rns --noconfirm "${orphans[@]}" || print_warning "Failed to remove some orphans."
        else
            print_info "No orphaned packages found."
        fi

        if command -v journalctl &>/dev/null; then
            print_info "Pruning systemd journal to 100MB..."
            sudo journalctl --vacuum-size=100M || print_warning "Journal pruning reported issues."
        fi

        print_success "Size optimizations completed."
    else
        print_info "Skipping size optimizations."
    fi
}

# Function to initialize eggs configuration
initialize_eggs_config() {
    print_info "Initializing eggs configuration..."

    local cfg_dir="$HOME/.config/eggs"
    if [[ -d "$cfg_dir" ]]; then
        print_warning "Existing eggs configuration detected at: $cfg_dir"
        print_info "Running 'eggs dad -d' may overwrite defaults and your customizations."
        if ask_yes_no "Back up and reinitialize now? (yes = backup+reinit, no = skip)" n; then
            local ts backup_dir
            ts=$(date +%Y%m%d%H%M%S)
            backup_dir="$HOME/.config/eggs.bak.$ts"
            if cp -a "$cfg_dir" "$backup_dir"; then
                print_success "Backed up current config to: $backup_dir"
            else
                print_error "Failed to back up existing config. Aborting to keep your settings safe."
                exit 1
            fi
        else
            print_warning "Skipping eggs reinitialization as requested."
            return 0
        fi
    fi
    
    if run_with_spinner "Initializing eggs defaults" sudo eggs dad -d; then
        print_success "Eggs configuration initialized successfully"
    else
        print_error "Failed to initialize eggs configuration"
        exit 1
    fi
}

# Function to get user preferences for ISO creation
get_user_preferences() {
    local flags=""
    local install_method=""
    
    echo
    if ask_yes_no "Do you want to add maximum compression (--max)? This will create a smaller ISO but take longer to build." n; then
        flags="$flags --max"
        print_info "Maximum compression enabled"
    else
        print_info "Standard compression will be used"
    fi
    
    echo
    if ask_yes_no "Do you want to install Calamares GUI installer?" n; then
        if run_with_spinner "Installing Calamares" sudo eggs calamares --install; then
            print_success "Calamares installed successfully"
            install_method="GUI (Calamares) and CLI (krill)"
        else
            print_warning "Failed to install Calamares. Only CLI installer will be available."
            install_method="CLI (krill) only"
        fi
    else
        print_info "Only CLI installer (krill) will be available"
        install_method="CLI (krill) only"
    fi
    
    echo
    if ask_yes_no "Do you want to include personal data in the ISO?" n; then
        flags="$flags --clone"
        if ask_yes_no "Do you want to encrypt your personal data?" n; then
            flags="${flags/--clone/--cryptedclone}"
            print_info "Personal data will be included and encrypted"
        else
            print_info "Personal data will be included without encryption"
        fi
    else
        print_info "Personal data will not be included (standard mode)"
    fi
    
    flags="$flags --standard"
    
    echo
    if use_gum; then
        gum style --foreground "#3B82F6" "=== ISO Creation Configuration ==="
        printf -- "- Flags: %s\n- Installation method: %s\n" "$flags" "$install_method" | gum format
        gum style --foreground "#3B82F6" "=================================="
    else
        print_info "=== ISO Creation Configuration ==="
        echo "Flags: $flags"
        echo "Installation method: $install_method"
        echo "=================================="
    fi
    
    if ask_yes_no "Do you want to create the ISO with these settings?" n; then
        # If using --cryptedclone, eggs needs interactive password input; avoid running under spinner
        local needs_input=false
        [[ "$flags" == *"--cryptedclone"* ]] && needs_input=true

        if [[ "$needs_input" == true ]]; then
            print_info "Encrypted clone selected. You will be prompted to enter and confirm an encryption password by eggs."
            if bash -lc "sudo eggs produce $flags"; then
                print_success "ISO created successfully!"
            else
                print_error "Failed to create ISO"
                exit 1
            fi
        elif run_with_spinner "Creating ISO" bash -lc "sudo eggs produce $flags"; then
             print_success "ISO created successfully!"
             local iso_path
             iso_path=$(find /home/eggs -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)
             if [[ -n "$iso_path" ]]; then
                 print_info "ISO path: $iso_path"
             else
                 print_warning "Could not locate ISO in /home/eggs."
             fi
             print_info "You can now boot from this ISO and install using:"
             print_info "- CLI: sudo eggs install"
             if [[ "$install_method" == *"GUI"* ]]; then
                 print_info "- GUI: Launch Calamares from the desktop/menu"
             fi
         else
             print_error "Failed to create ISO"
             exit 1
         fi
     else
         print_info "ISO creation cancelled"
         exit 0
     fi
 }

# Set up logging to a timestamped file and tee all output
setup_logging

# Main script execution
main() {
    print_info "=== Penguins-eggs ISO Creation Script ==="
    print_info "This script will help you create a bootable ISO of your current system"
    echo
     
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root (except for sudo commands)"
        exit 1
    fi

    validate_platform
    start_sudo_keepalive

    # Offer to install gum for a better TUI before further prompts
    ensure_gum_available

    preflight_checks
    optimize_size
     
    if ! check_penguins_eggs; then
         install_penguins_eggs
    fi
     
    if ensure_lsb_release_available; then
         if ! check_lsb_release; then
             configure_lsb_release
         fi
    else
         print_warning "lsb-release not available. Skipping lsb-release configuration."
    fi
     
    initialize_eggs_config
    get_user_preferences
     
    print_success "Script completed successfully!"
    if [[ -n "${LOG_FILE:-}" ]]; then
         print_info "Log saved to: $LOG_FILE"
    fi
 }
 
 # Run the main function
 main "$@"