#!/usr/bin/env bash

set -euo pipefail

# Script: Start_check_sha.sh
# Description: Interactive checksum validator with SHA-1, SHA-256, or SHA-512 support

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

# shellcheck disable=SC2329
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
    Interactive checksum validator. Select SHA algorithm (1/2/3), enter reference
    hash and file path, then verify the file integrity.

Options:
    --help, -h          Show this help message

Examples:
    $(basename "$0")

EOF
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    # shellcheck disable=SC2317
    shift
done

# ────────────────────────── Helper functions ────────────────────────────────
strip_quotes() {
    local s="$1"
    s="${s#\"}"
    printf '%s' "${s%\"}"
}

win2unix_path() {
    local p="$1"
    if [[ $p =~ ^([A-Za-z]):\\ ]]; then
        local drv=${BASH_REMATCH[1],,}
        p="${p//\\//}"
        if [[ -n ${WSL_DISTRO_NAME-} ]]; then
            p="/mnt/$drv/${p:3}"
        else
            p="/$drv/${p:3}"
        fi
    fi
    printf '%s' "$p"
}

resolve_file() {
    local cand
    cand=$(strip_quotes "$1")
    [[ -f $cand ]] && { printf '%s' "$cand"; return; }

    local alt
    alt=$(win2unix_path "$cand")
    [[ -f $alt ]] && { printf '%s' "$alt"; return; }

    msg_error "File not found or unreadable: $1"
    exit 3
}

normalize_hash() {
    local algo="$1"
    local raw="$2"
    raw=${raw#"${algo}":}
    raw=${raw//[[:space:]]/}
    raw=${raw,,}

    case $algo in
        sha1)   (( ${#raw} == 40  )) ;;
        sha256) (( ${#raw} == 64  )) ;;
        sha512) (( ${#raw} == 128 )) ;;
    esac || {
        msg_error "Wrong length for $algo hash (expected: sha1=40, sha256=64, sha512=128)"
        exit 4
    }

    [[ $raw =~ ^[0-9a-f]+$ ]] || {
        msg_error "Hash is not hexadecimal"
        exit 4
    }
    printf '%s' "$raw"
}

# ────────────────────────── Select algorithm ────────────────────────────────
if [ "$HAS_GUM" = true ]; then
    echo
    alg=$(gum choose "SHA-1" "SHA-256" "SHA-512" --header "Choose checksum algorithm" || true)
    case "$alg" in
        "SHA-1")   alg=sha1 ;;
        "SHA-256") alg=sha256 ;;
        "SHA-512") alg=sha512 ;;
        *)
            msg_error "No algorithm selected"
            exit 1
            ;;
    esac
else
    printf '\nChoose checksum algorithm:\n'
    printf '  1) SHA-1\n'
    printf '  2) SHA-256\n'
    printf '  3) SHA-512\n'
    while true; do
        read -rp 'Enter choice [1-3]: ' choice
        case "$choice" in
            1) alg=sha1   ; break ;;
            2) alg=sha256 ; break ;;
            3) alg=sha512 ; break ;;
            *) msg_warning "Please type 1, 2 or 3." ;;
        esac
    done
fi

# ────────────────────────── Collect user input ────────────────────────────────
if [ "$HAS_GUM" = true ]; then
    ref_raw=$(gum input --prompt "Official $alg checksum: " || true)
    in_path=$(gum input --prompt "Path to file to verify: " || true)
else
    read -rp "Official $alg checksum           : " ref_raw
    read -rp "Path to file to verify           : " in_path
fi

if [ -z "$ref_raw" ] || [ -z "$in_path" ]; then
    msg_error "Both checksum and file path are required"
    exit 1
fi

file_path=$(resolve_file "$in_path")
ref_hash=$(normalize_hash "$alg" "$ref_raw")
sum_cmd="${alg}sum"

# Check if checksum command exists
require_command "$sum_cmd" "Install coreutils package"

# ────────────────────────── Verify & report ─────────────────────────────────
msg_info "Verifying file integrity..."
if printf '%s  %s\n' "$ref_hash" "$file_path" | "$sum_cmd" --check --status; then
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 42 --bold "✅ MATCH – file is intact."
    else
        printf '✅ MATCH – file is intact.\n'
    fi
    exit 0
else
    if [ "$HAS_GUM" = true ]; then
        gum style --foreground 196 --bold "❌ MISMATCH – do NOT use this file."
    else
        printf '❌ MISMATCH – do NOT use this file.\n'
    fi
    exit 1
fi
