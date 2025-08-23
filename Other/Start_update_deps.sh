#!/usr/bin/env bash

# Description: Check which packages have updates available and show what depends on them

echo "Checking for available updates and their dependencies..."
echo "======================================================="
echo

# Get list of packages that have updates available
updates=$(checkupdates 2>/dev/null)

# Check if checkupdates returned any results
if [ -z "$updates" ]; then
    echo "No updates available."
    exit 0
fi

# Process each package that has an update
echo "$updates" | while read -r line; do
    # Extract package name from checkupdates output (format: "package old_version -> new_version")
    package_name=$(echo "$line" | awk '{print $1}')
    
    if [ -n "$package_name" ]; then
        echo "Package: $package_name"
        echo "Update: $line"
        
        # Get package info and grep for "Benötigt von" (Required By in German)
        required_by=$(pacman -Qi "$package_name" 2>/dev/null | grep "Benötigt von")
        
        if [ -n "$required_by" ]; then
            echo "$required_by"
        else
            echo "Benötigt von        : Keine"
        fi
        echo "---"
    fi
done

echo
echo "Script completed."