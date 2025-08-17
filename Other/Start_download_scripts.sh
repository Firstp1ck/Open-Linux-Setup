#!/usr/bin/env bash

set -e

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# 1. Get GitHub username
read -rp "Enter GitHub username: " GH_USER

# 2. List public repos
echo "Fetching public repositories for user '$GH_USER'..."
REPOS=$(curl -s "https://api.github.com/users/$GH_USER/repos?per_page=100" | jq -r '.[].name')

if [[ -z "$REPOS" ]]; then
    echo "No repositories found or user does not exist."
    exit 1
fi

echo "Available repositories:"
select REPO in $REPOS; do
    [[ -n "$REPO" ]] && break
    echo "Invalid selection."
done

# 3. List .sh files in the selected repo (from default branch)
echo "Fetching .sh scripts from repository '$REPO'..."
# Get default branch
DEFAULT_BRANCH=$(curl -s "https://api.github.com/repos/$GH_USER/$REPO" | jq -r '.default_branch')
# Get all .sh files (recursively)
SH_FILES=$(curl -s "https://api.github.com/repos/$GH_USER/$REPO/git/trees/$DEFAULT_BRANCH?recursive=1" | jq -r '.tree[] | select(.path | endswith(".sh")) | .path')

if [[ -z "$SH_FILES" ]]; then
    echo "No .sh scripts found in this repository."
    exit 1
fi

echo "Available .sh scripts:"
mapfile -t SH_ARRAY <<< "$SH_FILES"
for i in "${!SH_ARRAY[@]}"; do
    printf "%3d) %s\n" $((i+1)) "${SH_ARRAY[$i]}"
done

read -rp "Enter the numbers of the scripts to download (e.g. 1 2 3): " -a SCRIPT_NUMS

# 4. Ask download or download+execute
read -rp "Download only (d) or download and execute (e)? [d/e]: " ACTION

for NUM in "${SCRIPT_NUMS[@]}"; do
    IDX=$((NUM-1))
    SCRIPT_PATH="${SH_ARRAY[$IDX]}"
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    RAW_URL="https://raw.githubusercontent.com/$GH_USER/$REPO/$DEFAULT_BRANCH/$SCRIPT_PATH"
    echo "Downloading $SCRIPT_NAME..."
    curl -s -o "$SCRIPT_NAME" "$RAW_URL"
    chmod +x "$SCRIPT_NAME"
    if [[ "$ACTION" == "e" ]]; then
        echo "Executing $SCRIPT_NAME..."
        ./"$SCRIPT_NAME"
    fi
done

echo "Done."