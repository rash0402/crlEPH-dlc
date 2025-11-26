#!/bin/bash

# EPH Foundation Theory Experiments Runner
# Tests three core theoretical foundations:
#   1. Lubricant Effect - Haze reduces excessive collision avoidance
#   2. Epistemic Exploration - Uncertainty-driven vs random exploration
#   3. Compactness Invariance - Haze modulates but doesn't drive forces

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
N_TRIALS=5
EXPERIMENT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        1|2|3)
            EXPERIMENT="$1"
            shift
            ;;
        --trials)
            N_TRIALS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 <experiment_number> [--trials N]"
            echo ""
            echo "Experiments:"
            echo "  1: Lubricant Effect - Tests haze's smoothing effect on collision avoidance"
            echo "  2: Epistemic Exploration - Tests uncertainty-driven exploration vs random"
            echo "  3: Compactness Invariance - Tests haze as modulator, not driver"
            echo ""
            echo "Options:"
            echo "  --trials N    Number of trials per condition (default: 5)"
            echo ""
            echo "Examples:"
            echo "  $0 1                # Run Experiment 1 with 5 trials"
            echo "  $0 2 --trials 10    # Run Experiment 2 with 10 trials"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown argument '$1'${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate experiment number
if [[ -z "$EXPERIMENT" ]]; then
    echo -e "${RED}Error: Experiment number required${NC}"
    echo "Usage: $0 <1|2|3> [--trials N]"
    echo "Use --help for more information"
    exit 1
fi

# Julia executable path
JULIA_BIN="$HOME/.juliaup/bin/julia"

if [[ ! -f "$JULIA_BIN" ]]; then
    echo -e "${RED}Error: Julia not found at $JULIA_BIN${NC}"
    echo "Please install Julia via juliaup"
    exit 1
fi

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EPH Foundation Theory Experiments${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Run selected experiment
case $EXPERIMENT in
    1)
        echo -e "${GREEN}Experiment 1: Lubricant Effect${NC}"
        echo -e "${YELLOW}Tests whether high haze reduces excessive collision avoidance,${NC}"
        echo -e "${YELLOW}allowing agents to navigate narrow passages more smoothly.${NC}"
        echo ""
        echo -e "Environment: Narrow corridor with bottleneck"
        echo -e "Conditions: Low Haze vs High Haze"
        echo -e "Metrics: Pass-through success rate, average velocity, wall clearance"
        echo -e "Trials per condition: $N_TRIALS"
        echo ""
        
        SCRIPT="src_julia/experiments/exp1_lubricant_effect.jl"
        ;;
    2)
        echo -e "${GREEN}Experiment 2: Epistemic Exploration${NC}"
        echo -e "${YELLOW}Tests whether haze-driven exploration follows the gradient of${NC}"
        echo -e "${YELLOW}uncertainty (information gaps) rather than random wandering.${NC}"
        echo ""
        echo -e "Environment: Open field with unknown regions (high haze zones)"
        echo -e "Conditions: EPH Controller vs Random Baseline"
        echo -e "Metrics: Time to reach unknown, coverage efficiency, trajectory directedness"
        echo -e "Trials per condition: $N_TRIALS"
        echo ""
        
        SCRIPT="src_julia/experiments/exp2_epistemic_exploration.jl"
        ;;
    3)
        echo -e "${GREEN}Experiment 3: Compactness Invariance${NC}"
        echo -e "${YELLOW}Tests the fundamental property that Haze modulates existing forces${NC}"
        echo -e "${YELLOW}but does not create driving forces (Compactness Invariance).${NC}"
        echo ""
        echo -e "Environment: Open field with no obstacles"
        echo -e "Conditions: No Social Force vs With Social Force × 3 Haze Patterns"
        echo -e "Metrics: Swarm compactness (agent dispersion)"
        echo -e "Trials per condition: $N_TRIALS"
        echo ""
        
        SCRIPT="src_julia/experiments/exp3_compactness_invariance.jl"
        ;;
esac

# Check if script exists
if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${RED}Error: Experiment script not found: $SCRIPT${NC}"
    exit 1
fi

# Run experiment
echo -e "${BLUE}Starting experiment...${NC}"
echo ""

export N_TRIALS=$N_TRIALS

if N_TRIALS=$N_TRIALS "$JULIA_BIN" --project=src_julia "$SCRIPT"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Experiment completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "Results saved to: ${BLUE}data/experiments/${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  - Review JSON results in data/experiments/"
    echo -e "  - Analyze statistical significance"
    echo -e "  - Visualize results (consider creating visualization scripts)"
    exit 0
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Experiment failed!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
