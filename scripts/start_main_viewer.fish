#!/usr/bin/env fish
# EPH Main Viewer Launcher (Fish shell)
# Starts Python main viewer (4-group display)

set SCRIPT_DIR (realpath (dirname (status -f)))
set PROJECT_DIR (dirname $SCRIPT_DIR)

echo "============================================================"
echo "EPH Main Viewer Launcher"
echo "============================================================"
echo ""
echo "📂 Project: $PROJECT_DIR"
echo ""

# Check if Python venv exists
set PYTHON_BIN "$HOME/local/venv/bin/python"
if not test -f $PYTHON_BIN
    echo "❌ Error: Python venv not found at ~/local/venv"
    echo "   Please create venv and install dependencies:"
    echo "   pip install -r requirements.txt"
    exit 1
end

echo "✅ Python found: "($PYTHON_BIN --version)
echo ""

# Check if backend is running
echo "⚠️  Make sure Julia backend is running first!"
echo "   (Terminal 1: ./scripts/start_backend.fish)"
echo ""

# Run viewer
echo "🎨 Starting main viewer..."
echo "   Close window to exit"
echo ""

cd $PROJECT_DIR
exec $PYTHON_BIN viewer/main_viewer.py
