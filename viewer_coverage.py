#!/usr/bin/env python3
"""
EPH Coverage Experiment Viewer
Optimized GUI for coverage tracking experiments with Haze tensor editing
"""

import sys
import zmq
import json
import numpy as np
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                             QLabel, QPushButton, QSlider, QGroupBox, QSpinBox, QFileDialog,
                             QMessageBox, QSplitter)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal
from PyQt5.QtGui import QPainter, QColor, QPen, QFont, QBrush, QPainterPath
from PyQt5.QtCore import QPointF, QRectF
import matplotlib
matplotlib.use('Qt5Agg')
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
import threading

class SimulationWidget(QWidget):
    """Canvas for rendering the 2D simulation world."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.data = {}
        self.sim_world_size = (300, 300)  # Default, will update from data
        self.setMinimumSize(600, 600)

        # FOV parameters (from config/simulation.yaml)
        self.fov_angle = 210.0 * np.pi / 180.0  # Convert degrees to radians
        self.fov_range = 100.0

    def update_data(self, data):
        """Update simulation data and trigger repaint."""
        self.data = data

        # Update world size if provided
        agents = data.get("agents", [])
        if agents:
            # Infer world size from agent positions (assume toroidal, use max observed)
            # For now, keep fixed or update from metadata
            pass

        self.update()

    def paintEvent(self, event):
        """Render the simulation world."""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # Background
        painter.fillRect(self.rect(), QColor(240, 240, 240))

        # Calculate scaling to fit world in widget
        size = min(self.width(), self.height())
        scale = size / max(self.sim_world_size[0], self.sim_world_size[1])
        offset_x = (self.width() - self.sim_world_size[0] * scale) / 2
        offset_y = (self.height() - self.sim_world_size[1] * scale) / 2

        # Apply transformations
        painter.translate(offset_x, offset_y)
        painter.scale(scale, scale)

        # Draw Coverage Map (visit count visualization)
        coverage_map = self.data.get("coverage_map")
        if coverage_map is not None:
            coverage_arr = np.array(coverage_map)
            rows, cols = coverage_arr.shape
            cell_w = self.sim_world_size[0] / cols
            cell_h = self.sim_world_size[1] / rows

            max_visits = np.max(coverage_arr) if np.max(coverage_arr) > 0 else 1

            for y in range(rows):
                for x in range(cols):
                    visits = coverage_arr[y, x]
                    if visits > 0:
                        intensity = min(1.0, np.log1p(visits) / np.log1p(max_visits))
                        alpha = int(80 + 120 * intensity)
                        color = QColor(100, 150, 255, alpha)
                        painter.fillRect(QRectF(x * cell_w, y * cell_h, cell_w, cell_h), color)

        # Draw FOV for Red Agent (Agent 1) only
        agents = self.data.get("agents", [])
        if agents:
            # Find Agent 1 (red agent with id=1)
            red_agent = None
            for agent in agents:
                if agent["id"] == 1:
                    red_agent = agent
                    break

            if red_agent is not None:
                x = red_agent["x"]
                y = red_agent["y"]
                orientation = red_agent["orientation"]

                # Create FOV fan shape
                path = QPainterPath()
                path.moveTo(x, y)  # Start at agent position

                # Calculate arc angles (FOV is symmetric around orientation)
                half_fov = self.fov_angle / 2.0
                start_angle = orientation - half_fov

                # Create arc points
                num_arc_points = 50
                for i in range(num_arc_points + 1):
                    angle = start_angle + (self.fov_angle * i / num_arc_points)
                    arc_x = x + self.fov_range * np.cos(angle)
                    arc_y = y + self.fov_range * np.sin(angle)
                    path.lineTo(arc_x, arc_y)

                path.closeSubpath()

                # Draw FOV with semi-transparent red fill
                painter.setBrush(QBrush(QColor(255, 100, 100, 40)))  # Light red, very transparent
                painter.setPen(QPen(QColor(255, 80, 80, 100), 1.0))  # Red border, semi-transparent
                painter.drawPath(path)

        # Draw Agents
        agents = self.data.get("agents", [])
        for agent in agents:
            x, y = agent["x"], agent["y"]
            radius = agent["radius"]
            orientation = agent["orientation"]
            color = agent.get("color", [80, 120, 255])

            # Agent body
            painter.setBrush(QBrush(QColor(*color)))
            painter.setPen(QPen(QColor(0, 0, 0), 0.5))
            painter.drawEllipse(QPointF(x, y), radius, radius)

            # Direction indicator
            dx = np.cos(orientation) * radius * 1.5
            dy = np.sin(orientation) * radius * 1.5
            painter.setPen(QPen(QColor(0, 0, 0), 1.0))
            painter.drawLine(QPointF(x, y), QPointF(x + dx, y + dy))

        # Draw Info Overlay
        painter.resetTransform()
        frame = self.data.get("frame", 0)
        coverage = self.data.get("coverage", 0.0) * 100
        info_text = f"Frame: {frame} | Coverage: {coverage:.1f}%"

        painter.setPen(QColor(50, 50, 50))
        painter.setFont(QFont("Arial", 10))
        painter.drawText(10, 20, info_text)


class ControlPanel(QWidget):
    """Simplified control panel for coverage experiments."""

    start_sim = pyqtSignal()
    stop_sim = pyqtSignal()
    reset_sim = pyqtSignal()
    speed_changed = pyqtSignal(float)
    steps_changed = pyqtSignal(int)
    haze_value_changed = pyqtSignal(float)
    haze_reset = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        # Main vertical layout (2 rows)
        main_layout = QVBoxLayout(self)
        main_layout.setSpacing(5)
        main_layout.setContentsMargins(5, 5, 5, 5)

        # Row 1: Simulation group (with control buttons inside)
        sim_group = QGroupBox("Simulation")
        sim_layout = QHBoxLayout()
        sim_layout.setSpacing(10)

        # Control buttons on the left
        control_layout = QVBoxLayout()
        control_layout.setSpacing(3)

        self.start_btn = QPushButton("▶ Start")
        self.start_btn.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold; padding: 8px;")
        self.start_btn.clicked.connect(self.start_sim.emit)

        self.stop_btn = QPushButton("⏸ Stop")
        self.stop_btn.setStyleSheet("background-color: #f44336; color: white; font-weight: bold; padding: 8px;")
        self.stop_btn.clicked.connect(self.stop_sim.emit)
        self.stop_btn.setEnabled(False)

        self.reset_btn = QPushButton("⟲ Reset")
        self.reset_btn.setStyleSheet("background-color: #2196F3; color: white; font-weight: bold; padding: 8px;")
        self.reset_btn.clicked.connect(self.reset_sim.emit)

        control_layout.addWidget(self.start_btn)
        control_layout.addWidget(self.stop_btn)
        control_layout.addWidget(self.reset_btn)
        sim_layout.addLayout(control_layout)

        # Parameters on the right
        params_layout = QVBoxLayout()
        params_layout.setSpacing(5)

        # Playback speed
        pb_layout = QHBoxLayout()
        pb_layout.addWidget(QLabel("Speed:"))
        self.speed_label = QLabel("1.0x")
        self.speed_label.setMinimumWidth(40)
        self.speed_slider = QSlider(Qt.Horizontal)
        self.speed_slider.setMinimum(1)
        self.speed_slider.setMaximum(50)
        self.speed_slider.setValue(10)
        self.speed_slider.valueChanged.connect(self.on_speed_changed)
        pb_layout.addWidget(self.speed_slider)
        pb_layout.addWidget(self.speed_label)
        params_layout.addLayout(pb_layout)

        # Max steps
        steps_layout = QHBoxLayout()
        steps_layout.addWidget(QLabel("Steps:"))
        self.steps_spinbox = QSpinBox()
        self.steps_spinbox.setMinimum(10)
        self.steps_spinbox.setMaximum(10000)
        self.steps_spinbox.setValue(1000)
        self.steps_spinbox.setSingleStep(50)
        self.steps_spinbox.valueChanged.connect(self.steps_changed.emit)
        steps_layout.addWidget(self.steps_spinbox)
        steps_layout.addStretch()
        params_layout.addLayout(steps_layout)

        # Status Label
        self.status_label = QLabel("Status: Stopped")
        self.status_label.setStyleSheet("padding: 5px; background-color: #FFCDD2; border-radius: 3px;")
        params_layout.addWidget(self.status_label)

        sim_layout.addLayout(params_layout)
        sim_group.setLayout(sim_layout)
        main_layout.addWidget(sim_group)

        # Row 2: Haze Control group
        haze_group = QGroupBox("Haze Control")
        haze_layout = QVBoxLayout()
        haze_layout.setSpacing(5)

        # Haze value slider
        haze_slider_layout = QHBoxLayout()
        haze_slider_layout.addWidget(QLabel("Value:"))
        self.haze_value_label = QLabel("0.50")
        self.haze_value_label.setMinimumWidth(40)
        self.haze_value_slider = QSlider(Qt.Horizontal)
        self.haze_value_slider.setMinimum(0)
        self.haze_value_slider.setMaximum(100)
        self.haze_value_slider.setValue(50)
        self.haze_value_slider.valueChanged.connect(self.on_haze_value_changed)
        haze_slider_layout.addWidget(self.haze_value_slider)
        haze_slider_layout.addWidget(self.haze_value_label)
        haze_layout.addLayout(haze_slider_layout)

        # Reset button
        self.haze_reset_btn = QPushButton("Reset Haze Tensor")
        self.haze_reset_btn.setStyleSheet("background-color: #FF9800; color: white; font-weight: bold; padding: 8px;")
        self.haze_reset_btn.clicked.connect(self.haze_reset.emit)
        haze_layout.addWidget(self.haze_reset_btn)

        haze_group.setLayout(haze_layout)
        main_layout.addWidget(haze_group)

    def on_speed_changed(self, value):
        speed = value / 10.0
        self.speed_label.setText(f"{speed:.1f}x")
        self.speed_changed.emit(speed)

    def on_haze_value_changed(self, value):
        haze_val = value / 100.0
        self.haze_value_label.setText(f"{haze_val:.2f}")
        self.haze_value_changed.emit(haze_val)

    def set_running(self, running):
        self.start_btn.setEnabled(not running)
        self.stop_btn.setEnabled(running)
        if running:
            self.status_label.setText("Status: Running")
            self.status_label.setStyleSheet("padding: 5px; background-color: #C8E6C9; border-radius: 3px;")
        else:
            self.status_label.setText("Status: Stopped")
            self.status_label.setStyleSheet("padding: 5px; background-color: #FFCDD2; border-radius: 3px;")


class DashboardWidget(QWidget):
    """Simplified dashboard with EFE, Entropy, Surprise, Gradient, SPM heatmaps, and Haze editor."""

    def __init__(self, parent=None, control_socket=None, socket_lock=None, zmq_context=None):
        super().__init__(parent)
        self.control_socket = control_socket
        self.socket_lock = socket_lock
        self.context = zmq_context
        self.current_haze_value = 0.5  # Default haze spray value

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        # Create Matplotlib Figure
        self.figure = Figure(figsize=(8, 8), facecolor='#F0F0F0')
        self.canvas = FigureCanvas(self.figure)
        layout.addWidget(self.canvas)

        # Setup Subplots
        # Row 1: EFE, Entropy, Surprise, Gradient Norm (4 columns)
        # Row 2: SPM Occupancy, SPM Radial, SPM Tangential, Haze Editor (4 columns)
        # Row 3: Pred Occupancy, Pred Radial, Pred Tangential, Prediction Error (4 columns)
        gs = self.figure.add_gridspec(3, 4, height_ratios=[1, 1.2, 1.2], hspace=0.4, wspace=0.35)

        self.ax_efe = self.figure.add_subplot(gs[0, 0])
        self.ax_ent = self.figure.add_subplot(gs[0, 1])
        self.ax_surprise = self.figure.add_subplot(gs[0, 2])
        self.ax_grad = self.figure.add_subplot(gs[0, 3])

        self.ax_spm_occ = self.figure.add_subplot(gs[1, 0])
        self.ax_spm_rad = self.figure.add_subplot(gs[1, 1])
        self.ax_spm_tan = self.figure.add_subplot(gs[1, 2])
        self.ax_haze_editor = self.figure.add_subplot(gs[1, 3])

        self.ax_pred_occ = self.figure.add_subplot(gs[2, 0])
        self.ax_pred_rad = self.figure.add_subplot(gs[2, 1])
        self.ax_pred_tan = self.figure.add_subplot(gs[2, 2])
        self.ax_pred_error = self.figure.add_subplot(gs[2, 3])

        # Style axes
        for ax in [self.ax_efe, self.ax_ent, self.ax_surprise, self.ax_grad]:
            ax.grid(True, alpha=0.3)
            ax.set_facecolor('#FAFAFA')

        # Labels (compact titles)
        self.ax_efe.set_title("EFE", fontsize=9, fontweight='bold')
        self.ax_efe.set_xlabel("Frame", fontsize=7)
        self.ax_efe.set_ylabel("Value", fontsize=7)

        self.ax_ent.set_title("Entropy", fontsize=9, fontweight='bold')
        self.ax_ent.set_xlabel("Frame", fontsize=7)
        self.ax_ent.set_ylabel("H", fontsize=7)

        self.ax_surprise.set_title("Surprise", fontsize=9, fontweight='bold')
        self.ax_surprise.set_xlabel("Frame", fontsize=7)
        self.ax_surprise.set_ylabel("Value", fontsize=7)

        self.ax_grad.set_title("Gradient", fontsize=9, fontweight='bold')
        self.ax_grad.set_xlabel("Frame", fontsize=7)
        self.ax_grad.set_ylabel("||∇G||", fontsize=7)

        self.ax_haze_editor.set_title("Haze Editor", fontsize=9, fontweight='bold')
        self.ax_haze_editor.set_xlabel("θ", fontsize=7)
        self.ax_haze_editor.set_ylabel("r", fontsize=7)

        # SPM heatmaps (short titles)
        for ax, title in zip([self.ax_spm_occ, self.ax_spm_rad, self.ax_spm_tan],
                            ["Occupancy", "Radial Vel", "Tangential Vel"]):
            ax.set_title(title, fontsize=8, fontweight='bold')
            ax.set_xlabel("θ", fontsize=7)
            ax.set_ylabel("r", fontsize=7)
            ax.set_aspect('equal', adjustable='box')

        # Predicted SPM heatmaps
        for ax, title in zip([self.ax_pred_occ, self.ax_pred_rad, self.ax_pred_tan],
                            ["Pred Occ", "Pred Rad", "Pred Tan"]):
            ax.set_title(title, fontsize=8, fontweight='bold')
            ax.set_xlabel("θ", fontsize=7)
            ax.set_ylabel("r", fontsize=7)
            ax.set_aspect('equal', adjustable='box')

        # Prediction error plot
        self.ax_pred_error.set_title("Pred Error", fontsize=8, fontweight='bold')
        self.ax_pred_error.set_xlabel("θ", fontsize=7)
        self.ax_pred_error.set_ylabel("r", fontsize=7)
        self.ax_pred_error.set_aspect('equal', adjustable='box')

        # Data buffers
        self.efe_data = []
        self.ent_data = []
        self.surprise_data = []
        self.grad_data = []
        self.frames = []

        # Haze tensor (6x6 grid)
        self.haze_tensor = np.zeros((6, 6))
        self.haze_im = None

        # Connect click event for haze editor
        self.canvas.mpl_connect('button_press_event', self.on_haze_click)

        # Initialize haze editor display
        self.update_haze_editor()

    def set_haze_value(self, value):
        """Set the haze spray value from slider."""
        self.current_haze_value = value

    def reset_haze_tensor(self):
        """Reset haze tensor to current haze value."""
        self.haze_tensor = np.full((6, 6), self.current_haze_value)
        self._send_haze_update()
        self.update_haze_editor()

    def on_haze_click(self, event):
        """Handle mouse click on haze editor to spray Gaussian haze."""
        if event.inaxes != self.ax_haze_editor:
            return

        # Get click position in data coordinates
        theta_idx = int(event.xdata)
        r_idx = int(event.ydata)

        # Clamp to valid range
        if not (0 <= theta_idx < 6 and 0 <= r_idx < 6):
            return

        # Apply 2D Gaussian spray centered at click position
        sigma = 1.0  # Gaussian width
        for r in range(6):
            for t in range(6):
                dist_sq = (r - r_idx)**2 + (t - theta_idx)**2
                gaussian = np.exp(-dist_sq / (2 * sigma**2))
                self.haze_tensor[r, t] += self.current_haze_value * gaussian

        # Clamp values to [0, 1]
        self.haze_tensor = np.clip(self.haze_tensor, 0, 1)

        # Send update to Julia server
        self._send_haze_update()

        # Redraw
        self.update_haze_editor()

    def _send_haze_update(self):
        """Send haze tensor to Julia server via ZMQ."""
        if self.control_socket is None:
            return

        try:
            with self.socket_lock:
                message = {
                    "type": "set_haze_tensor",
                    "haze_tensor": self.haze_tensor.tolist()
                }
                self.control_socket.send_string(json.dumps(message))

                # Wait for response (with timeout)
                response_json = self.control_socket.recv_string()
                response = json.loads(response_json)

                if response.get("status") != "ok":
                    print(f"Warning: Haze update failed: {response.get('message')}")

        except Exception as e:
            print(f"Error sending haze update: {e}")
            self._reset_control_socket()

    def _reset_control_socket(self):
        """Reset control socket after error."""
        try:
            if self.control_socket is not None:
                self.control_socket.close()

            import zmq
            self.control_socket = self.context.socket(zmq.REQ)
            self.control_socket.connect("tcp://localhost:5556")
            self.control_socket.setsockopt(zmq.LINGER, 0)
            self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)
            print("✓ Control socket reset")
        except Exception as e:
            print(f"Error resetting control socket: {e}")

    def update_haze_editor(self):
        """Redraw haze tensor editor."""
        self.ax_haze_editor.clear()
        self.ax_haze_editor.set_title("Haze Editor", fontsize=9, fontweight='bold')
        self.ax_haze_editor.set_xlabel("θ", fontsize=7)
        self.ax_haze_editor.set_ylabel("r", fontsize=7)

        # Display haze tensor as heatmap
        self.haze_im = self.ax_haze_editor.imshow(
            self.haze_tensor,
            cmap='hot',
            interpolation='nearest',
            origin='lower',
            vmin=0,
            vmax=1,
            extent=[-0.5, 5.5, -0.5, 5.5]
        )

        # Add colorbar if not present
        if not hasattr(self, 'haze_cbar'):
            self.haze_cbar = self.figure.colorbar(self.haze_im, ax=self.ax_haze_editor, fraction=0.046, pad=0.04)
            self.haze_cbar.set_label('Haze', fontsize=8)

        self.canvas.draw()

    def update_plots(self, data):
        """Update all plots with new data."""
        tracked = data.get("tracked_agent")
        if tracked is None:
            return

        frame = data.get("frame", 0)
        self.frames.append(frame)
        self.efe_data.append(tracked.get("efe", 0))
        self.ent_data.append(tracked.get("entropy", 0))
        self.surprise_data.append(tracked.get("surprise", 0))
        self.grad_data.append(tracked.get("gradient_norm", 0))

        # Limit buffer size
        max_len = 200
        if len(self.frames) > max_len:
            self.frames = self.frames[-max_len:]
            self.efe_data = self.efe_data[-max_len:]
            self.ent_data = self.ent_data[-max_len:]
            self.surprise_data = self.surprise_data[-max_len:]
            self.grad_data = self.grad_data[-max_len:]

        # Update time series plots
        self.ax_efe.clear()
        self.ax_efe.plot(self.frames, self.efe_data, 'b-', linewidth=1.5)
        self.ax_efe.set_title("Expected Free Energy", fontsize=10, fontweight='bold')
        self.ax_efe.set_xlabel("Frame", fontsize=8)
        self.ax_efe.set_ylabel("EFE", fontsize=8)
        self.ax_efe.grid(True, alpha=0.3)

        self.ax_ent.clear()
        self.ax_ent.plot(self.frames, self.ent_data, 'g-', linewidth=1.5)
        self.ax_ent.set_title("Belief Entropy", fontsize=10, fontweight='bold')
        self.ax_ent.set_xlabel("Frame", fontsize=8)
        self.ax_ent.set_ylabel("H[q(s|a)]", fontsize=8)
        self.ax_ent.grid(True, alpha=0.3)

        self.ax_surprise.clear()
        self.ax_surprise.plot(self.frames, self.surprise_data, 'r-', linewidth=1.5)
        self.ax_surprise.set_title("Surprise", fontsize=10, fontweight='bold')
        self.ax_surprise.set_xlabel("Frame", fontsize=8)
        self.ax_surprise.set_ylabel("Surprise", fontsize=8)
        self.ax_surprise.grid(True, alpha=0.3)

        self.ax_grad.clear()
        self.ax_grad.plot(self.frames, self.grad_data, 'm-', linewidth=1.5)
        self.ax_grad.set_title("Gradient Norm", fontsize=10, fontweight='bold')
        self.ax_grad.set_xlabel("Frame", fontsize=8)
        self.ax_grad.set_ylabel("||∇G||", fontsize=8)
        self.ax_grad.grid(True, alpha=0.3)

        # Update SPM heatmaps
        spm_occ = tracked.get("spm_occupancy")
        spm_rad = tracked.get("spm_radial")
        spm_tan = tracked.get("spm_tangential")

        if spm_occ is not None:
            spm_occ_arr = np.array(spm_occ)
            self.ax_spm_occ.clear()
            self.ax_spm_occ.imshow(spm_occ_arr, cmap='viridis', origin='lower', aspect='equal')
            self.ax_spm_occ.set_title("Occupancy", fontsize=8, fontweight='bold')
            self.ax_spm_occ.set_xlabel("θ", fontsize=7)
            self.ax_spm_occ.set_ylabel("r", fontsize=7)
            self.ax_spm_occ.set_aspect('equal', adjustable='box')

        if spm_rad is not None:
            spm_rad_arr = np.array(spm_rad)
            self.ax_spm_rad.clear()
            self.ax_spm_rad.imshow(spm_rad_arr, cmap='coolwarm', origin='lower', aspect='equal')
            self.ax_spm_rad.set_title("Radial Vel", fontsize=8, fontweight='bold')
            self.ax_spm_rad.set_xlabel("θ", fontsize=7)
            self.ax_spm_rad.set_ylabel("r", fontsize=7)
            self.ax_spm_rad.set_aspect('equal', adjustable='box')

        if spm_tan is not None:
            spm_tan_arr = np.array(spm_tan)
            self.ax_spm_tan.clear()
            self.ax_spm_tan.imshow(spm_tan_arr, cmap='coolwarm', origin='lower', aspect='equal')
            self.ax_spm_tan.set_title("Tangential Vel", fontsize=8, fontweight='bold')
            self.ax_spm_tan.set_xlabel("θ", fontsize=7)
            self.ax_spm_tan.set_ylabel("r", fontsize=7)
            self.ax_spm_tan.set_aspect('equal', adjustable='box')

        # Update predicted SPM heatmaps
        spm_pred_occ = tracked.get("spm_pred_occupancy")
        spm_pred_rad = tracked.get("spm_pred_radial")
        spm_pred_tan = tracked.get("spm_pred_tangential")

        if spm_pred_occ is not None:
            spm_pred_occ_arr = np.array(spm_pred_occ)
            self.ax_pred_occ.clear()
            self.ax_pred_occ.imshow(spm_pred_occ_arr, cmap='viridis', origin='lower', aspect='equal')
            self.ax_pred_occ.set_title("Pred Occ", fontsize=8, fontweight='bold')
            self.ax_pred_occ.set_xlabel("θ", fontsize=7)
            self.ax_pred_occ.set_ylabel("r", fontsize=7)
            self.ax_pred_occ.set_aspect('equal', adjustable='box')

        if spm_pred_rad is not None:
            spm_pred_rad_arr = np.array(spm_pred_rad)
            self.ax_pred_rad.clear()
            self.ax_pred_rad.imshow(spm_pred_rad_arr, cmap='coolwarm', origin='lower', aspect='equal')
            self.ax_pred_rad.set_title("Pred Rad", fontsize=8, fontweight='bold')
            self.ax_pred_rad.set_xlabel("θ", fontsize=7)
            self.ax_pred_rad.set_ylabel("r", fontsize=7)
            self.ax_pred_rad.set_aspect('equal', adjustable='box')

        if spm_pred_tan is not None:
            spm_pred_tan_arr = np.array(spm_pred_tan)
            self.ax_pred_tan.clear()
            self.ax_pred_tan.imshow(spm_pred_tan_arr, cmap='coolwarm', origin='lower', aspect='equal')
            self.ax_pred_tan.set_title("Pred Tan", fontsize=8, fontweight='bold')
            self.ax_pred_tan.set_xlabel("θ", fontsize=7)
            self.ax_pred_tan.set_ylabel("r", fontsize=7)
            self.ax_pred_tan.set_aspect('equal', adjustable='box')

        # Update prediction error (L2 norm across all channels)
        if (spm_occ is not None and spm_pred_occ is not None and
            spm_rad is not None and spm_pred_rad is not None and
            spm_tan is not None and spm_pred_tan is not None):

            # Compute per-pixel prediction error (L2 norm)
            error_occ = (spm_occ_arr - spm_pred_occ_arr) ** 2
            error_rad = (spm_rad_arr - spm_pred_rad_arr) ** 2
            error_tan = (spm_tan_arr - spm_pred_tan_arr) ** 2
            total_error = np.sqrt(error_occ + error_rad + error_tan)

            self.ax_pred_error.clear()
            self.ax_pred_error.imshow(total_error, cmap='hot', origin='lower', aspect='equal')
            self.ax_pred_error.set_title("Pred Error", fontsize=8, fontweight='bold')
            self.ax_pred_error.set_xlabel("θ", fontsize=7)
            self.ax_pred_error.set_ylabel("r", fontsize=7)
            self.ax_pred_error.set_aspect('equal', adjustable='box')

        self.canvas.draw()


class MainWindow(QMainWindow):
    """Main application window."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("EPH Coverage Experiment Viewer")
        self.setGeometry(100, 100, 1400, 900)

        # ZMQ Setup
        self.context = zmq.Context()

        # SUB socket for simulation data
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect("tcp://localhost:5555")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, "")
        self.socket.setsockopt(zmq.RCVTIMEO, 100)

        # REQ socket for control commands
        self.control_socket = self.context.socket(zmq.REQ)
        self.control_socket.connect("tcp://localhost:5556")
        self.control_socket.setsockopt(zmq.LINGER, 0)
        self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)
        print("✓ Connected to Julia control socket (tcp://localhost:5556)")

        self.socket_lock = threading.Lock()

        # UI Setup
        self.init_ui()

        # Timer for polling ZMQ
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_simulation)
        self.timer.start(16)  # ~60 FPS

    def init_ui(self):
        """Initialize UI components."""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(5, 5, 5, 5)
        main_layout.setSpacing(5)

        # Horizontal Splitter for Simulation and Dashboard
        splitter = QSplitter(Qt.Horizontal)

        # Left side: Simulation + Haze Control
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(5)

        # Simulation Widget
        self.sim_widget = SimulationWidget()
        left_layout.addWidget(self.sim_widget)

        # Haze Control Panel (below simulation)
        self.control_panel = ControlPanel()
        self.control_panel.haze_value_changed.connect(self.on_haze_value_changed)
        self.control_panel.haze_reset.connect(self.on_haze_reset)
        left_layout.addWidget(self.control_panel)

        splitter.addWidget(left_widget)

        # Right side: Dashboard Widget
        self.dashboard = DashboardWidget(
            control_socket=self.control_socket,
            socket_lock=self.socket_lock,
            zmq_context=self.context
        )
        splitter.addWidget(self.dashboard)

        splitter.setSizes([600, 800])
        main_layout.addWidget(splitter)

    def on_haze_value_changed(self, value):
        """Update haze spray value in dashboard."""
        self.dashboard.set_haze_value(value)

    def on_haze_reset(self):
        """Reset haze tensor."""
        self.dashboard.reset_haze_tensor()

    def update_simulation(self):
        """Poll ZMQ socket for new data."""
        try:
            message_json = self.socket.recv_string(zmq.NOBLOCK)
            data = json.loads(message_json)

            # Update widgets
            self.sim_widget.update_data(data)
            self.dashboard.update_plots(data)

        except zmq.Again:
            pass  # No data available
        except Exception as e:
            print(f"Error receiving data: {e}")

    def closeEvent(self, event):
        """Cleanup on window close."""
        self.timer.stop()
        self.socket.close()
        self.control_socket.close()
        self.context.term()
        event.accept()


def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
