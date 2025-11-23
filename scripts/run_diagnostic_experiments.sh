#!/bin/bash
#
# EPH Comprehensive Diagnostic Experiments
#
# This script runs multiple EPH experiments with different self-haze parameter settings
# and generates diagnostic reports for each configuration.
#
# Usage:
#   ./scripts/run_diagnostic_experiments.sh [experiment_name] [num_steps]
#
# Arguments:
#   experiment_name  - Optional name prefix for experiments (default: "diagnostic")
#   num_steps        - Number of simulation steps per experiment (default: 1000)
#

set -e  # Exit on error

# Configuration
EXPERIMENT_NAME="${1:-diagnostic}"
NUM_STEPS="${2:-1000}"
JULIA_BIN="${HOME}/.juliaup/bin/julia"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${PROJECT_DIR}/src_julia"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"
LOG_DIR="${PROJECT_DIR}/data/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create log directory
mkdir -p "${LOG_DIR}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  EPH Comprehensive Diagnostic Experiments                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration:"
echo "  Experiment name: ${EXPERIMENT_NAME}"
echo "  Steps per run:   ${NUM_STEPS}"
echo "  Project dir:     ${PROJECT_DIR}"
echo ""

# Experiment configurations
declare -a EXPERIMENTS=(
    "default:0.8:10.0:0.05:2.0:Default configuration"
    "exploration:0.9:15.0:0.02:2.0:Exploration-focused (rough path shortcuts)"
    "uniform:0.3:3.0:0.10:2.0:Uniform distribution (density avoidance)"
    "stigmergic:0.6:8.0:0.05:5.0:Stigmergic trail formation"
)

# Function to run a single experiment
run_experiment() {
    local config_name="$1"
    local h_max="$2"
    local alpha="$3"
    local omega_th="$4"
    local gamma="$5"
    local description="$6"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Running: ${config_name}${NC}"
    echo -e "${YELLOW}${description}${NC}"
    echo "Parameters: h_max=${h_max}, α=${alpha}, Ω_th=${omega_th}, γ=${gamma}"
    echo ""

    # Create temporary Julia script for this experiment
    local temp_script="${SRC_DIR}/temp_experiment_${config_name}.jl"

    cat > "${temp_script}" <<EOF
# Auto-generated experiment script for: ${config_name}

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EPH
using .Simulation
using .SPMPredictor
using .ExperimentLogger

println("Experiment: ${config_name}")
println("Description: ${description}")
println("")

# Custom parameters
params = Types.EPHParams(
    h_max = ${h_max},
    α = ${alpha},
    Ω_threshold = ${omega_th},
    γ = ${gamma},
    predictor_type = :linear,
    collect_data = false
)

# Setup environment
env = Types.Environment(400.0, 400.0, grid_size=20)

# Add 10 agents
for i in 1:10
    x = rand() * env.width
    y = rand() * env.height
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env.agents, agent)
end

# Initialize predictor
predictor = SPMPredictor.LinearPredictor(env.dt)

# Initialize logger
logger = ExperimentLogger.Logger("${EXPERIMENT_NAME}_${config_name}")

# State tracking
prev_positions = nothing
prev_velocities = nothing
prev_actions = nothing
prev_self_haze = nothing

# Run experiment
println("Running ${NUM_STEPS} steps...")
for step in 1:${NUM_STEPS}
    # Capture state before simulation
    if step > 1 && step % 10 == 0
        prev_positions = [(a.position[1], a.position[2]) for a in env.agents]
        prev_velocities = [sqrt(a.velocity[1]^2 + a.velocity[2]^2) for a in env.agents]
        prev_actions = [copy(a.velocity) for a in env.agents]
        prev_self_haze = [a.self_haze for a in env.agents]
    end

    # Run simulation
    Simulation.step!(env, params, predictor)

    # Log every 10 steps
    if step % 10 == 0
        # Basic logging
        ExperimentLogger.log_step(logger, step, step * 0.1, env.agents, env)

        # System metrics
        coverage = Simulation.compute_coverage(env)
        total_haze = sum(env.haze_grid)
        avg_sep = mean([sqrt((a.position[1] - b.position[1])^2 + (a.position[2] - b.position[2])^2)
                       for a in env.agents for b in env.agents if a.id != b.id])
        ExperimentLogger.log_system_metrics(logger, coverage, total_haze, avg_sep, 0)

        # Phase 1: Health
        ExperimentLogger.log_health_metrics(logger, env.agents, env, prev_positions, prev_velocities)

        # Phase 2: Prediction
        spm_params = SPM.SPMParams()
        ExperimentLogger.log_prediction_metrics(logger, env.agents, predictor, env, spm_params)

        # Phase 3: Gradient
        ExperimentLogger.log_gradient_metrics(logger, env.agents, prev_actions, nothing, nothing)

        # Phase 4: Self-Haze
        ExperimentLogger.log_selfhaze_metrics(logger, env.agents, prev_self_haze)
    end

    # Progress indicator
    if step % 100 == 0
        print(".")
        flush(stdout)
    end
end

println("")
println("")
println("Experiment complete. Saving log...")

# Save log
log_path = ExperimentLogger.save_log(logger)
println("Log saved: \$log_path")

# Return log path for analysis
println("LOG_PATH=\$log_path")
EOF

    # Run the experiment
    cd "${SRC_DIR}"
    local output
    output=$("${JULIA_BIN}" --project=. "${temp_script}" 2>&1)

    # Extract log path from output
    local log_path
    log_path=$(echo "$output" | grep "^LOG_PATH=" | cut -d'=' -f2)

    # Display output
    echo "$output" | grep -v "^LOG_PATH="

    # Clean up temp script
    rm -f "${temp_script}"

    # Return log path
    echo "$log_path"
}

# Function to analyze experiment results
analyze_experiment() {
    local log_path="$1"
    local config_name="$2"

    echo ""
    echo -e "${BLUE}Analyzing results for: ${config_name}${NC}"
    echo ""

    cd "${SRC_DIR}"
    "${JULIA_BIN}" --project=. "${SCRIPTS_DIR}/analyze_experiment.jl" "${log_path}"

    echo ""
}

# Main execution
echo -e "${YELLOW}Starting ${#EXPERIMENTS[@]} experiments...${NC}"
echo ""

# Array to store log paths
declare -a LOG_PATHS=()
declare -a CONFIG_NAMES=()

# Run all experiments
for experiment in "${EXPERIMENTS[@]}"; do
    IFS=':' read -r config_name h_max alpha omega_th gamma description <<< "$experiment"

    log_path=$(run_experiment "$config_name" "$h_max" "$alpha" "$omega_th" "$gamma" "$description")

    LOG_PATHS+=("$log_path")
    CONFIG_NAMES+=("$config_name")

    echo ""
    sleep 1
done

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}All experiments completed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Analyze all results
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Diagnostic Analysis                                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

for i in "${!LOG_PATHS[@]}"; do
    analyze_experiment "${LOG_PATHS[$i]}" "${CONFIG_NAMES[$i]}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
done

# Summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Experiment Summary                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Completed ${#EXPERIMENTS[@]} experiments:"
for i in "${!LOG_PATHS[@]}"; do
    echo "  ${CONFIG_NAMES[$i]}: ${LOG_PATHS[$i]}"
done
echo ""
echo -e "${YELLOW}All logs saved in: ${LOG_DIR}${NC}"
echo ""
echo -e "${GREEN}✓ Diagnostic experiments complete!${NC}"
