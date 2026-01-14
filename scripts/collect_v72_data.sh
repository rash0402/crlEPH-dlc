#!/bin/bash
################################################################################
# V7.2 Data Collection Script
# Runs data collection for all 3 scenarios (Scramble, Corridor, Random Obstacles)
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}================================================================================${NC}"
echo -e "${BLUE}V7.2 Data Collection: 5D State Space with Heading Alignment${NC}"
echo -e "${BLUE}================================================================================${NC}"
echo ""

# Default parameters
DENSITIES="10,15,20"
SEEDS="1,2,3"
STEPS=1500
OBSTACLE_COUNTS="30,50,70"
RUN_SCRAMBLE=true
RUN_CORRIDOR=true
RUN_RANDOM=true

# Parse command line arguments
SHOW_HELP=false
for arg in "$@"; do
    case $arg in
        --scramble-only)
            RUN_CORRIDOR=false
            RUN_RANDOM=false
            shift
            ;;
        --corridor-only)
            RUN_SCRAMBLE=false
            RUN_RANDOM=false
            shift
            ;;
        --random-only)
            RUN_SCRAMBLE=false
            RUN_CORRIDOR=false
            shift
            ;;
        --quick)
            STEPS=100
            DENSITIES="10"
            SEEDS="1"
            OBSTACLE_COUNTS="30"
            shift
            ;;
        --help)
            SHOW_HELP=true
            shift
            ;;
        *)
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --scramble-only    Run only Scramble Crossing scenario"
    echo "  --corridor-only    Run only Corridor scenario"
    echo "  --random-only      Run only Random Obstacles scenario"
    echo "  --quick            Quick test mode (100 steps, density=10, seed=1)"
    echo "  --help             Show this help message"
    echo ""
    echo "Default configuration:"
    echo "  Densities: 10,15,20"
    echo "  Seeds: 1,2,3"
    echo "  Steps: 1500"
    echo "  Obstacle counts (Random): 30,50,70"
    echo ""
    echo "Examples:"
    echo "  $0                        # Run all scenarios (full data collection)"
    echo "  $0 --quick                # Quick test (100 steps)"
    echo "  $0 --scramble-only        # Only Scramble Crossing"
    echo ""
    exit 0
fi

# Display configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "  Densities: $DENSITIES"
echo "  Seeds: $SEEDS"
echo "  Steps: $STEPS"
if [ "$RUN_RANDOM" = true ]; then
    echo "  Obstacle counts: $OBSTACLE_COUNTS"
fi
echo ""
echo -e "${YELLOW}Scenarios to run:${NC}"
[ "$RUN_SCRAMBLE" = true ] && echo "  ✓ Scramble Crossing (4-group intersection)"
[ "$RUN_CORRIDOR" = true ] && echo "  ✓ Corridor (2-group bidirectional)"
[ "$RUN_RANDOM" = true ] && echo "  ✓ Random Obstacles (4-group + obstacles)"
echo ""

# Confirm execution
read -p "$(echo -e ${GREEN}Start data collection? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Change to project root
cd "$PROJECT_ROOT"

# Check if Julia is available
if ! command -v julia &> /dev/null; then
    echo -e "${RED}ERROR: Julia not found in PATH${NC}"
    exit 1
fi

# Check if project is activated
if [ ! -f "Project.toml" ]; then
    echo -e "${RED}ERROR: Project.toml not found in $PROJECT_ROOT${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Starting data collection...${NC}"
echo ""

# Create output directories
mkdir -p data/vae_training/raw_v72
mkdir -p logs

# Run Scramble Crossing
if [ "$RUN_SCRAMBLE" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}1. Scramble Crossing${NC}"
    echo -e "${BLUE}========================================${NC}"

    julia --project=. scripts/create_dataset_v72_scramble.jl \
        --densities "$DENSITIES" \
        --seeds "$SEEDS" \
        --steps "$STEPS" \
        2>&1 | tee logs/v72_scramble_$(date +%Y%m%d_%H%M%S).log

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Scramble Crossing completed${NC}"
    else
        echo -e "${RED}✗ Scramble Crossing failed${NC}"
        exit 1
    fi
    echo ""
fi

# Run Corridor
if [ "$RUN_CORRIDOR" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}2. Corridor${NC}"
    echo -e "${BLUE}========================================${NC}"

    julia --project=. scripts/create_dataset_v72_corridor.jl \
        --densities "$DENSITIES" \
        --seeds "$SEEDS" \
        --steps "$STEPS" \
        2>&1 | tee logs/v72_corridor_$(date +%Y%m%d_%H%M%S).log

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Corridor completed${NC}"
    else
        echo -e "${RED}✗ Corridor failed${NC}"
        exit 1
    fi
    echo ""
fi

# Run Random Obstacles
if [ "$RUN_RANDOM" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}3. Random Obstacles${NC}"
    echo -e "${BLUE}========================================${NC}"

    julia --project=. scripts/create_dataset_v72_random_obstacles.jl \
        --densities "$DENSITIES" \
        --obstacle-counts "$OBSTACLE_COUNTS" \
        --seeds "$SEEDS" \
        --steps "$STEPS" \
        2>&1 | tee logs/v72_random_$(date +%Y%m%d_%H%M%S).log

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Random Obstacles completed${NC}"
    else
        echo -e "${RED}✗ Random Obstacles failed${NC}"
        exit 1
    fi
    echo ""
fi

# Summary
echo -e "${BLUE}================================================================================${NC}"
echo -e "${BLUE}Data Collection Complete${NC}"
echo -e "${BLUE}================================================================================${NC}"
echo ""

# Count generated files
NUM_FILES=$(find data/vae_training/raw_v72 -name "v72_*.h5" -type f 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh data/vae_training/raw_v72 2>/dev/null | cut -f1)

echo -e "${GREEN}Generated files: $NUM_FILES${NC}"
echo -e "${GREEN}Total size: $TOTAL_SIZE${NC}"
echo ""

echo "Next steps:"
echo "  1. View data: scripts/view_v72_data.sh"
echo "  2. Train VAE: julia --project=. scripts/train_action_vae_v72.jl"
echo "  3. Test EPH: julia --project=. scripts/test_eph_v72.jl"
echo ""
