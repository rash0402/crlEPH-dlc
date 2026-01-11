#!/bin/bash
# EPH v5.6 Visualization Launcher
# Starts EPH simulation with real-time visualization

# Get the project root directory (absolute path)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT" || exit 1

# --- Configuration ---
JULIA_CMD="julia --project=."
SIM_SCRIPT="scripts/run_simulation_eph.jl"
VENV_PYTHON=~/local/venv/bin/python
VIEWER_SCRIPT="viewer/detail_viewer.py"

# Simulation parameters (short test)
STEPS=300
DENSITY=10
HAZE=0.5

# --- Checks ---
if [ ! -f "$VENV_PYTHON" ]; then
    echo "❌ Error: Virtual environment python not found at $VENV_PYTHON"
    exit 1
fi

if [ ! -f "$SIM_SCRIPT" ]; then
    echo "❌ Error: Simulation script not found at $SIM_SCRIPT"
    exit 1
fi

if [ ! -f "$VIEWER_SCRIPT" ]; then
    echo "❌ Error: Viewer script not found at $VIEWER_SCRIPT"
    exit 1
fi

# --- Cleanup Function ---
cleanup() {
    echo ""
    echo "🛑 Stopping all processes..."
    if [ ! -z "$SIM_PID" ]; then
        kill "$SIM_PID" 2>/dev/null
    fi
    exit
}
trap cleanup SIGINT SIGTERM EXIT

# --- Execution ---
echo "============================================================"
echo "🚀 EPH v5.6 Visualization Launcher"
echo "============================================================"
echo "📂 Project Root: $PROJECT_ROOT"
echo "⚙️  Parameters: Steps=$STEPS, Density=$DENSITY, Haze=$HAZE"
echo ""

echo "▶️  Starting EPH Simulation with Visualization (Background)..."
$JULIA_CMD $SIM_SCRIPT \
    --visualize \
    --steps $STEPS \
    --density $DENSITY \
    --haze-fixed $HAZE \
    --lambda-goal 1.0 \
    --lambda-safety 5.0 \
    --lambda-surprise 1.0 &
SIM_PID=$!

echo "⏳ Waiting 10 seconds for simulation initialization..."
for i in {1..10}; do
    printf "▓"
    sleep 1
done
echo " Done!"
echo ""

echo "▶️  Starting Python Detail Viewer (Foreground)..."
echo "   (Using Python from: $VENV_PYTHON)"
$VENV_PYTHON $VIEWER_SCRIPT

# If viewer closes, wait for simulation or user interrupt
echo ""
echo "✅ Viewer closed. Simulation running in background (PID: $SIM_PID)."
echo "   Press Ctrl+C to stop simulation."
wait $SIM_PID
