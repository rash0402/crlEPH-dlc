#!/bin/bash
# VAE SPM 可視化 GUI ランチャー
# 
# 使用方法:
#   ./scripts/run_vae_viewer.sh
#
# 機能:
#   - raw v7.2 HDF5ファイルからSPM（実測）とVAE予測を可視化
#   - インタラクティブにタイムステップ・エージェントを選択
#   - Grid View: 3チャンネル × (実測/予測/差分)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Python 仮想環境
VENV_PATH="${HOME}/local/venv"

if [ ! -d "$VENV_PATH" ]; then
    echo "Error: Python venv not found at $VENV_PATH"
    exit 1
fi

echo "========================================"
echo "VAE SPM Viewer - EPH v7.2"
echo "========================================"
echo ""
echo "起動中..."
echo ""

cd "$PROJECT_ROOT"
"$VENV_PATH/bin/python" viewer/interactive_vae_viewer.py
