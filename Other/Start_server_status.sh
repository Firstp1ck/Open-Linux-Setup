#!/bin/bash

# Services to check
services=("nginx" "xrdp" "docker" "NetworkManager.service")

# Requirements checks
if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required (systemd)." >&2
    exit 1
fi

if ! command -v gum >/dev/null 2>&1; then
    echo "This script requires 'gum'. Install from https://github.com/charmbracelet/gum and re-run." >&2
    exit 1
fi

all_ok=true
rows=()

# Header
gum style \
    --border normal \
    --margin ". 1" \
    --padding "1 2" \
    --border-foreground 63 \
    "Service Status Checks"

# Helper: does unit exist
unit_exists() {
    local unit="$1"
    local state
    state=$(systemctl show -p LoadState --value "$unit" 2>/dev/null || true)
    [[ "$state" == "loaded" ]]
}

# Check services
for service in "${services[@]}"; do
    # Quick spinner to indicate progress
    gum spin --spinner dot --title "Checking ${service}" -- sleep 0.1

    if ! unit_exists "$service"; then
        status=$(gum style --foreground 214 "not installed")
        note="skipped"
        rows+=("${service}\t${status}\t${note}")
        continue
    fi

    if systemctl is-active --quiet "$service"; then
        status=$(gum style --foreground 42 "running")
        note="active"
    else
        status=$(gum style --foreground 196 "not running")
        note="inactive"
        all_ok=false
    fi

    rows+=("${service}\t${status}\t${note}")
done

# Nginx config test
gum style --margin "1 ." --foreground 99 "Testing nginx configuration..."
if command -v nginx >/dev/null 2>&1; then
    if gum spin --spinner pulse --title "nginx -t" -- sudo nginx -t >/tmp/nginx_test.out 2>&1; then
        rows+=("nginx.conf\t$(gum style --foreground 42 PASSED)\tconfiguration valid")
    else
        rows+=("nginx.conf\t$(gum style --foreground 196 FAILED)\tsee /tmp/nginx_test.out")
        all_ok=false
    fi
else
    rows+=("nginx\t$(gum style --foreground 214 missing)\tnginx not installed")
fi

# Results table
printf '%s\n' "${rows[@]}" | \
    gum table \
        --print \
        --separator $'\t' \
        --columns "Service,Status,Notes"

# Summary
echo
if $all_ok; then
    gum style \
        --border rounded \
        --border-foreground 42 \
        --padding "0 2" \
        --foreground 42 \
        "All installed services are running properly."
else
    gum style \
        --border rounded \
        --border-foreground 196 \
        --padding "0 2" \
        --foreground 196 \
        "Some services have issues. Review the table above."
fi

# Wait for user
gum input --placeholder "Press Enter to exit" >/dev/null

exit 0