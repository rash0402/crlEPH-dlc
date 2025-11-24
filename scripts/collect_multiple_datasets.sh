#!/bin/bash
#
# Multiple GRU Training Data Collection Script
#
# Collects diverse training data across multiple runs with varying parameters
# to ensure good generalization of the GRU predictor.
#
# Usage:
#   ./scripts/collect_multiple_datasets.sh [num_runs]
#
# Arguments:
#   num_runs - Number of collection runs (default: 10)
#

set -e

# Configuration
NUM_RUNS="${1:-10}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  GRU Training Data Collection (Multiple Diverse Runs)     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration:"
echo "  Total runs: ${NUM_RUNS}"
echo "  Project directory: ${PROJECT_DIR}"
echo ""

# Diverse parameter sets for each run
# Format: steps agents_min agents_max
# We vary:
# - Simulation length (15k-25k steps)
# - Agent density (10-30 agents)
# - This creates diverse interaction patterns

declare -a PARAM_SETS=(
    "20000 15 15"   # Run 1: Standard density, long simulation
    "18000 20 20"   # Run 2: Higher density
    "22000 12 12"   # Run 3: Lower density, longer sim
    "20000 18 18"   # Run 4: Medium-high density
    "25000 10 10"   # Run 5: Very long, low density
    "16000 25 25"   # Run 6: Very high density
    "20000 22 22"   # Run 7: High density
    "20000 14 14"   # Run 8: Medium-low density
    "24000 16 16"   # Run 9: Long, medium density
    "18000 28 28"   # Run 10: Very high density, shorter
)

# Calculate how many times to cycle through param sets
CYCLES=$(( (NUM_RUNS + ${#PARAM_SETS[@]} - 1) / ${#PARAM_SETS[@]} ))

echo -e "${YELLOW}Parameter variations for diverse data:${NC}"
echo "  Simulation steps: 16,000 - 25,000"
echo "  Agent count: 10 - 30"
echo "  Total scenarios: ${NUM_RUNS}"
echo ""

# Check for existing data
EXISTING_FILES=$(find "${PROJECT_DIR}/data/training" -name "spm_sequences_*.jld2" 2>/dev/null | wc -l | tr -d ' ')

if [ "$EXISTING_FILES" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found ${EXISTING_FILES} existing training data files${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  1) Keep existing data and add new data (recommended)"
    echo "  2) Clear existing data and start fresh"
    echo "  3) Cancel"
    echo ""
    read -p "Choose option [1-3]: " choice

    case $choice in
        1)
            echo "  → Keeping existing data (will accumulate)"
            ;;
        2)
            echo "  → Clearing existing data..."
            rm -f "${PROJECT_DIR}/data/training/spm_sequences_"*.jld2
            echo "  ✓ Cleared"
            ;;
        3)
            echo "  → Cancelled"
            exit 0
            ;;
        *)
            echo "  → Invalid choice. Keeping existing data."
            ;;
    esac
    echo ""
fi

# Main collection loop
SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_TRANSITIONS=0

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Starting data collection (${NUM_RUNS} runs)...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

START_TIME=$(date +%s)

for run in $(seq 1 $NUM_RUNS); do
    # Select parameter set (cycle through if needed)
    param_idx=$(( (run - 1) % ${#PARAM_SETS[@]} ))
    params=(${PARAM_SETS[$param_idx]})
    steps=${params[0]}
    agents_min=${params[1]}
    agents_max=${params[2]}

    # Random agent count within range (for variation)
    agents=$(( agents_min + RANDOM % (agents_max - agents_min + 1) ))

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Run ${run}/${NUM_RUNS}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo "  Parameters: ${steps} steps × ${agents} agents"
    echo ""

    RUN_START=$(date +%s)

    # Run data collection
    if "${PROJECT_DIR}/scripts/collect_gru_training_data.sh" "$steps" "$agents"; then
        RUN_END=$(date +%s)
        RUN_DURATION=$((RUN_END - RUN_START))

        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

        # Estimate transitions (rough)
        EST_TRANSITIONS=$((steps * agents))
        TOTAL_TRANSITIONS=$((TOTAL_TRANSITIONS + EST_TRANSITIONS))

        echo ""
        echo -e "${GREEN}✓ Run ${run} completed in ${RUN_DURATION}s${NC}"
        echo -e "${GREEN}  Estimated transitions: ~${EST_TRANSITIONS}${NC}"
    else
        RUN_END=$(date +%s)
        RUN_DURATION=$((RUN_END - RUN_START))

        FAIL_COUNT=$((FAIL_COUNT + 1))

        echo ""
        echo -e "${RED}✗ Run ${run} failed after ${RUN_DURATION}s${NC}"
        echo -e "${YELLOW}  Continuing with remaining runs...${NC}"
    fi

    echo ""

    # Progress summary every 3 runs
    if [ $((run % 3)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        AVG_TIME=$((ELAPSED / run))
        REMAINING=$((NUM_RUNS - run))
        ETA=$((AVG_TIME * REMAINING))

        echo -e "${MAGENTA}Progress: ${run}/${NUM_RUNS} runs (${SUCCESS_COUNT} success, ${FAIL_COUNT} failed)${NC}"
        echo -e "${MAGENTA}Elapsed: ${ELAPSED}s | Avg: ${AVG_TIME}s/run | ETA: ~${ETA}s${NC}"
        echo ""
    fi
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Final summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Data Collection Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Summary:"
echo "  Total runs: ${NUM_RUNS}"
echo "  Successful: ${SUCCESS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
echo "  Total duration: ${TOTAL_DURATION}s (~$((TOTAL_DURATION / 60)) minutes)"
echo ""
echo "  Estimated total transitions: ~${TOTAL_TRANSITIONS}"
echo "  (Actual count may vary based on agent interactions)"
echo ""

# Count final data files
FINAL_FILES=$(find "${PROJECT_DIR}/data/training" -name "spm_sequences_*.jld2" 2>/dev/null | wc -l | tr -d ' ')
echo "  Training data files: ${FINAL_FILES}"
echo ""

if [ "$SUCCESS_COUNT" -ge 5 ]; then
    echo -e "${GREEN}✅ Sufficient data collected!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Verify data quality:"
    echo "     ${CYAN}cd src_julia && julia --project=. verify_training_data.jl${NC}"
    echo ""
    echo "  2. Train GRU model:"
    echo "     ${CYAN}./scripts/gru/update_gru.sh${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠ Limited data collected (${SUCCESS_COUNT} successful runs)${NC}"
    echo ""
    echo "  Recommendation: Run again to accumulate more data"
    echo "     ${CYAN}./scripts/collect_multiple_datasets.sh${NC}"
    echo ""
fi
