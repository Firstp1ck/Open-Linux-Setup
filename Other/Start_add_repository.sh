#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Script: Start_add_repository.sh
# ============================================================================
# Description:
#   Interactive Arch Linux repository manager that adds custom repositories
#   to pacman.conf with validation, GPG key management, and package
#   installation. Supports both Include (mirrorlist) and Server URL methods.
#
# What it does:
#   - Adds generic repositories with guided prompts
#   - Validates repository names, SigLevel, URLs, and paths
#   - Imports GPG keys from keyservers
#   - Installs keyring and mirrorlist packages from URLs
#   - Backs up pacman.conf before modifications
#   - Supports Include (mirrorlist file) and Server (direct URL) methods
#   - Includes preset for Chaotic-AUR repository
#   - Performs full system sync after repository addition
#
# How to use:
#   Run with appropriate privileges:
#     sudo ./Start_add_repository.sh
#   
#   Options:
#     --help, -h      Show help message
#     --dry-run       Preview actions without making changes
#
#   Menu options:
#     1) Add generic repository (guided)
#     2) Add Chaotic-AUR (preset)
#     3) Quit
#
# Target:
#   - Arch Linux users adding third-party repositories
#   - Users wanting to add Chaotic-AUR repository
#   - System administrators managing custom package repositories
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

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Add repositories to pacman.conf with validation, key management, and
    optional package installation. Supports both Include and Server repository
    types.

Options:
    --help, -h          Show this help message
    --dry-run           Show what would be done without making changes

Examples:
    $(basename "$0")
    $(basename "$0") --dry-run

EOF
}

# Parse arguments
DRY_RUN=0

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
        *)
            msg_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    shift
done

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
    if [ "$HAS_GUM" = true ]; then
        # Use ANSI color code for orange/yellow (214) - gum style adds newline, so use printf with color
        printf '\033[38;5;214m[dry-run]\033[0m '
    else
        printf '[dry-run] '
    fi
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
  
  # Keyserver connectivity test (shows output in dry-run mode)
  if ! test_keyserver_connectivity "$keyserver" 10; then
    if ! prompt_continue_on_failure "Keyserver connectivity test failed. Key import may fail."; then
      return 1
    fi
  fi
  
  # Check if key already imported
  if check_key_imported "$keyid"; then
    msg_info "Key $keyid is already imported. Skipping import."
    return 0
  fi
  
  # Check if key exists on keyserver (informational, shows output in dry-run mode)
  check_key_exists "$keyid" "$keyserver"
  
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
  # Length validation (1-50 characters)
  if [[ ${#name} -lt 1 ]] || [[ ${#name} -gt 50 ]]; then
    echo "Repository name must be between 1 and 50 characters."
    return 1
  fi
  # Check reserved names
  if ! check_reserved_repo_name "$name"; then
    return 1
  fi
  # Case sensitivity warning
  local name_lower="${name,,}"
  if [[ "$name" != "$name_lower" ]]; then
    msg_warning "Repository name contains uppercase letters. Pacman repository names are case-sensitive."
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
  local has_never=false
  local has_trustall=false
  local has_required=false
  
  for word in "${words[@]}"; do
    case " $valid_keywords " in
      *" $word "*)
        case "$word" in
          Never|PackageNever|DatabaseNever)
            has_never=true
            ;;
          TrustAll)
            has_trustall=true
            ;;
          Required|PackageRequired|DatabaseRequired)
            has_required=true
            ;;
        esac
        ;;
      *)
        echo "Invalid SigLevel. Valid values: Required, Optional, Never, TrustAll, TrustOnly, DatabaseRequired, DatabaseOptional, PackageRequired, PackageOptional, PackageNever, DatabaseNever (or combinations)."
        return 1
        ;;
    esac
  done
  
  # Security warnings
  if [[ "$has_never" == "true" ]]; then
    msg_warning "SigLevel contains 'Never' - this disables signature verification and is a security risk!"
    if ! prompt_continue_on_failure "Using 'Never' disables package signature verification."; then
      return 1
    fi
  fi
  
  if [[ "$has_trustall" == "true" ]]; then
    msg_warning "SigLevel contains 'TrustAll' - this trusts all keys without verification and is a security risk!"
    if ! prompt_continue_on_failure "Using 'TrustAll' bypasses key verification."; then
      return 1
    fi
  fi
  
  # Conflicting options detection
  if [[ "$has_never" == "true" ]] && [[ "$has_required" == "true" ]]; then
    msg_warning "Conflicting SigLevel options detected: 'Never' and 'Required' cannot be used together."
    if ! prompt_continue_on_failure "Conflicting SigLevel options may cause unexpected behavior."; then
      return 1
    fi
  fi
  
  # Best practices suggestion
  if [[ "$has_never" == "true" ]] || [[ "$has_trustall" == "true" ]]; then
    msg_info "Security best practice: Use 'Required' for package signature verification."
  fi
  
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
  # Path traversal protection
  if [[ "$path" =~ \.\. ]]; then
    echo "Include path cannot contain '..' (path traversal)."
    return 1
  fi
  # Check file existence (warning only)
  check_file_exists "$path"
  # Check file permissions if file exists
  if ! check_file_permissions "$path"; then
    return 1
  fi
  # Check directory existence
  if ! check_directory_exists "$path"; then
    return 1
  fi
  return 0
}

validate_server_url() {
  local url="$1"
  local repo_name="${2:-}"
  # Server URL should start with http:// or https://
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "Server URL must start with 'http://' or 'https://'."
    return 1
  fi
  # HTTPS preference warning
  if [[ "$url" =~ ^http:// ]]; then
    msg_warning "Using HTTP instead of HTTPS. HTTP connections are not encrypted and vulnerable to MITM attacks."
    if ! prompt_continue_on_failure "HTTP is insecure. Consider using HTTPS instead."; then
      return 1
    fi
  fi
  # Basic URL validation - should have something after the protocol
  # This allows domains, IPs, and variables like $repo/$arch
  local url_without_protocol="${url#http://}"
  url_without_protocol="${url_without_protocol#https://}"
  if [[ -z "$url_without_protocol" ]]; then
    echo "Server URL format is invalid. Expected format: https://example.com/\$repo/\$arch"
    return 1
  fi
  # Extract hostname for DNS test
  local hostname="${url_without_protocol%%/*}"
  hostname="${hostname%%:*}"
  # DNS resolution check (shows output in dry-run mode)
  if ! test_dns_resolution "$hostname"; then
    return 1
  fi
  # URL connectivity test (shows output in dry-run mode)
  if ! test_url_connectivity "$url" 10; then
    return 1
  fi
  # Repository structure test (if URL contains $repo or $arch) (shows output in dry-run mode)
  if [[ "$url" =~ \$repo ]] || [[ "$url" =~ \$arch ]]; then
    if ! test_repository_structure "$url" 10; then
      return 1
    fi
  fi
  # Duplicate Server check
  if [[ -n "$repo_name" ]]; then
    if ! check_duplicate_server "$url" "$repo_name"; then
      return 1
    fi
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
    # URL reachability test (shows output in dry-run mode)
    if ! test_package_url_reachability "$url" 10; then
      return 1
    fi
    # Architecture check (shows output in dry-run mode)
    if ! check_package_architecture "$url"; then
      return 1
    fi
    return 0
  fi
  # Check for .tar.zst, .tar.xz, .tar.gz
  if [[ "$url" =~ \.tar\.(zst|xz|gz)$ ]]; then
    # URL reachability test (shows output in dry-run mode)
    if ! test_package_url_reachability "$url" 10; then
      return 1
    fi
    # Architecture check (shows output in dry-run mode)
    if ! check_package_architecture "$url"; then
      return 1
    fi
    return 0
  fi
  echo "Package URL should point to a package file (.pkg.tar.zst, .pkg.tar.xz, .pkg.tar.gz, .tar.zst, .tar.xz, or .tar.gz)."
  return 1
}

# Prompt user to continue or abort on validation failure
prompt_continue_on_failure() {
  local message="$1"
  msg_warning "$message"
  while true; do
    read -rp "Continue anyway? (y/N): " RESPONSE
    case "${RESPONSE,,}" in
      y|yes)
        return 0
        ;;
      n|no|"")
        return 1
        ;;
      *)
        echo "Please enter 'y' for yes or 'n' for no."
        ;;
    esac
  done
}

# Pre-flight system checks
check_required_tools() {
  local missing_tools=()
  local tools=("pacman" "pacman-key")
  
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done
  
  # Check for curl or wget (at least one needed for connectivity tests)
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing_tools+=("curl or wget")
  fi
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    msg_error "Missing required tools: ${missing_tools[*]}"
    if ! prompt_continue_on_failure "Some required tools are missing. The script may not work correctly."; then
      exit 1
    fi
  fi
}

check_pacman_lock() {
  if [[ -f /var/lib/pacman/db.lck ]]; then
    msg_error "Pacman database is locked. Another pacman process may be running."
    msg_info "If you're sure no other pacman process is running, remove /var/lib/pacman/db.lck"
    if ! prompt_continue_on_failure "Pacman lock file exists. Continuing may cause conflicts."; then
      exit 1
    fi
  fi
}

check_disk_space() {
  local min_space_mb=100
  local available_space_kb
  available_space_kb=$(df -k / | awk 'NR==2 {print $4}')
  local available_space_mb=$((available_space_kb / 1024))
  
  if [[ $available_space_mb -lt $min_space_mb ]]; then
    msg_warning "Low disk space: ${available_space_mb}MB available (minimum recommended: ${min_space_mb}MB)"
    if ! prompt_continue_on_failure "Insufficient disk space may cause operations to fail."; then
      exit 1
    fi
  fi
}

check_network_connectivity() {
  local test_hosts=("8.8.8.8" "1.1.1.1" "archlinux.org")
  local reachable=false
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing network connectivity (8.8.8.8, 1.1.1.1, archlinux.org)..."
  fi
  
  for host in "${test_hosts[@]}"; do
    if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
      reachable=true
      break
    fi
  done
  
  if [[ "$reachable" == "false" ]]; then
    msg_warning "Network connectivity test failed. Internet connection may be unavailable."
    if ! prompt_continue_on_failure "Network operations may fail."; then
      exit 1
    fi
  elif [[ $DRY_RUN -eq 1 ]]; then
    msg_success "[dry-run] Network connectivity test passed"
  fi
}

check_pacman_conf_writable() {
  if [[ ! -w "$PACMAN_CONF" ]] && [[ $DRY_RUN -eq 0 ]]; then
    if [[ -z "${EUID-}" ]] || [[ "$EUID" -ne 0 ]]; then
      if [[ ${#SUDO[@]} -eq 0 ]]; then
        msg_error "Cannot write to $PACMAN_CONF. Root privileges required."
        exit 1
      fi
    else
      msg_error "Cannot write to $PACMAN_CONF. Check permissions."
      exit 1
    fi
  fi
}

# Enhanced repository name validation
check_reserved_repo_name() {
  local name="$1"
  local reserved_repos=("core" "extra" "community" "multilib" "testing" "multilib-testing" "options" "archlinuxfr")
  local name_lower="${name,,}"
  
  for reserved in "${reserved_repos[@]}"; do
    if [[ "$name_lower" == "$reserved" ]]; then
      msg_warning "Repository name '$name' matches reserved Arch repository name '$reserved'."
      if ! prompt_continue_on_failure "Using a reserved repository name may cause conflicts."; then
        return 1
      fi
    fi
  done
  return 0
}

# Enhanced include path validation
check_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    msg_warning "File does not exist: $path"
    msg_info "The file may be created by a package installation. Continuing..."
    return 0  # Warning only, not an error
  fi
  return 0
}

check_file_permissions() {
  local path="$1"
  if [[ -f "$path" ]]; then
    if [[ ! -r "$path" ]]; then
      msg_error "File is not readable: $path"
      if ! prompt_continue_on_failure "Cannot read file. Operations may fail."; then
        return 1
      fi
    fi
  fi
  return 0
}

check_directory_exists() {
  local path="$1"
  local parent_dir
  parent_dir=$(dirname "$path")
  
  if [[ ! -d "$parent_dir" ]]; then
    msg_error "Parent directory does not exist: $parent_dir"
    if ! prompt_continue_on_failure "Directory must exist for Include path to work."; then
      return 1
    fi
  fi
  return 0
}

# Enhanced server URL validation
test_dns_resolution() {
  local hostname="$1"
  
  # Extract hostname from URL if needed
  if [[ "$hostname" =~ ^https?:// ]]; then
    hostname="${hostname#http://}"
    hostname="${hostname#https://}"
    hostname="${hostname%%/*}"
    hostname="${hostname%%:*}"
  fi
  
  # Remove port if present
  hostname="${hostname%:*}"

  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing DNS resolution for: $hostname"
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$hostname" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        msg_success "[dry-run] DNS resolution successful for: $hostname"
      fi
      return 0
    fi
  elif command -v host >/dev/null 2>&1; then
    if host "$hostname" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        msg_success "[dry-run] DNS resolution successful for: $hostname"
      fi
      return 0
    fi
  else
    # Fallback: try ping (may not work for all hosts but better than nothing)
    if ping -c 1 -W 2 "$hostname" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        msg_success "[dry-run] DNS resolution successful for: $hostname"
      fi
      return 0
    fi
  fi
  
  msg_warning "DNS resolution failed for: $hostname"
  if ! prompt_continue_on_failure "Hostname may be unreachable."; then
    return 1
  fi
  return 0
}

test_url_connectivity() {
  local url="$1"
  local timeout="${2:-10}"
  
  local http_client=""
  if command -v curl >/dev/null 2>&1; then
    http_client="curl"
  elif command -v wget >/dev/null 2>&1; then
    http_client="wget"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      msg_warning "[dry-run] No HTTP client (curl/wget) available, skipping URL connectivity test"
    fi
    return 0  # Skip if no HTTP client available
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing URL connectivity: $url (timeout: ${timeout}s)"
  fi
  
  if [[ "$http_client" == "curl" ]]; then
    if curl -sSf --max-time "$timeout" --head "$url" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        msg_success "[dry-run] URL connectivity test passed: $url"
      fi
      return 0
    fi
  elif [[ "$http_client" == "wget" ]]; then
    if wget --spider --timeout="$timeout" --tries=1 "$url" >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        msg_success "[dry-run] URL connectivity test passed: $url"
      fi
      return 0
    fi
  fi
  
  msg_warning "URL connectivity test failed: $url"
  if ! prompt_continue_on_failure "URL may be unreachable."; then
    return 1
  fi
  return 0
}

test_repository_structure() {
  local base_url="$1"
  local timeout="${2:-10}"
  
  # Test if $repo/$arch pattern resolves
  # Replace $repo and $arch with test values
  local test_url="${base_url//\$repo/testrepo}"
  test_url="${test_url//\$arch/x86_64}"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing repository structure: $test_url (timeout: ${timeout}s)"
  fi
  
  # Try to access the repository structure
  if ! test_url_connectivity "$test_url" "$timeout"; then
    msg_warning "Repository structure test failed. URL pattern may be incorrect."
    if ! prompt_continue_on_failure "Repository may not be accessible with this URL pattern."; then
      return 1
    fi
  elif [[ $DRY_RUN -eq 1 ]]; then
    msg_success "[dry-run] Repository structure test passed"
  fi
  return 0
}

check_duplicate_server() {
  local url="$1"
  local repo_name="$2"
  
  # Check if this exact Server URL already exists in the same repo block
  if grep -A 5 "^\[${repo_name}\]" "$PACMAN_CONF" 2>/dev/null | grep -q "Server = ${url}$"; then
    msg_warning "Duplicate Server URL found in repository [$repo_name]: $url"
    if ! prompt_continue_on_failure "Duplicate Server entries may cause issues."; then
      return 1
    fi
  fi
  return 0
}

# Enhanced GPG key validation
test_keyserver_connectivity() {
  local keyserver="$1"
  local timeout="${2:-10}"
  
  local hostname="${keyserver%:*}"
  local port=""
  if [[ "$keyserver" == *:* ]]; then
    port="${keyserver#*:}"
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing keyserver connectivity: $keyserver"
  fi
  
  # Test DNS resolution
  if ! test_dns_resolution "$hostname"; then
    return 1
  fi
  
  # Test port accessibility if custom port specified
  if [[ -n "$port" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      msg_info "[dry-run] Testing port accessibility: $hostname:$port"
    fi
    if command -v nc >/dev/null 2>&1 || command -v nmap >/dev/null 2>&1; then
      if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$hostname" "$port" 2>/dev/null; then
          if [[ $DRY_RUN -eq 1 ]]; then
            msg_success "[dry-run] Port $port on $hostname is accessible"
          fi
        else
          msg_warning "Port $port on $hostname is not accessible"
          if ! prompt_continue_on_failure "Keyserver port may be unreachable."; then
            return 1
          fi
        fi
      fi
    elif [[ $DRY_RUN -eq 1 ]]; then
      msg_warning "[dry-run] No port testing tool (nc/nmap) available, skipping port check"
    fi
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_success "[dry-run] Keyserver connectivity test passed"
  fi
  return 0
}

check_key_exists() {
  local keyid="$1"
  local keyserver="$2"
  
  if [[ -z "$keyid" ]]; then
    return 0
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would check if GPG key exists on keyserver: $keyid @ $keyserver"
    return 0
  fi
  
  # Note: We can't easily check if a key exists on a keyserver without trying to fetch it
  # The actual import will handle errors if the key doesn't exist
  # This function is kept for potential future enhancements
  return 0
}

check_key_imported() {
  local keyid="$1"
  
  if [[ -z "$keyid" ]]; then
    return 0
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Checking if GPG key is already imported: $keyid"
  fi
  
  # Check if key is already in keyring (read-only operation, safe in dry-run)
  if "${SUDO[@]}" pacman-key --list-keys 2>/dev/null | grep -q "$keyid"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      msg_info "[dry-run] GPG key $keyid is already imported in the keyring"
    else
      msg_info "GPG key $keyid is already imported in the keyring."
    fi
    return 0
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] GPG key $keyid is not yet imported"
  fi
  return 1
}

verify_key_fingerprint() {
  local keyid="$1"
  local expected_fingerprint="$2"
  
  if [[ -z "$keyid" ]] || [[ -z "$expected_fingerprint" ]]; then
    return 0
  fi
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would verify key fingerprint: $keyid (expected: $expected_fingerprint)"
    return 0
  fi
  
  # This is optional - only verify if expected fingerprint is provided
  local actual_fingerprint
  actual_fingerprint=$("${SUDO[@]}" pacman-key --list-keys "$keyid" 2>/dev/null | grep -i "fingerprint" | head -1 | awk '{print $NF}')
  
  if [[ -n "$actual_fingerprint" ]] && [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
    msg_warning "Key fingerprint mismatch. Expected: $expected_fingerprint, Got: $actual_fingerprint"
    if ! prompt_continue_on_failure "Key fingerprint does not match expected value."; then
      return 1
    fi
  fi
  return 0
}

# Enhanced package URL validation
test_package_url_reachability() {
  local url="$1"
  local timeout="${2:-10}"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Testing package URL reachability: $url (timeout: ${timeout}s)"
  fi
  
  if ! test_url_connectivity "$url" "$timeout"; then
    return 1
  fi
  
  return 0
}

check_package_architecture() {
  local url="$1"
  local system_arch
  system_arch=$(uname -m)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Checking package architecture match for: $url (system: $system_arch)"
  fi
  
  # Extract architecture from URL if present
  # Common patterns: .../x86_64/..., .../aarch64/..., etc.
  if [[ "$url" =~ /(x86_64|aarch64|armv7h|i686)/ ]]; then
    local url_arch="${BASH_REMATCH[1]}"
    if [[ "$url_arch" != "$system_arch" ]]; then
      msg_warning "Package architecture ($url_arch) does not match system architecture ($system_arch)"
      if ! prompt_continue_on_failure "Installing wrong architecture packages may cause issues."; then
        return 1
      fi
    elif [[ $DRY_RUN -eq 1 ]]; then
      msg_success "[dry-run] Package architecture matches system architecture: $url_arch"
    fi
  elif [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] No architecture pattern found in URL, skipping architecture check"
  fi
  return 0
}

# Post-modification validation
verify_backup_created() {
  local backup_file="${PACMAN_CONF}.bak.${BACKUP_SUFFIX}"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would verify backup created: $backup_file"
    return 0
  fi
  
  if [[ ! -f "$backup_file" ]]; then
    msg_error "Backup file was not created: $backup_file"
    if ! prompt_continue_on_failure "Backup verification failed. Proceeding may be unsafe."; then
      return 1
    fi
  else
    msg_success "Backup created: $backup_file"
  fi
  return 0
}

validate_pacman_conf_syntax() {
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would validate pacman.conf syntax using pacman-conf"
    return 0
  fi
  
  if command -v pacman-conf >/dev/null 2>&1; then
    if ! "${SUDO[@]}" pacman-conf >/dev/null 2>&1; then
      msg_error "pacman.conf syntax validation failed"
      if ! prompt_continue_on_failure "Invalid pacman.conf syntax detected. System may be in inconsistent state."; then
        return 1
      fi
    else
      msg_success "pacman.conf syntax is valid"
    fi
  else
    msg_warning "pacman-conf not available, skipping syntax validation"
  fi
  return 0
}

test_repository_accessibility() {
  local repo_name="$1"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would test repository accessibility: pacman -Sy $repo_name"
    return 0
  fi
  
  msg_info "Testing repository accessibility..."
  if ! "${SUDO[@]}" pacman -Sy "$repo_name" --noconfirm >/dev/null 2>&1; then
    msg_warning "Repository sync test failed for [$repo_name]"
    if ! prompt_continue_on_failure "Repository may not be accessible or properly configured."; then
      return 1
    fi
  else
    msg_success "Repository [$repo_name] is accessible"
  fi
  return 0
}

test_package_listing() {
  local repo_name="$1"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    msg_info "[dry-run] Would test package listing: pacman -Sl $repo_name"
    return 0
  fi
  
  msg_info "Testing package listing from repository..."
  if ! "${SUDO[@]}" pacman -Sl "$repo_name" >/dev/null 2>&1; then
    msg_warning "Package listing test failed for [$repo_name]"
    if ! prompt_continue_on_failure "Cannot list packages from repository."; then
      return 1
    fi
  else
    local package_count
    package_count=$("${SUDO[@]}" pacman -Sl "$repo_name" 2>/dev/null | wc -l)
    msg_success "Repository [$repo_name] contains $package_count packages"
  fi
  return 0
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
          if validate_server_url "$VALUE" "$REPO_NAME"; then
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
    local seen_urls=()
    for url in "${URLS[@]}"; do
      # Check for duplicates
      for seen_url in "${seen_urls[@]}"; do
        if [[ "$url" == "$seen_url" ]]; then
          msg_warning "Duplicate package URL detected: $url"
          if ! prompt_continue_on_failure "Duplicate URLs may cause installation issues."; then
            url_valid=false
            break 2
          fi
        fi
      done
      seen_urls+=("$url")
      
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
  verify_backup_created
  
  [[ -n "$KEYID" ]] && import_repo_key "$KEYID" "${KEYSERVER:-keyserver.ubuntu.com}"
  [[ ${#URLS[@]} -gt 0 ]] && install_from_urls "${URLS[@]}"
  append_repo_block "$REPO_NAME" "$SIGLEVEL" "$MODE_KEY" "$VALUE"
  
  # Post-modification validation
  validate_pacman_conf_syntax
  test_repository_accessibility "$REPO_NAME"
  test_package_listing "$REPO_NAME"
  
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
  verify_backup_created
  
  import_repo_key "$KEYID" "$KEYSERVER"
  install_from_urls "$KEYRING_URL" "$MIRRORLIST_URL"

  if ! repo_exists "$REPO_NAME"; then
    append_repo_block "$REPO_NAME" "" "Include" "$INCLUDE_PATH"
    
    # Post-modification validation
    validate_pacman_conf_syntax
    test_repository_accessibility "$REPO_NAME"
    test_package_listing "$REPO_NAME"
  else
    echo "[$REPO_NAME] already present in pacman.conf; not duplicating."
  fi

  full_sync_upgrade
  echo "Chaotic-AUR steps completed."
}

# Pre-flight system checks
run_preflight_checks() {
  msg_info "Running pre-flight system checks..."
  check_required_tools
  check_pacman_lock
  check_disk_space
  # Network connectivity is read-only, safe to run in dry-run
  check_network_connectivity
  check_pacman_conf_writable
  msg_success "Pre-flight checks completed"
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

# Run pre-flight checks before main menu
run_preflight_checks
main_menu
