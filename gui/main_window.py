"""
Main Window - EPH Dashboard メインウィンドウ
"""

from pathlib import Path

from PySide6.QtWidgets import QMainWindow, QTabWidget
from PySide6.QtCore import Qt
from PySide6.QtGui import QIcon

from .tabs.validation_tab import ValidationTab
from .tabs.gru_training_tab import GRUTrainingTab
from .tabs.experiments_tab import ExperimentsTab
from .tabs.analysis_tab import AnalysisTab
from .widgets.system_status import SystemStatusWidget
from .utils.system_checker import SystemChecker


class MainWindow(QMainWindow):
    """EPH Dashboard メインウィンドウ"""

    def __init__(self):
        super().__init__()
        self.project_root = Path(__file__).parent.parent
        self.system_checker = SystemChecker(self.project_root)

        self.init_ui()
        self.load_stylesheet()

    def init_ui(self):
        """UI初期化"""
        self.setWindowTitle("EPH Dashboard - Emergent Perceptual Haze Control Center")
        self.setGeometry(100, 100, 1400, 900)

        # タブウィジェット
        self.tabs = QTabWidget()
        self.tabs.setTabPosition(QTabWidget.North)

        # Validationタブ
        self.validation_tab = ValidationTab(self.system_checker)
        self.tabs.addTab(self.validation_tab, "✅ Validation")

        # GRU Trainingタブ
        self.gru_tab = GRUTrainingTab(self.system_checker)
        self.tabs.addTab(self.gru_tab, "🧠 GRU Training")

        # Experimentsタブ
        self.experiments_tab = ExperimentsTab(self.system_checker)
        self.tabs.addTab(self.experiments_tab, "🧪 Experiments")

        # Analysisタブ
        self.analysis_tab = AnalysisTab(self.system_checker)
        self.tabs.addTab(self.analysis_tab, "📊 Analysis")

        self.setCentralWidget(self.tabs)

        # ステータスバー
        self.status_widget = SystemStatusWidget(self.system_checker)
        self.statusBar().addPermanentWidget(self.status_widget)
        self.statusBar().showMessage("Welcome to EPH Dashboard")

    def load_stylesheet(self):
        """スタイルシート読み込み"""
        style_path = self.project_root / "gui" / "styles" / "material_dark.qss"
        if style_path.exists():
            with open(style_path, "r") as f:
                self.setStyleSheet(f.read())

    def closeEvent(self, event):
        """ウィンドウクローズ処理"""
        from PySide6.QtCore import QProcess

        # 定期更新停止
        if hasattr(self, 'status_widget'):
            self.status_widget.stop_updates()

        # 実行中プロセスがあれば停止
        for tab in [self.validation_tab, self.gru_tab, self.experiments_tab]:
            if hasattr(tab, 'process') and tab.process:
                try:
                    if tab.process.state() == QProcess.Running:
                        tab.process.kill()
                        tab.process.waitForFinished(3000)  # Wait up to 3 seconds
                except Exception as e:
                    print(f"Warning: Error stopping process in tab: {e}")

        # GRU Training タブのタイマー停止
        if hasattr(self, 'gru_tab') and hasattr(self.gru_tab, 'refresh_timer'):
            try:
                self.gru_tab.refresh_timer.stop()
            except Exception as e:
                print(f"Warning: Error stopping timer: {e}")

        event.accept()
