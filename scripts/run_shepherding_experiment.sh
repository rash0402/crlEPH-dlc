#!/bin/bash
#
# Shepherding Experiment Runner (Phase 4 - Updated)
# ShepherdingEPHv2 (SPM-based Social Value) + Sheep BOIDS
#
# Usage:
#   ./scripts/run_shepherding_experiment.sh [OPTIONS]
#
# Options:
#   --n-sheep NUM       羊の数（デフォルト: 5）
#   --n-dogs NUM        犬の数（デフォルト: 1）
#   --steps NUM         シミュレーションステップ数（デフォルト: 100）
#   --world-size NUM    ワールドサイズ（デフォルト: 400）
#   --seed NUM          乱数シード（デフォルト: 42、再現性のため）
#   --test              テストモード（短時間実行）
#

set -e  # Exit on error

# Default parameters
N_SHEEP=5
N_DOGS=1
STEPS=100
WORLD_SIZE=400
SEED=42
TEST_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --n-sheep)
            N_SHEEP="$2"
            shift 2
            ;;
        --n-dogs)
            N_DOGS="$2"
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
        --test)
            TEST_MODE=true
            N_SHEEP=3
            STEPS=50
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--n-sheep NUM] [--n-dogs NUM] [--steps NUM] [--world-size NUM] [--seed NUM] [--test]"
            exit 1
            ;;
    esac
done

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
echo -e "${BLUE}║  Phase 4 Shepherding Experiment                              ║${NC}"
echo -e "${BLUE}║  ShepherdingEPHv2 (SPM-based Social Value)                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}実験設定:${NC}"
echo -e "  羊の数:           ${GREEN}${N_SHEEP}${NC}"
echo -e "  犬の数:           ${GREEN}${N_DOGS}${NC}"
echo -e "  シミュレーション:  ${GREEN}${STEPS}${NC} steps"
echo -e "  ワールドサイズ:    ${GREEN}${WORLD_SIZE}${NC} × ${GREEN}${WORLD_SIZE}${NC}"
echo -e "  乱数シード:        ${GREEN}${SEED}${NC}"
if [ "$TEST_MODE" = true ]; then
    echo -e "  ${YELLOW}⚠ テストモード${NC}"
fi
echo ""

# Check if Julia is installed
if ! command -v ~/.juliaup/bin/julia &> /dev/null; then
    echo -e "${RED}✗ Error: Julia not found at ~/.juliaup/bin/julia${NC}"
    echo "  Please install Julia via juliaup"
    exit 1
fi

echo -e "${GREEN}✓ Julia found: $(~/.juliaup/bin/julia --version)${NC}"
echo ""

# Use test script instead of old shepherding_experiment.jl
EXPERIMENT_SCRIPT="$PROJECT_ROOT/src_julia/test_shepherding_basic.jl"
if [ ! -f "$EXPERIMENT_SCRIPT" ]; then
    echo -e "${RED}✗ Error: Phase 4 test script not found${NC}"
    echo "  Expected: $EXPERIMENT_SCRIPT"
    exit 1
fi

echo -e "${GREEN}✓ Phase 4 shepherding script found${NC}"
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
echo -e "${BLUE}Phase 4 Shepherding Configuration:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Agents:"
echo "    - Sheep: ${N_SHEEP} agents (BOIDS + flee behavior)"
echo "    - Dogs: ${N_DOGS} agent(s) (ShepherdingEPHv2)"
echo ""
echo "  Features:"
echo "    - SPM-based Social Value (Angular Compactness + Goal Pushing)"
echo "    - Soft-binning for Zygote compatibility"
echo "    - Adaptive Social Value weights"
echo ""
echo "  Evaluation Metrics:"
echo "    1. Goal distance (target: < 100 units)"
echo "    2. Sheep cohesion maintenance"
echo "    3. Movement towards goal"
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

# Set environment variables for Julia script
export EPH_N_SHEEP="$N_SHEEP"
export EPH_N_DOGS="$N_DOGS"
export EPH_STEPS="$STEPS"
export EPH_WORLD_SIZE="$WORLD_SIZE"
export EPH_SEED="$SEED"
export EPH_NON_INTERACTIVE="1"

# Run the experiment
START_TIME=$(date +%s)

if ~/.juliaup/bin/julia --project=src_julia "$EXPERIMENT_SCRIPT"; then
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
    echo "  1. Scale up experiment (recommended seeds for 20 sheep):"
    echo "     $0 --n-sheep 20 --steps 500 --seed 300  # Best: goal dist ~27"
    echo "     $0 --n-sheep 20 --steps 500 --seed 100  # Good: goal dist ~70"
    echo ""
    echo "  2. Test multiple dogs:"
    echo "     $0 --n-dogs 3 --n-sheep 15"
    echo ""
    echo "  3. Run full validation:"
    echo "     ./scripts/run_basic_validation.sh all"
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
