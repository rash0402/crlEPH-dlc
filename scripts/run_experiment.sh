#!/bin/bash
set -e

echo "=== Starting AI-DLC Experiment ==="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Add Julia to PATH
export PATH="$HOME/.juliaup/bin:$PATH"

# Activate Python virtual environment
source ~/local/venv/bin/activate

cd "$PROJECT_DIR"

# Start Julia Server in background
echo "Starting Julia EPH Server..."
julia src_julia/main.jl &
SERVER_PID=$!

# Wait for server to initialize
sleep 3

# Start Python Viewer
echo "Starting Python EPH Viewer..."
export PYTHONPATH=.
python viewer.py &
VIEWER_PID=$!

echo ""
echo "=== Experiment Running ==="
echo "Server PID: $SERVER_PID"
echo "Viewer PID: $VIEWER_PID"
echo ""
echo "Press Ctrl+C to stop both processes"

# Trap to kill both processes on exit
trap "echo 'Stopping...'; kill $SERVER_PID $VIEWER_PID 2>/dev/null; exit" INT TERM

# Wait for viewer to exit
wait $VIEWER_PID

# Kill server when viewer exits
kill $SERVER_PID 2>/dev/null

echo "Experiment stopped."
