#!/bin/bash
set -e

# Add Julia to PATH if installed via juliaup
export PATH="$HOME/.juliaup/bin:$PATH"

echo "Starting Julia EPH Server..."
cd "$(dirname "$0")/.."
julia src_julia/main.jl
