#!/bin/bash
#
# Complete EPH Experiment Workflow
#
# This script automates the entire EPH experiment workflow:
#   1. Clear old data (optional)
#   2. Collect GRU training data
#   3. Train GRU predictor (optional)
#   4. Run comprehensive diagnostic experiments
#   5. Generate analysis reports
#
# Usage:
#   ./scripts/run_complete_workflow.sh [workflow_type]
#
# Workflow Types:
#   quick       - Quick workflow (100 steps data, skip GRU training, 1 diagnostic)
#   standard    - Standard workflow (2000 steps data, train GRU, 4 diagnostics)
#   full        - Full workflow (5000 steps data, train GRU, 4 diagnostics)
#   custom      - Custom configuration (prompts for parameters)
#
# Example:
#   ./scripts/run_complete_workflow.sh standard
#

set -e  # Exit on error

# Configuration
WORKFLOW_TYPE="${1:-standard}"
JULIA_BIN="${HOME}/.juliaup/bin/julia"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${PROJECT_DIR}/src_julia"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="${PROJECT_DIR}/data/logs/workflow_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_colored() {
    echo -e "$1"
    echo "$2" >> "$LOG_FILE"
}

# Header
clear
log_colored "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}" "========================================"
log_colored "${MAGENTA}║                                                            ║${NC}" ""
log_colored "${MAGENTA}║     EPH Complete Experiment Workflow Automation            ║${NC}" "    EPH Complete Experiment Workflow Automation"
log_colored "${MAGENTA}║                                                            ║${NC}" ""
log_colored "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}" "========================================"
log ""

# Configure workflow based on type
case "$WORKFLOW_TYPE" in
    quick)
        log_colored "${CYAN}Workflow Type: Quick${NC}" "Workflow Type: Quick"
        DATA_STEPS=500
        DATA_AGENTS=5
        TRAIN_GRU=false
        DIAGNOSTIC_EXPERIMENTS=1
        DIAGNOSTIC_STEPS=1000
        ;;
    standard)
        log_colored "${CYAN}Workflow Type: Standard${NC}" "Workflow Type: Standard"
        DATA_STEPS=3000
        DATA_AGENTS=10
        TRAIN_GRU=true
        DIAGNOSTIC_EXPERIMENTS=4
        DIAGNOSTIC_STEPS=5000
        ;;
    full)
        log_colored "${CYAN}Workflow Type: Full${NC}" "Workflow Type: Full"
        DATA_STEPS=10000
        DATA_AGENTS=15
        TRAIN_GRU=true
        DIAGNOSTIC_EXPERIMENTS=4
        DIAGNOSTIC_STEPS=10000
        ;;
    custom)
        log_colored "${CYAN}Workflow Type: Custom${NC}" "Workflow Type: Custom"
        log ""
        read -p "Data collection steps [3000]: " DATA_STEPS
        DATA_STEPS=${DATA_STEPS:-3000}
        read -p "Number of agents [10]: " DATA_AGENTS
        DATA_AGENTS=${DATA_AGENTS:-10}
        read -p "Diagnostic experiment steps [5000]: " DIAGNOSTIC_STEPS
        DIAGNOSTIC_STEPS=${DIAGNOSTIC_STEPS:-5000}
        read -p "Train GRU model? (y/n) [y]: " train_choice
        TRAIN_GRU=true
        [[ "$train_choice" == "n" ]] && TRAIN_GRU=false
        read -p "Number of diagnostic experiments [4]: " DIAGNOSTIC_EXPERIMENTS
        DIAGNOSTIC_EXPERIMENTS=${DIAGNOSTIC_EXPERIMENTS:-4}
        ;;
    *)
        log_colored "${RED}Error: Unknown workflow type '$WORKFLOW_TYPE'${NC}" "Error: Unknown workflow type"
        log "Valid types: quick, standard, full, custom"
        exit 1
        ;;
esac

log ""
log "Configuration Summary:"
log "  Data collection steps:  $DATA_STEPS"
log "  Diagnostic steps:       $DIAGNOSTIC_STEPS"
log "  Number of agents:       $DATA_AGENTS"
log "  Train GRU model:        $TRAIN_GRU"
log "  Diagnostic experiments: $DIAGNOSTIC_EXPERIMENTS"
log "  Log file:               $LOG_FILE"
log ""

# Confirmation
read -p "Proceed with this configuration? (y/n) [y]: " confirm
confirm=${confirm:-y}

if [[ "$confirm" != "y" ]]; then
    log "Workflow cancelled by user."
    exit 0
fi

log ""
log_colored "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" "=================================================="
log_colored "${GREEN}Starting Complete Workflow${NC}" "Starting Complete Workflow"
log_colored "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" "=================================================="
log ""

START_TIME=$(date +%s)

# Step 1: Clear old data (optional)
log_colored "${BLUE}[Step 1/5] Data Cleanup${NC}" "[Step 1/5] Data Cleanup"
log "Checking existing data..."

EXISTING_LOGS=$(find "${PROJECT_DIR}/data/logs" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')
EXISTING_TRAINING=$(find "${PROJECT_DIR}/data/training" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')
EXISTING_MODELS=$(find "${PROJECT_DIR}/data/models" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')

log "  Existing logs:     $EXISTING_LOGS files"
log "  Existing training: $EXISTING_TRAINING files"
log "  Existing models:   $EXISTING_MODELS files"

if [ "$EXISTING_LOGS" -gt 0 ] || [ "$EXISTING_TRAINING" -gt 0 ] || [ "$EXISTING_MODELS" -gt 0 ]; then
    log ""
    read -p "Clear existing data? (y/n) [n]: " clear_data
    clear_data=${clear_data:-n}

    if [[ "$clear_data" == "y" ]]; then
        log "Clearing data directories..."
        rm -rf "${PROJECT_DIR}/data/logs/"*.jld2 "${PROJECT_DIR}/data/logs/"*.png 2>/dev/null || true
        rm -rf "${PROJECT_DIR}/data/training/"*.jld2 2>/dev/null || true
        rm -rf "${PROJECT_DIR}/data/models/"*.jld2 2>/dev/null || true
        log "✓ Data cleared"
    else
        log "→ Keeping existing data"
    fi
fi
log ""

# Step 2: Collect GRU Training Data
log_colored "${BLUE}[Step 2/5] GRU Training Data Collection${NC}" "[Step 2/5] GRU Training Data Collection"
log "Collecting training data with $DATA_STEPS steps and $DATA_AGENTS agents..."
log ""

cd "${SRC_DIR}"
"${JULIA_BIN}" --project=. collect_training_data.jl "$DATA_STEPS" "$DATA_AGENTS" 2>&1 | tee -a "$LOG_FILE"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_colored "${RED}✗ Data collection failed${NC}" "✗ Data collection failed"
    exit 1
fi

log_colored "${GREEN}✓ Data collection completed${NC}" "✓ Data collection completed"
log ""

# Verify data
log "Verifying collected data..."
"${JULIA_BIN}" --project=. verify_training_data.jl 2>&1 | tee -a "$LOG_FILE"
log ""

# Step 3: Train GRU Model (optional)
if [ "$TRAIN_GRU" = true ]; then
    log_colored "${BLUE}[Step 3/5] GRU Model Training${NC}" "[Step 3/5] GRU Model Training"
    log "Training GRU predictor model..."
    log ""

    if [ -f "${SCRIPTS_DIR}/gru/update_gru.sh" ]; then
        bash "${SCRIPTS_DIR}/gru/update_gru.sh" 2>&1 | tee -a "$LOG_FILE"

        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            log_colored "${YELLOW}⚠ GRU training encountered issues (continuing)${NC}" "⚠ GRU training encountered issues"
        else
            log_colored "${GREEN}✓ GRU training completed${NC}" "✓ GRU training completed"
        fi
    else
        log_colored "${YELLOW}⚠ GRU training script not found, skipping${NC}" "⚠ GRU training script not found"
    fi
    log ""
else
    log_colored "${YELLOW}[Step 3/5] GRU Model Training - SKIPPED${NC}" "[Step 3/5] GRU Model Training - SKIPPED"
    log ""
fi

# Step 4: Run Diagnostic Experiments
log_colored "${BLUE}[Step 4/5] Comprehensive Diagnostic Experiments${NC}" "[Step 4/5] Comprehensive Diagnostic Experiments"
log "Running $DIAGNOSTIC_EXPERIMENTS diagnostic experiment(s)..."
log ""

if [ "$DIAGNOSTIC_EXPERIMENTS" -eq 1 ]; then
    # Single diagnostic experiment
    log "Running single diagnostic experiment ($DIAGNOSTIC_STEPS steps)..."
    cd "${SRC_DIR}"
    "${JULIA_BIN}" --project=. run_single_diagnostic.jl "$DIAGNOSTIC_STEPS" 2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_colored "${RED}✗ Diagnostic experiment failed${NC}" "✗ Diagnostic experiment failed"
        exit 1
    fi
else
    # Multiple parameter configurations
    log "Running multi-configuration diagnostic experiments ($DIAGNOSTIC_STEPS steps each)..."
    bash "${SCRIPTS_DIR}/run_diagnostic_experiments.sh" "workflow" "$DIAGNOSTIC_STEPS" 2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_colored "${YELLOW}⚠ Some diagnostic experiments encountered issues${NC}" "⚠ Some experiments encountered issues"
    fi
fi

log_colored "${GREEN}✓ Diagnostic experiments completed${NC}" "✓ Diagnostic experiments completed"
log ""

# Step 5: Generate Summary Report
log_colored "${BLUE}[Step 5/5] Generating Summary Report${NC}" "[Step 5/5] Generating Summary Report"
log ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# Count results
FINAL_LOGS=$(find "${PROJECT_DIR}/data/logs" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')
FINAL_TRAINING=$(find "${PROJECT_DIR}/data/training" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')
FINAL_MODELS=$(find "${PROJECT_DIR}/data/models" -name "*.jld2" 2>/dev/null | wc -l | tr -d ' ')

log_colored "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}" "========================================"
log_colored "${GREEN}║  Workflow Completed Successfully!                         ║${NC}" "  Workflow Completed Successfully!"
log_colored "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}" "========================================"
log ""
log "Summary:"
log "  Workflow type:       $WORKFLOW_TYPE"
log "  Total duration:      ${DURATION_MIN}m ${DURATION_SEC}s"
log ""
log "Generated Files:"
log "  Diagnostic logs:     $FINAL_LOGS files"
log "  Training data:       $FINAL_TRAINING files"
log "  GRU models:          $FINAL_MODELS files"
log ""
log "Output Locations:"
log "  Logs:        ${PROJECT_DIR}/data/logs/"
log "  Training:    ${PROJECT_DIR}/data/training/"
log "  Models:      ${PROJECT_DIR}/data/models/"
log "  Workflow log: $LOG_FILE"
log ""
log_colored "${YELLOW}Next Steps:${NC}" "Next Steps:"
log "  1. Review diagnostic reports in data/logs/"
log "  2. Analyze results with:"
log "     cd src_julia"
log "     julia --project=. ../scripts/analyze_experiment.jl <log_file>"
log "  3. Run additional experiments with different parameters"
log ""
log_colored "${GREEN}✓ All tasks completed!${NC}" "✓ All tasks completed!"
