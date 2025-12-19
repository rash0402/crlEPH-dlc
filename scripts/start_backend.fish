#!/usr/bin/env fish
# EPH Backend Launcher (Fish shell)
# Starts Julia simulation with proper project environment

set SCRIPT_DIR (realpath (dirname (status -f)))
set PROJECT_DIR (dirname $SCRIPT_DIR)

echo "============================================================"
echo "EPH Backend Launcher"
echo "============================================================"
echo ""
echo "📂 Project: $PROJECT_DIR"
echo ""

# Julia path
set JULIA_BIN "$HOME/.juliaup/bin/julia"

# Check if Julia is installed
if not test -f $JULIA_BIN
    echo "❌ Error: Julia not found at $JULIA_BIN"
    echo "   Please install Julia 1.10+ from https://julialang.org"
    exit 1
end

echo "✅ Julia found: "($JULIA_BIN --version)
echo ""

# Check if dependencies are installed
if not test -f "$PROJECT_DIR/Manifest.toml"
    echo "📦 Installing Julia dependencies..."
    cd $PROJECT_DIR
    $JULIA_BIN --project=. -e 'using Pkg; Pkg.instantiate()'
    echo ""
end

# Run simulation
echo "🚀 Starting EPH simulation..."
echo "   Press Ctrl+C to stop"
echo ""

cd $PROJECT_DIR
exec $JULIA_BIN --project=. scripts/run_simulation.jl
