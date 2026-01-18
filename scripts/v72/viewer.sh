#!/bin/bash
#
# Quick launcher for EPH v7.2 Raw Trajectory Viewer
#
# Usage:
#   ./scripts/run_viewer_v72.sh [file.h5]
#
# If no file is provided, file selection dialog will appear.
#

set -e

# Get script directory (project root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Python virtual environment
VENV_PYTHON="$HOME/local/venv/bin/python"

# Check if venv exists
if [ ! -f "$VENV_PYTHON" ]; then
    echo "Error: Python virtual environment not found at: $VENV_PYTHON"
    echo "Please create it or update the path in this script."
    exit 1
fi

# Change to project root
cd "$PROJECT_ROOT"

# Clear Python cache to ensure latest code is used
echo "Clearing Python cache..."
rm -rf "$PROJECT_ROOT/viewer/__pycache__"

# Launch viewer
echo "=================================================="
echo "  EPH v7.2 Raw Trajectory Viewer"
echo "=================================================="
echo ""

if [ -z "$1" ]; then
    echo "No file specified. File selection dialog will appear..."
    "$VENV_PYTHON" -B viewer/raw_viewer_v72.py
else
    FILE_PATH="$1"
    if [ ! -f "$FILE_PATH" ]; then
        echo "Error: File not found: $FILE_PATH"
        exit 1
    fi
    echo "Opening: $FILE_PATH"
    "$VENV_PYTHON" -B viewer/raw_viewer_v72.py --file "$FILE_PATH"
fi
