#!/bin/bash
#
# GRU Training Data Collection Script
#
# Automatically collects training data for the GRU predictor by running
# simulations with data collection enabled.
#
# Usage:
#   ./scripts/collect_gru_training_data.sh [num_steps] [num_agents]
#
# Arguments:
#   num_steps   - Number of simulation steps (default: 20000)
#   num_agents  - Number of agents (default: 15)
#
# Example:
#   ./scripts/collect_gru_training_data.sh 5000 15
#

set -e  # Exit on error

# Configuration
NUM_STEPS="${1:-20000}"
NUM_AGENTS="${2:-15}"
JULIA_BIN="${HOME}/.juliaup/bin/julia"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${PROJECT_DIR}/src_julia"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  GRU Training Data Collection                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration:"
echo "  Simulation steps: ${NUM_STEPS}"
echo "  Number of agents: ${NUM_AGENTS}"
echo "  Project directory: ${PROJECT_DIR}"
echo ""

# Create data directories if they don't exist
mkdir -p "${PROJECT_DIR}/data/training"

# Check current training data
echo -e "${YELLOW}Checking existing training data...${NC}"
EXISTING_FILES=$(find "${PROJECT_DIR}/data/training" -name "spm_sequences_*.jld2" 2>/dev/null | wc -l | tr -d ' ')

if [ "$EXISTING_FILES" -gt 0 ]; then
    echo "  Found ${EXISTING_FILES} existing training data files"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  1) Keep existing data and add new data"
    echo "  2) Clear existing data and start fresh"
    echo "  3) Cancel"
    echo ""
    read -p "Choose option [1-3]: " choice

    case $choice in
        1)
            echo "  → Keeping existing data"
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
else
    echo "  No existing training data found"
    echo ""
fi

# Run data collection
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Starting data collection...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "${SRC_DIR}"

# Run Julia data collection script
"${JULIA_BIN}" --project=. collect_training_data.jl "${NUM_STEPS}" "${NUM_AGENTS}"

EXIT_CODE=$?

echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Data collection completed successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Verify collected data
    echo -e "${BLUE}Verifying collected data...${NC}"
    echo ""

    "${JULIA_BIN}" --project=. verify_training_data.jl

    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Review the data statistics above"
    echo "  2. If sufficient data (>= 10,000 transitions), train the GRU model:"
    echo "     ${GREEN}./scripts/gru/update_gru.sh${NC}"
    echo "  3. Or collect more data with:"
    echo "     ${GREEN}./scripts/collect_gru_training_data.sh <num_steps> <num_agents>${NC}"
    echo ""
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}Data collection failed!${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Exit code: $EXIT_CODE"
    exit $EXIT_CODE
fi
