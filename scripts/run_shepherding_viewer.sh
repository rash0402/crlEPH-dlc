#!/bin/bash
#
# Shepherding Experiment Viewer Runner (Phase 4)
# Runs real-time shepherding simulation with visualization
#
# Usage:
#   ./scripts/run_shepherding_viewer.sh [OPTIONS]
#
# Options:
#   --n-sheep NUM       羊の数（デフォルト: 5）
#   --steps NUM         シミュレーションステップ数（デフォルト: 1000）
#   --world-size NUM    ワールドサイズ（デフォルト: 400）
#   --seed NUM          乱数シード（デフォルト: 42）
#

set -e  # Exit on error

# Default parameters
N_SHEEP=5
STEPS=1000
WORLD_SIZE=400
SEED=42

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --n-sheep)
            N_SHEEP="$2"
            shift 2
            ;;
        --steps)
            STEPS="$2"
            shift 2
            ;;
        --world-size)
            WORLD_SIZE="$2"
            shift 2
            ;;
        --seed)
            SEED="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--n-sheep NUM] [--steps NUM] [--world-size NUM] [--seed NUM]"
            exit 1
            ;;
    esac
done

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Phase 4 Shepherding Visualization                          ║${NC}"
echo -e "${BLUE}║  Real-time ZeroMQ Viewer                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}設定:${NC}"
echo -e "  羊の数:           ${GREEN}${N_SHEEP}${NC}"
echo -e "  シミュレーション:  ${GREEN}${STEPS}${NC} steps"
echo -e "  ワールドサイズ:    ${GREEN}${WORLD_SIZE}${NC} × ${GREEN}${WORLD_SIZE}${NC}"
echo -e "  乱数シード:        ${GREEN}${SEED}${NC}"
echo ""

# Check Julia
if ! command -v ~/.juliaup/bin/julia &> /dev/null; then
    echo -e "${RED}✗ Error: Julia not found at ~/.juliaup/bin/julia${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Julia: $(~/.juliaup/bin/julia --version)${NC}"

# Check Python venv
if [ ! -d ~/local/venv ]; then
    echo -e "${RED}✗ Error: Python venv not found at ~/local/venv${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python venv found${NC}"

# Check main_shepherding.jl
MAIN_SCRIPT="$PROJECT_ROOT/src_julia/main_shepherding.jl"
if [ ! -f "$MAIN_SCRIPT" ]; then
    echo -e "${RED}✗ Error: main_shepherding.jl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Shepherding script found${NC}"

# Check viewer.py
if [ ! -f "$PROJECT_ROOT/viewer.py" ]; then
    echo -e "${RED}✗ Error: viewer.py not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Viewer script found${NC}"
echo ""

# Check if port 5555 is already in use
if lsof -i :5555 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Warning: Port 5555 is already in use${NC}"
    echo "Terminating existing process..."
    pkill -f "julia.*main" || true
    sleep 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Starting Shepherding Simulation with Viewer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Set environment variables
export EPH_N_SHEEP="$N_SHEEP"
export EPH_STEPS="$STEPS"
export EPH_WORLD_SIZE="$WORLD_SIZE"
export EPH_SEED="$SEED"

# Activate Python venv
source ~/local/venv/bin/activate

# Start Julia server in background
echo -e "${GREEN}[1/2] Starting Julia Shepherding Server...${NC}"
~/.juliaup/bin/julia --project=src_julia "$MAIN_SCRIPT" &
SERVER_PID=$!
echo "  Server PID: $SERVER_PID"

# Wait for server initialization
echo "  Waiting for server to initialize (3 seconds)..."
sleep 3

# Start Python viewer
echo ""
echo -e "${GREEN}[2/2] Starting Python Viewer...${NC}"
export PYTHONPATH=.
python viewer.py &
VIEWER_PID=$!
echo "  Viewer PID: $VIEWER_PID"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Simulation Running${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Server PID: $SERVER_PID"
echo "  Viewer PID: $VIEWER_PID"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop both processes${NC}"
echo ""

# Trap to kill both processes on exit
trap "echo ''; echo 'Stopping...'; kill $SERVER_PID $VIEWER_PID 2>/dev/null; echo 'Stopped.'; exit" INT TERM

# Wait for viewer to exit
wait $VIEWER_PID

# Kill server when viewer exits
kill $SERVER_PID 2>/dev/null || true

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Simulation stopped${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
