#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${2}${1}${NC}"
}

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}=== $1 ===${NC}\n"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a package exists in official repositories
package_exists_in_repo() {
    pacman -Si "$1" >/dev/null 2>&1
}

# Function to check if a package exists in AUR
package_exists_in_aur() {
    if command_exists yay; then
        yay -Si "$1" >/dev/null 2>&1
    else
        return 1
    fi
}

# Function to install packages with pacman
install_with_pacman() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    print_message "Installing ${#packages[@]} packages with pacman..." "${BLUE}"
    print_message "Packages: ${packages[*]}" "${YELLOW}"
    
    if sudo pacman -S --needed --noconfirm "${packages[@]}"; then
        print_message "Successfully installed packages with pacman" "${GREEN}"
        return 0
    else
        print_message "Failed to install some packages with pacman" "${RED}"
        return 1
    fi
}

# Function to install packages with yay
install_with_yay() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    print_message "Installing ${#packages[@]} packages with yay..." "${BLUE}"
    print_message "Packages: ${packages[*]}" "${YELLOW}"
    
    if yay -S --needed --noconfirm "${packages[@]}"; then
        print_message "Successfully installed packages with yay" "${GREEN}"
        return 0
    else
        print_message "Failed to install some packages with yay" "${RED}"
        return 1
    fi
}

# Function to parse package file and categorize packages
parse_package_file() {
    local file="$1"
    local pacman_packages=()
    local aur_packages=()
    local unknown_packages=()
    
    print_section "Analyzing package file: $file"
    
    # Read the file and process each line
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Remove leading/trailing whitespace
        package=$(echo "$line" | xargs)
        
        if [[ -z "$package" ]]; then
            continue
        fi
        
        print_message "Checking package: $package" "${YELLOW}"
        
        # Check if package exists in official repositories
        if package_exists_in_repo "$package"; then
            pacman_packages+=("$package")
            print_message "  → Found in official repositories" "${GREEN}"
        # Check if package exists in AUR
        elif package_exists_in_aur "$package"; then
            aur_packages+=("$package")
            print_message "  → Found in AUR" "${BLUE}"
        else
            unknown_packages+=("$package")
            print_message "  → Not found in repositories or AUR" "${RED}"
        fi
    done < "$file"
    
    # Print summary
    print_section "Package Analysis Summary"
    print_message "Official repository packages: ${#pacman_packages[@]}" "${GREEN}"
    print_message "AUR packages: ${#aur_packages[@]}" "${BLUE}"
    print_message "Unknown packages: ${#unknown_packages[@]}" "${RED}"
    
    if [ ${#unknown_packages[@]} -gt 0 ]; then
        print_message "Unknown packages:" "${RED}"
        for pkg in "${unknown_packages[@]}"; do
            print_message "  - $pkg" "${RED}"
        done
    fi
    
    # Store results in global arrays
    PACMAN_PACKAGES=("${pacman_packages[@]}")
    AUR_PACKAGES=("${aur_packages[@]}")
    UNKNOWN_PACKAGES=("${unknown_packages[@]}")
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $(basename "$0") [options] <package_file>

Install packages from a text file using pacman and yay.

Arguments:
  package_file    Path to text file containing package names (one per line)

Options:
  --dry-run       Show what would be installed without actually installing
  --pacman-only   Only install packages from official repositories
  --aur-only      Only install packages from AUR
  --skip-unknown  Skip packages not found in any repository
  --help, -h      Show this help message

Examples:
  $(basename "$0") user_installed_packages_2025-05-24.txt
  $(basename "$0") --dry-run packages.txt
  $(basename "$0") --pacman-only packages.txt

Package file format:
  - One package name per line
  - Lines starting with # are treated as comments
  - Empty lines are ignored
EOF
}

# Main function
main() {
    local dry_run=false
    local pacman_only=false
    local aur_only=false
    local skip_unknown=false
    local package_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --pacman-only)
                pacman_only=true
                shift
                ;;
            --aur-only)
                aur_only=true
                shift
                ;;
            --skip-unknown)
                skip_unknown=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                print_message "Unknown option: $1" "${RED}"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$package_file" ]]; then
                    package_file="$1"
                else
                    print_message "Multiple package files specified. Only one is allowed." "${RED}"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if package file is provided
    if [[ -z "$package_file" ]]; then
        print_message "Error: Package file is required" "${RED}"
        show_usage
        exit 1
    fi
    
    # Check if package file exists
    if [[ ! -f "$package_file" ]]; then
        print_message "Error: Package file '$package_file' not found" "${RED}"
        exit 1
    fi
    
    # Check for required commands
    if ! command_exists pacman; then
        print_message "Error: pacman is required but not installed" "${RED}"
        exit 1
    fi
    
    if ! command_exists yay && [[ "$aur_only" == false ]]; then
        print_message "Warning: yay is not installed. AUR packages will be skipped." "${YELLOW}"
        aur_only=true
    fi
    
    # Check for sudo access
    if ! sudo -n true 2>/dev/null; then
        print_message "This script requires sudo access for package installation." "${YELLOW}"
        print_message "Please run with sudo or ensure you have passwordless sudo configured." "${YELLOW}"
        exit 1
    fi
    
    print_section "Package Installation Script"
    print_message "Package file: $package_file" "${BLUE}"
    print_message "Dry run: $dry_run" "${BLUE}"
    print_message "Pacman only: $pacman_only" "${BLUE}"
    print_message "AUR only: $aur_only" "${BLUE}"
    print_message "Skip unknown: $skip_unknown" "${BLUE}"
    
    # Parse the package file
    parse_package_file "$package_file"
    
    # Handle unknown packages
    if [ ${#UNKNOWN_PACKAGES[@]} -gt 0 ] && [[ "$skip_unknown" == false ]]; then
        print_message "Found ${#UNKNOWN_PACKAGES[@]} unknown packages. These will be skipped." "${YELLOW}"
        print_message "Use --skip-unknown to suppress this message." "${YELLOW}"
    fi
    
    # Install packages
    local install_success=true
    
    if [[ "$dry_run" == true ]]; then
        print_section "Dry Run - Installation Preview"
        if [[ "$aur_only" == false ]] && [ ${#PACMAN_PACKAGES[@]} -gt 0 ]; then
            print_message "Would install with pacman: ${PACMAN_PACKAGES[*]}" "${GREEN}"
        fi
        if [[ "$pacman_only" == false ]] && [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
            print_message "Would install with yay: ${AUR_PACKAGES[*]}" "${BLUE}"
        fi
    else
        # Install pacman packages
        if [[ "$aur_only" == false ]] && [ ${#PACMAN_PACKAGES[@]} -gt 0 ]; then
            if ! install_with_pacman "${PACMAN_PACKAGES[@]}"; then
                install_success=false
            fi
        fi
        
        # Install AUR packages
        if [[ "$pacman_only" == false ]] && [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
            if ! install_with_yay "${AUR_PACKAGES[@]}"; then
                install_success=false
            fi
        fi
    fi
    
    # Final summary
    print_section "Installation Summary"
    if [[ "$dry_run" == true ]]; then
        print_message "Dry run completed successfully" "${GREEN}"
    else
        if [[ "$install_success" == true ]]; then
            print_message "Package installation completed successfully" "${GREEN}"
        else
            print_message "Some packages failed to install. Check the output above for details." "${RED}"
            exit 1
        fi
    fi
    
    print_message "Total packages processed: $((${#PACMAN_PACKAGES[@]} + ${#AUR_PACKAGES[@]} + ${#UNKNOWN_PACKAGES[@]}))" "${BLUE}"
    print_message "Official repository packages: ${#PACMAN_PACKAGES[@]}" "${GREEN}"
    print_message "AUR packages: ${#AUR_PACKAGES[@]}" "${BLUE}"
    print_message "Unknown packages: ${#UNKNOWN_PACKAGES[@]}" "${RED}"
}

# Run main function with all arguments
main "$@"
