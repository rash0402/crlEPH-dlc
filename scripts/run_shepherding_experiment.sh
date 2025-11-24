#!/bin/bash
#
# Shepherding Experiment Runner
# EPH-based dog agents herding Boids-based sheep agents
#
# Usage:
#   ./scripts/run_shepherding_experiment.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Shepherding Experiment Runner                               ║${NC}"
echo -e "${BLUE}║  EPH Dogs vs Boids Sheep                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Julia is installed
if ! command -v ~/.juliaup/bin/julia &> /dev/null; then
    echo -e "${RED}✗ Error: Julia not found at ~/.juliaup/bin/julia${NC}"
    echo "  Please install Julia via juliaup"
    exit 1
fi

echo -e "${GREEN}✓ Julia found: $(~/.juliaup/bin/julia --version)${NC}"
echo ""

# Check if experiment script exists
EXPERIMENT_SCRIPT="$PROJECT_ROOT/scripts/shepherding_experiment.jl"
if [ ! -f "$EXPERIMENT_SCRIPT" ]; then
    echo -e "${RED}✗ Error: Experiment script not found${NC}"
    echo "  Expected: $EXPERIMENT_SCRIPT"
    exit 1
fi

echo -e "${GREEN}✓ Experiment script found${NC}"
echo ""

# Check if log directory exists
LOG_DIR="$PROJECT_ROOT/src_julia/data/logs"
if [ ! -d "$LOG_DIR" ]; then
    echo -e "${YELLOW}⚠ Creating log directory: $LOG_DIR${NC}"
    mkdir -p "$LOG_DIR"
fi

echo -e "${GREEN}✓ Log directory ready: $LOG_DIR${NC}"
echo ""

# Display experiment configuration
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Experiment Configuration:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Agents:"
echo "    - Sheep: 15 agents (Boids model)"
echo "    - Dogs: 2 agents (ShepherdingEPH)"
echo ""
echo "  Phases:"
echo "    - F1 (0-100s): Convergence phase"
echo "    - F2 (100-120s): Escape induction (2× repulsion)"
echo "    - F3 (120-200s): Recovery phase"
echo ""
echo "  Evaluation Metrics:"
echo "    1. Recovery Time (seconds)"
echo "    2. Path Smoothness (total jerk)"
echo "    3. Final Distance to target (meters)"
echo ""

# Confirm before running (skip if non-interactive mode)
if [ -z "$EPH_NON_INTERACTIVE" ]; then
    echo -e "${YELLOW}Press Enter to start the experiment (or Ctrl+C to cancel)${NC}"
    read -r
else
    echo -e "${GREEN}Running in non-interactive mode...${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Running Shepherding Experiment...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Run the experiment
START_TIME=$(date +%s)

if ~/.juliaup/bin/julia --project=src_julia scripts/shepherding_experiment.jl; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Experiment completed successfully${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Execution time: ${ELAPSED}s"
    echo ""

    # Find the most recent log file
    LATEST_LOG=$(ls -t "$LOG_DIR"/shepherding_eph_*.jld2 2>/dev/null | head -n 1)

    if [ -n "$LATEST_LOG" ]; then
        echo -e "${GREEN}✓ Results saved:${NC}"
        echo "  $LATEST_LOG"
        echo ""

        # Show file size
        FILE_SIZE=$(du -h "$LATEST_LOG" | cut -f1)
        echo "  File size: $FILE_SIZE"
    else
        echo -e "${YELLOW}⚠ Warning: Could not find log file${NC}"
        echo "  Expected pattern: $LOG_DIR/shepherding_eph_*.jld2"
    fi

    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Analyze results with Julia:"
    echo "     julia> using JLD2"
    echo "     julia> data = load(\"$LATEST_LOG\")"
    echo ""
    echo "  2. Compare with baseline (Boids-only dogs)"
    echo "  3. Optimize parameters (w_target, w_density, w_work)"
    echo ""

else
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Experiment failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Execution time: ${ELAPSED}s"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Check if all modules load correctly:"
    echo "     ~/.juliaup/bin/julia --project=src_julia -e 'include(\"scripts/shepherding_experiment.jl\")'"
    echo ""
    echo "  2. Verify dependencies are installed:"
    echo "     cd src_julia && julia --project=. -e 'using Pkg; Pkg.instantiate()'"
    echo ""
    echo "  3. Check log directory permissions:"
    echo "     ls -la $LOG_DIR"
    echo ""
    exit 1
fi
