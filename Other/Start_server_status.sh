#!/bin/bash

# Define the services to check
services=("nginx" "xrdp" "docker" "NetworkManager.service")

# Initialize a flag to track overall status
all_ok=true

echo "Starting service status checks..."

# Check if systemd is available
if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl is not available. This script requires systemd."
    exit 1
fi

# Loop through each service and check its status
for service in "${services[@]}"; do
    echo "----------------------------------------"
    echo "Checking $service..."
    
    # Check if the service exists
    if ! systemctl list-unit-files "${service}" >/dev/null 2>&1; then
        echo "$service is not installed - skipping."
        continue
    fi

    echo "Checking status of $service..."
    # Check if the service is active
    if sudo systemctl is-active --quiet "$service"; then
        echo "$service is running."
    else
        echo "$service is NOT running."
        all_ok=false
    fi
done

echo "----------------------------------------"
echo "Testing nginx configuration..."

# Check if nginx is installed before testing configuration
if command -v nginx >/dev/null 2>&1; then
    if sudo nginx -t; then
        echo "Nginx configuration test PASSED."
    else
        echo "Nginx configuration test FAILED."
        all_ok=false
    fi
else
    echo "Nginx is not installed - skipping configuration test."
fi

echo "----------------------------------------"

# Final summary
if $all_ok; then
    echo "All installed services are running properly."
else
    echo "Some services have issues. Please review the above messages."
fi

echo -e "\nPress Enter to exit..."
read -r

exit 0