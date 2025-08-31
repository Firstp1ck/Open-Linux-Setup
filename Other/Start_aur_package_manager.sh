#!/usr/bin/env bash

# See Open-Linux-Setup/Documents/aur_package_manager.md for detailed Instructions and Importent Notes.

# Config paths for persisting defaults
CONFIG_DIR="$HOME/.config/open-linux-setup"
CONFIG_FILE="$CONFIG_DIR/aur_manager.conf"

# Flags (defaults)
ASSUME_YES=0
SKIP_BUILD=0
DRY_RUN=0
SKIP_SSH=0

print_usage() {
    cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --yes, -y       Assume "yes" to all confirmations (non-interactive)
  --skip-build    Skip building/testing steps
  --dry-run       Show what would be done, but do not execute commands
  --skip-ssh      Skip AUR SSH setup/checks
  --help, -h      Show this help message
USAGE
}

# Parse CLI options
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)
            ASSUME_YES=1
            ;;
        --skip-build)
            SKIP_BUILD=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --skip-ssh)
            SKIP_SSH=1
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
    shift
done

# Check for required dependencies
check_dependencies() {
    local deps=("git" "curl" "makepkg" "namcap" "gum")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Error: $dep is required but not installed"
            exit 1
        fi
    done
}

# One-time setup wizard for installing and explaining dependencies (gum, namcap)
one_time_setup_wizard() {
    local config_dir="$HOME/.config/open-linux-setup"
    local sentinel_file="$config_dir/aur_manager_setup_done"

    # Skip if already completed
    if [ -f "$sentinel_file" ]; then
        return 0
    fi

    # Determine missing deps (focus on gum and namcap for the wizard)
    local target_deps=("gum" "namcap")
    local missing=()
    for d in "${target_deps[@]}"; do
        if ! command -v "$d" >/dev/null 2>&1; then
            missing+=("$d")
        fi
    done

    # If nothing missing, mark wizard as done and return
    if [ ${#missing[@]} -eq 0 ]; then
        mkdir -p "$config_dir"
        echo "done" > "$sentinel_file"
        return 0
    fi

    # Explanation text
    local explanation
    explanation="AUR Manager - One-time setup\n\nDependencies:\n\n- gum: Provides a user-friendly terminal UI (menus, prompts, spinners).\n- namcap: Lints PKGBUILD and package files to catch common issues.\n\nSome required tools are missing: ${missing[*]}\nWe'll install them using your preferred package manager."

    if command -v gum >/dev/null 2>&1; then
        printf "%s" "$explanation" | gum style --border normal --margin "1 2" --padding "1 2"
    else
        echo "$explanation"
    fi

    # Ask to install
    local proceed_install=""
    if confirm_action "Install missing dependencies now? (${missing[*]})"; then
        proceed_install="yes"
    fi

    if [ "$proceed_install" != "yes" ]; then
        echo "Skipping installation. You can install later and re-run the script."
        return 0
    fi

    # Choose installer (persist last choice)
    local installer="pacman"
    local last_installer
    last_installer=$(config_get last_installer)
    if command -v yay >/dev/null 2>&1; then
        if command -v gum >/dev/null 2>&1; then
            # Reorder options so last choice is first
            if [ "$last_installer" = "yay" ]; then
                installer=$(printf "yay\npacman" | gum choose --header "Choose installer")
            else
                installer=$(printf "pacman\nyay" | gum choose --header "Choose installer")
            fi
        else
            if [ "$last_installer" = "yay" ]; then
                installer="yay"
            else
                if confirm_action "Use 'yay' instead of 'pacman'?"; then installer="yay"; fi
            fi
        fi
    fi
    config_set last_installer "$installer"

    # Install command
    local cmd
    if [ "$installer" = "yay" ]; then
        cmd=(yay -S --needed "${missing[@]}")
    else
        cmd=(sudo pacman -S --needed "${missing[@]}")
    fi

    # Run install with optional spinner (and dry-run support)
    if ! run_with_spinner "Installing: ${missing[*]} via $installer" "${cmd[@]}"; then
        echo "Installation failed. Please install the missing packages manually: ${missing[*]}"
        return 1
    fi

    # Recheck and mark as done if successful
    local still_missing=()
    for d in "${target_deps[@]}"; do
        command -v "$d" >/dev/null 2>&1 || still_missing+=("$d")
    done
    if [ ${#still_missing[@]} -eq 0 ]; then
        mkdir -p "$config_dir"
        echo "done" > "$sentinel_file"
    else
        echo "Some dependencies are still missing: ${still_missing[*]}"
        return 1
    fi
}
# Spinner helper for long-running commands
run_with_spinner() {
    local title="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] $title: $*"
    else
        if command -v gum >/dev/null 2>&1; then
            gum spin --title "$title" -- "$@"
        else
            "$@"
        fi
    fi
}

# Simple config helpers (persist last selections)
config_get() {
    local key="$1"
    if [ -f "$CONFIG_FILE" ]; then
        grep -E "^${key}=" "$CONFIG_FILE" | tail -n1 | cut -d= -f2-
    fi
}

config_set() {
    local key="$1"
    local value="$2"
    mkdir -p "$CONFIG_DIR"
    local tmp
    tmp=$(mktemp)
    if [ -f "$CONFIG_FILE" ]; then
        awk -v k="$key" -v v="$value" -F'=' 'BEGIN{OFS=FS} { if($1==k){$0=k"="v; seen=1} print } END { if(!seen) print k"="v }' "$CONFIG_FILE" > "$tmp"
    else
        printf '%s=%s\n' "$key" "$value" > "$tmp"
    fi
    mv "$tmp" "$CONFIG_FILE"
}

# Styled error banner
show_error() {
    local message="$1"
    if command -v gum >/dev/null 2>&1; then
        printf "%s\n" "Error: $message" | gum style --border double --margin "1" --padding "0 1"
    else
        echo "Error: $message"
    fi
}

# Unified confirmation helper that respects --yes and supports non-gum fallback
confirm_action() {
    local prompt="$1"
    if [ "$ASSUME_YES" -eq 1 ]; then
        echo "[yes] $prompt"
        return 0
    fi
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$prompt"
        return $?
    else
        read -rp "$prompt [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]]
        return $?
    fi
}
# Validate package name
validate_package_name() {
    local name=$1
    if [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        echo "Error: Package name must be lowercase and can only contain letters, numbers, and hyphens"
        return 1
    fi
    return 0
}

# Validate and clean package version
validate_package_version() {
    local version=$1
    # Strip any non-numeric characters except dots
    PKG_VER=$(echo "$version" | sed 's/[^0-9.]//g')
    # Ensure version starts with a number
    if [[ ! "$PKG_VER" =~ ^[0-9] ]]; then
        echo "Error: Version must start with a number"
        return 1
    fi
    return 0
}

# Check if SSH key is set up for AUR
check_aur_ssh() {
    if [ "$SKIP_SSH" -eq 1 ]; then
        echo "Skipping AUR SSH checks (--skip-ssh)"
        return 0
    fi
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 aur@aur.archlinux.org help > /dev/null 2>&1; then
        echo "Error: SSH key not set up for AUR. Please set up your SSH key first."

        # Check if aur_ed25519 key exists, if not, offer to generate or choose
        if [ ! -f ~/.ssh/aur_ed25519 ]; then
            if command -v gum >/dev/null 2>&1; then
                key_option=$(printf "Generate new key\nChoose existing key" | gum choose --limit=1 --height=2 --header "No 'aur_ed25519' found. Choose key option:")
            else
                echo "Error: gum is required for interactive selection. Please install gum."
                exit 1
            fi
            if [[ "$key_option" == "Generate new key" ]]; then
                # Prefill last used AUR email
                local last_aur_email
                last_aur_email=$(config_get last_aur_email)
                if [ -n "$last_aur_email" ]; then
                    user_email=$(gum input --placeholder "your_email@example.com" --prompt "Email for SSH key comment: " --value "$last_aur_email")
                else
                    user_email=$(gum input --placeholder "your_email@example.com" --prompt "Email for SSH key comment: ")
                fi
                [ -z "$user_email" ] && echo "Error: Email is required." && exit 1
                config_set last_aur_email "$user_email"
                echo "Generating SSH key. You will be prompted to enter a passphrase."
                ssh-keygen -t ed25519 -C "$user_email" -f ~/.ssh/aur_ed25519
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to generate SSH key."
                    exit 1
                fi
                echo "SSH key generated successfully at ~/.ssh/aur_ed25519"
                SELECTED_KEY_FILE="aur_ed25519"
            elif [[ "$key_option" == "Choose existing key" ]]; then
                echo "Available public keys in ~/.ssh/:"
                mapfile -t ssh_keys < <(find ~/.ssh/ -maxdepth 1 -name "*.pub" -printf '%f\n' | sed 's/\.pub$//')

                if [ ${#ssh_keys[@]} -eq 0 ]; then
                    echo "No public keys found in ~/.ssh/. Please generate a new key."
                    exit 1
                fi

                SELECTED_KEY_FILE=$(printf "%s\n" "${ssh_keys[@]}" | sed 's/\.pub$//' | gum choose --limit=1 --header "Choose a key:")
                [ -z "$SELECTED_KEY_FILE" ] && echo "No key selected." && exit 1
                echo "Selected key: ~/.ssh/$SELECTED_KEY_FILE"
            else
                echo "Invalid option. Aborting."
                exit 1
            fi
        else
            # If aur_ed25519 already exists, use it by default
            SELECTED_KEY_FILE="aur_ed25519"
        fi

        echo "Next steps:"
        echo "1. Add your Public Key to your AUR account:"
        echo "  a. Open https://aur.archlinux.org/account/<your_account_name>/edit"
        echo "  b. Your Keyvalue is:"
        cat ~/.ssh/"${SELECTED_KEY_FILE}".pub | gum pager

        # Offer clipboard copy of the public key
        if confirm_action "Copy public key to clipboard?"; then
            if command -v wl-copy >/dev/null 2>&1; then
                wl-copy < ~/.ssh/"${SELECTED_KEY_FILE}".pub && echo "Public key copied to clipboard via wl-copy."
            elif command -v xclip >/dev/null 2>&1; then
                xclip -selection clipboard < ~/.ssh/"${SELECTED_KEY_FILE}".pub && echo "Public key copied to clipboard via xclip."
            else
                show_error "No clipboard tool found (install 'wl-clipboard' or 'xclip')."
            fi
        fi

        # Offer to open the AUR account page
        if confirm_action "Open AUR account page in your browser?"; then
            # Prefill last used AUR account name
            local last_aur_account
            last_aur_account=$(config_get last_aur_account)
            if [ -n "$last_aur_account" ]; then
                account_name=$(gum input --placeholder "your_account_name" --prompt "AUR account name (optional): " --value "$last_aur_account")
            else
                account_name=$(gum input --placeholder "your_account_name" --prompt "AUR account name (optional): ")
            fi
            [ -n "$account_name" ] && config_set last_aur_account "$account_name"
            if [ -n "$account_name" ]; then
                AUR_URL="https://aur.archlinux.org/account/${account_name}/edit"
            else
                AUR_URL="https://aur.archlinux.org/account/"
            fi
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$AUR_URL" >/dev/null 2>&1 &
                echo "Opened: $AUR_URL"
            else
                echo "Please open this URL in your browser: $AUR_URL"
            fi
        fi
        if confirm_action "Create SSH config for AUR using ~/.ssh/${SELECTED_KEY_FILE}?"; then
            mkdir -p ~/.ssh
            local config_file="$HOME/.ssh/config"
            touch "$config_file"
            if grep -qE '^Host[[:space:]]+aur$' "$config_file"; then
                echo "SSH config for 'aur' already exists in $config_file"
            else
                {
                    [ -s "$config_file" ] && echo ""
                    echo "Host aur"
                    echo "    HostName aur.archlinux.org"
                    echo "    User aur"
                    echo "    IdentityFile ~/.ssh/${SELECTED_KEY_FILE}"
                } >> "$config_file"
                echo "Added 'aur' host to $config_file"
            fi

            # Offer to start ssh-agent and add the key for this session
            if confirm_action "Start ssh-agent and add ~/.ssh/${SELECTED_KEY_FILE} now?"; then
                if [ -z "${SSH_AUTH_SOCK:-}" ]; then
                    eval "$(ssh-agent -s)" >/dev/null
                fi
                if ! run_with_spinner "Adding SSH key" ssh-add "$HOME/.ssh/${SELECTED_KEY_FILE}"; then
                    echo "Warning: Failed to add SSH key. You may need to run 'ssh-add ~/.ssh/${SELECTED_KEY_FILE}' manually."
                fi
            fi

            # Re-check SSH connection after configuration
            if ! ssh -o BatchMode=yes -o ConnectTimeout=5 aur@aur.archlinux.org help > /dev/null 2>&1; then
                echo "Failed to connect to AUR Repository after configuration attempt using ~/.ssh/${SELECTED_KEY_FILE}. Please check your setup."
                exit 1
            fi
        else
            exit 1 # Exit if user does not want to set up config
        fi
        exit 1 # Exit only if the initial check failed and user did not set up config
    fi
}

# Test and clean the package
test_and_clean_package() {
    if [ "$SKIP_BUILD" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        echo "Skipping build/test steps ($([ "$SKIP_BUILD" -eq 1 ] && echo --skip-build) $([ "$DRY_RUN" -eq 1 ] && echo --dry-run))"
        return 0
    fi
    # Check package with namcap
    if ! run_with_spinner "Checking package with namcap" namcap PKGBUILD; then
        echo "Warning: namcap found issues with the package, but continuing..."
    fi

    # Test the package build and installation
    if ! run_with_spinner "Building and installing package" makepkg -fsi --skippgpcheck; then
        echo "Error: Package build or installation failed. Please check the PKGBUILD file."
        return 1
    fi

    # Clean build files after successful test
    if ! run_with_spinner "Cleaning build files" makepkg -fc; then
        echo "Warning: Failed to clean build files, but continuing..."
        # Offer safer cleanup inside the current Git repository
        if confirm_action "Run 'git clean -xdf' to remove untracked files in this repository?"; then
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "[dry-run] git clean -xdf"
            else
                if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    if ! run_with_spinner "Cleaning repository (git clean -xdf)" git clean -xdf; then
                        echo "Warning: 'git clean -xdf' failed."
                    fi
                else
                    echo "Not inside a Git repository. Skipping 'git clean -xdf'."
                fi
            fi
        else
            echo "Skipping repository cleanup."
        fi
    fi
    return 0
}

create_aur_package() {
    # Check dependencies and SSH setup
    check_dependencies
    check_aur_ssh

    # Create a new AUR package
    # Load last-used answers to prefill prompts
    local last_pkg_name last_pkg_ver last_pkg_desc last_pkg_url last_pkg_depends
    last_pkg_name=$(config_get last_pkg_name)
    last_pkg_ver=$(config_get last_pkg_ver)
    last_pkg_desc=$(config_get last_pkg_desc)
    last_pkg_url=$(config_get last_pkg_url)
    last_pkg_depends=$(config_get last_pkg_depends)
    while true; do
        if [ -n "$last_pkg_name" ]; then
            PKG_NAME=$(gum input --placeholder "package-name (lowercase, numbers, hyphens)" --prompt "Package name: " --value "$last_pkg_name")
        else
            PKG_NAME=$(gum input --placeholder "package-name (lowercase, numbers, hyphens)" --prompt "Package name: ")
        fi
        if [ -z "$PKG_NAME" ]; then
            show_error "Package name cannot be empty"
            continue
        fi
        if validate_package_name "$PKG_NAME"; then
            break
        else
            show_error "Package name must be lowercase and can contain numbers and hyphens"
        fi
    done
    config_set last_pkg_name "$PKG_NAME"

    while true; do
        if [ -n "$last_pkg_ver" ]; then
            if ! PKG_VER=$(gum input --placeholder "0.0.1" --prompt "Version: " --value "$last_pkg_ver"); then
                echo "Cancelled."
                return 1
            fi
        else
            if ! PKG_VER=$(gum input --placeholder "0.0.1" --prompt "Version: "); then
                echo "Cancelled."
                return 1
            fi
        fi
        if [ -z "$PKG_VER" ]; then
            show_error "Version cannot be empty"
            continue
        fi
        if validate_package_version "$PKG_VER"; then
            break
        else
            show_error "Invalid version. It must start with a number (e.g., 0.0.1)"
        fi
    done
    config_set last_pkg_ver "$PKG_VER"

    if [ -n "$last_pkg_desc" ]; then
        PKG_DESC=$(gum input --placeholder "Short description" --prompt "Description: " --value "$last_pkg_desc")
    else
        PKG_DESC=$(gum input --placeholder "Short description" --prompt "Description: ")
    fi
    config_set last_pkg_desc "$PKG_DESC"

    while true; do
        if [ -n "$last_pkg_url" ]; then
            PKG_URL=$(gum input --placeholder "https://github.com/USER/REPO.git" --prompt "Git URL: " --value "$last_pkg_url")
        else
            PKG_URL=$(gum input --placeholder "https://github.com/USER/REPO.git" --prompt "Git URL: ")
        fi
        if [ -z "$PKG_URL" ]; then
            show_error "Git URL cannot be empty"
            continue
        fi
        if run_with_spinner "Validating source URL" curl --output /dev/null --silent --head --fail "$PKG_URL"; then
            break
        else
            show_error "Invalid or unreachable URL. Please provide a valid repository URL."
        fi
    done
    config_set last_pkg_url "$PKG_URL"
    
    # License selection with sensible defaults
    local license_options=("MIT" "GPL-3.0-or-later" "Apache-2.0" "BSD-3-Clause")
    local last_license
    last_license=$(config_get last_license)
    local ordered_licenses=()
    local seen="false"
    for l in "${license_options[@]}"; do [ "$l" = "$last_license" ] && seen="true" && break; done
    if [ -n "$last_license" ] && [ "$seen" = "true" ]; then
        ordered_licenses=("$last_license")
        for l in "${license_options[@]}"; do [ "$l" = "$last_license" ] || ordered_licenses+=("$l"); done
    else
        ordered_licenses=("${license_options[@]}")
    fi
    PKG_LICENSE=$(printf "%s\n" "${ordered_licenses[@]}" | gum choose --header "Select license")
    [ -z "$PKG_LICENSE" ] && PKG_LICENSE="MIT"
    config_set last_license "$PKG_LICENSE"

    # Dependencies (free text)
    if [ -n "$last_pkg_depends" ]; then
        PKG_DEPENDS=$(gum input --placeholder "dep1 dep2" --prompt "Dependencies (space-separated): " --value "$last_pkg_depends")
    else
        PKG_DEPENDS=$(gum input --placeholder "dep1 dep2" --prompt "Dependencies (space-separated): ")
    fi
    config_set last_pkg_depends "$PKG_DEPENDS"

    # Arch selection with persisted default
    local arch_options=("any" "x86_64")
    local last_arch
    last_arch=$(config_get last_arch)
    local ordered_arch=()
    seen="false"
    for a in "${arch_options[@]}"; do [ "$a" = "$last_arch" ] && seen="true" && break; done
    if [ -n "$last_arch" ] && [ "$seen" = "true" ]; then
        ordered_arch=("$last_arch")
        for a in "${arch_options[@]}"; do [ "$a" = "$last_arch" ] || ordered_arch+=("$a"); done
    else
        ordered_arch=("${arch_options[@]}")
    fi
    PKG_ARCH=$(printf "%s\n" "${ordered_arch[@]}" | gum choose --header "Select architecture")
    [ -z "$PKG_ARCH" ] && PKG_ARCH="any"
    config_set last_arch "$PKG_ARCH"

    # Summary before proceeding
    summary_content=$(cat <<EOS
Name:     $PKG_NAME
Version:  $PKG_VER
URL:      $PKG_URL
License:  $PKG_LICENSE
Depends:  $PKG_DEPENDS
Arch:     $PKG_ARCH
EOS
)
    printf "%s" "$summary_content" | gum style --border normal --margin "1 2" --padding "1 2" --bold
    if ! confirm_action "Proceed with these settings?"; then
        echo "Aborted by user."
        return 1
    fi

    # URL already validated above

    # Change to aur-packages directory
    cd ~/aur-packages || exit

    # Check if package already exists
    if [ -d "$PKG_NAME" ]; then
        echo "Error: Package directory already exists"
        exit 1
    fi

    # Clone the AUR repository
    if ! run_with_spinner "Cloning AUR repository" git clone ssh://aur@aur.archlinux.org/"$PKG_NAME".git; then
        echo "Error cloning AUR repository"
        exit 1
    fi
    cd "$PKG_NAME" || exit

    # Check for setup.sh in the source repository
    if ! run_with_spinner "Validating source URL" curl --output /dev/null --silent --head --fail "$PKG_URL"; then
        echo "Error: Invalid URL"
        exit 1
    fi

    # Clone the repository temporarily to check for setup.sh (shallow)
    temp_dir=$(mktemp -d)
    if ! run_with_spinner "Cloning source repository (shallow)" git clone --depth=1 "$PKG_URL" "$temp_dir"; then
        echo "Error: Could not clone the repository"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Locate setup.sh anywhere in the repo (relative paths)
    mapfile -t setup_candidates < <(cd "$temp_dir" && find . -type f -name 'setup.sh' -printf '%P\n')

    CHOSEN_SETUP_REL_PATH=""
    if [ ${#setup_candidates[@]} -eq 1 ]; then
        CHOSEN_SETUP_REL_PATH="${setup_candidates[0]}"
    elif [ ${#setup_candidates[@]} -gt 1 ]; then
        CHOSEN_SETUP_REL_PATH=$(printf "%s\n" "${setup_candidates[@]}" | gum filter --placeholder "Search setup.sh paths...")
    else
        # No setup.sh found → allow user to pick an alternative script path
        if command -v gum >/dev/null 2>&1; then
            printf "%s" "No setup.sh found in the repository.\nSelect an alternative script (.sh) to install as the entry point." | \
                gum style --border normal --margin "1 2" --padding "1 2"
        else
            echo "No setup.sh found in the repository. You can select an alternative .sh script."
        fi
        mapfile -t sh_candidates < <(cd "$temp_dir" && find . -type f -name '*.sh' -printf '%P\n')
        if [ ${#sh_candidates[@]} -gt 0 ]; then
            CHOSEN_SETUP_REL_PATH=$(printf "%s\n" "${sh_candidates[@]}" | gum filter --placeholder "Search .sh files...")
        else
            # As a last resort, ask for a manual relative path
            CHOSEN_SETUP_REL_PATH=$(gum input --placeholder "path/inside/repo/script.sh" --prompt "Enter relative path to script: ")
        fi
    fi

    # Validate chosen path exists in the repo
    if [ -z "$CHOSEN_SETUP_REL_PATH" ] || [ ! -f "$temp_dir/$CHOSEN_SETUP_REL_PATH" ]; then
        echo "Error: Chosen script path not found in repository: $CHOSEN_SETUP_REL_PATH"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"

    # Create the PKGBUILD file
    echo "Creating PKGBUILD file..."
    cat <<EOF > PKGBUILD
# Maintainer: $(git config user.name) <$(git config user.email)>
pkgname="$PKG_NAME"
pkgver="$PKG_VER"
pkgrel=1
pkgdesc="$PKG_DESC"
arch=('$PKG_ARCH')
url="$PKG_URL"
license=('$PKG_LICENSE')
makedepends=('git')
depends=('git' $(echo "$PKG_DEPENDS" | tr ' ' '\n' | sed 's/^/'\''/;s/$/'\''/'))
source=("\$pkgname::git+$PKG_URL")
sha256sums=('SKIP')

package() {
    cd "\$pkgname"

    # Install all files to /usr/share/\$pkgname
    install -dm755 "\$pkgdir/usr/share/\$pkgname"
    cp -a . "\$pkgdir/usr/share/\$pkgname/"

    # Install the chosen entry script to /usr/bin
    install -Dm755 "$CHOSEN_SETUP_REL_PATH" "\$pkgdir/usr/bin/$PKG_NAME"
}

post_install() {
    echo "==> Run '$PKG_NAME' to start the Hyprland setup."
}
EOF

    # Create the .SRCINFO file
    echo "Creating .SRCINFO file..."
    if ! run_with_spinner "Generating .SRCINFO" bash -lc 'makepkg --printsrcinfo > .SRCINFO'; then
        echo "Error creating .SRCINFO file"
        exit 1
    fi

    # Test and clean the package
    if ! test_and_clean_package; then
        exit 1
    fi

    # Display files and ask for confirmation
    echo -e "\n=== PKGBUILD ==="
    cat PKGBUILD | gum pager
    echo -e "\n=== .SRCINFO ==="
    cat .SRCINFO | gum pager
    echo -e "\n"
    if ! confirm_action "Push these changes to AUR?"; then
        echo "Aborting push to AUR"
        exit 0
    fi

    # Setup Git Repository
    echo "Setting up Git Repository"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Create .gitignore with PKGBUILD and .SRCINFO exceptions"
    elif ! echo -e "*\n!.SRCINFO\n!PKGBUILD" > .gitignore; then
        echo "Error creating .gitignore file"
        exit 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git branch --unset-upstream"
    elif ! git branch --unset-upstream; then
        echo "Error Unsetting-Upstream Warning"
        exit 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git add PKGBUILD .SRCINFO"
    elif ! git add PKGBUILD .SRCINFO; then
        echo "Error adding files to Git"
        exit 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git commit -m 'Initial release'"
    elif ! git commit -m "Initial release"; then
        echo "Error committing to Git"
        exit 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git branch -m main master && git push --set-upstream origin master"
    elif ! git branch -m main master && git push --set-upstream origin master; then
        echo "Error pushing to Git"
        exit 1
    fi
}

# Update the AUR package
update_aur_package() {
    # Check dependencies and SSH setup
    check_dependencies
    check_aur_ssh

    # Check if aur-packages directory exists
    if [ ! -d ~/aur-packages ]; then
        echo "Error: ~/aur-packages directory does not exist"
        exit 1
    fi

    # List all packages in the aur-packages directory
    echo "Available packages in aur-packages directory:"
    cd ~/aur-packages || exit
    mapfile -d '' -t packages < <(find . -mindepth 1 -maxdepth 1 -type d -printf '%f\0' 2>/dev/null)
    if [ ${#packages[@]} -eq 0 ]; then
        echo "No packages found in ~/aur-packages"
        exit 1
    fi
    # Reorder with last selected package first
    local last_selected_pkg ordered_packages=()
    last_selected_pkg=$(config_get last_selected_pkg)
    if [ -n "$last_selected_pkg" ]; then
        ordered_packages=("$last_selected_pkg")
        for p in "${packages[@]}"; do [ "$p" = "$last_selected_pkg" ] || ordered_packages+=("$p"); done
    else
        ordered_packages=("${packages[@]}")
    fi
    if [ ${#packages[@]} -gt 20 ]; then
        selected_package=$(printf "%s\n" "${ordered_packages[@]}" | gum filter --placeholder "Search packages...")
    else
        selected_package=$(printf "%s\n" "${ordered_packages[@]}" | gum choose --header "Select a package to update:")
    fi
    [ -z "$selected_package" ] && echo "No package selected" && return 1
    config_set last_selected_pkg "$selected_package"
    
    # Change to the selected package directory
    cd "$selected_package" || exit
    
    # Verify it's a valid AUR package
    if [ ! -f PKGBUILD ] || [ ! -f .SRCINFO ]; then
        echo "Error: Not a valid AUR package directory"
        return 1
    fi

    # Get current version from PKGBUILD
    current_version=$(grep "^pkgver=" PKGBUILD | cut -d'"' -f2)
    current_pkgrel=$(grep "^pkgrel=" PKGBUILD | cut -d'"' -f2)
    echo "Current version: $current_version"
    echo "Current pkgrel: $current_pkgrel"
    
    # Get new version from user (with validation loop)
    while true; do
        # Prefill with last used version from create flow if available
        local last_pkg_ver
        last_pkg_ver=$(config_get last_pkg_ver)
        if [ -n "$last_pkg_ver" ]; then
            if ! new_version=$(gum input --placeholder "0.0.1" --prompt "New version: " --value "$last_pkg_ver"); then
                echo "Cancelled."
                return 1
            fi
        else
            if ! new_version=$(gum input --placeholder "0.0.1" --prompt "New version: "); then
                echo "Cancelled."
                return 1
            fi
        fi
        if [ -z "$new_version" ]; then
            show_error "Version cannot be empty"
            continue
        fi
        if validate_package_version "$new_version"; then
            break
        else
            show_error "Invalid version. It must start with a number (e.g., 0.0.1)"
        fi
    done
    config_set last_pkg_ver "$new_version"

    # Update version in PKGBUILD
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Update pkgver to $new_version in PKGBUILD"
    else
        sed -i "s/^pkgver=.*/pkgver=\"$new_version\"/" PKGBUILD
    fi

    # If version hasn't changed, increment pkgrel
    if [ "$new_version" = "$current_version" ]; then
        new_pkgrel=$((current_pkgrel + 1))
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "[dry-run] Increment pkgrel to $new_pkgrel in PKGBUILD"
        else
            sed -i "s/^pkgrel=.*/pkgrel=\"$new_pkgrel\"/" PKGBUILD
        fi
        echo "Version unchanged, incrementing pkgrel to $new_pkgrel"
    else
        # Reset pkgrel to 1 for new versions
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "[dry-run] Reset pkgrel to 1 in PKGBUILD"
        else
            sed -i "s/^pkgrel=.*/pkgrel=\"1\"/" PKGBUILD
        fi
        echo "New version detected, resetting pkgrel to 1"
    fi

    # Update the AUR package
    echo "Updating AUR package..."
    if ! run_with_spinner "Generating .SRCINFO" bash -lc 'makepkg --printsrcinfo > .SRCINFO'; then
        echo "Error creating .SRCINFO file"
        exit 1
    fi

    # Test and clean the package
    if ! test_and_clean_package; then
        exit 1
    fi

    # Check if there are changes
    if git diff --quiet PKGBUILD .SRCINFO; then
        echo "No changes to commit"
        return 0
    fi

    # Display files and ask for confirmation
    echo -e "\n=== PKGBUILD ==="
    cat PKGBUILD | gum pager
    echo -e "\n=== .SRCINFO ==="
    cat .SRCINFO | gum pager
    echo -e "\n"
    if ! confirm_action "Push these changes to AUR?"; then
        echo "Aborting push to AUR"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git add PKGBUILD .SRCINFO"
    elif ! git add PKGBUILD .SRCINFO; then
        echo "Error adding files to Git"
        exit 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git commit -m 'Update package to version $new_version'"
    elif ! git commit -m "Update package to version $new_version"; then
        echo "Error committing to Git"
        exit 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] git push --set-upstream origin master"
    elif ! git push --set-upstream origin master; then
        echo "Error pushing to Git"
        exit 1
    fi
    echo "AUR package updated successfully to version $new_version"
}

# Run one-time setup wizard first (may install gum/namcap and explain them)
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Run one_time_setup_wizard"
else
    one_time_setup_wizard
fi

# Choose the action Create or Update using gum (after wizard ensures gum presence or user skipped)
if ! command -v gum >/dev/null 2>&1; then
    echo "Error: gum is required but not installed"
    exit 1
fi

# Persist last action and reorder accordingly
last_action=$(config_get last_action)
if [ "$last_action" = "Update AUR package" ]; then
    ACTION=$(printf "Update AUR package\nCreate AUR package\nExit" | gum choose --header "AUR Package Manager")
elif [ "$last_action" = "Create AUR package" ]; then
    ACTION=$(printf "Create AUR package\nUpdate AUR package\nExit" | gum choose --header "AUR Package Manager")
else
    ACTION=$(printf "Create AUR package\nUpdate AUR package\nExit" | gum choose --header "AUR Package Manager")
fi
case "$ACTION" in
    "Create AUR package")
        config_set last_action "$ACTION"
        create_aur_package
        ;;
    "Update AUR package")
        config_set last_action "$ACTION"
        update_aur_package
        ;;
    *)
        echo "Goodbye."
        ;;
esac