#!/usr/bin/env python3
"""
EPH Dashboard - Emergent Perceptual Haze Experiment Control Center

Usage:
    python eph_dashboard.py
"""

import sys
from pathlib import Path

# プロジェクトルートをPythonパスに追加
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from PySide6.QtWidgets import QApplication
from gui.main_window import MainWindow


def main():
    """メイン関数"""
    app = QApplication(sys.argv)
    app.setApplicationName("EPH Dashboard")
    app.setOrganizationName("EPH Research")

    # メインウィンドウ作成・表示
    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
