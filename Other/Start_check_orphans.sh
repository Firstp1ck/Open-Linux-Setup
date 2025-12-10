#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# Script: Start_check_orphans.sh
# ============================================================================
# Description:
#   Orphaned package analyzer that identifies dependencies no longer needed
#   and groups them by which explicitly installed packages still use them.
#   Provides option to safely remove unused orphaned packages.
#
# What it does:
#   - Identifies orphaned packages (dependencies no longer required)
#   - Groups orphaned packages by explicitly installed packages that use them
#   - Separates unused orphaned packages (not used by any explicit package)
#   - Displays pacman logs for orphaned packages
#   - Provides option to remove unused orphaned packages
#   - Uses pactree to analyze reverse dependencies
#
# How to use:
#   Run with appropriate privileges:
#     ./Start_check_orphans.sh
#     sudo ./Start_check_orphans.sh  (for removal)
#   
#   Options:
#     --help, -h      Show help message
#     --dry-run       Preview removal without executing
#     --yes, -y       Assume yes to removal prompts
#
#   Requirements: pacman, pactree (pacman-contrib)
#
# Target:
#   - Arch Linux users cleaning up unused dependencies
#   - System administrators maintaining clean package installations
#   - Users wanting to free up disk space
# ============================================================================

# Gum detection
HAS_GUM=false
if command -v gum >/dev/null 2>&1; then
    HAS_GUM=true
fi

# Standard message functions
msg_info() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 63 "[INFO] $1"
    else
        echo "[INFO] $1"
    fi
}

msg_success() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 42 "[SUCCESS] $1"
    else
        echo "[SUCCESS] $1"
    fi
}

msg_error() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 196 "[ERROR] $1" >&2
    else
        echo "[ERROR] $1" >&2
    fi
}

msg_warning() {
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 214 "[WARNING] $1"
    else
        echo "[WARNING] $1"
    fi
}

# Dependency checking
require_command() {
    local cmd="$1"
    local install_hint="${2:-Install it via your package manager}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        msg_error "'$cmd' is required but not installed."
        echo "Hint: $install_hint" >&2
        exit 1
    fi
}

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Check for orphaned packages (dependencies no longer needed) and group them
    by explicitly installed packages that use them. Optionally remove unused
    orphaned packages.

Options:
    --help, -h          Show this help message
    --dry-run           Show what would be done without making changes
    --yes, -y           Assume yes to all prompts

Examples:
    $(basename "$0")
    $(basename "$0") --dry-run
    $(basename "$0") --yes

EOF
}

# Parse arguments
DRY_RUN=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            msg_info "Running in DRY RUN mode: No changes will be made."
            ;;
        --yes|-y)
            ASSUME_YES=1
            ;;
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    shift
done

# Check dependencies
require_command "pacman" "This script requires Arch Linux with pacman"
require_command "pactree" "Install with: pacman -S pacman-contrib"

PACMAN_LOG="/var/log/pacman.log"

# Check if pacman.log exists
if [ ! -f "$PACMAN_LOG" ]; then
    msg_warning "Pacman log not found at $PACMAN_LOG"
    msg_info "Some features may be limited"
fi

# Get list of explicitly installed packages
msg_info "Getting list of explicitly installed packages..."
mapfile -t explicit_installed < <(pacman -Qe --quiet)

# Get list of orphaned packages
msg_info "Getting list of orphaned packages..."
mapfile -t orphans < <(pacman -Qdtq || true)

if [ ${#orphans[@]} -eq 0 ]; then
    msg_success "No orphaned packages found."
    exit 0
fi

declare -A used_orphans_map
unused_orphans=()

print_logs_for_package() {
    local pkg=$1
    if [ -f "$PACMAN_LOG" ]; then
        echo "---- Logs for package: $pkg ----"
        grep -E "\[(ALPM|PACMAN)\] (installed|upgraded|removed|downgraded) $pkg" "$PACMAN_LOG" 2>/dev/null | tail -n 5 || true
        echo
    fi
}

msg_info "Analyzing orphaned packages..."
for orphan in "${orphans[@]}"; do
    mapfile -t revdeps < <(pactree -r "$orphan" 2>/dev/null || true)
    explicitly_using=()
    for dep in "${revdeps[@]}"; do
        if [[ " ${explicit_installed[*]} " == *" $dep "* ]]; then
            explicitly_using+=("$dep")
        fi
    done
    if (( ${#explicitly_using[@]} > 0 )); then
        for user_pkg in "${explicitly_using[@]}"; do
            used_orphans_map["$user_pkg"]+="$orphan "
        done
    else
        unused_orphans+=("$orphan")
    fi
done

echo
if [ "$HAS_GUM" = true ]; then
    gum style --border normal --margin "1 2" --padding "1 2" --foreground 63 "Orphaned Dependencies Analysis"
else
    echo "=== Orphaned Dependencies Analysis ==="
fi
echo

if [ ${#used_orphans_map[@]} -gt 0 ]; then
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 214 "Orphaned dependencies grouped by explicitly installed packages using them:"
    else
        echo "Orphaned dependencies grouped by explicitly installed packages using them:"
    fi
    for pkg in "${explicit_installed[@]}"; do
        if [[ -n "${used_orphans_map[$pkg]}" ]]; then
            echo "$pkg:"
            for orphan_pkg in ${used_orphans_map[$pkg]}; do
                echo "  - $orphan_pkg"
            done
        fi
    done
    echo
fi

if [ ${#unused_orphans[@]} -gt 0 ]; then
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 196 "Orphaned dependencies not used by any explicitly installed package:"
    else
        echo "Orphaned dependencies not used by any explicitly installed package:"
    fi
    for orphan_pkg in "${unused_orphans[@]}"; do
        echo "  - $orphan_pkg"
    done
else
    msg_success "No unused orphaned packages found."
fi

if [ -f "$PACMAN_LOG" ]; then
    echo
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 63 "== Pacman logs for orphans still used =="
    else
        echo "== Pacman logs for orphans still used =="
    fi
    for pkg in "${explicit_installed[@]}"; do
        if [[ -n "${used_orphans_map[$pkg]}" ]]; then
            for orphan_pkg in ${used_orphans_map[$pkg]}; do
                print_logs_for_package "$orphan_pkg"
            done
        fi
    done

    if [ ${#unused_orphans[@]} -gt 0 ]; then
        if [ "$HAS_GUM" = true ]; then
            gum style --foreground 63 "== Pacman logs for orphans not used =="
        else
            echo "== Pacman logs for orphans not used =="
        fi
        for orphan_pkg in "${unused_orphans[@]}"; do
            print_logs_for_package "$orphan_pkg"
        done
    fi
fi

echo
if (( ${#unused_orphans[@]} > 0 )); then
    msg_info "You can remove the ${#unused_orphans[@]} unused orphaned packages listed above."
    echo "Packages: ${unused_orphans[*]}"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        msg_info "[DRY-RUN] Would remove packages: ${unused_orphans[*]}"
        msg_info "[DRY-RUN] Command: pacman -Rns -- ${unused_orphans[*]}"
    else
        if [ "$ASSUME_YES" -eq 1 ]; then
            remove_choice="y"
        else
            read -r -p "Remove them now with 'pacman -Rns'? (y/N): " remove_choice
        fi
        
        if [[ "$remove_choice" =~ ^[Yy]$ ]]; then
            msg_info "Removing unused orphaned packages..."
            if [[ $EUID -eq 0 ]]; then
                pacman -Rns -- "${unused_orphans[@]}"
                msg_success "Successfully removed orphaned packages."
            else
                if command -v sudo >/dev/null 2>&1; then
                    sudo pacman -Rns -- "${unused_orphans[@]}"
                    msg_success "Successfully removed orphaned packages."
                else
                    msg_error "This operation requires root privileges. Install sudo or run as root."
                    exit 1
                fi
            fi
        else
            msg_info "Skipping removal of unused orphaned packages."
        fi
    fi
else
    msg_success "No unused orphaned packages to remove."
fi

exit 0
