#!/bin/bash
set -e

echo "=== AI-DLC Environment Setup ==="

# 1. Check for Julia
if ! command -v julia &> /dev/null; then
    echo "Julia not found. Installing via juliaup..."
    
    # Install juliaup (official installer)
    curl -fsSL https://install.julialang.org | sh -s -- -y
    
    # Source the new environment
    source ~/.bashrc || source ~/.zshrc || true
    
    # Add to current path manually for this script execution
    export PATH="$HOME/.juliaup/bin:$PATH"
else
    echo "Julia is already installed: $(julia --version)"
fi

# 2. Setup Julia Project
echo "Setting up Julia project dependencies..."
cd "$(dirname "$0")/../src_julia"

# Instantiate the project (downloads and precompiles packages)
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

echo "=== Setup Complete! ==="
echo "You can now run the simulation with:"
echo "  julia --project=src_julia src_julia/main.jl"
