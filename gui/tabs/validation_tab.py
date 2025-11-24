"""
Validation Tab - Phase検証タブ

Phase 1/2/compat/all の検証を実行し、結果をリアルタイム表示
"""

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton,
    QTextEdit, QComboBox, QLabel, QGroupBox, QProgressBar
)
from PySide6.QtCore import Qt, QProcess, Signal
from PySide6.QtGui import QFont, QTextCursor

from ..utils.system_checker import SystemChecker


class ValidationTab(QWidget):
    """Phase検証タブ"""

    validation_finished = Signal(bool, str)  # (成功, メッセージ)

    def __init__(self, system_checker: SystemChecker, parent=None):
        super().__init__(parent)
        self.system_checker = system_checker
        self.process = None

        self.init_ui()

    def init_ui(self):
        """UI初期化"""
        layout = QVBoxLayout()

        # タイトル
        title = QLabel("✅ EPH Phase Validation")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title.setFont(title_font)
        layout.addWidget(title)

        # 説明
        desc = QLabel(
            "Validate EPH Phase implementations (Phase 1: Scalar Self-Haze, "
            "Phase 2: Environmental Haze, Compatibility checks)"
        )
        desc.setWordWrap(True)
        layout.addWidget(desc)

        # コントロールパネル
        control_group = QGroupBox("Validation Control")
        control_layout = QHBoxLayout()

        # Phase選択
        control_layout.addWidget(QLabel("Phase:"))
        self.phase_combo = QComboBox()
        self.phase_combo.addItems(["all", "1", "2", "compat"])
        self.phase_combo.setCurrentText("all")
        control_layout.addWidget(self.phase_combo)

        control_layout.addStretch()

        # 実行ボタン
        self.run_button = QPushButton("▶ Run Validation")
        self.run_button.clicked.connect(self.run_validation)
        control_layout.addWidget(self.run_button)

        # 停止ボタン
        self.stop_button = QPushButton("⏹ Stop")
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop_validation)
        control_layout.addWidget(self.stop_button)

        control_group.setLayout(control_layout)
        layout.addWidget(control_group)

        # 進捗バー
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)  # インデターミネート
        self.progress_bar.setVisible(False)
        layout.addWidget(self.progress_bar)

        # 出力ログ
        log_group = QGroupBox("Output Log")
        log_layout = QVBoxLayout()

        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setFont(QFont("Courier", 10))
        self.log_output.setStyleSheet(
            "background-color: #1E1E1E; color: #D4D4D4;"
        )
        log_layout.addWidget(self.log_output)

        log_group.setLayout(log_layout)
        layout.addWidget(log_group)

        # ステータス
        self.status_label = QLabel("Ready")
        self.status_label.setStyleSheet("color: #9E9E9E;")
        layout.addWidget(self.status_label)

        self.setLayout(layout)

    def run_validation(self):
        """検証実行"""
        if self.process and self.process.state() == QProcess.Running:
            return

        phase = self.phase_combo.currentText()

        # UI状態更新
        self.run_button.setEnabled(False)
        self.stop_button.setEnabled(True)
        self.progress_bar.setVisible(True)
        self.log_output.clear()
        self.status_label.setText(f"Running validation for phase: {phase}")
        self.status_label.setStyleSheet("color: #2196F3;")

        # プロセス準備
        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.handle_finished)

        # コマンド実行
        cmd = self.system_checker.get_bash_command(
            f"scripts/run_basic_validation.sh"
        )
        cmd.append(phase)

        self.append_log(f"$ {' '.join(cmd)}\n", color="#9E9E9E")
        self.process.start(cmd[0], cmd[1:])

    def stop_validation(self):
        """検証停止"""
        if self.process and self.process.state() == QProcess.Running:
            self.process.kill()
            self.append_log("\n[Process terminated by user]\n", color="#F44336")

    def handle_stdout(self):
        """標準出力処理"""
        data = self.process.readAllStandardOutput().data().decode()
        self.append_log(data)

    def handle_stderr(self):
        """標準エラー出力処理"""
        data = self.process.readAllStandardError().data().decode()
        self.append_log(data, color="#FFA726")

    def handle_finished(self, exit_code, exit_status):
        """プロセス終了処理"""
        self.run_button.setEnabled(True)
        self.stop_button.setEnabled(False)
        self.progress_bar.setVisible(False)

        if exit_code == 0:
            self.status_label.setText("✅ Validation passed!")
            self.status_label.setStyleSheet("color: #4CAF50;")
            self.append_log("\n✅ All tests passed!\n", color="#4CAF50")
            self.validation_finished.emit(True, "Validation passed")
        else:
            self.status_label.setText("❌ Validation failed")
            self.status_label.setStyleSheet("color: #F44336;")
            self.append_log(f"\n❌ Validation failed (exit code: {exit_code})\n", color="#F44336")
            self.validation_finished.emit(False, f"Validation failed (exit code: {exit_code})")

    def append_log(self, text: str, color: str = None):
        """ログ追加"""
        cursor = self.log_output.textCursor()
        cursor.movePosition(QTextCursor.End)

        if color:
            self.log_output.setTextColor(color)

        cursor.insertText(text)
        self.log_output.setTextCursor(cursor)
        self.log_output.ensureCursorVisible()
