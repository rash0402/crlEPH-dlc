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

        # 説明（役割を明確化）
        desc = QLabel(
            "🔧 <b>開発者向け：システム動作確認・品質テスト</b><br>"
            "EPH実装が正しく動作するかを検証します（単体テスト相当）。<br>"
            "研究実験を行う前に、まずこのValidationが全てPassすることを確認してください。<br><br>"
            "<b>Experimentsタブとの違い:</b> こちらは動作確認のみ。実験データは生成しません。"
        )
        desc.setWordWrap(True)
        desc.setTextFormat(Qt.RichText)
        desc.setStyleSheet(
            "background-color: #FFF3E0; "
            "border: 1px solid #FF9800; "
            "border-radius: 4px; "
            "padding: 12px; "
            "color: #E65100; "
            "margin: 10px 0px;"
        )
        layout.addWidget(desc)

        # コントロールパネル
        control_group = QGroupBox("Validation Control")
        control_layout = QHBoxLayout()

        # Phase選択
        control_layout.addWidget(QLabel("Phase:"))
        self.phase_combo = QComboBox()
        self.phase_combo.addItems(["all", "1", "2", "3", "4"])
        self.phase_combo.setCurrentText("all")
        self.phase_combo.currentIndexChanged.connect(self.update_phase_description)
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

        # Phase説明
        self.phase_description = QLabel()
        self.phase_description.setWordWrap(True)
        self.phase_description.setStyleSheet(
            "background-color: #E3F2FD; "
            "border: 1px solid #2196F3; "
            "border-radius: 4px; "
            "padding: 12px; "
            "color: #1565C0; "
            "margin: 5px 0px;"
        )
        layout.addWidget(self.phase_description)
        self.update_phase_description()

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

    def update_phase_description(self):
        """Phase説明を更新"""
        phase = self.phase_combo.currentText()

        descriptions = {
            "all": "📋 <b>All Phases:</b> 全Phase（1, 2, 3, 4）の検証を順次実行します。<br><br>"
                   "すべてのテストが成功することで、EPHシステム全体の動作が保証されます。",

            "1": "🔵 <b>Phase 1 - Scalar Self-Haze:</b> <br>"
                 "エージェントが<b>自分自身のヘイズ値（スカラー値）</b>を持ち、周囲のエージェントとの相互作用を通じて行動を調整します。<br><br>"
                 "<b>特徴:</b><br>"
                 "• 各エージェントが1つのヘイズ値（0.0〜1.0）を持つ<br>"
                 "• 他エージェントとの接触時にヘイズが増加<br>"
                 "• 時間経過でヘイズが減衰<br>"
                 "• 最もシンプルなスティグマージー実装<br><br>"
                 "<b>用途:</b> 基本的な群知能・回避行動の検証",

            "2": "🌐 <b>Phase 2 - 2D Environmental Haze:</b> <br>"
                 "環境空間に<b>2次元ヘイズグリッド</b>が存在し、エージェントがヘイズを堆積・感知します。<br><br>"
                 "<b>特徴:</b><br>"
                 "• 環境全体が2Dグリッドでヘイズ値を保持<br>"
                 "• エージェントが移動経路にヘイズを残す<br>"
                 "• GRU予測器により将来のヘイズを予測可能<br>"
                 "• より複雑な集団行動パターンが創発<br><br>"
                 "<b>用途:</b> 経路計画・群れ行動・shepherdingタスク",

            "3": "🚀 <b>Phase 3 - Advanced Integration:</b> <br>"
                 "<b>GRU予測器</b>と<b>Shepherding機能</b>の高度な統合を検証します。<br><br>"
                 "<b>検証項目:</b><br>"
                 "• SPMPredictor（LinearPredictor, NeuralPredictor）のロード<br>"
                 "• ShepherdingEPH（犬エージェントの制御）のロード<br>"
                 "• BoidsAgent（羊エージェントの制御）のロード<br>"
                 "• GRUモデルの読み込み（学習済みモデルがある場合）<br><br>"
                 "<b>用途:</b> Phase 2の高度な応用機能の動作確認",

            "4": "🎯 <b>Phase 4 - Full 3D Tensor Haze:</b> <br>"
                 "<b>3次元ヘイズテンソル H(r, θ, c)</b> を用いた最も高度な精度制御を検証します。<br><br>"
                 "<b>特徴:</b><br>"
                 "• チャネル毎（占有、速度）に独立したヘイズ値を持つ<br>"
                 "• Per-channel precision modulation: Π = (1-h)^γ<br>"
                 "• Selective attention via channel masking<br>"
                 "• 「障害物は見えるが無視する」ような高度な認知的バイアスを実現<br><br>"
                 "<b>検証項目:</b><br>"
                 "• FullTensorHaze module import<br>"
                 "• FullTensorHazeParams instantiation<br>"
                 "• 3D haze tensor computation<br>"
                 "• Per-channel precision computation<br>"
                 "• Channel mask application<br>"
                 "• Weighted surprise computation<br><br>"
                 "<b>用途:</b> 最先端の認知制御・選択的注意機構の検証"
        }

        self.phase_description.setText(descriptions.get(phase, ""))
