#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  echo "Running in DRY RUN mode: No changes will be made."
fi

# Use an argv array so we can conditionally prepend sudo without empty-command issues.
SUDO=()
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ -z "${EUID-}" ]] || [[ "$EUID" -ne 0 ]]; then
    SUDO=(sudo)
  fi
fi

PACMAN_CONF="/etc/pacman.conf"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

# Safe runner: no eval; preserves argv and quoting.
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

backup_conf() {
  run "${SUDO[@]}" cp -a "$PACMAN_CONF" "${PACMAN_CONF}.bak.${BACKUP_SUFFIX}"
}

repo_exists() {
  local name="$1"
  grep -qE "^\[${name}\]" "$PACMAN_CONF"
}

append_repo_block() {
  local name="$1"
  local siglevel="$2"
  local mode="$3"      # "Include" or "Server"
  local value="$4"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Would append block for [$name] with $mode $value"
  else
    if [[ ${#SUDO[@]} -gt 0 ]]; then
      {
        echo
        echo "[$name]"
        [[ -n "$siglevel" ]] && echo "SigLevel = $siglevel"
        if [[ "$mode" == "Include" ]]; then
          echo "Include = $value"
        else
          echo "Server = $value"
        fi
      } | "${SUDO[@]}" tee -a "$PACMAN_CONF" >/dev/null
    else
      {
        echo
        echo "[$name]"
        [[ -n "$siglevel" ]] && echo "SigLevel = $siglevel"
        if [[ "$mode" == "Include" ]]; then
          echo "Include = $value"
        else
          echo "Server = $value"
        fi
      } | tee -a "$PACMAN_CONF" >/dev/null
    fi
  fi
}

import_repo_key() {
  local keyid="$1"
  local keyserver="$2"
  [[ -z "$keyid" ]] && return 0
  run "${SUDO[@]}" pacman-key --recv-key "$keyid" --keyserver "$keyserver"
  run "${SUDO[@]}" pacman-key --lsign-key "$keyid"
}

install_from_urls() {
  # FIX: must be an array assignment, not a brace block
  local urls=("$@")
  [[ ${#urls[@]} -eq 0 ]] && return 0
  run "${SUDO[@]}" pacman -U --noconfirm "${urls[@]}"
}

full_sync_upgrade() {
  run "${SUDO[@]}" pacman -Syu --noconfirm
}

# Validation functions
validate_repo_name() {
  local name="$1"
  # Repository name should not contain brackets, spaces, or special characters that break pacman.conf
  if [[ "$name" =~ [\[\]\(\)\{\}\s] ]]; then
    echo "Repository name cannot contain brackets, parentheses, braces, or spaces."
    return 1
  fi
  # Should not start with a dash or contain consecutive dashes
  if [[ "$name" =~ ^- ]] || [[ "$name" =~ -- ]]; then
    echo "Repository name cannot start with a dash or contain consecutive dashes."
    return 1
  fi
  return 0
}

validate_siglevel() {
  local siglevel="$1"
  # SigLevel should contain valid keywords: Required, Optional, Never, TrustAll, TrustOnly, DatabaseRequired, DatabaseOptional, PackageRequired, PackageOptional
  # Allow combinations separated by spaces
  if [[ -z "$siglevel" ]]; then
    return 0  # Empty is valid (will use default)
  fi
  # Valid SigLevel keywords
  local valid_keywords="Required Optional Never TrustAll TrustOnly DatabaseRequired DatabaseOptional PackageRequired PackageOptional PackageNever DatabaseNever"
  # Split by spaces and check each word
  local words
  read -ra words <<< "$siglevel"
  for word in "${words[@]}"; do
    case " $valid_keywords " in
      *" $word "*)
        ;;
      *)
        echo "Invalid SigLevel. Valid values: Required, Optional, Never, TrustAll, TrustOnly, DatabaseRequired, DatabaseOptional, PackageRequired, PackageOptional, PackageNever, DatabaseNever (or combinations)."
        return 1
        ;;
    esac
  done
  return 0
}

validate_include_path() {
  local path="$1"
  # Include path should be an absolute path starting with /
  if [[ ! "$path" =~ ^/ ]]; then
    echo "Include path must be an absolute path starting with '/'."
    return 1
  fi
  # Should not contain invalid characters
  if echo "$path" | grep -qE '[<>"'"'"'|&;]'; then
    echo "Include path contains invalid characters."
    return 1
  fi
  return 0
}

validate_server_url() {
  local url="$1"
  # Server URL should start with http:// or https://
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "Server URL must start with 'http://' or 'https://'."
    return 1
  fi
  # Basic URL validation - should have something after the protocol
  # This allows domains, IPs, and variables like $repo/$arch
  local url_without_protocol="${url#http://}"
  url_without_protocol="${url_without_protocol#https://}"
  if [[ -z "$url_without_protocol" ]]; then
    echo "Server URL format is invalid. Expected format: https://example.com/\$repo/\$arch"
    return 1
  fi
  return 0
}

validate_gpg_keyid() {
  local keyid="$1"
  # GPG KEYID should be hexadecimal (0-9, A-F) and typically 8, 16, or 40 characters
  if [[ -z "$keyid" ]]; then
    return 0  # Empty is valid (skip)
  fi
  # Remove any spaces and convert to uppercase for validation
  keyid="${keyid// /}"
  keyid="${keyid^^}"
  if [[ ! "$keyid" =~ ^[0-9A-F]{8,40}$ ]]; then
    echo "Invalid GPG KEYID. It should be a hexadecimal string (8-40 characters)."
    return 1
  fi
  return 0
}

validate_keyserver() {
  local keyserver="$1"
  # Keyserver should be a valid hostname (may include port)
  if [[ -z "$keyserver" ]]; then
    return 0  # Empty is valid (will use default)
  fi
  # Extract hostname and port if present
  local hostname="${keyserver%:*}"
  local port=""
  if [[ "$keyserver" == *:* ]]; then
    port="${keyserver#*:}"
  fi
  
  # Check if it's an IP address (basic validation)
  if [[ "$hostname" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # Valid IP address format
    if [[ -n "$port" ]] && [[ ! "$port" =~ ^[0-9]+$ ]]; then
      echo "Invalid keyserver format. Port must be a number. Expected format: keyserver.ubuntu.com or keyserver.ubuntu.com:11371"
      return 1
    fi
    return 0
  fi
  
  # For domain names, must contain at least one dot
  if [[ ! "$hostname" =~ \. ]]; then
    echo "Invalid keyserver format. Must be a valid domain name (contain at least one dot) or IP address. Expected format: keyserver.ubuntu.com or keyserver.ubuntu.com:11371"
    return 1
  fi
  
  # Basic hostname validation: alphanumeric, dots, dashes
  if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Invalid keyserver format. Hostname contains invalid characters. Expected format: keyserver.ubuntu.com or keyserver.ubuntu.com:11371"
    return 1
  fi
  
  # Validate port if present
  if [[ -n "$port" ]] && [[ ! "$port" =~ ^[0-9]+$ ]]; then
    echo "Invalid keyserver format. Port must be a number. Expected format: keyserver.ubuntu.com or keyserver.ubuntu.com:11371"
    return 1
  fi
  
  return 0
}

validate_package_url() {
  local url="$1"
  # Trim whitespace
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  
  # Package URL should be a valid URL
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "Package URL must start with 'http://' or 'https://'."
    return 1
  fi
  # Should end with .pkg.tar.(zst|xz|gz) or similar
  # Check for .pkg.tar.zst, .pkg.tar.xz, .pkg.tar.gz
  if [[ "$url" =~ \.pkg\.tar\.(zst|xz|gz)$ ]]; then
    return 0
  fi
  # Check for .tar.zst, .tar.xz, .tar.gz
  if [[ "$url" =~ \.tar\.(zst|xz|gz)$ ]]; then
    return 0
  fi
  echo "Package URL should point to a package file (.pkg.tar.zst, .pkg.tar.xz, .pkg.tar.gz, .tar.zst, .tar.xz, or .tar.gz)."
  return 1
}

prompt_generic_repo() {
  echo "=== Add a generic repository ==="
  echo ""
  echo "INFO: Repository name is typically found in the repository's documentation."
  echo "      It's usually a short identifier like 'myrepo', 'custom', or the repo's official name."
  echo "      Check the repository's website or README for the exact name."
  echo ""
  while true; do
    read -rp "Repository name: " REPO_NAME
    if [[ -z "${REPO_NAME}" ]]; then
      echo "Repository name cannot be empty. Please try again."
      continue
    fi
    if validate_repo_name "$REPO_NAME"; then
      break
    fi
  done

  if repo_exists "$REPO_NAME"; then
    echo "Repository [$REPO_NAME] already exists in pacman.conf."
    while true; do
      read -rp "Append another block anyway? (y/N): " OVER
      case "${OVER,,}" in
        y|yes)
          break
          ;;
        n|no|"")
          echo "Cancelled. Returning to main menu."
          return 0
          ;;
        *)
          echo "Please enter 'y' for yes or 'n' for no."
          ;;
      esac
    done
  fi

  echo ""
  echo "INFO: SigLevel controls package signature verification."
  echo "      Common values: 'Required' (default), 'Optional', 'Never', or combinations like 'Required DatabaseOptional'."
  echo "      Check the repository's documentation for their recommended SigLevel setting."
  echo "      If unsure, use the default 'Required' for security."
  echo ""
  while true; do
    read -rp "SigLevel override (default: 'Required'): " SIGLEVEL
    SIGLEVEL=${SIGLEVEL:-Required}
    if validate_siglevel "$SIGLEVEL"; then
      break
    fi
  done

  echo ""
  echo "Add repository by:"
  echo "INFO: Choose 'Include file' if the repository provides a mirrorlist file (usually installed via package)."
  echo "      Choose 'Server URL' if you want to directly specify the repository server URL."
  echo "      Check the repository's documentation to see which method they recommend."
  echo ""
  local MODE_KEY=""
  select MODE in "Include file" "Server URL"; do
    case "$MODE" in
      "Include file")
        echo ""
        echo "INFO: The mirrorlist file path is usually provided by the repository's keyring/mirrorlist package."
        echo "      Common locations: /etc/pacman.d/<repo-name>-mirrorlist"
        echo "      Check the repository's installation instructions for the exact path."
        echo ""
        while true; do
          read -rp "Path to mirrorlist file: " VALUE
          if [[ -z "$VALUE" ]]; then
            echo "Include path cannot be empty. Please try again."
            continue
          fi
          if validate_include_path "$VALUE"; then
            MODE_KEY="Include"
            break
          fi
        done
        break
        ;;
      "Server URL")
        echo ""
        echo "INFO: Server URL format typically includes variables like \$repo and \$arch."
        echo "      Example: https://example.com/\$repo/\$arch"
        echo "      The repository's documentation should provide the exact URL format."
        echo "      Common patterns: https://server.com/\$repo/\$arch or https://server.com/\$arch"
        echo ""
        while true; do
          read -rp "Server URL: " VALUE
          if [[ -z "$VALUE" ]]; then
            echo "Server URL cannot be empty. Please try again."
            continue
          fi
          if validate_server_url "$VALUE"; then
            MODE_KEY="Server"
            break
          fi
        done
        break
        ;;
      *)
        echo "Choose 1 or 2."
        ;;
    esac
  done

  echo ""
  echo "INFO: GPG KEYID is required if the repository signs its packages."
  echo "      Find the KEYID in the repository's documentation, usually listed as a hexadecimal string."
  echo "      Example: 3056513887B78AEB"
  echo "      If the repository doesn't sign packages, you can skip this step."
  echo ""
  while true; do
    read -rp "Import GPG key? Enter KEYID or leave empty to skip: " KEYID
    if [[ -z "$KEYID" ]]; then
      break  # Empty is valid (skip)
    fi
    # Normalize KEYID: remove spaces and convert to uppercase
    KEYID="${KEYID// /}"
    KEYID="${KEYID^^}"
    if validate_gpg_keyid "$KEYID"; then
      break
    fi
  done
  if [[ -n "$KEYID" ]]; then
    echo ""
    echo "INFO: Keyserver is the GPG keyserver used to fetch the public key."
    echo "      Common keyservers: keyserver.ubuntu.com, pgp.mit.edu, keyserver.archlinux.org"
    echo "      The repository documentation usually specifies which keyserver to use."
    echo ""
    while true; do
      read -rp "Keyserver (default: keyserver.ubuntu.com): " KEYSERVER
      KEYSERVER=${KEYSERVER:-keyserver.ubuntu.com}
      if validate_keyserver "$KEYSERVER"; then
        break
      fi
    done
  fi

  echo ""
  echo "INFO: Some repositories provide pre-built keyring and mirrorlist packages."
  echo "      These packages contain the GPG keys and mirror configurations."
  echo "      Check the repository's installation instructions for download URLs."
  echo "      Common package types: .pkg.tar.zst (zstd compressed) or .pkg.tar.xz (xz compressed)"
  echo "      Example URLs: https://example.com/keyring.pkg.tar.zst https://example.com/mirrorlist.pkg.tar.zst"
  echo "      If the repository doesn't provide these packages, leave empty to skip."
  echo ""
  while true; do
    read -rp "Enter package URLs (space-separated) or leave empty to skip: " -a URLS
    if [[ ${#URLS[@]} -eq 0 ]]; then
      break  # Empty is valid (skip)
    fi
    local url_valid=true
    for url in "${URLS[@]}"; do
      if ! validate_package_url "$url"; then
        url_valid=false
        break
      fi
    done
    if [[ "$url_valid" == "true" ]]; then
      break
    fi
  done

  backup_conf
  [[ -n "$KEYID" ]] && import_repo_key "$KEYID" "${KEYSERVER:-keyserver.ubuntu.com}"
  [[ ${#URLS[@]} -gt 0 ]] && install_from_urls "${URLS[@]}"
  append_repo_block "$REPO_NAME" "$SIGLEVEL" "$MODE_KEY" "$VALUE"
  full_sync_upgrade

  echo "Repository [$REPO_NAME] script completed."
}

chaotic_aur_preset() {
  echo "=== Add Chaotic-AUR (preset) ==="
  while true; do
    read -rp "Proceed? (y/N): " OK
    case "${OK,,}" in
      y|yes)
        break
        ;;
      n|no|"")
        echo "Cancelled. Returning to main menu."
        return 0
        ;;
      *)
        echo "Please enter 'y' for yes or 'n' for no."
        ;;
    esac
  done

  local KEYID="3056513887B78AEB"
  local KEYSERVER="keyserver.ubuntu.com"
  local KEYRING_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
  local MIRRORLIST_URL="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"
  local REPO_NAME="chaotic-aur"
  local INCLUDE_PATH="/etc/pacman.d/chaotic-mirrorlist"

  backup_conf
  import_repo_key "$KEYID" "$KEYSERVER"
  install_from_urls "$KEYRING_URL" "$MIRRORLIST_URL"

  if ! repo_exists "$REPO_NAME"; then
    append_repo_block "$REPO_NAME" "" "Include" "$INCLUDE_PATH"
  else
    echo "[$REPO_NAME] already present in pacman.conf; not duplicating."
  fi

  full_sync_upgrade
  echo "Chaotic-AUR steps completed."
}

main_menu() {
  echo "==============================="
  echo "  Arch Repo Helper"
  echo "==============================="
  echo "1) Add generic repository (guided)"
  echo "2) Add Chaotic-AUR (preset)"
  echo "3) Quit"
  while true; do
    read -rp "Select an option [1-3]: " CH
    case "$CH" in
      1) prompt_generic_repo; break ;;
      2) chaotic_aur_preset; break ;;
      3) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
  done
}

main_menu
