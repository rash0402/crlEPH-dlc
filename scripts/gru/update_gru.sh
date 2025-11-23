#!/bin/bash
# Update GRU Model Script
# Wrapper script to retrain and update the GRU predictor model

# Set up Julia path
export PATH="$HOME/.juliaup/bin:$PATH"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================================"
echo "GRU Model Update"
echo "============================================================"
echo ""

# Check if Julia is available
if ! command -v julia &> /dev/null; then
    echo "Error: Julia not found in PATH"
    echo "Please install Julia or add it to your PATH"
    exit 1
fi

# Run the Julia update script
cd "$PROJECT_DIR"
julia scripts/update_gru_model.jl

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "============================================================"
    echo "Model update completed successfully!"
    echo "============================================================"
    echo ""
    echo "The updated GRU model is now ready to use."
    echo "Restart the simulation to use the new model:"
    echo "  cd scripts"
    echo "  ./run_experiment.sh"
else
    echo ""
    echo "============================================================"
    echo "Model update failed with exit code: $exit_code"
    echo "============================================================"
    exit $exit_code
fi
