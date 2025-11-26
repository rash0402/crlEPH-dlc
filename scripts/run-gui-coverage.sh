#!/bin/bash
# Run EPH Coverage Experiment with optimized viewer

echo "=== Starting EPH Coverage Experiment ==="

# Cleanup function
cleanup() {
    echo -e "\n=== Cleaning up ==="
    if [ ! -z "$JULIA_PID" ]; then
        echo "Stopping Julia server (PID: $JULIA_PID)..."
        kill $JULIA_PID 2>/dev/null
    fi
    if [ ! -z "$VIEWER_PID" ]; then
        echo "Stopping viewer (PID: $VIEWER_PID)..."
        kill $VIEWER_PID 2>/dev/null
    fi
    exit 0
}

# Set trap for cleanup on Ctrl+C
trap cleanup SIGINT SIGTERM

# Start Julia EPH Server
echo "Starting Julia EPH Server..."
cd "$(dirname "$0")/.."
~/.juliaup/bin/julia --project=src_julia src_julia/main.jl &
JULIA_PID=$!
echo "Server PID: $JULIA_PID"

# Wait for server to initialize
sleep 3

# Start Python Coverage Viewer
echo "Starting Python Coverage Viewer..."
source ~/local/venv/bin/activate
export PYTHONPATH=.
python viewer_coverage.py &
VIEWER_PID=$!
echo "Viewer PID: $VIEWER_PID"

echo -e "\n=== Experiment Running ==="
echo "Server PID: $JULIA_PID"
echo "Viewer PID: $VIEWER_PID"
echo -e "\nPress Ctrl+C to stop both processes"

# Wait for user interrupt
wait
