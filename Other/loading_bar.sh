#!/bin/bash

# Loading Bar Emulator Script
# This script displays a visual loading bar that progresses over time

# Function to display the loading bar
display_loading_bar() {
    local total_steps=10
    local current_step=0
    
    # Clear screen and set up terminal
    clear
    echo "Loading Bar Emulator"
    echo "Press Ctrl+C to stop"
    echo ""
    
    while [ $current_step -le $total_steps ]; do
        # Calculate the number of '#' characters based on progress (using integer arithmetic)
        local filled=$((current_step * 10 / total_steps))
        local bar="["
        
        # Build the progress bar string
        for ((i=0; i<10; i++)); do
            if [ $i -lt $filled ]; then
                bar="${bar}#"
            else
                bar="${bar}-"
            fi
        done
        bar="${bar}]"
        
        # Display the progress bar with percentage (using integer arithmetic)
        local percent=$((current_step * 100 / total_steps))
        echo -ne "\r$bar $percent%"
        
        # Sleep for a short time to simulate progress
        sleep 0.3
        
        # Increment the step counter
        current_step=$((current_step + 1))
    done
    
    echo ""
    echo "Loading complete!"
}

# Main execution
display_loading_bar
