#!/bin/bash
#
# GUI起動スクリプト
# EPH Dashboard (PySide6) を起動します
#
# Usage:
#   ./scripts/start_gui.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  EPH Dashboard - GUI起動                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Error: python3が見つかりません${NC}"
    echo ""
    echo "Python 3をインストールしてください："
    echo -e "${CYAN}  brew install python@3${NC}"
    exit 1
fi

# Check if PySide6 is installed
if ! python3 -c "import PySide6" 2>/dev/null; then
    echo -e "${RED}✗ Error: PySide6がインストールされていません${NC}"
    echo ""
    echo "以下のコマンドでインストールしてください："
    echo -e "${CYAN}  pip3 install PySide6${NC}"
    echo ""
    echo "または、requirements.txtがある場合："
    echo -e "${CYAN}  pip3 install -r requirements.txt${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Python 3 が見つかりました${NC}"
echo -e "${GREEN}✓ PySide6 がインストールされています${NC}"
echo -e "${CYAN}GUIを起動しています...${NC}"
echo ""

# Launch GUI using python -m gui
python3 -m gui
