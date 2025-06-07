#!/bin/bash

# Check for required dependencies
check_dependencies() {
    local deps=("git" "curl" "makepkg" "namcap")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Error: $dep is required but not installed"
            exit 1
        fi
    done
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
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 aur@aur.archlinux.org help > /dev/null 2>&1; then
        echo "Error: SSH key not set up for AUR. Please set up your SSH key first."

        # Check if aur_ed25519 key exists, if not, offer to generate or choose
        if [ ! -f ~/.ssh/aur_ed25519 ]; then
            read -rp "It seems you don't have an 'aur_ed25519' key. Do you want to (g)enerate a new one or (c)hoose an existing key from ~/.ssh/? (g/c): " key_option
            if [[ "$key_option" =~ ^[Gg]$ ]]; then
                read -rp "Enter your email for the SSH key comment (e.g., your_email@example.com): " user_email
                echo "Generating SSH key. You will be prompted to enter a passphrase."
                ssh-keygen -t ed25519 -C "$user_email" -f ~/.ssh/aur_ed25519
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to generate SSH key."
                    exit 1
                fi
                echo "SSH key generated successfully at ~/.ssh/aur_ed25519"
                SELECTED_KEY_FILE="aur_ed25519"
            elif [[ "$key_option" =~ ^[Cc]$ ]]; then
                echo "Available public keys in ~/.ssh/:"
                mapfile -t ssh_keys < <(find ~/.ssh/ -maxdepth 1 -name "*.pub" -printf '%f\n' | sed 's/\.pub$//')

                if [ ${#ssh_keys[@]} -eq 0 ]; then
                    echo "No public keys found in ~/.ssh/. Please generate a new key."
                    exit 1
                fi

                for i in "${!ssh_keys[@]}"; do
                    echo "$((i+1)). ${ssh_keys[$i]}"
                done

                read -rp "Enter the number of the key you want to use: " key_selection
                if ! [[ "$key_selection" =~ ^[0-9]+$ ]] || [ "$key_selection" -lt 1 ] || [ "$key_selection" -gt "${#ssh_keys[@]}" ]; then
                    echo "Invalid selection."
                    exit 1
                fi
                SELECTED_KEY_FILE="${ssh_keys[$((key_selection-1))]}"
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
        cat ~/.ssh/"${SELECTED_KEY_FILE}".pub
        read -rp "Do you want to create the config for the AUR SSH Setup (Y/n): " ssh_setup
        if [[ "$ssh_setup" =~ ^[Yy]$ ]]; then
            mkdir -p ~/.ssh # Ensure .ssh directory exists
            # Navigate to ~/.ssh only if we are creating config. Otherwise, stay in current dir.
            (cd ~/.ssh || exit
            cat <<EOF > config
Host aur
    HostName aur.archlinux.org
    User aur
    IdentityFile ~/.ssh/${SELECTED_KEY_FILE}
EOF
            ) # End of subshell

            # Re-check SSH connection after creating config
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
    # Check package with namcap
    echo "Checking package with namcap..."
    if ! namcap PKGBUILD; then
        echo "Warning: namcap found issues with the package, but continuing..."
    fi

    # Test the package build and installation
    echo "Testing package build and installation..."
    if ! makepkg -fsi --skippgpcheck; then
        echo "Error: Package build or installation failed. Please check the PKGBUILD file."
        return 1
    fi

    # Clean build files after successful test
    echo "Cleaning build files..."
    if ! makepkg -fc; then
        echo "Warning: Failed to clean build files, but continuing..."

        # Ask user if they want to perform a complete cleanup
        read -rp "Do you want to perform a complete cleanup of the local repository? (y/n): " cleanup_choice
        if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
            echo "Performing complete cleanup..."
            echo "Removing build files..."
            rm -rf src/ pkg/ *.pkg.tar.zst *.tar.gz

            echo "Removing git files..."
            rm -rf .git/ .gitignore

            echo "Removing the source directory..."
            rm -rf "$(basename "$PWD")"
            
            echo "Cleanup completed successfully."
        else
            echo "Skipping complete cleanup."
        fi
    fi
    return 0
}

create_aur_package() {
    # Check dependencies and SSH setup
    check_dependencies
    check_aur_ssh

    # Create a new AUR package
    read -rp "Enter the name of the package: " PKG_NAME
    if ! validate_package_name "$PKG_NAME"; then
        exit 1
    fi
    read -rp "Enter the version of the package (e.g 0.0.1): " PKG_VER
    if ! validate_package_version "$PKG_VER"; then
        exit 1
    fi
    read -rp "Enter the description of the package: " PKG_DESC
    read -rp "Enter the URL of the Git package (e.g. 'https://github.com/USER_NAME/REPO_NAME.git'): " PKG_URL
    read -rp "Enter the license of the package (e.g. GLP3 or MIT): " PKG_LICENSE
    read -rp "Enter the dependencies of the package (space-separated): " PKG_DEPENDS
    read -rp "Enter the architecture (e.g any or x86_64): " PKG_ARCH

    # Validate URL
    if ! curl --output /dev/null --silent --head --fail "$PKG_URL"; then
        echo "Error: Invalid URL"
        exit 1
    fi

    # Change to aur-packages directory
    cd ~/aur-packages || exit

    # Check if package already exists
    if [ -d "$PKG_NAME" ]; then
        echo "Error: Package directory already exists"
        exit 1
    fi

    # Clone the AUR repository
    echo "Cloning AUR repository..."
    if ! git clone ssh://aur@aur.archlinux.org/"$PKG_NAME".git; then
        echo "Error cloning AUR repository"
        exit 1
    fi
    cd "$PKG_NAME" || exit

    # Check for setup.sh in the source repository
    echo "Checking for setup.sh in the source repository..."
    if ! curl --output /dev/null --silent --head --fail "$PKG_URL"; then
        echo "Error: Invalid URL"
        exit 1
    fi

    # Clone the repository temporarily to check for setup.sh
    temp_dir=$(mktemp -d)
    if ! git clone "$PKG_URL" "$temp_dir"; then
        echo "Error: Could not clone the repository"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Check for setup.sh in the repository
    setup_found=false
    if [ -f "$temp_dir/setup.sh" ]; then
        setup_found=true
    else
        # Check one level deep
        for dir in "$temp_dir"/*/; do
            if [ -f "${dir}setup.sh" ]; then
                setup_found=true
                break
            fi
        done
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"

    if [ "$setup_found" = false ]; then
        echo "Error: setup.sh not found in main directory or one level deep"
        exit 1
    fi

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
    
    # Find and install setup.sh
    if [ -f "setup.sh" ]; then
        # If setup.sh is in root directory
        install -Dm755 "setup.sh" "\$pkgdir/usr/bin/$PKG_NAME"
    else
        # Look in subdirectories
        for dir in */; do
            if [ -f "\${dir}setup.sh" ]; then
                install -Dm755 "\${dir}setup.sh" "\$pkgdir/usr/bin/$PKG_NAME"
                break
            fi
        done
    fi
}

post_install() {
    echo "==> Run '$PKG_NAME' to start the Hyprland setup."
}
EOF

    # Create the .SRCINFO file
    echo "Creating .SRCINFO file..."
    if ! makepkg --printsrcinfo > .SRCINFO; then
        echo "Error creating .SRCINFO file"
        exit 1
    fi

    # Test and clean the package
    if ! test_and_clean_package; then
        exit 1
    fi

    # Display files and ask for confirmation
    echo -e "\n=== PKGBUILD ==="
    cat PKGBUILD
    echo -e "\n=== .SRCINFO ==="
    cat .SRCINFO
    echo -e "\n"
    read -rp "Do you want to push these changes to AUR? (y/n): " confirm_push
    if [[ ! "$confirm_push" =~ ^[Yy]$ ]]; then
        echo "Aborting push to AUR"
        exit 0
    fi

    # Setup Git Repository
    echo "Setting up Git Repository"
    if ! echo -e "*\n!.SRCINFO\n!PKGBUILD" > .gitignore; then
        echo "Error creating .gitignore file"
        exit 1
    fi
    if ! git branch --unset-upstream; then
        echo "Error Unsetting-Upstream Warning"
        exit 1
    fi

    if ! git add PKGBUILD .SRCINFO; then
        echo "Error adding files to Git"
        exit 1
    fi
    if ! git commit -m "Initial release"; then
        echo "Error committing to Git"
        exit 1
    fi
    if ! git branch -m main master && git push --set-upstream origin master; then
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
    mapfile -t packages < <(ls -d ./*/)
    
    if [ ${#packages[@]} -eq 0 ]; then
        echo "No packages found in ~/aur-packages"
        exit 1
    fi
    
    # Display numbered list of packages
    for i in "${!packages[@]}"; do
        echo "$((i+1)). ${packages[$i]%/}"
    done
    
    # Get user selection
    read -rp "Enter the number of the package to update: " selection
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#packages[@]}" ]; then
        echo "Invalid selection"
        return 1
    fi
    
    # Get selected package name
    selected_package="${packages[$((selection-1))]%/}"
    
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
    
    # Get new version from user
    read -rp "Enter the new version (e.g. 0.0.1): " new_version
    if ! validate_package_version "$new_version"; then
        exit 1
    fi

    # Update version in PKGBUILD
    sed -i "s/^pkgver=.*/pkgver=\"$new_version\"/" PKGBUILD

    # If version hasn't changed, increment pkgrel
    if [ "$new_version" = "$current_version" ]; then
        new_pkgrel=$((current_pkgrel + 1))
        sed -i "s/^pkgrel=.*/pkgrel=\"$new_pkgrel\"/" PKGBUILD
        echo "Version unchanged, incrementing pkgrel to $new_pkgrel"
    else
        # Reset pkgrel to 1 for new versions
        sed -i "s/^pkgrel=.*/pkgrel=\"1\"/" PKGBUILD
        echo "New version detected, resetting pkgrel to 1"
    fi

    # Update the AUR package
    echo "Updating AUR package..."
    if ! makepkg --printsrcinfo > .SRCINFO; then
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
    cat PKGBUILD
    echo -e "\n=== .SRCINFO ==="
    cat .SRCINFO
    echo -e "\n"
    read -rp "Do you want to push these changes to AUR? (y/n): " confirm_push
    if [[ ! "$confirm_push" =~ ^[Yy]$ ]]; then
        echo "Aborting push to AUR"
        return 0
    fi

    if ! git add PKGBUILD .SRCINFO; then
        echo "Error adding files to Git"
        exit 1
    fi
    if ! git commit -m "Update package to version $new_version"; then
        echo "Error committing to Git"
        exit 1
    fi
    if ! git push --set-upstream origin master; then
        echo "Error pushing to Git"
        exit 1
    fi
    echo "AUR package updated successfully to version $new_version"
}

# Choose the action Create or Update
read -rp "Do you want to create or update an AUR package? (c/u): " CREATE_PKG
if [ "$CREATE_PKG" == "c" ]; then
    create_aur_package
elif [ "$CREATE_PKG" == "u" ]; then
    update_aur_package
else
    echo "Invalid option"
fi