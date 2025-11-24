"""
Placeholder Tab - 未実装タブのプレースホルダー
"""

from PySide6.QtWidgets import QWidget, QVBoxLayout, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QFont


class PlaceholderTab(QWidget):
    """未実装タブのプレースホルダー"""

    def __init__(self, tab_name: str, description: str, parent=None):
        super().__init__(parent)
        self.tab_name = tab_name
        self.description = description
        self.init_ui()

    def init_ui(self):
        """UI初期化"""
        layout = QVBoxLayout()
        layout.setAlignment(Qt.AlignCenter)

        # タイトル
        title = QLabel(f"🚧 {self.tab_name}")
        title_font = QFont()
        title_font.setPointSize(20)
        title_font.setBold(True)
        title.setFont(title_font)
        title.setAlignment(Qt.AlignCenter)
        layout.addWidget(title)

        # 説明
        desc = QLabel(self.description)
        desc.setWordWrap(True)
        desc.setAlignment(Qt.AlignCenter)
        desc_font = QFont()
        desc_font.setPointSize(12)
        desc.setFont(desc_font)
        desc.setStyleSheet("color: #9E9E9E; margin: 20px;")
        layout.addWidget(desc)

        # Coming Soon
        coming_soon = QLabel("Coming Soon...")
        coming_soon_font = QFont()
        coming_soon_font.setPointSize(14)
        coming_soon_font.setItalic(True)
        coming_soon.setFont(coming_soon_font)
        coming_soon.setAlignment(Qt.AlignCenter)
        coming_soon.setStyleSheet("color: #FFA726;")
        layout.addWidget(coming_soon)

        self.setLayout(layout)
