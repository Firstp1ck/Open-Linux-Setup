#!/bin/bash

# Script to check Pi-hole functionality
echo "=== Starting Pi-hole Tests ==="

# Initialize variables to track test status
pihole_test=0
flurry_test=0

echo -e "\n=== Testing Pi-hole DNS Resolution ==="
echo "Checking pi.hole..."
if nslookup pi.hole > /dev/null 2>&1; then
    echo "✓ pi.hole resolution successful"
    pihole_test=1
else
    echo "✗ pi.hole resolution failed"
fi

echo -e "\n=== Testing Pi-hole Ad Blocking ==="
echo "Checking flurry.com..."
if nslookup flurry.com | grep -q "0.0.0.0\|NXDOMAIN\|refused"; then
    echo "✓ flurry.com properly blocked"
    flurry_test=1
else
    echo "✗ flurry.com not blocked"
fi

echo -e "\n=== Test Results ==="
if [ $pihole_test -eq 1 ] && [ $flurry_test -eq 1 ]; then
    echo "✅ All tests PASSED!"
    echo -e "\nPress Enter to exit..."
    read -r
    exit 0
else
    echo "❌ Some tests FAILED!"
    echo -e "\nPress Enter to exit..."
    read -r
    exit 1
fi