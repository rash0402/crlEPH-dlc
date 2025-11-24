"""
System Status Widget - システム状態表示ウィジェット

ステータスバーに表示するシステム状態インジケーター
"""

from PySide6.QtWidgets import QWidget, QHBoxLayout, QLabel
from PySide6.QtCore import QTimer
from PySide6.QtGui import QFont

from ..utils.system_checker import SystemChecker


class SystemStatusWidget(QWidget):
    """システム状態表示ウィジェット（ステータスバー用）"""

    def __init__(self, system_checker: SystemChecker, parent=None):
        super().__init__(parent)
        self.system_checker = system_checker

        # レイアウト
        layout = QHBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(15)

        # ステータスラベル（Julia, Data, Scripts, Project）
        self.julia_label = self._create_status_label()
        self.data_label = self._create_status_label()
        self.scripts_label = self._create_status_label()
        self.project_label = self._create_status_label()

        layout.addWidget(QLabel("🖥️"))
        layout.addWidget(self.julia_label)
        layout.addWidget(QLabel("|"))
        layout.addWidget(QLabel("📁"))
        layout.addWidget(self.data_label)
        layout.addWidget(QLabel("|"))
        layout.addWidget(QLabel("📜"))
        layout.addWidget(self.scripts_label)
        layout.addWidget(QLabel("|"))
        layout.addWidget(QLabel("📦"))
        layout.addWidget(self.project_label)

        self.setLayout(layout)

        # 初回チェック
        self.update_status()

        # 定期更新タイマー（30秒ごと）
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_status)
        self.timer.start(30000)

    def _create_status_label(self) -> QLabel:
        """ステータスラベル生成"""
        label = QLabel("...")
        font = QFont("Courier", 10)
        label.setFont(font)
        return label

    def update_status(self):
        """ステータス更新"""
        results = self.system_checker.check_all()

        # Julia
        success, msg = results.get("Julia", (False, ""))
        self.julia_label.setText("Julia ✅" if success else "Julia ❌")
        self.julia_label.setToolTip(msg)
        self.julia_label.setStyleSheet(
            "color: #4CAF50;" if success else "color: #F44336;"
        )

        # Data Dirs
        success, msg = results.get("Data Dirs", (False, ""))
        self.data_label.setText("Data ✅" if success else "Data ❌")
        self.data_label.setToolTip(msg)
        self.data_label.setStyleSheet(
            "color: #4CAF50;" if success else "color: #F44336;"
        )

        # Scripts
        success, msg = results.get("Scripts", (False, ""))
        self.scripts_label.setText("Scripts ✅" if success else "Scripts ❌")
        self.scripts_label.setToolTip(msg)
        self.scripts_label.setStyleSheet(
            "color: #4CAF50;" if success else "color: #F44336;"
        )

        # Julia Project
        success, msg = results.get("Julia Project", (False, ""))
        self.project_label.setText("Project ✅" if success else "Project ❌")
        self.project_label.setToolTip(msg)
        self.project_label.setStyleSheet(
            "color: #4CAF50;" if success else "color: #F44336;"
        )

    def stop_updates(self):
        """定期更新停止"""
        self.timer.stop()
