#!/bin/bash

# check.sh - Syntax check and lint for ansible-log.sh

set -euo pipefail

SCRIPT_FILE="ansible-log.sh"

echo "=== Checking $SCRIPT_FILE ==="
echo

# Check if file exists
if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo "Error: $SCRIPT_FILE not found"
    exit 1
fi

# Basic syntax check
echo "1. Running bash syntax check..."
if bash -n "$SCRIPT_FILE"; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax check failed"
    exit 1
fi

echo

# ShellCheck if available
echo "2. Running ShellCheck..."
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$SCRIPT_FILE"; then
        echo "✓ ShellCheck passed"
    else
        echo "✗ ShellCheck found issues"
        exit 1
    fi
else
    echo "⚠ ShellCheck not available (install with: apt install shellcheck)"
fi

echo

# Test basic functionality
echo "3. Testing basic functionality..."
if ./"$SCRIPT_FILE" help >/dev/null 2>&1; then
    echo "✓ Basic functionality test passed"
else
    echo "✗ Basic functionality test failed"
    exit 1
fi

echo
echo "All checks passed! ✓"