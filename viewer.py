"""
PyQt5 Viewer for Julia EPH Simulation (Sparse Foraging Task).
Integrates simulation visualization and real-time data plots into a single window.
"""
import sys
import zmq
import json
import numpy as np
from collections import deque

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
                             QPushButton, QSlider, QLabel, QSpinBox, QGroupBox, QGridLayout)
from PyQt5.QtCore import QTimer, Qt, QRectF, QPointF, pyqtSignal
from PyQt5.QtGui import QPainter, QColor, QBrush, QPen, QFont, QPolygonF

import matplotlib
matplotlib.use('Qt5Agg')
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure

# --- Configuration ---
WINDOW_WIDTH = 1400
WINDOW_HEIGHT = 800
SIM_WIDTH = 600  # Width of simulation panel
BG_COLOR = QColor(240, 240, 240)  # Light Gray
SIM_BG_COLOR = QColor(255, 255, 255) # White for sim area

class SimulationWidget(QWidget):
    """Widget to render the agent simulation."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(SIM_WIDTH, SIM_WIDTH)  # Square aspect ratio
        self.data = None
        self.sim_world_size = (300, 300) # Default, will update from data
    
    def heightForWidth(self, width):
        """Maintain square aspect ratio"""
        return width
    
    def hasHeightForWidth(self):
        """Enable aspect ratio constraint"""
        return True

    def update_data(self, data):
        self.data = data
        # Update world size from data if available
        if data and "world_size" in data:
            world_size = data["world_size"]
            self.sim_world_size = (world_size[0], world_size[1])
        self.update() # Trigger repaint

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # Draw Background
        painter.fillRect(self.rect(), SIM_BG_COLOR)

        if not self.data:
            painter.drawText(self.rect(), Qt.AlignCenter, "Waiting for Simulation Data...")
            return

        # Coordinate Transformation - maintain square aspect ratio
        size = min(self.width(), self.height())
        
        # Scale to fit square
        scale = size / max(self.sim_world_size[0], self.sim_world_size[1])
        
        # Center the simulation view
        offset_x = (self.width() - self.sim_world_size[0] * scale) / 2
        offset_y = (self.height() - self.sim_world_size[1] * scale) / 2

        painter.translate(offset_x, offset_y)
        painter.scale(scale, scale)

        # Draw Haze Grid
        haze_grid = self.data.get("haze_grid")
        if haze_grid:
            haze_arr = np.array(haze_grid)
            rows, cols = haze_arr.shape
            cell_w = self.sim_world_size[0] / cols
            cell_h = self.sim_world_size[1] / rows
            
            for r in range(rows):
                for c in range(cols):
                    val = haze_arr[r, c]
                    if val > 0.01:
                        # Green haze (Lubricant)
                        alpha = int(min(255, val * 200))
                        color = QColor(0, 200, 0, alpha)
                        painter.fillRect(QRectF(c * cell_w, r * cell_h, cell_w, cell_h), color)

        # Draw Agents
        agents = self.data.get("agents", [])
        for agent in agents:
            self.draw_agent(painter, agent)

        # Draw Info Overlay (reset transform first)
        painter.resetTransform()
        frame = self.data.get("frame", 0)
        coverage = self.data.get("coverage", 0.0) * 100
        info_text = f"Frame: {frame} | Coverage: {coverage:.1f}%"
        painter.setPen(Qt.black)
        painter.setFont(QFont("Arial", 12))
        painter.drawText(10, 20, info_text)

    def draw_agent(self, painter, agent):
        x = agent["x"]
        y = agent["y"]
        radius = agent["radius"]
        orientation = agent["orientation"]
        agent_id = agent["id"]
        has_goal = agent.get("has_goal", False)
        agent_type = agent.get("type", "default")
        color = agent.get("color", [80, 120, 255])

        # Agent 1 or magenta-colored agents are tracked
        is_tracked = (agent_id == 1) or (agent_type in ["dog", "sheep"] and color == [255, 0, 255])

        # Draw FOV (Field of View) - only for non-shepherding agents
        if agent_type == "default":
            fov_angle = np.radians(210)
            fov_radius = 100

            fov_start_angle = -np.degrees(orientation + fov_angle/2) * 16
            fov_span_angle = np.degrees(fov_angle) * 16

            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(200, 200, 200, 50))
            painter.drawPie(QRectF(x - fov_radius, y - fov_radius, fov_radius*2, fov_radius*2),
                            int(fov_start_angle), int(fov_span_angle))

        # Draw Body
        if agent_type in ["dog", "sheep"]:
            # Shepherding agents: Use provided color
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(color[0], color[1], color[2]))

            # Add white outline for tracked agent
            if is_tracked:
                painter.setPen(QPen(Qt.white, 2))
        elif is_tracked and agent_type == "default":
            # Tracked agent (EPH foraging): Red
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(255, 80, 80))
        else:
            # Default: Blue
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(80, 120, 255))

        painter.drawEllipse(QPointF(x, y), radius, radius)

        # Draw Direction Indicator
        end_x = x + np.cos(orientation) * radius * 1.5
        end_y = y + np.sin(orientation) * radius * 1.5
        painter.setPen(QPen(Qt.black, 2))
        painter.drawLine(QPointF(x, y), QPointF(end_x, end_y))
        
        # Draw Gradient Vector for tracked agent
        if is_tracked:
            # Get gradient from tracked_agent data in main data dict
            tracked_data = self.data.get("tracked_agent", {})
            gradient = tracked_data.get("gradient", None)
            
            if gradient and len(gradient) == 2:
                grad_norm = np.linalg.norm(gradient)
                if grad_norm > 0.01:  # Only draw if gradient is significant
                    # Negate gradient to show descent direction (opposite of gradient)
                    grad_scale = 10.0  # Reduced scale factor for smaller arrows
                    grad_end_x = x - gradient[0] * grad_scale  # Negated
                    grad_end_y = y - gradient[1] * grad_scale  # Negated
                    
                    # Draw gradient arrow in bright red
                    painter.setPen(QPen(QColor(255, 0, 0), 3))
                    painter.drawLine(QPointF(x, y), QPointF(grad_end_x, grad_end_y))
                    
                    # Draw arrowhead
                    arrow_size = 10
                    angle = np.arctan2(-gradient[1], -gradient[0])  # Negated for correct direction
                    arrow_p1 = QPointF(
                        grad_end_x - arrow_size * np.cos(angle - np.pi/6),
                        grad_end_y - arrow_size * np.sin(angle - np.pi/6)
                    )
                    arrow_p2 = QPointF(
                        grad_end_x - arrow_size * np.cos(angle + np.pi/6),
                        grad_end_y - arrow_size * np.sin(angle + np.pi/6)
                    )
                    painter.setBrush(QColor(255, 0, 0))
                    painter.drawPolygon(QPolygonF([QPointF(grad_end_x, grad_end_y), arrow_p1, arrow_p2]))


class ControlPanel(QWidget):
    """Control panel for simulation parameters."""

    # Signals for control
    start_sim = pyqtSignal()
    stop_sim = pyqtSignal()
    reset_sim = pyqtSignal()
    speed_changed = pyqtSignal(float)  # Speed multiplier
    steps_changed = pyqtSignal(int)    # Max steps

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # Control Group
        control_group = QGroupBox("Simulation Control")
        control_layout = QGridLayout()

        # Buttons
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

        control_layout.addWidget(self.start_btn, 0, 0)
        control_layout.addWidget(self.stop_btn, 0, 1)
        control_layout.addWidget(self.reset_btn, 1, 0, 1, 2)

        control_group.setLayout(control_layout)
        layout.addWidget(control_group)

        # Speed Control Group
        speed_group = QGroupBox("Playback Speed")
        speed_layout = QVBoxLayout()

        self.speed_label = QLabel("Speed: 1.0x")
        self.speed_label.setAlignment(Qt.AlignCenter)

        self.speed_slider = QSlider(Qt.Horizontal)
        self.speed_slider.setMinimum(1)
        self.speed_slider.setMaximum(50)  # 0.1x to 5.0x
        self.speed_slider.setValue(10)  # 1.0x
        self.speed_slider.setTickPosition(QSlider.TicksBelow)
        self.speed_slider.setTickInterval(5)
        self.speed_slider.valueChanged.connect(self.on_speed_changed)

        speed_layout.addWidget(self.speed_label)
        speed_layout.addWidget(self.speed_slider)

        # Speed presets
        preset_layout = QGridLayout()
        speeds = [("0.5x", 5), ("1x", 10), ("2x", 20), ("5x", 50)]
        for i, (label, value) in enumerate(speeds):
            btn = QPushButton(label)
            btn.clicked.connect(lambda checked, v=value: self.speed_slider.setValue(v))
            preset_layout.addWidget(btn, 0, i)

        speed_layout.addLayout(preset_layout)
        speed_group.setLayout(speed_layout)
        layout.addWidget(speed_group)

        # Steps Control Group
        steps_group = QGroupBox("Max Steps")
        steps_layout = QVBoxLayout()

        self.steps_spinbox = QSpinBox()
        self.steps_spinbox.setMinimum(10)
        self.steps_spinbox.setMaximum(10000)
        self.steps_spinbox.setValue(1000)
        self.steps_spinbox.setSingleStep(50)
        self.steps_spinbox.valueChanged.connect(self.steps_changed.emit)

        steps_layout.addWidget(QLabel("Steps:"))
        steps_layout.addWidget(self.steps_spinbox)

        steps_group.setLayout(steps_layout)
        layout.addWidget(steps_group)

        # Status Label
        self.status_label = QLabel("Status: Ready")
        self.status_label.setStyleSheet("padding: 5px; background-color: #E0E0E0; border-radius: 3px;")
        layout.addWidget(self.status_label)

        layout.addStretch()

    def on_speed_changed(self, value):
        speed = value / 10.0
        self.speed_label.setText(f"Speed: {speed:.1f}x")
        self.speed_changed.emit(speed)

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
    """Widget to display real-time plots using Matplotlib."""
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        
        # Create Matplotlib Figure with adjusted size and color
        self.figure = Figure(figsize=(8, 10), facecolor='#F0F0F0') # Taller figure
        self.canvas = FigureCanvas(self.figure)
        
        # Use a ScrollArea to handle vertical overflow
        from PyQt5.QtWidgets import QScrollArea
        scroll = QScrollArea()
        scroll.setWidget(self.canvas)
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        
        # Style the scroll area
        scroll.setStyleSheet("QScrollArea { border: none; background-color: #F0F0F0; }")
        
        layout.addWidget(scroll)

        # Setup Subplots with better spacing
        # Top row: EFE, Entropy, Surprise (3 plots)
        # Middle row: Gradient Norm, Self-Haze (2 plots)
        # Bottom row: SPM Heatmaps (3 plots)
        gs = self.figure.add_gridspec(3, 3, height_ratios=[1, 1, 1.2], hspace=0.4, wspace=0.3)

        self.ax_efe = self.figure.add_subplot(gs[0, 0])
        self.ax_ent = self.figure.add_subplot(gs[0, 1])
        self.ax_surprise = self.figure.add_subplot(gs[0, 2])
        
        self.ax_grad = self.figure.add_subplot(gs[1, 0:2])
        self.ax_haze = self.figure.add_subplot(gs[1, 2])

        self.ax_spm_occ = self.figure.add_subplot(gs[2, 0])
        self.ax_spm_rad = self.figure.add_subplot(gs[2, 1])
        self.ax_spm_tan = self.figure.add_subplot(gs[2, 2])

        self.axes = [self.ax_efe, self.ax_ent, self.ax_surprise, self.ax_grad, self.ax_haze,
                     self.ax_spm_occ, self.ax_spm_rad, self.ax_spm_tan]

        # Initial Styling
        titles = ['Expected Free Energy', 'Belief Entropy', 'Surprise (F_percept)',
                  'Gradient Norm', 'Self-Haze',
                  'SPM: Occupancy', 'SPM: Radial Vel', 'SPM: Tangential Vel']
        
        for ax, title in zip(self.axes, titles):
            ax.set_title(title, fontsize=10, pad=10)
            ax.grid(True, linestyle='--', alpha=0.6)
            ax.set_facecolor('white')
            ax.tick_params(labelsize=8)

        self.figure.tight_layout()

        # Data History
        self.max_history = 200
        self.history = {
            'frame': deque(maxlen=self.max_history),
            'efe': deque(maxlen=self.max_history),
            'entropy': deque(maxlen=self.max_history),
            'surprise': deque(maxlen=self.max_history),
            'haze': deque(maxlen=self.max_history),
            'grad_norm': deque(maxlen=self.max_history)
        }

    def update_plots(self, data):
        tracked_data = data.get("tracked_agent")
        if not tracked_data:
            return

        frame = data.get("frame", 0)
        
        # Update History
        self.history['frame'].append(frame)
        self.history['efe'].append(tracked_data.get("efe", 0))
        self.history['entropy'].append(tracked_data.get("entropy", 0))
        self.history['surprise'].append(tracked_data.get("surprise", 0))
        self.history['haze'].append(tracked_data.get("self_haze", 0))
        
        grad = tracked_data.get("gradient", [0, 0])
        grad_norm = np.linalg.norm(grad) if grad else 0
        self.history['grad_norm'].append(grad_norm)

        # Redraw Time Series
        x = list(self.history['frame'])
        
        # Helper to plot time series
        def plot_ts(ax, y_data, color, title, ylim=None):
            ax.clear()
            ax.set_title(title, fontsize=10)
            ax.plot(x, y_data, color=color, linewidth=1.5)
            ax.grid(True, linestyle='--', alpha=0.6)
            ax.tick_params(labelsize=8)
            if ylim: ax.set_ylim(ylim)

        plot_ts(self.ax_efe, self.history['efe'], 'b', 'Expected Free Energy')
        plot_ts(self.ax_ent, self.history['entropy'], 'r', 'Belief Entropy')
        plot_ts(self.ax_surprise, self.history['surprise'], 'orange', 'Surprise (F_percept)')
        plot_ts(self.ax_grad, self.history['grad_norm'], 'k', 'Gradient Norm')
        plot_ts(self.ax_haze, self.history['haze'], 'g', 'Self-Haze', ylim=(0, 1.0))

        # Update Heatmaps
        spm_occ = np.array(tracked_data.get("spm_occupancy", []))
        spm_rad = np.array(tracked_data.get("spm_radial", []))
        spm_tan = np.array(tracked_data.get("spm_tangential", []))

        # Helper to plot heatmap
        def plot_hm(ax, data, title, cmap, vmin=None, vmax=None):
            if data.size > 0 and data.ndim == 2:
                ax.clear()
                ax.set_title(title, fontsize=10)
                ax.imshow(data, cmap=cmap, aspect='auto', interpolation='nearest', vmin=vmin, vmax=vmax)
                ax.tick_params(labelsize=8)

        plot_hm(self.ax_spm_occ, spm_occ, 'SPM: Occupancy', 'hot')
        plot_hm(self.ax_spm_rad, spm_rad, 'SPM: Radial Vel', 'RdBu', -50, 50)
        plot_hm(self.ax_spm_tan, spm_tan, 'SPM: Tangential Vel', 'RdBu', -50, 50)

        self.canvas.draw()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Julia EPH Viewer - Active Inference Dashboard")
        self.resize(WINDOW_WIDTH, WINDOW_HEIGHT)
        
        # Main Layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        # Set light gray background
        central_widget.setStyleSheet(f"background-color: {BG_COLOR.name()};")
        
        layout = QHBoxLayout(central_widget)
        layout.setContentsMargins(20, 20, 20, 20) # Increased margins
        layout.setSpacing(20) # Increased spacing

        # Add Widgets
        # Left panel: Control + Simulation
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        left_layout.setSpacing(10)

        self.control_panel = ControlPanel()
        self.sim_widget = SimulationWidget()

        left_layout.addWidget(self.control_panel)
        left_layout.addWidget(self.sim_widget, stretch=1)

        self.dashboard_widget = DashboardWidget()

        layout.addWidget(left_panel, stretch=4)
        layout.addWidget(self.dashboard_widget, stretch=6)

        # Connect control signals
        self.control_panel.speed_changed.connect(self.on_speed_changed)
        self.is_paused = False
        self.speed_multiplier = 1.0

        # ZeroMQ Setup
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect("tcp://localhost:5555")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, '')
        
        # Timer for polling ZMQ
        self.base_interval = 16  # ~60 FPS base
        self.timer = QTimer()
        self.timer.timeout.connect(self.poll_zmq)
        self.timer.start(self.base_interval)

    def on_speed_changed(self, speed):
        """Adjust polling rate based on speed multiplier."""
        self.speed_multiplier = speed
        # Faster speed = shorter interval (poll more frequently to keep up)
        # Slower speed = longer interval (poll less frequently)
        new_interval = max(1, int(self.base_interval / speed))
        self.timer.setInterval(new_interval)

    def poll_zmq(self):
        if self.is_paused:
            return

        try:
            # Poll multiple messages if speed > 1.0 to catch up
            max_msgs = max(1, int(self.speed_multiplier))
            for _ in range(max_msgs):
                try:
                    msg = self.socket.recv_string(flags=zmq.NOBLOCK)
                    data = json.loads(msg)

                    # Update widgets
                    self.sim_widget.update_data(data)

                    # Throttle plot updates
                    if data.get("frame", 0) % 5 == 0:
                        self.dashboard_widget.update_plots(data)

                except zmq.Again:
                    break
        except Exception as e:
            print(f"Error: {e}")

    def closeEvent(self, event):
        # Stop the timer to prevent further polling
        self.timer.stop()
        
        # Set LINGER to 0 to discard pending messages immediately
        self.socket.setsockopt(zmq.LINGER, 0)
        self.socket.close()
        
        # Terminate context
        self.context.term()
        event.accept()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    
    # Set application style
    app.setStyle("Fusion")
    
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())
