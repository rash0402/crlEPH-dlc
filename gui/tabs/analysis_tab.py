"""
Analysis Tab - 実験結果の可視化と分析
"""

import json
from pathlib import Path

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton,
    QLabel, QFileDialog, QGroupBox, QScrollArea, QSplitter
)
from PySide6.QtCore import Qt, Signal, QThread
import matplotlib
matplotlib.use('Qt5Agg')
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
import matplotlib.pyplot as plt


class AnalysisTab(QWidget):
    """実験結果分析タブ"""

    def __init__(self, system_checker):
        super().__init__()
        self.system_checker = system_checker
        self.project_root = system_checker.project_root
        self.current_data = None

        self.init_ui()

    def init_ui(self):
        """UI初期化"""
        layout = QVBoxLayout()

        # ========== ヘッダー ==========
        header = QGroupBox("📊 Experiment Analysis - Phase 1 vs Phase 2 Comparison")
        header_layout = QHBoxLayout()

        # ファイル選択
        self.file_label = QLabel("No file selected")
        self.file_label.setWordWrap(True)
        header_layout.addWidget(self.file_label, 1)

        # ボタン
        btn_load = QPushButton("📁 Load JSON Result")
        btn_load.clicked.connect(self.load_json_file)
        btn_load.setMinimumHeight(40)
        header_layout.addWidget(btn_load)

        btn_refresh = QPushButton("🔄 Refresh")
        btn_refresh.clicked.connect(self.refresh_plots)
        btn_refresh.setMinimumHeight(40)
        header_layout.addWidget(btn_refresh)

        header.setLayout(header_layout)
        layout.addWidget(header)

        # ========== メインコンテンツ ==========
        main_splitter = QSplitter(Qt.Vertical)

        # サマリー
        self.summary_group = QGroupBox("📋 Summary")
        self.summary_layout = QVBoxLayout()
        self.summary_label = QLabel("No data loaded. Run comparison experiment and load JSON file.")
        self.summary_label.setWordWrap(True)
        self.summary_layout.addWidget(self.summary_label)
        self.summary_group.setLayout(self.summary_layout)
        main_splitter.addWidget(self.summary_group)

        # グラフエリア
        self.plots_group = QGroupBox("📈 Visualizations")
        plots_layout = QVBoxLayout()

        # Matplotlibキャンバス作成
        self.figure = Figure(figsize=(14, 10))
        self.canvas = FigureCanvas(self.figure)
        plots_layout.addWidget(self.canvas)

        self.plots_group.setLayout(plots_layout)
        main_splitter.addWidget(self.plots_group)

        # スプリッターの比率設定
        main_splitter.setStretchFactor(0, 1)  # Summary
        main_splitter.setStretchFactor(1, 4)  # Plots

        layout.addWidget(main_splitter)

        self.setLayout(layout)

        # 初期プロット（空）
        self.plot_empty_state()

    def plot_empty_state(self):
        """データなし状態の表示"""
        self.figure.clear()
        ax = self.figure.add_subplot(111)
        ax.text(0.5, 0.5, 'Load experiment results to visualize\n\nRun: julia --project=. compare_phase1_phase2.jl',
                ha='center', va='center', fontsize=14, color='gray')
        ax.axis('off')
        self.canvas.draw()

    def load_json_file(self):
        """JSON結果ファイルを読み込み"""
        analysis_dir = self.project_root / "data" / "analysis"

        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Select Experiment Result (JSON)",
            str(analysis_dir) if analysis_dir.exists() else str(self.project_root),
            "JSON Files (*.json);;All Files (*)"
        )

        if not file_path:
            return

        try:
            with open(file_path, 'r') as f:
                self.current_data = json.load(f)

            self.file_label.setText(f"Loaded: {Path(file_path).name}")
            self.update_summary()
            self.refresh_plots()

        except Exception as e:
            self.file_label.setText(f"Error loading file: {str(e)}")
            self.summary_label.setText(f"❌ Error loading file:\n{str(e)}")

    def update_summary(self):
        """サマリー情報を更新"""
        if not self.current_data:
            return

        metadata = self.current_data.get("metadata", {})
        phase1 = self.current_data.get("phase1", {})
        phase2 = self.current_data.get("phase2", {})
        comparison = self.current_data.get("comparison", {})

        summary_html = f"""
        <h3>Experiment Information</h3>
        <table style='width: 100%; border-collapse: collapse;'>
            <tr><td style='padding: 5px;'><b>Timestamp:</b></td><td>{metadata.get('timestamp', 'N/A')}</td></tr>
            <tr><td style='padding: 5px;'><b>Steps:</b></td><td>{metadata.get('num_steps', 'N/A')}</td></tr>
            <tr><td style='padding: 5px;'><b>Agents:</b></td><td>{metadata.get('num_agents', 'N/A')}</td></tr>
        </table>

        <h3>Phase 1 (Scalar Self-Haze Only)</h3>
        <table style='width: 100%; border-collapse: collapse;'>
            <tr><td style='padding: 5px;'><b>Coverage:</b></td><td>{phase1.get('final_coverage', 0)*100:.1f}%</td></tr>
            <tr><td style='padding: 5px;'><b>Avg Separation:</b></td><td>{phase1.get('avg_separation', 0):.1f}px</td></tr>
            <tr><td style='padding: 5px;'><b>Avg Self-Haze:</b></td><td>{phase1.get('avg_self_haze', 0):.3f}</td></tr>
        </table>

        <h3>Phase 2 (Spatial + Environmental Haze)</h3>
        <table style='width: 100%; border-collapse: collapse;'>
            <tr><td style='padding: 5px;'><b>Coverage:</b></td><td>{phase2.get('final_coverage', 0)*100:.1f}%</td></tr>
            <tr><td style='padding: 5px;'><b>Avg Separation:</b></td><td>{phase2.get('avg_separation', 0):.1f}px</td></tr>
            <tr><td style='padding: 5px;'><b>Avg Self-Haze:</b></td><td>{phase2.get('avg_self_haze', 0):.3f}</td></tr>
            <tr><td style='padding: 5px;'><b>Avg Env Haze:</b></td><td>{phase2.get('avg_env_haze', 0):.1f}</td></tr>
        </table>

        <h3>Comparison (Phase 2 - Phase 1)</h3>
        <table style='width: 100%; border-collapse: collapse;'>
            <tr><td style='padding: 5px;'><b>Δ Coverage:</b></td><td>{comparison.get('coverage_diff', 0):.1f}% {"↑" if comparison.get('coverage_diff', 0) > 0 else "↓"}</td></tr>
            <tr><td style='padding: 5px;'><b>Δ Separation:</b></td><td>{comparison.get('separation_diff', 0):.1f}px {"↑" if comparison.get('separation_diff', 0) > 0 else "↓"}</td></tr>
            <tr><td style='padding: 5px;'><b>Δ Self-Haze:</b></td><td>{comparison.get('self_haze_diff', 0):.3f} {"↑" if comparison.get('self_haze_diff', 0) > 0 else "↓"}</td></tr>
        </table>
        """

        self.summary_label.setText(summary_html)

    def refresh_plots(self):
        """グラフを再描画"""
        if not self.current_data:
            self.plot_empty_state()
            return

        phase1 = self.current_data.get("phase1", {})
        phase2 = self.current_data.get("phase2", {})

        # データ取得
        coverage_p1 = phase1.get("coverage_history", [])
        coverage_p2 = phase2.get("coverage_history", [])
        separation_p1 = phase1.get("separation_history", [])
        separation_p2 = phase2.get("separation_history", [])
        haze_p1 = phase1.get("self_haze_history", [])
        haze_p2 = phase2.get("self_haze_history", [])
        env_haze_p2 = phase2.get("env_haze_history", [])

        # グラフ描画
        self.figure.clear()

        # 2x3 グリッド
        ax1 = self.figure.add_subplot(2, 3, 1)
        ax2 = self.figure.add_subplot(2, 3, 2)
        ax3 = self.figure.add_subplot(2, 3, 3)
        ax4 = self.figure.add_subplot(2, 3, 4)
        ax5 = self.figure.add_subplot(2, 3, 5)
        ax6 = self.figure.add_subplot(2, 3, 6)

        # 時間軸（10ステップごと）
        time_steps = list(range(0, len(coverage_p1) * 10, 10))

        # 1. Coverage比較
        ax1.plot(time_steps, [c*100 for c in coverage_p1], 'b-', label='Phase 1', linewidth=2)
        ax1.plot(time_steps, [c*100 for c in coverage_p2], 'r-', label='Phase 2', linewidth=2)
        ax1.set_xlabel('Step')
        ax1.set_ylabel('Coverage (%)')
        ax1.set_title('Coverage Over Time')
        ax1.legend()
        ax1.grid(True, alpha=0.3)

        # 2. Separation比較
        ax2.plot(time_steps, separation_p1, 'b-', label='Phase 1', linewidth=2)
        ax2.plot(time_steps, separation_p2, 'r-', label='Phase 2', linewidth=2)
        ax2.set_xlabel('Step')
        ax2.set_ylabel('Separation (px)')
        ax2.set_title('Agent Separation Over Time')
        ax2.legend()
        ax2.grid(True, alpha=0.3)

        # 3. Self-Haze比較
        ax3.plot(time_steps, haze_p1, 'b-', label='Phase 1', linewidth=2)
        ax3.plot(time_steps, haze_p2, 'r-', label='Phase 2', linewidth=2)
        ax3.set_xlabel('Step')
        ax3.set_ylabel('Self-Haze')
        ax3.set_title('Average Self-Haze Over Time')
        ax3.legend()
        ax3.grid(True, alpha=0.3)

        # 4. Environmental Haze (Phase 2のみ)
        ax4.plot(time_steps, env_haze_p2, 'g-', linewidth=2)
        ax4.set_xlabel('Step')
        ax4.set_ylabel('Total Env Haze')
        ax4.set_title('Environmental Haze (Phase 2)')
        ax4.grid(True, alpha=0.3)

        # 5. 最終値比較（バーチャート）
        metrics = ['Coverage\n(%)', 'Separation\n(px)', 'Self-Haze']
        p1_values = [
            phase1.get('final_coverage', 0) * 100,
            phase1.get('avg_separation', 0),
            phase1.get('avg_self_haze', 0)
        ]
        p2_values = [
            phase2.get('final_coverage', 0) * 100,
            phase2.get('avg_separation', 0),
            phase2.get('avg_self_haze', 0)
        ]

        x = range(len(metrics))
        width = 0.35
        ax5.bar([i - width/2 for i in x], p1_values, width, label='Phase 1', color='blue', alpha=0.7)
        ax5.bar([i + width/2 for i in x], p2_values, width, label='Phase 2', color='red', alpha=0.7)
        ax5.set_ylabel('Value')
        ax5.set_title('Final Metrics Comparison')
        ax5.set_xticks(x)
        ax5.set_xticklabels(metrics)
        ax5.legend()
        ax5.grid(True, alpha=0.3, axis='y')

        # 6. スティグマージー効果（Env Haze vs Coverage）
        if len(env_haze_p2) > 0 and len(coverage_p2) > 0:
            ax6.scatter(env_haze_p2, [c*100 for c in coverage_p2], alpha=0.5, color='purple')
            ax6.set_xlabel('Environmental Haze')
            ax6.set_ylabel('Coverage (%)')
            ax6.set_title('Stigmergy Effect: Env Haze vs Coverage')
            ax6.grid(True, alpha=0.3)

        self.figure.tight_layout()
        self.canvas.draw()
