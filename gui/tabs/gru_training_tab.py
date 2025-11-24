"""
GRU Training Tab - GRU学習管理タブ
"""

from pathlib import Path
from datetime import datetime

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox,
    QPushButton, QLabel, QTextEdit, QProgressBar,
    QSpinBox, QDoubleSpinBox, QFormLayout, QComboBox
)
from PySide6.QtCore import Qt, QProcess, QProcessEnvironment, Signal, QTimer
from PySide6.QtGui import QTextCursor, QColor

from ..utils.system_checker import SystemChecker


class GRUTrainingTab(QWidget):
    """GRU Training管理タブ"""

    training_finished = Signal(bool, str)

    def __init__(self, system_checker: SystemChecker, parent=None):
        super().__init__(parent)
        self.system_checker = system_checker
        self.project_root = system_checker.project_root
        self.training_dir = self.project_root / "data" / "training"
        self.process = None

        self.init_ui()
        self.update_status()

        # Auto-refresh timer (every 10 seconds)
        self.refresh_timer = QTimer(self)
        self.refresh_timer.timeout.connect(self.update_status)
        self.refresh_timer.start(10000)

    def init_ui(self):
        """UI初期化"""
        layout = QVBoxLayout()

        # ===== Status Section =====
        status_group = QGroupBox("📊 Training Data Status")
        status_layout = QVBoxLayout()

        # Status labels
        self.data_count_label = QLabel("Training files: Checking...")
        self.last_update_label = QLabel("Last update: Checking...")
        self.training_needed_label = QLabel("Status: Checking...")

        status_layout.addWidget(self.data_count_label)
        status_layout.addWidget(self.last_update_label)
        status_layout.addWidget(self.training_needed_label)

        status_group.setLayout(status_layout)
        layout.addWidget(status_group)

        # ===== Data Collection Section =====
        collection_group = QGroupBox("🗂️ Data Collection")
        collection_layout = QVBoxLayout()

        collection_info = QLabel(
            "Collect SPM sequences for GRU training. "
            "This runs simulations with data collection enabled to generate training data."
        )
        collection_info.setWordWrap(True)
        collection_layout.addWidget(collection_info)

        # Collection parameters
        params_form = QFormLayout()

        self.num_steps_spinbox = QSpinBox()
        self.num_steps_spinbox.setRange(1000, 200000)
        self.num_steps_spinbox.setValue(20000)
        self.num_steps_spinbox.setSingleStep(1000)
        self.num_steps_spinbox.setSuffix(" steps")
        self.num_steps_spinbox.setToolTip("Number of simulation steps")
        params_form.addRow("Simulation steps:", self.num_steps_spinbox)

        self.num_agents_spinbox = QSpinBox()
        self.num_agents_spinbox.setRange(5, 50)
        self.num_agents_spinbox.setValue(15)
        self.num_agents_spinbox.setToolTip("Total number of agents in simulation")
        params_form.addRow("Total agents (sim):", self.num_agents_spinbox)

        self.collect_agents_spinbox = QSpinBox()
        self.collect_agents_spinbox.setRange(1, 50)
        self.collect_agents_spinbox.setValue(15)
        self.collect_agents_spinbox.setToolTip(
            "Number of agents to collect data from (1 to all).\n"
            "More agents = more diverse data = better learning.\n"
            "Recommended: Use all agents (15) for maximum diversity."
        )
        params_form.addRow("Agents to collect:", self.collect_agents_spinbox)

        # Link collect_agents to not exceed num_agents
        self.num_agents_spinbox.valueChanged.connect(
            lambda v: self.collect_agents_spinbox.setMaximum(v)
        )

        # Estimated time label
        self.estimated_time_label = QLabel()
        self.update_estimated_time()
        self.num_steps_spinbox.valueChanged.connect(self.update_estimated_time)
        params_form.addRow("Estimated time:", self.estimated_time_label)

        collection_layout.addLayout(params_form)

        # Preset buttons
        preset_layout = QHBoxLayout()
        preset_label = QLabel("Presets:")
        preset_layout.addWidget(preset_label)

        quick_btn = QPushButton("⚡ Quick Test")
        quick_btn.setToolTip("5000 steps, 10 agents, collect all (~4 min)")
        quick_btn.clicked.connect(lambda: self.apply_preset(5000, 10, 10))
        preset_layout.addWidget(quick_btn)

        standard_btn = QPushButton("📊 Standard")
        standard_btn.setToolTip("20000 steps, 15 agents, collect all (~16 min)")
        standard_btn.clicked.connect(lambda: self.apply_preset(20000, 15, 15))
        preset_layout.addWidget(standard_btn)

        long_btn = QPushButton("🔬 Long Run")
        long_btn.setToolTip("50000 steps, 20 agents, collect all (~42 min)")
        long_btn.clicked.connect(lambda: self.apply_preset(50000, 20, 20))
        preset_layout.addWidget(long_btn)

        preset_layout.addStretch()
        collection_layout.addLayout(preset_layout)

        # Data collection buttons
        btn_layout = QHBoxLayout()

        self.collect_btn = QPushButton("📦 Collect Training Data")
        self.collect_btn.clicked.connect(self.collect_data)

        self.clear_data_btn = QPushButton("🗑️ Clear Data")
        self.clear_data_btn.clicked.connect(self.clear_training_data)
        self.clear_data_btn.setStyleSheet("background-color: #F44336;")

        btn_layout.addWidget(self.collect_btn)
        btn_layout.addWidget(self.clear_data_btn)

        collection_layout.addLayout(btn_layout)
        collection_group.setLayout(collection_layout)
        layout.addWidget(collection_group)

        # ===== Training Section =====
        training_group = QGroupBox("🧠 GRU Model Training")
        training_layout = QVBoxLayout()

        training_info = QLabel(
            "Train GRU predictor using collected data. "
            "The model will be saved to data/models/."
        )
        training_info.setWordWrap(True)
        training_layout.addWidget(training_info)

        # Training data file selection
        file_selection_layout = QVBoxLayout()
        file_selection_label = QLabel("Training Data Files:")
        file_selection_label.setStyleSheet("font-weight: bold;")
        file_selection_layout.addWidget(file_selection_label)

        self.data_files_combo = QComboBox()
        self.data_files_combo.setToolTip("Select which training data files to use")
        file_selection_layout.addWidget(self.data_files_combo)

        refresh_files_btn = QPushButton("🔄 Refresh File List")
        refresh_files_btn.clicked.connect(self.refresh_data_files)
        file_selection_layout.addWidget(refresh_files_btn)

        training_layout.addLayout(file_selection_layout)

        # Training hyperparameters
        params_form = QFormLayout()

        self.epochs_spinbox = QSpinBox()
        self.epochs_spinbox.setRange(10, 500)
        self.epochs_spinbox.setValue(50)
        self.epochs_spinbox.setSuffix(" epochs")
        self.epochs_spinbox.setToolTip("Number of training epochs")
        params_form.addRow("Epochs:", self.epochs_spinbox)

        self.learning_rate_spinbox = QDoubleSpinBox()
        self.learning_rate_spinbox.setRange(0.00001, 0.01)
        self.learning_rate_spinbox.setValue(0.0001)
        self.learning_rate_spinbox.setSingleStep(0.00001)
        self.learning_rate_spinbox.setDecimals(5)
        self.learning_rate_spinbox.setToolTip("Learning rate (Adam optimizer)")
        params_form.addRow("Learning Rate:", self.learning_rate_spinbox)

        self.batch_size_spinbox = QSpinBox()
        self.batch_size_spinbox.setRange(1, 64)
        self.batch_size_spinbox.setValue(16)
        self.batch_size_spinbox.setToolTip("Batch size for training")
        params_form.addRow("Batch Size:", self.batch_size_spinbox)

        self.hidden_size_spinbox = QSpinBox()
        self.hidden_size_spinbox.setRange(32, 512)
        self.hidden_size_spinbox.setValue(128)
        self.hidden_size_spinbox.setSingleStep(32)
        self.hidden_size_spinbox.setToolTip("GRU hidden layer size")
        params_form.addRow("Hidden Size:", self.hidden_size_spinbox)

        self.gradient_clip_spinbox = QDoubleSpinBox()
        self.gradient_clip_spinbox.setRange(0.0, 20.0)
        self.gradient_clip_spinbox.setValue(5.0)
        self.gradient_clip_spinbox.setSingleStep(0.5)
        self.gradient_clip_spinbox.setDecimals(1)
        self.gradient_clip_spinbox.setToolTip("Gradient clipping threshold (0 = disabled)")
        params_form.addRow("Gradient Clip:", self.gradient_clip_spinbox)

        training_layout.addLayout(params_form)

        # Preset buttons for training
        train_preset_layout = QHBoxLayout()
        train_preset_label = QLabel("Training Presets:")
        train_preset_layout.addWidget(train_preset_label)

        fast_train_btn = QPushButton("⚡ Fast")
        fast_train_btn.setToolTip("20 epochs, LR=0.0005 (quick test)")
        fast_train_btn.clicked.connect(lambda: self.apply_train_preset(20, 0.0005, 16, 128, 5.0))
        train_preset_layout.addWidget(fast_train_btn)

        standard_train_btn = QPushButton("📊 Standard")
        standard_train_btn.setToolTip("50 epochs, LR=0.0001 (recommended)")
        standard_train_btn.clicked.connect(lambda: self.apply_train_preset(50, 0.0001, 16, 128, 5.0))
        train_preset_layout.addWidget(standard_train_btn)

        thorough_train_btn = QPushButton("🔬 Thorough")
        thorough_train_btn.setToolTip("100 epochs, LR=0.00005 (best accuracy)")
        thorough_train_btn.clicked.connect(lambda: self.apply_train_preset(100, 0.00005, 16, 128, 5.0))
        train_preset_layout.addWidget(thorough_train_btn)

        train_preset_layout.addStretch()
        training_layout.addLayout(train_preset_layout)

        # Training buttons
        train_btn_layout = QHBoxLayout()

        self.train_btn = QPushButton("🚀 Train GRU Model")
        self.train_btn.clicked.connect(self.train_model)

        self.update_model_btn = QPushButton("🔄 Update Existing Model")
        self.update_model_btn.clicked.connect(self.update_model)

        self.stop_btn = QPushButton("⏹️ Stop")
        self.stop_btn.clicked.connect(self.stop_process)
        self.stop_btn.setEnabled(False)

        train_btn_layout.addWidget(self.train_btn)
        train_btn_layout.addWidget(self.update_model_btn)
        train_btn_layout.addWidget(self.stop_btn)

        training_layout.addLayout(train_btn_layout)
        training_group.setLayout(training_layout)
        layout.addWidget(training_group)

        # ===== Progress Bar =====
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        layout.addWidget(self.progress_bar)

        # ===== Log Output =====
        log_group = QGroupBox("📜 Output Log")
        log_layout = QVBoxLayout()

        self.log_output = QTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setMinimumHeight(300)

        log_layout.addWidget(self.log_output)
        log_group.setLayout(log_layout)
        layout.addWidget(log_group)

        self.setLayout(layout)

        # Initialize file list
        self.refresh_data_files()

    def refresh_data_files(self):
        """学習データファイルリストを更新"""
        self.data_files_combo.clear()

        if not self.training_dir.exists():
            self.data_files_combo.addItem("❌ No data directory found")
            self.data_files_combo.setEnabled(False)
            return

        files = list(self.training_dir.glob("spm_sequences_*.jld2"))

        if not files:
            self.data_files_combo.addItem("❌ No training data files found")
            self.data_files_combo.setEnabled(False)
            return

        # Sort by modification time (newest first)
        files.sort(key=lambda f: f.stat().st_mtime, reverse=True)

        self.data_files_combo.setEnabled(True)

        # Group files by date
        from collections import defaultdict
        date_groups = defaultdict(list)

        for f in files:
            # Extract date from filename: spm_sequences_YYYYMMDD_HHMMSS.jld2
            import re
            match = re.search(r'spm_sequences_(\d{4})-(\d{2})-(\d{2})_', f.name)
            if match:
                date_str = f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
                date_groups[date_str].append(f)

        # Add date-based options (most recent dates first)
        self.data_files_combo.addItem("📚 All dates ({} files)".format(len(files)), "all")
        self.data_files_combo.addItem("📄 Latest file only", "latest_1")
        self.data_files_combo.addItem("──────────────────", None)

        # Add grouped by date
        for date_str in sorted(date_groups.keys(), reverse=True)[:5]:  # Show 5 most recent dates
            date_files = date_groups[date_str]
            total_size = sum(f.stat().st_size for f in date_files) / (1024 * 1024)

            # Count total agents from files in this date
            # (Assuming filename or we just show file count)
            self.data_files_combo.addItem(
                f"📅 {date_str} ({len(date_files)} files, {total_size:.1f}MB)",
                f"date:{date_str}"
            )

        self.data_files_combo.addItem("──────────────────", None)

        # Add individual files (up to 5 most recent)
        for f in files[:5]:
            mtime = datetime.fromtimestamp(f.stat().st_mtime)
            time_str = mtime.strftime("%m/%d %H:%M")
            size_mb = f.stat().st_size / (1024 * 1024)
            self.data_files_combo.addItem(
                f"📄 {f.name} ({time_str}, {size_mb:.1f}MB)",
                f.name
            )

        if len(files) > 5:
            self.data_files_combo.addItem(f"... and {len(files) - 5} more files", None)

    def apply_preset(self, num_steps: int, num_agents: int, collect_agents: int):
        """プリセット設定を適用（データ収集用）"""
        self.num_steps_spinbox.setValue(num_steps)
        self.num_agents_spinbox.setValue(num_agents)
        self.collect_agents_spinbox.setValue(collect_agents)

    def apply_train_preset(self, epochs: int, lr: float, batch_size: int, hidden_size: int, grad_clip: float):
        """トレーニングプリセットを適用"""
        self.epochs_spinbox.setValue(epochs)
        self.learning_rate_spinbox.setValue(lr)
        self.batch_size_spinbox.setValue(batch_size)
        self.hidden_size_spinbox.setValue(hidden_size)
        self.gradient_clip_spinbox.setValue(grad_clip)

    def update_estimated_time(self):
        """推定実行時間を更新"""
        num_steps = self.num_steps_spinbox.value()

        # Estimated time calculation
        # dt = 0.15, optimized simulation
        # Approximate: 1000 steps ≈ 50 seconds (with optimization)
        estimated_seconds = num_steps * 0.05

        if estimated_seconds < 60:
            time_str = f"~{int(estimated_seconds)} seconds"
        else:
            minutes = int(estimated_seconds / 60)
            seconds = int(estimated_seconds % 60)
            time_str = f"~{minutes}m {seconds}s"

        self.estimated_time_label.setText(time_str)

    def update_status(self):
        """学習データのステータスを更新"""
        if not self.training_dir.exists():
            self.data_count_label.setText("Training files: ❌ Directory not found")
            self.last_update_label.setText("Last update: N/A")
            self.training_needed_label.setText("Status: ⚠️ Initial training required")
            return

        # Count training files
        files = list(self.training_dir.glob("spm_sequences_*.jld2"))
        file_count = len(files)

        self.data_count_label.setText(f"Training files: {file_count} files")

        # Get last update time
        if files:
            latest_file = max(files, key=lambda f: f.stat().st_mtime)
            mtime = datetime.fromtimestamp(latest_file.stat().st_mtime)
            time_str = mtime.strftime("%Y-%m-%d %H:%M:%S")
            self.last_update_label.setText(f"Last update: {time_str}")

            # Determine training status
            if file_count >= 50:
                self.training_needed_label.setText("Status: ✅ Sufficient data available")
            elif file_count >= 20:
                self.training_needed_label.setText("Status: ⚠️ More data recommended")
            else:
                self.training_needed_label.setText("Status: ⚠️ More data needed")
        else:
            self.last_update_label.setText("Last update: No data")
            self.training_needed_label.setText("Status: ⚠️ Initial data collection required")

    def collect_data(self):
        """データ収集を実行"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("❌ Process already running\n", QColor("#F44336"))
            return

        # Get parameters from UI
        num_steps = self.num_steps_spinbox.value()
        num_agents = self.num_agents_spinbox.value()
        collect_agents = self.collect_agents_spinbox.value()

        self.log_output.clear()
        self.append_log("📦 Starting data collection...\n", QColor("#2196F3"))
        self.append_log(f"Running: scripts/collect_gru_training_data.sh {num_steps} {num_agents}\n")
        self.append_log(f"Configuration:\n")
        self.append_log(f"  - Simulation steps: {num_steps}\n")
        self.append_log(f"  - Total agents (simulation): {num_agents}\n")
        self.append_log(f"  - Agents to collect data from: {collect_agents}\n")
        self.append_log(f"  - Expected data samples: ~{num_steps * collect_agents}\n")
        self.append_log("\n")

        # Start process
        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.handle_finished)

        # Set process environment
        env = QProcessEnvironment.systemEnvironment()
        env.insert("EPH_NON_INTERACTIVE", "1")
        env.insert("EPH_COLLECT_AGENTS", str(collect_agents))  # Pass collection target count
        # Ensure HOME is set (required for bash scripts)
        if not env.contains("HOME"):
            env.insert("HOME", str(Path.home()))
        self.process.setProcessEnvironment(env)

        cmd = self.system_checker.get_bash_command("scripts/collect_gru_training_data.sh")
        # Add command-line arguments
        cmd.append(str(num_steps))
        cmd.append(str(num_agents))

        self.set_buttons_enabled(False)
        self.progress_bar.setVisible(True)
        # Set progress bar range based on simulation steps
        self.progress_bar.setRange(0, num_steps)
        self.progress_bar.setValue(0)

        # Store num_steps for progress tracking
        self.current_num_steps = num_steps

        self.process.start(cmd[0], cmd[1:])

    def clear_training_data(self):
        """学習データをクリア"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("❌ Cannot clear data while process is running\n", QColor("#F44336"))
            return

        self.log_output.clear()
        self.append_log("🗑️ Clearing training data...\n", QColor("#FF9800"))

        if not self.training_dir.exists():
            self.append_log("❌ Training directory does not exist\n", QColor("#F44336"))
            return

        files = list(self.training_dir.glob("spm_sequences_*.jld2"))
        for f in files:
            f.unlink()

        self.append_log(f"✅ Deleted {len(files)} files\n", QColor("#4CAF50"))
        self.update_status()

    def train_model(self):
        """GRUモデルを学習"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("❌ Process already running\n", QColor("#F44336"))
            return

        # Get selected data file option
        selected_data = self.data_files_combo.currentData()
        if selected_data is None or not self.data_files_combo.isEnabled():
            self.append_log("❌ Please select a valid training data file\n", QColor("#F44336"))
            return

        # Get training parameters
        epochs = self.epochs_spinbox.value()
        learning_rate = self.learning_rate_spinbox.value()
        batch_size = self.batch_size_spinbox.value()
        hidden_size = self.hidden_size_spinbox.value()
        gradient_clip = self.gradient_clip_spinbox.value()

        self.log_output.clear()
        self.append_log("🚀 Starting GRU training...\n", QColor("#2196F3"))
        self.append_log("Running: scripts/gru/train_gru.jl\n")
        self.append_log("Configuration:\n")
        self.append_log(f"  - Training data: {self.data_files_combo.currentText()}\n")

        # Show more details for date-based selection
        if isinstance(selected_data, str) and selected_data.startswith("date:"):
            date_str = selected_data.replace("date:", "")
            # Count files for this date
            import re
            matching_files = [
                f for f in self.training_dir.glob("spm_sequences_*.jld2")
                if re.search(rf'spm_sequences_{re.escape(date_str)}_', f.name)
            ]
            self.append_log(f"    → Will load all files from {date_str}\n")
            self.append_log(f"    → {len(matching_files)} file(s) found\n")
            self.append_log(f"    → Agents will be automatically read from files\n")

        self.append_log(f"  - Epochs: {epochs}\n")
        self.append_log(f"  - Learning rate: {learning_rate}\n")
        self.append_log(f"  - Batch size: {batch_size}\n")
        self.append_log(f"  - Hidden size: {hidden_size}\n")
        self.append_log(f"  - Gradient clip: {gradient_clip}\n")
        self.append_log("\n")

        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.handle_finished)

        # Set process environment with training parameters
        env = QProcessEnvironment.systemEnvironment()
        if not env.contains("HOME"):
            env.insert("HOME", str(Path.home()))

        # Pass training parameters as environment variables
        env.insert("GRU_EPOCHS", str(epochs))
        env.insert("GRU_LEARNING_RATE", str(learning_rate))
        env.insert("GRU_BATCH_SIZE", str(batch_size))
        env.insert("GRU_HIDDEN_SIZE", str(hidden_size))
        env.insert("GRU_GRADIENT_CLIP", str(gradient_clip))
        env.insert("GRU_DATA_FILES", str(selected_data))

        self.process.setProcessEnvironment(env)

        cmd = self.system_checker.get_julia_command("scripts/gru/train_gru.jl")

        self.set_buttons_enabled(False)
        self.progress_bar.setVisible(True)
        # Set progress bar range based on epochs
        self.progress_bar.setRange(0, epochs)
        self.progress_bar.setValue(0)

        # Store epochs for progress tracking
        self.current_epochs = epochs

        self.process.start(cmd[0], cmd[1:])

    def update_model(self):
        """既存モデルを更新"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("❌ Process already running\n", QColor("#F44336"))
            return

        self.log_output.clear()
        self.append_log("🔄 Updating GRU model...\n", QColor("#2196F3"))
        self.append_log("Running: scripts/gru/update_gru.sh\n")

        self.process = QProcess(self)
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.handle_finished)

        # Set process environment
        env = QProcessEnvironment.systemEnvironment()
        env.insert("EPH_NON_INTERACTIVE", "1")
        if not env.contains("HOME"):
            env.insert("HOME", str(Path.home()))
        self.process.setProcessEnvironment(env)

        cmd = self.system_checker.get_bash_command("scripts/gru/update_gru.sh")

        self.set_buttons_enabled(False)
        self.progress_bar.setVisible(True)
        self.progress_bar.setRange(0, 0)

        self.process.start(cmd[0], cmd[1:])

    def stop_process(self):
        """実行中のプロセスを停止"""
        if self.process and self.process.state() == QProcess.Running:
            self.append_log("\n⏹️ Stopping process...\n", QColor("#FF9800"))
            self.process.kill()

    def set_buttons_enabled(self, enabled: bool):
        """ボタンの有効/無効を切り替え"""
        self.collect_btn.setEnabled(enabled)
        self.clear_data_btn.setEnabled(enabled)
        self.train_btn.setEnabled(enabled)
        self.update_model_btn.setEnabled(enabled)
        self.stop_btn.setEnabled(not enabled)

    def handle_stdout(self):
        """標準出力を処理"""
        import re
        data = self.process.readAllStandardOutput().data().decode()
        self.append_log(data)

        # Update progress bar based on epoch number (for training)
        epoch_match = re.search(r'Epoch (\d+):', data)
        if epoch_match:
            current_epoch = int(epoch_match.group(1))
            if hasattr(self, 'current_epochs'):
                self.progress_bar.setValue(current_epoch)

        # Update progress bar based on step number (for data collection)
        progress_match = re.search(r'Progress: (\d+) / (\d+)', data)
        if progress_match:
            current_step = int(progress_match.group(1))
            if hasattr(self, 'current_num_steps'):
                self.progress_bar.setValue(current_step)

    def handle_stderr(self):
        """標準エラー出力を処理"""
        data = self.process.readAllStandardError().data().decode()
        self.append_log(data, QColor("#F44336"))

    def handle_finished(self, exit_code, exit_status):
        """プロセス終了を処理"""
        self.progress_bar.setVisible(False)
        self.set_buttons_enabled(True)

        if exit_code == 0:
            self.append_log("\n✅ Process completed successfully\n", QColor("#4CAF50"))
            self.training_finished.emit(True, "Success")
        else:
            self.append_log(f"\n❌ Process failed with exit code {exit_code}\n", QColor("#F44336"))
            self.training_finished.emit(False, f"Exit code: {exit_code}")

        self.update_status()
        self.refresh_data_files()  # Refresh file list after process completes

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
            if hasattr(self, 'refresh_timer') and self.refresh_timer:
                self.refresh_timer.stop()
        except Exception as e:
            print(f"Warning: Error stopping refresh timer: {e}")

        try:
            if hasattr(self, 'process') and self.process and self.process.state() == QProcess.Running:
                self.process.kill()
                self.process.waitForFinished(3000)
        except Exception as e:
            print(f"Warning: Error stopping process: {e}")

        event.accept()
