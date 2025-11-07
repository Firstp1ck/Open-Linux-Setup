
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

prompt_generic_repo() {
  echo "=== Add a generic repository ==="
  read -rp "Repository name (e.g., myrepo): " REPO_NAME
  if [[ -z "${REPO_NAME}" ]]; then
    echo "Repository name cannot be empty."
    exit 1
  fi

  if repo_exists "$REPO_NAME"; then
    echo "Repository [$REPO_NAME] already exists in pacman.conf."
    read -rp "Append another block anyway? (y/N): " OVER
    [[ "${OVER,,}" == "y" ]] || exit 1
  fi

  read -rp "SigLevel override (leave empty to skip, example: 'Required DatabaseOptional'): " SIGLEVEL

  echo "Add repository by:"
  local MODE_KEY=""
  select MODE in "Include file, e.g. /etc/pacman.d/myrepo-mirrorlist" "Server URL, e.g. https://example.com/\$repo/\$arch"; do
    case "$MODE" in
      "Include file, e.g. /etc/pacman.d/myrepo-mirrorlist")
        read -rp "Path to mirrorlist file (example: /etc/pacman.d/myrepo-mirrorlist): " VALUE
        [[ -z "$VALUE" ]] && { echo "Include path cannot be empty."; exit 1; }
        MODE_KEY="Include"
        break
        ;;
      "Server URL, e.g. https://example.com/\$repo/\$arch")
        read -rp "Server URL (example: https://example.com/\$repo/\$arch): " VALUE
        [[ -z "$VALUE" ]] && { echo "Server URL cannot be empty."; exit 1; }
        MODE_KEY="Server"
        break
        ;;
      *)
        echo "Choose 1 or 2."
        ;;
    esac
  done

  read -rp "Import GPG key? Enter KEYID (example: 3056513887B78AEB) or leave empty to skip: " KEYID
  if [[ -n "$KEYID" ]]; then
    read -rp "Keyserver (default: keyserver.ubuntu.com): " KEYSERVER
    KEYSERVER=${KEYSERVER:-keyserver.ubuntu.com}
  fi

  echo "If the repo provides keyring/mirrorlist packages, enter their URLs space-separated (example: https://example.com/keyring.pkg.tar.zst https://example.com/mirrorlist.pkg.tar.zst), or leave empty to skip:"
  read -rp "URLs: " -a URLS

  backup_conf
  [[ -n "$KEYID" ]] && import_repo_key "$KEYID" "${KEYSERVER:-keyserver.ubuntu.com}"
  [[ ${#URLS[@]} -gt 0 ]] && install_from_urls "${URLS[@]}"
  append_repo_block "$REPO_NAME" "$SIGLEVEL" "$MODE_KEY" "$VALUE"
  full_sync_upgrade

  echo "Repository [$REPO_NAME] script completed."
}

chaotic_aur_preset() {
  echo "=== Add Chaotic-AUR (preset) ==="
  read -rp "Proceed? (y/N): " OK
  [[ "${OK,,}" == "y" ]] || exit 0

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
