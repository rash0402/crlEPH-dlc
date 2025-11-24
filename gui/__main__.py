"""
EPH Dashboard - Entry Point
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from PySide6.QtWidgets import QApplication
from gui.main_window import MainWindow


def main():
    """Main entry point for EPH Dashboard"""
    app = QApplication(sys.argv)
    app.setApplicationName("EPH Dashboard")

    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
