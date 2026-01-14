#!/bin/bash
################################################################################
# V7.2 Raw Trajectory Viewer Launcher
# Activates Python venv and launches interactive viewer
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Python venv path
VENV_PATH="$HOME/local/venv"
PYTHON_BIN="$VENV_PATH/bin/python"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}V7.2 Raw Trajectory Viewer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if venv exists
if [ ! -d "$VENV_PATH" ]; then
    echo -e "${RED}ERROR: Python venv not found at $VENV_PATH${NC}"
    echo ""
    echo "Please create venv first:"
    echo "  python3 -m venv ~/local/venv"
    echo "  ~/local/venv/bin/pip install h5py numpy matplotlib"
    echo ""
    exit 1
fi

# Check if Python binary exists
if [ ! -f "$PYTHON_BIN" ]; then
    echo -e "${RED}ERROR: Python binary not found at $PYTHON_BIN${NC}"
    exit 1
fi

# Check if viewer script exists
VIEWER_SCRIPT="$SCRIPT_DIR/raw_v72_viewer.py"
if [ ! -f "$VIEWER_SCRIPT" ]; then
    echo -e "${RED}ERROR: Viewer script not found at $VIEWER_SCRIPT${NC}"
    exit 1
fi

# Check required Python packages
echo -e "${YELLOW}Checking Python dependencies...${NC}"
MISSING_PACKAGES=()

for package in h5py numpy matplotlib; do
    if ! "$PYTHON_BIN" -c "import $package" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo -e "${RED}ERROR: Missing Python packages: ${MISSING_PACKAGES[*]}${NC}"
    echo ""
    echo "Install missing packages:"
    echo "  $VENV_PATH/bin/pip install ${MISSING_PACKAGES[*]}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Check if data directory exists
DATA_DIR="$PROJECT_ROOT/data/vae_training/raw_v72"
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${YELLOW}WARNING: Data directory not found at $DATA_DIR${NC}"
    echo "The viewer will start, but you may need to navigate to your data files manually."
    echo ""
fi

# Count available data files
if [ -d "$DATA_DIR" ]; then
    NUM_FILES=$(find "$DATA_DIR" -name "*.h5" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$NUM_FILES" -eq 0 ]; then
        echo -e "${YELLOW}WARNING: No HDF5 files found in $DATA_DIR${NC}"
        echo "Please run data collection first:"
        echo "  julia --project=. scripts/create_dataset_v72_scramble.jl"
        echo ""
    else
        echo -e "${GREEN}Found $NUM_FILES HDF5 file(s) in $DATA_DIR${NC}"
        echo ""
    fi
fi

# Display usage info
echo -e "${BLUE}Usage:${NC}"
echo "  1. File selection dialog will appear (default)"
echo "  2. Or specify file as argument:"
echo "     $0 path/to/file.h5"
echo ""

# Launch viewer
echo -e "${GREEN}Launching V7.2 Trajectory Viewer...${NC}"
echo ""

cd "$PROJECT_ROOT"

if [ $# -eq 0 ]; then
    # No arguments - show file dialog
    "$PYTHON_BIN" "$VIEWER_SCRIPT"
else
    # File path provided
    H5_FILE="$1"
    if [ ! -f "$H5_FILE" ]; then
        echo -e "${RED}ERROR: File not found: $H5_FILE${NC}"
        exit 1
    fi
    "$PYTHON_BIN" "$VIEWER_SCRIPT" "$H5_FILE"
fi
