#!/usr/bin/env bash

# Script to check Pi-hole functionality using Charmbracelet gum TUI

# Ensure gum is installed
if ! command -v gum >/dev/null 2>&1; then
    echo "gum is required for this script. Install from: https://github.com/charmbracelet/gum"
    exit 2
fi

# Title
gum format -t markdown "# Pi-hole Tests"

# Initialize variables to track test status
pihole_test=0
flurry_test=0

# Section: DNS Resolution
gum style --border normal --margin "1 2" --padding "0 1" "Testing Pi-hole DNS Resolution"
if gum spin --spinner dot --title "Checking pi.hole DNS" -- bash -lc 'nslookup pi.hole >/dev/null 2>&1'; then
    gum style --foreground green "✓ pi.hole resolution successful"
    pihole_test=1
else
    gum style --foreground red "✗ pi.hole resolution failed"
fi

# Section: Ad Blocking
gum style --border normal --margin "1 2" --padding "0 1" "Testing Pi-hole Ad Blocking"
if gum spin --spinner dot --title "Checking flurry.com blocking" -- bash -lc 'nslookup flurry.com 2>/dev/null | grep -Eq "0\\.0\\.0\\.0|NXDOMAIN|refused"'; then
    gum style --foreground green "✓ flurry.com properly blocked"
    flurry_test=1
else
    gum style --foreground red "✗ flurry.com not blocked"
fi

# Results
gum style --border rounded --margin "1 2" --padding "1 2" "Test Results"
if [ "$pihole_test" -eq 1 ]; then
    gum style --foreground green -- "- Pi-hole DNS: PASS"
else
    gum style --foreground red -- "- Pi-hole DNS: FAIL"
fi

if [ "$flurry_test" -eq 1 ]; then
    gum style --foreground green -- "- Ad Blocking: PASS"
else
    gum style --foreground red -- "- Ad Blocking: FAIL"
fi

# Final status and exit
if [ $pihole_test -eq 1 ] && [ $flurry_test -eq 1 ]; then
    gum style --border double --padding "1 2" --foreground green "All tests PASSED!"
    gum input --placeholder "Press Enter to exit..." >/dev/null
    exit 0
else
    gum style --border double --padding "1 2" --foreground red "Some tests FAILED!"
    gum input --placeholder "Press Enter to exit..." >/dev/null
    exit 1
fi