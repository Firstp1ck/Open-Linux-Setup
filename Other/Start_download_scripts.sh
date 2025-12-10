#!/usr/bin/env bash

set -euo pipefail

# Script: Start_download_scripts.sh
# Description: Download shell scripts from GitHub repositories

# Help function
print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Interactive tool to download shell scripts from GitHub repositories.
    Fetches public repositories, allows selection, and downloads .sh files.

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
            echo "Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
    esac
    # shellcheck disable=SC2317
    shift
done

# Dependencies check
missing_deps=()
for dep in jq curl gum; do
    if ! command -v "$dep" &>/dev/null; then
        missing_deps+=("$dep")
    fi
done
if (( ${#missing_deps[@]} > 0 )); then
    echo "Missing required dependencies: ${missing_deps[*]}"
    echo "Please install them and re-run."
    exit 1
fi

# 1) Ask for GitHub username using gum
GH_USER=$(gum input --prompt "GitHub username: " --placeholder "e.g. torvalds")
if [[ -z "$GH_USER" ]]; then
    echo "GitHub username is required."
    exit 1
fi

# 2) Fetch public repos with a spinner
REPO_JSON=$(gum spin --spinner line --title "Fetching public repositories for '$GH_USER'..." -- \
    curl -s "https://api.github.com/users/$GH_USER/repos?per_page=100")
REPOS=$(echo "$REPO_JSON" | jq -r '.[].name')

if [[ -z "$REPOS" ]]; then
    echo "No repositories found or user does not exist."
    exit 1
fi

# 3) Select repository via gum
REPO=$(printf "%s\n" "$REPOS" | gum filter --placeholder "Type to filter and select a repository" )
if [[ -z "$REPO" ]]; then
    echo "No repository selected."
    exit 1
fi

# 4) Get default branch and list .sh files
REPO_INFO=$(gum spin --spinner line --title "Fetching repository info for '$REPO'..." -- \
    curl -s "https://api.github.com/repos/$GH_USER/$REPO")
DEFAULT_BRANCH=$(echo "$REPO_INFO" | jq -r '.default_branch')

TREE_JSON=$(gum spin --spinner line --title "Scanning '$REPO' for .sh files (branch: $DEFAULT_BRANCH)..." -- \
    curl -s "https://api.github.com/repos/$GH_USER/$REPO/git/trees/$DEFAULT_BRANCH?recursive=1")
SH_FILES=$(echo "$TREE_JSON" | jq -r '.tree[] | select(.path | endswith(".sh")) | .path')

if [[ -z "$SH_FILES" ]]; then
    echo "No .sh scripts found in this repository."
    exit 1
fi

# 5) Multi-select scripts to download
mapfile -t SH_ARRAY <<< "$(printf "%s\n" "$SH_FILES" | \
    gum choose --no-limit --header "Select .sh scripts to download (Space to toggle, Enter to confirm)")"

if (( ${#SH_ARRAY[@]} == 0 )); then
    echo "No scripts selected."
    exit 1
fi

# 6) Choose action
ACTION=$(printf "%s\n" "Download only" "Download and execute" | gum choose --header "Choose action")
EXECUTE=false
if [[ "$ACTION" == "Download and execute" ]]; then
    EXECUTE=true
fi

# 7) Download (and optionally execute) selected scripts
for SCRIPT_PATH in "${SH_ARRAY[@]}"; do
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    RAW_URL="https://raw.githubusercontent.com/$GH_USER/$REPO/$DEFAULT_BRANCH/$SCRIPT_PATH"

    gum spin --spinner line --title "Downloading $SCRIPT_NAME" -- \
        curl -L -sS -o "$SCRIPT_NAME" "$RAW_URL"
    chmod +x "$SCRIPT_NAME"

    if $EXECUTE; then
        gum style --border normal --margin "1 0" --padding "0 1" --foreground 212 "Executing $SCRIPT_NAME..."
        ./"$SCRIPT_NAME"
    fi
done

gum style --border normal --margin "1 0" --padding "0 1" --foreground 82 "Done."