"""
Main Window - EPH Dashboard メインウィンドウ
"""

from pathlib import Path

from PySide6.QtWidgets import QMainWindow, QTabWidget
from PySide6.QtCore import Qt
from PySide6.QtGui import QIcon

from .tabs.validation_tab import ValidationTab
from .tabs.placeholder_tab import PlaceholderTab
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

        # GRU Trainingタブ（プレースホルダー）
        self.gru_tab = PlaceholderTab(
            "GRU Training",
            "Train GRU predictor for Phase 2 EPH. Collect training data, "
            "configure hyperparameters, and monitor training progress."
        )
        self.tabs.addTab(self.gru_tab, "🧠 GRU Training")

        # Experimentsタブ（プレースホルダー）
        self.experiments_tab = PlaceholderTab(
            "Experiments",
            "Run experiments (Baseline Comparison, Shepherding, etc.). "
            "Configure parameters, execute simulations, and view real-time results."
        )
        self.tabs.addTab(self.experiments_tab, "🧪 Experiments")

        # Analysisタブ（プレースホルダー）
        self.analysis_tab = PlaceholderTab(
            "Analysis & Reports",
            "Analyze experimental logs (.jld2), generate plots (EFE, haze, entropy), "
            "and export reports (PDF/Markdown)."
        )
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
        # 定期更新停止
        self.status_widget.stop_updates()

        # 実行中プロセスがあれば停止
        if hasattr(self.validation_tab, 'process') and self.validation_tab.process:
            if self.validation_tab.process.state() == self.validation_tab.process.Running:
                self.validation_tab.process.kill()

        event.accept()
