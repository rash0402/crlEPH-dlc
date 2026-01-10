#!/usr/bin/env bash
#
# EPH Project Setup Script
# Automatically installs Julia and Python dependencies
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

info "EPH Project Setup"
info "Project root: $PROJECT_ROOT"
echo ""

# ========================================
# 1. Check Julia Installation
# ========================================
info "Checking Julia installation..."

if ! command -v julia &> /dev/null; then
    error "Julia not found. Please install Julia 1.10+ first:

    Option 1 (Recommended): juliaup
        curl -fsSL https://install.julialang.org | sh

    Option 2: Homebrew
        brew install julia

    Option 3: Official download
        https://julialang.org/downloads/"
fi

JULIA_VERSION=$(julia --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
JULIA_MAJOR=$(echo "$JULIA_VERSION" | cut -d. -f1)
JULIA_MINOR=$(echo "$JULIA_VERSION" | cut -d. -f2)

if [ "$JULIA_MAJOR" -lt 1 ] || ([ "$JULIA_MAJOR" -eq 1 ] && [ "$JULIA_MINOR" -lt 10 ]); then
    error "Julia $JULIA_VERSION found, but 1.10+ is required. Please upgrade."
fi

success "Julia $JULIA_VERSION found"

# ========================================
# 2. Install Julia Dependencies
# ========================================
info "Installing Julia dependencies..."
echo ""

julia --project=. -e '
using Pkg
println("Resolving package versions...")
Pkg.instantiate()
println("\nPrecompiling packages...")
Pkg.precompile()
println("\nPackage status:")
Pkg.status()
'

if [ $? -eq 0 ]; then
    success "Julia dependencies installed"
else
    error "Julia dependency installation failed"
fi

echo ""

# ========================================
# 3. Check Python Installation
# ========================================
info "Checking Python installation..."

# Try multiple Python locations
PYTHON_CMD=""
if [ -x "$HOME/local/venv/bin/python" ]; then
    PYTHON_CMD="$HOME/local/venv/bin/python"
    PYTHON_VENV="$HOME/local/venv"
elif command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_VENV=""
else
    warning "Python not found in ~/local/venv/. Do you want to create a virtual environment? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info "Creating virtual environment at ~/local/venv/..."
        mkdir -p "$HOME/local"
        python3 -m venv "$HOME/local/venv"
        PYTHON_CMD="$HOME/local/venv/bin/python"
        PYTHON_VENV="$HOME/local/venv"
        success "Virtual environment created"
    else
        warning "Skipping Python setup. Install manually with:

        mkdir -p ~/local
        python3 -m venv ~/local/venv
        ~/local/venv/bin/pip install -r requirements.txt"
        exit 0
    fi
fi

PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
success "Python $PYTHON_VERSION found"

if [ -n "$PYTHON_VENV" ]; then
    info "Using virtual environment: $PYTHON_VENV"
fi

# ========================================
# 4. Install Python Dependencies
# ========================================
info "Installing Python dependencies..."
echo ""

if [ -n "$PYTHON_VENV" ]; then
    PIP_CMD="$PYTHON_VENV/bin/pip"
else
    PIP_CMD="pip3"
fi

$PIP_CMD install -r requirements.txt

if [ $? -eq 0 ]; then
    success "Python dependencies installed"
else
    error "Python dependency installation failed"
fi

echo ""

# ========================================
# 5. Verify Installation
# ========================================
info "Verifying installation..."
echo ""

# Check Julia packages
info "Julia packages:"
julia --project=. -e 'using Pkg; Pkg.status()' | grep -E "(Flux|ForwardDiff|HDF5|ZMQ|MsgPack)"

echo ""

# Check Python packages
info "Python packages:"
$PIP_CMD list | grep -E "(pygame|matplotlib|numpy|pyzmq|msgpack)"

echo ""

# ========================================
# 6. Setup Complete
# ========================================
success "Setup complete!"
echo ""
info "Next steps:"
echo ""
echo "  1. Run simulation:"
echo "     ${GREEN}./scripts/run_all.sh${NC}"
echo ""
echo "  2. Or run backend and viewers separately:"
echo "     ${GREEN}julia --project=. scripts/run_simulation.jl${NC}"
echo "     ${GREEN}~/local/venv/bin/python viewer/detail_viewer.py${NC}"
echo ""
echo "  3. Train VAE:"
echo "     ${GREEN}julia --project=. scripts/train_action_vae.jl${NC}"
echo ""
echo "  4. Validate Haze:"
echo "     ${GREEN}julia --project=. scripts/validate_haze.jl${NC}"
echo ""
info "For more information, see CLAUDE.md or SETUP.md"
