#!/bin/bash
# EPH Simulation Launcher

echo "🚀 Starting EPH Simulation..."
echo "   Command: julia --project=. scripts/run_simulation.jl"
echo ""

julia --project=. scripts/run_simulation.jl
