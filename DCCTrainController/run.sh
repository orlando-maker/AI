#!/bin/bash
# DCC Train Layout Controller — macOS launcher
# Double-click this file in Finder, or run it from Terminal.

set -e
cd "$(dirname "$0")"

# Install Python 3 via Homebrew if missing
if ! command -v python3 &>/dev/null; then
    echo "Python 3 not found. Install it from https://python.org or run: brew install python"
    exit 1
fi

# Create a virtual environment the first time
if [ ! -d ".venv" ]; then
    echo "Setting up virtual environment (one time only)..."
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install / update dependencies quietly
pip install -q -r requirements.txt

echo ""
echo "  Starting DCC Train Layout Controller..."
echo ""

python3 -m src.main "$@"
