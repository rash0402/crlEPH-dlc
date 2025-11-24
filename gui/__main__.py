#!/usr/bin/env python3
"""
EPH Dashboard - Entry Point

Usage:
    python -m gui
    python3 -m gui
"""

import sys
from PySide6.QtWidgets import QApplication
from .main_window import MainWindow


def main():
    """EPH Dashboard メインエントリーポイント"""
    app = QApplication(sys.argv)
    app.setApplicationName("EPH Dashboard")
    app.setOrganizationName("EPH Research")

    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
