# Script Improvements Suggestions

## Overview
This document outlines user-friendly and general improvements for all scripts in the `Other/` directory.

---

## 1. Error Handling & Safety

### Current Issues
- **Inconsistent error handling**: Some scripts use `set -euo pipefail`, others use `set -e`, `set -u`, or none
- **Missing error checks**: Many scripts don't verify command success before proceeding
- **Unsafe command execution**: Some scripts use unquoted variables or unsafe command substitution

### Recommendations

#### Standardize Error Handling
**All scripts should start with:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Benefits:**
- `set -e`: Exit immediately if a command exits with non-zero status
- `set -u`: Treat unset variables as errors
- `set -o pipefail`: Return value of a pipeline is the status of the last command to exit with non-zero

**Exception handling for commands that may fail:**
```bash
# Instead of: command || true
# Use: command || { echo "Warning: command failed"; }
```

#### Fix Shebang Inconsistency
- **Issue**: `Start_create_custom_iso.sh` uses `#!/bin/bash` instead of `#!/usr/bin/env bash`
- **Fix**: Change to `#!/usr/bin/env bash` for portability

---

## 2. Dependency Checking

### Current Issues
- Some scripts check dependencies, others don't
- Inconsistent dependency checking patterns
- Missing helpful error messages when dependencies are missing

### Recommendations

#### Standard Dependency Check Function
Create a reusable function:
```bash
# Check if command exists, exit with helpful message if not
require_command() {
    local cmd="$1"
    local install_hint="${2:-Install it via your package manager}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required but not installed." >&2
        echo "Hint: $install_hint" >&2
        exit 1
    fi
}

# Usage:
require_command "gum" "Install with: pacman -S gum"
require_command "pacman" "This script requires Arch Linux"
```

#### Check Multiple Dependencies at Once
```bash
check_dependencies() {
    local deps=("gum" "pacman" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}" >&2
        exit 1
    fi
}
```

---

## 3. User-Friendly Error Messages

### Current Issues
- Generic error messages like "Error" or "Failed"
- Missing context about what went wrong
- No suggestions for how to fix issues

### Recommendations

#### Provide Context-Rich Error Messages
```bash
# Bad:
if ! pacman -S package; then
    echo "Error"
    exit 1
fi

# Good:
if ! pacman -S package; then
    echo "Error: Failed to install 'package'" >&2
    echo "Possible causes:" >&2
    echo "  - Insufficient permissions (try with sudo)" >&2
    echo "  - Package not found in repositories" >&2
    echo "  - Network connectivity issues" >&2
    exit 1
fi
```

#### Use Consistent Error Formatting
```bash
error() {
    echo "Error: $1" >&2
    [ -n "${2:-}" ] && echo "Hint: $2" >&2
    exit "${3:-1}"
}

warning() {
    echo "Warning: $1" >&2
}

info() {
    echo "Info: $1"
}
```

---

## 4. Input Validation & Security

### Current Issues
- Some scripts don't validate user input
- Potential command injection vulnerabilities
- Unsafe use of variables in command substitution

### Recommendations

#### Validate User Input
```bash
# Validate username format
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Invalid username format" "Use lowercase letters, digits, '_' or '-'"
    fi
}

# Validate file paths
validate_file_path() {
    local path="$1"
    if [[ "$path" != /* ]] && [[ "$path" != "$HOME"/* ]]; then
        error "Invalid path" "Path must be absolute or relative to HOME"
    fi
    if [ ! -f "$path" ]; then
        error "File not found" "Path: $path"
    fi
}
```

#### Safe Command Execution
```bash
# Bad: Unquoted variables
sudo pacman -Rns $packages

# Good: Properly quoted arrays
sudo pacman -Rns -- "${packages[@]}"

# Bad: Unsafe eval
eval "command $user_input"

# Good: Use arrays and proper quoting
command "${args[@]}"
```

---

## 5. Sudo Handling

### Current Issues
- Inconsistent sudo checking
- Some scripts assume sudo is available
- Hardcoded sudo usage without checking if already root

### Recommendations

#### Standard Sudo Check Function
```bash
# Check if running as root, prompt for sudo if needed
check_root() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            error "This script requires root privileges" "Install sudo or run as root"
        fi
        if [ "${ASSUME_YES:-0}" -eq 1 ]; then
            exec sudo -E -- "$0" "$@"
        else
            echo "This script requires root privileges."
            read -rp "Run with sudo? (y/N): " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                exec sudo -E -- "$0" "$@"
            else
                exit 1
            fi
        fi
    fi
}

# Or: Check if command needs sudo and use it conditionally
run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}
```

---

## 6. Dry-Run Support

### Current Issues
- Only some scripts support `--dry-run`
- Inconsistent dry-run implementation

### Recommendations

#### Standard Dry-Run Pattern
```bash
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "Running in DRY RUN mode: No changes will be made."
fi

# Safe command runner
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would execute: $*"
    else
        "$@"
    fi
}

# Usage:
run pacman -S package
run systemctl restart service
```

---

## 7. Logging & Output

### Current Issues
- Inconsistent output formatting
- Some scripts use colors, others don't
- Missing progress indicators for long operations

### Recommendations

#### Standard Output Functions
```bash
# Check if gum is available for better output
HAS_GUM=false
if command -v gum >/dev/null 2>&1; then
    HAS_GUM=true
fi

# Consistent message functions
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
```

#### Progress Indicators
```bash
# For long operations
with_spinner() {
    local title="$1"
    shift
    if [ "$HAS_GUM" = true ]; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo "[...] $title"
        "$@"
    fi
}
```

---

## 8. Configuration & Defaults

### Current Issues
- Hardcoded paths and values
- No configuration file support
- Inconsistent default values

### Recommendations

#### Configuration File Support
```bash
# Load configuration with defaults
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/open-linux-setup"
CONFIG_FILE="$CONFIG_DIR/script.conf"
mkdir -p "$CONFIG_DIR"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Set defaults
PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}"
LOG_DIR="${LOG_DIR:-/var/log}"
```

---

## 9. Help & Usage Information

### Current Issues
- Many scripts lack `--help` option
- No usage information
- Missing script descriptions

### Recommendations

#### Standard Help Function
```bash
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Brief description of what the script does.

Options:
    --help, -h          Show this help message
    --dry-run           Show what would be done without making changes
    --yes, -y           Assume yes to all prompts
    --verbose, -v       Enable verbose output

Examples:
    $(basename "$0") --dry-run
    $(basename "$0") --yes

EOF
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --yes|-y)
            ASSUME_YES=1
            ;;
        *)
            error "Unknown option: $1" "Use --help for usage information"
            ;;
    esac
    shift
done
```

---

## 10. Exit Codes

### Current Issues
- Inconsistent exit codes
- Some scripts exit with 0 even on failure
- Missing exit code documentation

### Recommendations

#### Standard Exit Codes
```bash
# Define exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_MISSING_DEPENDENCY=2
EXIT_INVALID_INPUT=3
EXIT_PERMISSION_DENIED=4

# Use appropriate exit codes
if ! command -v required_tool >/dev/null 2>&1; then
    error "Missing dependency: required_tool" "Install it first" "$EXIT_MISSING_DEPENDENCY"
fi

if [ "$EUID" -ne 0 ] && [ ! -w "$target_file" ]; then
    error "Permission denied" "Run as root or with sudo" "$EXIT_PERMISSION_DENIED"
fi
```

---

## 11. Specific Script Improvements

### Start_check_orphans.sh
- ✅ Good: Uses proper error handling patterns
- ⚠️ **Improve**: Add `--dry-run` support
- ⚠️ **Improve**: Add summary statistics at the end
- ⚠️ **Improve**: Better formatting for large lists

### Start_network_check.sh
- ✅ Good: Comprehensive checks
- ✅ Good: Uses gum for nice output
- ⚠️ **Improve**: Add `--help` option
- ⚠️ **Improve**: Make checks configurable (skip certain checks)

### Start_ssh_server.sh
- ⚠️ **Improve**: Add error handling (`set -euo pipefail`)
- ⚠️ **Improve**: Validate file path before sourcing
- ⚠️ **Improve**: Add `--help` option
- ⚠️ **Improve**: Better error messages if file not found

### Start_bluetooth_check.sh
- ⚠️ **Improve**: Add error handling (`set -euo pipefail`)
- ⚠️ **Improve**: Check if commands exist before using
- ⚠️ **Improve**: Add `--help` option
- ⚠️ **Improve**: Better error messages

### Start_restart_wifi.sh
- ⚠️ **Improve**: Add error handling (`set -euo pipefail`)
- ⚠️ **Improve**: Check command exit codes properly
- ⚠️ **Improve**: Add `--dry-run` support
- ⚠️ **Improve**: Validate interface exists before operations

### Start_create_custom_iso.sh
- ⚠️ **Fix**: Change shebang from `#!/bin/bash` to `#!/usr/bin/env bash`
- ⚠️ **Improve**: Add error handling (`set -euo pipefail`)
- ⚠️ **Improve**: Add `--help` option

### Start_server_status.sh
- ✅ Good: Uses gum for nice output
- ✅ Good: Checks dependencies
- ⚠️ **Improve**: Add `--help` option
- ⚠️ **Improve**: Make service list configurable

### Start_pihole_check.sh
- ✅ Good: Uses gum for nice output
- ✅ Good: Checks dependencies
- ⚠️ **Improve**: Add `--help` option
- ⚠️ **Improve**: Make test targets configurable

---

## 12. Code Quality Improvements

### General Best Practices

1. **Quote all variables**: Always use `"$variable"` instead of `$variable`
2. **Use arrays properly**: Use `"${array[@]}"` for expansion
3. **Avoid eval**: Use arrays and proper quoting instead
4. **Check array length**: Before iterating, check `[ ${#array[@]} -gt 0 ]`
5. **Use local variables**: Always use `local` in functions
6. **Document functions**: Add comments explaining what functions do
7. **Consistent naming**: Use lowercase with underscores for variables and functions

### Example Function Template
```bash
# Function: Brief description
# Arguments:
#   $1: Description of first argument
#   $2: Description of second argument (optional)
# Returns: Description of return value or side effects
function_name() {
    local arg1="$1"
    local arg2="${2:-default}"
    
    # Validate inputs
    [ -z "$arg1" ] && error "arg1 is required"
    
    # Implementation
    # ...
    
    return 0
}
```

---

## 13. Testing & Validation

### Recommendations

1. **Add validation checks**: Test scripts with various inputs
2. **Test error paths**: Ensure error handling works correctly
3. **Test edge cases**: Empty inputs, missing files, etc.
4. **Test on clean systems**: Ensure dependencies are properly checked

---

## Summary of Priority Fixes

### High Priority
1. ✅ Add `set -euo pipefail` to all scripts missing it
2. ✅ Fix shebang inconsistency (`Start_create_custom_iso.sh`)
3. ✅ Add dependency checking to all scripts
4. ✅ Add proper error messages with context
5. ✅ Add `--help` option to all scripts

### Medium Priority
6. ✅ Standardize sudo handling
7. ✅ Add `--dry-run` support where applicable
8. ✅ Improve input validation
9. ✅ Standardize output formatting
10. ✅ Add configuration file support where appropriate

### Low Priority
11. ✅ Add progress indicators for long operations
12. ✅ Improve code documentation
13. ✅ Add logging capabilities
14. ✅ Standardize exit codes

---

## Implementation Checklist

For each script, ensure:
- [ ] Uses `#!/usr/bin/env bash`
- [ ] Has `set -euo pipefail` (or appropriate error handling)
- [ ] Checks for required dependencies
- [ ] Has `--help` option
- [ ] Provides clear error messages
- [ ] Validates user input
- [ ] Uses proper quoting
- [ ] Has consistent output formatting
- [ ] Documents functions
- [ ] Uses appropriate exit codes

