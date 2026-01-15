#!/bin/bash
################################################################################
# V7.2 Raw Trajectory Viewer Launcher
# Activates Python venv and launches interactive viewer
#
# Usage:
#   ./view_v72_data.sh                    # GUI file dialog (default)
#   ./view_v72_data.sh --menu             # Terminal menu
#   ./view_v72_data.sh path/to/file.h5    # Direct file specification
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

# Parse options
USE_MENU=false
if [ "$1" = "--menu" ]; then
    USE_MENU=true
    shift  # Remove --menu from arguments
fi

# Python venv path (primary choice)
VENV_PATH="$HOME/local/venv"
VENV_PYTHON="$VENV_PATH/bin/python"

# Determine which Python to use
PYTHON_BIN=""

if [ -f "$VENV_PYTHON" ]; then
    PYTHON_BIN="$VENV_PYTHON"
    echo -e "${YELLOW}Using Python from venv: $PYTHON_BIN${NC}"
elif command -v python3 &> /dev/null; then
    PYTHON_BIN=$(command -v python3)
    echo -e "${YELLOW}Using system Python: $PYTHON_BIN${NC}"
else
    echo -e "${RED}ERROR: No valid Python interpreter found.${NC}"
    echo "Checked:"
    echo "  1. $VENV_PYTHON"
    echo "  2. python3 command in PATH"
    echo ""
    echo "Please install Python 3 or create the venv:"
    echo "  python3 -m venv ~/local/venv"
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
    echo "  $PYTHON_BIN -m pip install ${MISSING_PACKAGES[*]}"
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
        if [ "$USE_MENU" = true ]; then
            echo -e "${GREEN}Found $NUM_FILES HDF5 file(s) in $DATA_DIR${NC}"
            echo ""
        else
            echo -e "${GREEN}Found $NUM_FILES HDF5 file(s)${NC}"
            echo -e "${BLUE}Tip: Use --menu flag for terminal menu selection${NC}"
            echo ""
        fi
    fi
fi

# Change to project root
cd "$PROJECT_ROOT"

if [ $# -eq 0 ]; then
    # No arguments - use GUI dialog or terminal menu
    if [ "$USE_MENU" = true ]; then
        # Terminal menu mode
        if [ -d "$DATA_DIR" ] && [ "$NUM_FILES" -gt 0 ]; then
            echo -e "${BLUE}========================================${NC}"
            echo -e "${BLUE}Select a file to visualize:${NC}"
            echo -e "${BLUE}========================================${NC}"
            echo ""

            # Create array of files (compatible with bash 3.2+)
            # Store find results in variable first
            FILE_LIST=$(find "$DATA_DIR" -name "*.h5" -type f | sort)

            FILES=()
            while IFS= read -r file; do
                [ -n "$file" ] && FILES+=("$file")
            done <<EOF
$FILE_LIST
EOF

            # Display files with numbers
            i=0
            for file in "${FILES[@]}"; do
                BASENAME=$(basename "$file")
                printf "%3d) %s\n" $((i+1)) "$BASENAME"
                i=$((i+1))
            done

            echo ""
            echo -e "${GREEN}Enter file number (1-$NUM_FILES), or press Enter for most recent:${NC}"
            read -r SELECTION

            if [ -z "$SELECTION" ]; then
                # No selection - use most recent file
                H5_FILE=$(find "$DATA_DIR" -name "*.h5" -type f -print0 | xargs -0 ls -t | head -1)
                echo -e "${YELLOW}Using most recent file: $(basename "$H5_FILE")${NC}"
            elif [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$NUM_FILES" ]; then
                # Valid selection
                H5_FILE="${FILES[$((SELECTION-1))]}"
                echo -e "${YELLOW}Selected: $(basename "$H5_FILE")${NC}"
            else
                echo -e "${RED}ERROR: Invalid selection${NC}"
                exit 1
            fi

            echo ""
            echo -e "${GREEN}Launching V7.2 Trajectory Viewer...${NC}"
            echo ""

            "$PYTHON_BIN" "$VIEWER_SCRIPT" "$H5_FILE"
        else
            # No files available - fall back to GUI dialog
            echo -e "${YELLOW}No files in $DATA_DIR${NC}"
            echo -e "${YELLOW}Launching GUI file selection dialog...${NC}"
            echo ""
            "$PYTHON_BIN" "$VIEWER_SCRIPT"
        fi
    else
        # GUI dialog mode (default)
        echo -e "${GREEN}Launching V7.2 Trajectory Viewer with GUI file dialog...${NC}"
        echo ""
        "$PYTHON_BIN" "$VIEWER_SCRIPT"
    fi
else
    # File path provided
    H5_FILE="$1"
    if [ ! -f "$H5_FILE" ]; then
        echo -e "${RED}ERROR: File not found: $H5_FILE${NC}"
        exit 1
    fi

    echo -e "${GREEN}Launching V7.2 Trajectory Viewer...${NC}"
    echo ""

    "$PYTHON_BIN" "$VIEWER_SCRIPT" "$H5_FILE"
fi
