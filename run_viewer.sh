#!/bin/bash
# EPH Detail Viewer Launcher
# Uses the user-specified virtual environment at ~/local/venv

VENV_PYTHON=~/local/venv/bin/python

if [ ! -f "$VENV_PYTHON" ]; then
    echo "❌ Error: Virtual environment python not found at $VENV_PYTHON"
    exit 1
fi

echo "🚀 Starting EPH Detail Viewer..."
echo "   Using Python: $VENV_PYTHON"
echo "   Script: viewer/detail_viewer.py"
echo ""

$VENV_PYTHON viewer/detail_viewer.py
