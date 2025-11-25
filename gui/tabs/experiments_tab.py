"""
Experiments Tab - 実験実行・パラメータ設定タブ
"""

from pathlib import Path

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox,
    QPushButton, QLabel, QTextEdit, QProgressBar,
    QComboBox, QSpinBox, QDoubleSpinBox, QFormLayout
)
from PySide6.QtCore import Qt, QProcess, Signal, QProcessEnvironment
from PySide6.QtGui import QTextCursor, QColor

from ..utils.system_checker import SystemChecker


class ExperimentsTab(QWidget):
    """実験実行・パラメータ設定タブ"""

    experiment_finished = Signal(bool, str)

    def __init__(self, system_checker: SystemChecker, parent=None):
        super().__init__(parent)
        self.system_checker = system_checker
        self.project_root = system_checker.project_root
        self.process = None

        self.init_ui()

    def init_ui(self):
        """UI初期化"""
        layout = QVBoxLayout()

        # ===== 全体説明 =====
        overview = QLabel(
            "🔬 <b>研究者向け：実験実行・データ収集</b><br>"
            "パラメータを調整して実際の研究実験を実行し、論文用のデータを生成します。<br>"
            "実験結果は <code>src_julia/data/logs/</code> に保存されます。<br><br>"
            "<b>Validationタブとの違い:</b> こちらは研究データ生成目的。パラメータ調整可能。"
        )
        overview.setWordWrap(True)
        overview.setTextFormat(Qt.RichText)
        overview.setStyleSheet(
            "background-color: #E8F5E9; "
            "border: 1px solid #4CAF50; "
            "border-radius: 4px; "
            "padding: 12px; "
            "color: #1B5E20; "
            "margin: 10px 0px;"
        )
        layout.addWidget(overview)

        # ===== Experiment Type Selection =====
        type_group = QGroupBox("🧪 Experiment Type")
        type_layout = QVBoxLayout()

        self.experiment_combo = QComboBox()
        self.experiment_combo.addItems([
            "Phase 1 - Scalar Self-Haze",
            "Phase 2 - Environmental Haze (Optimized)",
            "Phase 3 - Full Tensor Haze (Per-Channel)",
            "Phase 4 - Shepherding Task",
            "Baseline Comparison",
            "Custom Experiment"
        ])
        self.experiment_combo.currentIndexChanged.connect(self.update_description)

        type_layout.addWidget(QLabel("Select experiment type:"))
        type_layout.addWidget(self.experiment_combo)

        # Experiment description
        self.description_label = QLabel()
        self.description_label.setWordWrap(True)
        self.description_label.setStyleSheet(
            "background-color: #E3F2FD; "
            "border: 1px solid #2196F3; "
            "border-radius: 4px; "
            "padding: 12px; "
            "color: #1565C0; "
            "margin: 10px 0px;"
        )
        type_layout.addWidget(self.description_label)

        type_group.setLayout(type_layout)
        layout.addWidget(type_group)

        # ===== Parameters Section =====
        params_group = QGroupBox("⚙️ Experiment Parameters")
        params_layout = QFormLayout()

        # Number of agents
        self.n_agents_spin = QSpinBox()
        self.n_agents_spin.setRange(1, 100)
        self.n_agents_spin.setValue(10)
        params_layout.addRow("Number of Agents:", self.n_agents_spin)

        # Simulation time
        self.sim_time_spin = QSpinBox()
        self.sim_time_spin.setRange(10, 1000)
        self.sim_time_spin.setValue(200)
        self.sim_time_spin.setSuffix(" seconds")
        params_layout.addRow("Simulation Time:", self.sim_time_spin)

        # World size
        self.world_size_spin = QSpinBox()
        self.world_size_spin.setRange(100, 2000)
        self.world_size_spin.setValue(400)
        self.world_size_spin.setSuffix(" pixels")
        params_layout.addRow("World Size:", self.world_size_spin)

        # Haze decay rate
        self.haze_decay_spin = QDoubleSpinBox()
        self.haze_decay_spin.setRange(0.8, 0.999)
        self.haze_decay_spin.setValue(0.99)
        self.haze_decay_spin.setSingleStep(0.01)
        self.haze_decay_spin.setDecimals(3)
        params_layout.addRow("Haze Decay Rate:", self.haze_decay_spin)

        # Haze deposit amount
        self.haze_deposit_spin = QDoubleSpinBox()
        self.haze_deposit_spin.setRange(0.0, 1.0)
        self.haze_deposit_spin.setValue(0.2)
        self.haze_deposit_spin.setSingleStep(0.05)
        self.haze_deposit_spin.setDecimals(2)
        params_layout.addRow("Haze Deposit:", self.haze_deposit_spin)

        params_group.setLayout(params_layout)
        layout.addWidget(params_group)

        # Parameter note
        params_note = QLabel(
            "✓ Parameters are applied via environment variables. "
            "Experiments will use these values instead of default configurations."
        )
        params_note.setWordWrap(True)
        params_note.setStyleSheet("color: #4CAF50; font-style: italic; margin: 5px;")
        layout.addWidget(params_note)

        # ===== Execution Control =====
        control_group = QGroupBox("🚀 Execution Control")
        control_layout = QHBoxLayout()

        self.run_btn = QPushButton("▶ Run Experiment")
        self.run_btn.clicked.connect(self.run_experiment)
        self.run_btn.setStyleSheet("background-color: #4CAF50;")

        self.stop_btn = QPushButton("⏹ Stop")
        self.stop_btn.clicked.connect(self.stop_experiment)
        self.stop_btn.setEnabled(False)
        self.stop_btn.setStyleSheet("background-color: #F44336;")

        self.reset_btn = QPushButton("🔄 Reset Parameters")
        self.reset_btn.clicked.connect(self.reset_parameters)

        control_layout.addWidget(self.run_btn)
        control_layout.addWidget(self.stop_btn)
        control_layout.addWidget(self.reset_btn)

        control_group.setLayout(control_layout)
        layout.addWidget(control_group)

        # ===== Progress Bar =====
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        layout.addWidget(self.progress_bar)

        # ===== Log Output =====
        log_group = QGroupBox("📜 Experiment Log")
        log_layout = QVBoxLayout()

        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setMinimumHeight(300)

        log_layout.addWidget(self.log_output)
        log_group.setLayout(log_layout)
        layout.addWidget(log_group)

        self.setLayout(layout)

        # Initial description
        self.update_description()

    def update_description(self):
        """実験タイプの説明を更新"""
        descriptions = {
            0: "🔵 <b>Phase 1 - Scalar Self-Haze:</b><br>"
               "エージェントが<b>自分自身のヘイズ値（スカラー値）</b>を持ち、周囲のエージェントとの相互作用を通じて行動を調整します。<br><br>"
               "<b>特徴:</b><br>"
               "• 各エージェントが1つのヘイズ値（0.0〜1.0）を持つ<br>"
               "• 他エージェントとの接触時にヘイズが増加<br>"
               "• 時間経過でヘイズが減衰<br>"
               "• 最もシンプルなスティグマージー実装<br><br>"
               "<b>用途:</b> 基本的な群知能・回避行動の研究データ生成",

            1: "🌐 <b>Phase 2 - 2D Environmental Haze (Basic):</b><br>"
               "環境空間に<b>2次元ヘイズグリッド</b>が存在し、エージェントがヘイズを堆積・感知します。<br><br>"
               "<b>特徴:</b><br>"
               "• 環境全体が2Dグリッドでヘイズ値を保持<br>"
               "• エージェントが移動経路にヘイズを残す<br>"
               "• 基本的な環境ヘイズ実装（予測器なし）<br>"
               "• より複雑な集団行動パターンが創発<br><br>"
               "<b>用途:</b> 経路計画・群れ行動の基礎データ収集",

            2: "🎯 <b>Phase 3 - Full Tensor Haze:</b><br>"
               "<b>3次元ヘイズテンソル H(r, θ, c)</b> を用いた高度な精度制御実験を実行します。<br><br>"
               "<b>特徴:</b><br>"
               "• チャネル毎（占有、速度）に独立したヘイズ値<br>"
               "• Per-channel precision modulation: Π = (1-h)^γ<br>"
               "• Selective attention via channel masking<br>"
               "• 「障害物は見えるが無視する」ような高度な認知的バイアス<br><br>"
               "<b>評価指標:</b> チャネル選択的注意の効果、Coverage、探索効率<br>"
               "<b>用途:</b> 最先端の認知制御研究・選択的注意の実現",

            3: "🚀 <b>Phase 4 - Shepherding Task:</b><br>"
               "<b>GRU予測器</b>と<b>Shepherding機能</b>の高度な統合実験を実行します。<br><br>"
               "<b>実験内容:</b><br>"
               "• GRU予測器による将来SPM予測<br>"
               "• Shepherding Task: 犬エージェントが羊を誘導<br>"
               "• 犬: EPH制御、羊: Boids制御<br>"
               "• 予測的行動計画の効果を検証<br><br>"
               "<b>評価指標:</b> 収束時間、経路滑らかさ、タスク成功率<br>"
               "<b>用途:</b> 目標駆動型タスクでの応用研究",

            4: "📊 <b>Baseline Comparison:</b><br>"
               "EPHエージェントと<b>ベースラインコントローラー</b>を比較評価します。<br><br>"
               "<b>比較対象:</b><br>"
               "• Random controller<br>"
               "• Pure Gradient controller<br>"
               "• Repulsion-based controller<br><br>"
               "<b>評価指標:</b> 回避成功率、経路効率、群れ維持性能<br>"
               "<b>用途:</b> EPHの有効性を定量的に実証",

            5: "⚙️ <b>Custom Experiment:</b><br>"
               "カスタム実験設定を実行（手動スクリプト設定が必要）。<br><br>"
               "<b>注意:</b> 実験スクリプトの手動設定が必要です。<br>"
               "独自の実験を実施したい場合に使用してください。"
        }

        index = self.experiment_combo.currentIndex()
        self.description_label.setText(descriptions.get(index, ""))

    def reset_parameters(self):
        """パラメータをリセット"""
        self.n_agents_spin.setValue(10)
        self.sim_time_spin.setValue(200)
        self.world_size_spin.setValue(400)
        self.haze_decay_spin.setValue(0.99)
        self.haze_deposit_spin.setValue(0.2)
        self.append_log("✓ Parameters reset to defaults\n", QColor("#2196F3"))

    def run_experiment(self):
        """実験を実行"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("❌ Experiment already running\n", QColor("#F44336"))
            return

        self.log_output.clear()
        experiment_type = self.experiment_combo.currentIndex()

        # Get experiment script
        script_map = {
            0: ("scripts/run_basic_validation.sh", "1"),  # Phase 1
            1: ("scripts/run_basic_validation.sh", "2"),  # Phase 2
            2: ("scripts/run_shepherding_experiment.sh", None),  # Phase 3
            3: ("scripts/run_basic_validation.sh", "4"),  # Phase 4
            4: ("scripts/baseline_comparison.jl", None),  # Baseline
            5: (None, None)  # Custom
        }

        script_info = script_map.get(experiment_type)

        if script_info is None or script_info[0] is None:
            self.append_log(
                "❌ Custom experiments not yet supported\n",
                QColor("#F44336")
            )
            return

        script, arg = script_info

        self.append_log(f"🚀 Starting experiment: {self.experiment_combo.currentText()}\n", QColor("#2196F3"))
        self.append_log(f"Running: {script}")
        if arg:
            self.append_log(f" {arg}")
        self.append_log("\n")
        self.append_log(f"Parameters:\n")
        self.append_log(f"  - Agents: {self.n_agents_spin.value()}\n")
        self.append_log(f"  - Time: {self.sim_time_spin.value()}s\n")
        self.append_log(f"  - World: {self.world_size_spin.value()}px\n")
        self.append_log(f"  - Haze Decay: {self.haze_decay_spin.value()}\n")
        self.append_log(f"  - Haze Deposit: {self.haze_deposit_spin.value()}\n")
        self.append_log("\n")

        # Start process
        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.handle_finished)

        # Set environment variables (inherit system env + add experiment parameters)
        env = QProcessEnvironment.systemEnvironment()
        env.insert("EPH_NON_INTERACTIVE", "1")

        # パラメータを環境変数として設定
        env.insert("EPH_N_AGENTS", str(self.n_agents_spin.value()))
        env.insert("EPH_SIM_TIME", str(self.sim_time_spin.value()))
        env.insert("EPH_WORLD_SIZE", str(self.world_size_spin.value()))
        env.insert("EPH_HAZE_DECAY", str(self.haze_decay_spin.value()))
        env.insert("EPH_HAZE_DEPOSIT", str(self.haze_deposit_spin.value()))

        self.process.setProcessEnvironment(env)

        # Build command based on experiment type
        if script.endswith(".sh"):
            cmd = self.system_checker.get_bash_command(script)
            if arg:
                cmd.append(arg)
        else:
            cmd = self.system_checker.get_julia_command(script)

        self.set_buttons_enabled(False)
        self.progress_bar.setVisible(True)
        self.progress_bar.setRange(0, 0)  # Indeterminate

        self.process.start(cmd[0], cmd[1:])

    def stop_experiment(self):
        """実験を停止"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("\n⏹ Stopping experiment...\n", QColor("#FF9800"))
            self.process.kill()

    def set_buttons_enabled(self, enabled: bool):
        """ボタンの有効/無効を切り替え"""
        self.run_btn.setEnabled(enabled)
        self.stop_btn.setEnabled(not enabled)
        self.reset_btn.setEnabled(enabled)
        self.experiment_combo.setEnabled(enabled)

    def handle_stdout(self):
        """標準出力を処理"""
        data = self.process.readAllStandardOutput().data().decode()
        self.append_log(data)

    def handle_stderr(self):
        """標準エラー出力を処理"""
        data = self.process.readAllStandardError().data().decode()
        self.append_log(data, QColor("#F44336"))

    def handle_finished(self, exit_code, exit_status):
        """プロセス終了を処理"""
        self.progress_bar.setVisible(False)
        self.set_buttons_enabled(True)

        if exit_code == 0:
            self.append_log("\n✅ Experiment completed successfully\n", QColor("#4CAF50"))
            self.experiment_finished.emit(True, "Success")
        else:
            self.append_log(f"\n❌ Experiment failed with exit code {exit_code}\n", QColor("#F44336"))
            self.experiment_finished.emit(False, f"Exit code: {exit_code}")

    def append_log(self, text: str, color: QColor = None):
        """ログに追記"""
        cursor = self.log_output.textCursor()
        cursor.movePosition(QTextCursor.End)

        if color:
            self.log_output.setTextColor(color)
        else:
            self.log_output.setTextColor(QColor("#212121"))

        cursor.insertText(text)
        self.log_output.setTextCursor(cursor)
        self.log_output.ensureCursorVisible()

    def closeEvent(self, event):
        """タブクローズ時の処理"""
        try:
            if hasattr(self, 'process') and self.process and self.process.state() == QProcess.Running:
                self.process.kill()
                self.process.waitForFinished(3000)
        except Exception as e:
            print(f"Warning: Error stopping process: {e}")

        event.accept()
