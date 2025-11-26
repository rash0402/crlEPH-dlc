"""
PyQt5 Viewer for Julia EPH Simulation (Sparse Foraging Task).
Integrates simulation visualization and real-time data plots into a single window.
"""
import sys
import zmq
import json
import numpy as np
import threading
from collections import deque

from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
                             QPushButton, QSlider, QLabel, QSpinBox, QGroupBox, QGridLayout)
from PyQt5.QtCore import QTimer, Qt, QRectF, QPointF, pyqtSignal, QDateTime
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
        self.goal_position = None  # Will be updated from data
    
    def heightForWidth(self, width):
        """Maintain square aspect ratio"""
        return width
    
    def hasHeightForWidth(self):
        """Enable aspect ratio constraint"""
        return True

    def widget_to_world_coords(self, widget_x, widget_y):
        """Convert widget pixel coordinates to world coordinates.

        Must match the coordinate transformation in paintEvent:
        - painter.translate(offset_x, offset_y)
        - painter.scale(scale, scale)
        """
        # Calculate same transformation as in paintEvent
        size = min(self.width(), self.height())
        scale = size / max(self.sim_world_size[0], self.sim_world_size[1])
        offset_x = (self.width() - self.sim_world_size[0] * scale) / 2
        offset_y = (self.height() - self.sim_world_size[1] * scale) / 2

        # Inverse transformation: (widget - offset) / scale = world
        world_x = (widget_x - offset_x) / scale
        world_y = (widget_y - offset_y) / scale

        return world_x, world_y

    def update_data(self, data):
        self.data = data
        # Update world size from data if available
        if data and "world_size" in data:
            world_size = data["world_size"]
            self.sim_world_size = (world_size[0], world_size[1])
        # NOTE: goal_position is now managed by MainWindow, not updated from data here
        # This prevents Julia messages from overwriting user-controlled goal position
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

        # Draw Coverage Map (visit count visualization)
        coverage_map = self.data.get("coverage_map")
        if coverage_map is not None:
            coverage_arr = np.array(coverage_map)
            rows, cols = coverage_arr.shape
            cell_w = self.sim_world_size[0] / cols
            cell_h = self.sim_world_size[1] / rows

            # Compute max visit count for normalization
            max_visits = np.max(coverage_arr) if np.max(coverage_arr) > 0 else 1

            for r in range(rows):
                for c in range(cols):
                    visits = coverage_arr[r, c]
                    if visits > 0:
                        # Blue translucent overlay, darker with more visits
                        # Logarithmic scaling for better visibility
                        intensity = min(1.0, np.log1p(visits) / np.log1p(max_visits))
                        alpha = int(80 + 120 * intensity)  # 80-200 range
                        color = QColor(100, 150, 255, alpha)  # Light blue
                        painter.fillRect(QRectF(c * cell_w, r * cell_h, cell_w, cell_h), color)

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

        # Draw Goal Position (if available)
        if self.goal_position is not None:
            goal_x, goal_y = self.goal_position
            goal_radius = 20

            # Draw target circle with crosshair
            painter.setPen(QPen(QColor(255, 200, 0), 3))  # Yellow-orange outline
            painter.setBrush(QColor(255, 200, 0, 80))  # Semi-transparent fill
            painter.drawEllipse(QPointF(goal_x, goal_y), goal_radius, goal_radius)

            # Draw crosshair
            painter.setPen(QPen(QColor(255, 150, 0), 2))
            painter.drawLine(QPointF(goal_x - goal_radius - 5, goal_y),
                           QPointF(goal_x + goal_radius + 5, goal_y))
            painter.drawLine(QPointF(goal_x, goal_y - goal_radius - 5),
                           QPointF(goal_x, goal_y + goal_radius + 5))

            # Draw "GOAL" label
            painter.setPen(QColor(255, 200, 0))
            painter.setFont(QFont("Arial", 10, QFont.Bold))
            painter.drawText(QPointF(goal_x - 15, goal_y - goal_radius - 10), "GOAL")

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

        # Draw FOV (Field of View) for tracked shepherding dog
        if is_tracked and agent_type == "dog":
            # SPM perception range: 210 degrees, max range ~100.0
            fov_angle = np.radians(210)
            fov_radius = 100  # Max SPM perception range (narrowed from 200)

            fov_start_angle = -np.degrees(orientation + fov_angle/2) * 16
            fov_span_angle = np.degrees(fov_angle) * 16

            # Draw semi-transparent FOV sector
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(255, 0, 255, 30))  # Semi-transparent magenta
            painter.drawPie(QRectF(x - fov_radius, y - fov_radius, fov_radius*2, fov_radius*2),
                            int(fov_start_angle), int(fov_span_angle))

            # Draw FOV boundary arc
            painter.setPen(QPen(QColor(255, 0, 255, 100), 1, Qt.DashLine))
            painter.setBrush(Qt.NoBrush)
            painter.drawArc(QRectF(x - fov_radius, y - fov_radius, fov_radius*2, fov_radius*2),
                            int(fov_start_angle), int(fov_span_angle))

        # Draw FOV (Field of View) - only for non-shepherding agents
        elif agent_type == "default":
            fov_angle = np.radians(210)
            fov_radius = 100

            fov_start_angle = -np.degrees(orientation + fov_angle/2) * 16
            fov_span_angle = np.degrees(fov_angle) * 16

            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(200, 200, 200, 50))
            painter.drawPie(QRectF(x - fov_radius, y - fov_radius, fov_radius*2, fov_radius*2),
                            int(fov_start_angle), int(fov_span_angle))

        # Keep same radius for all agents
        display_radius = radius

        # Draw Body
        if agent_type in ["dog", "sheep"]:
            # Shepherding agents: Use provided color
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(color[0], color[1], color[2]))

            # Add yellow outline for tracked agent
            if is_tracked:
                painter.setPen(QPen(QColor(255, 255, 0), 3))  # Yellow outline
        elif is_tracked and agent_type == "default":
            # Tracked agent (EPH foraging): Red
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(255, 80, 80))
        else:
            # Default: Blue
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(80, 120, 255))

        painter.drawEllipse(QPointF(x, y), display_radius, display_radius)

        # Draw Direction Indicator
        end_x = x + np.cos(orientation) * radius * 1.5
        end_y = y + np.sin(orientation) * radius * 1.5
        painter.setPen(QPen(Qt.black, 3 if is_tracked else 2))
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
    speed_changed = pyqtSignal(float)  # Playback speed multiplier
    steps_changed = pyqtSignal(int)    # Max steps
    dog_speed_changed = pyqtSignal(float)   # Dog max speed
    sheep_speed_changed = pyqtSignal(float) # Sheep max speed
    boids_params_changed = pyqtSignal(dict) # BOIDS parameters
    save_config = pyqtSignal()         # Save configuration
    load_config = pyqtSignal()         # Load configuration

    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()

    def init_ui(self):
        # Use horizontal layout for compact design
        layout = QHBoxLayout(self)
        layout.setSpacing(5)
        layout.setContentsMargins(5, 5, 5, 5)

        # Control Buttons (vertical mini panel)
        control_group = QGroupBox("Control")
        control_layout = QVBoxLayout()
        control_layout.setSpacing(3)

        # Buttons (smaller)
        self.start_btn = QPushButton("▶")
        self.start_btn.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold; padding: 5px;")
        self.start_btn.setToolTip("Start")
        self.start_btn.clicked.connect(self.start_sim.emit)

        self.stop_btn = QPushButton("⏸")
        self.stop_btn.setStyleSheet("background-color: #f44336; color: white; font-weight: bold; padding: 5px;")
        self.stop_btn.setToolTip("Stop")
        self.stop_btn.clicked.connect(self.stop_sim.emit)
        self.stop_btn.setEnabled(False)

        self.reset_btn = QPushButton("⟲")
        self.reset_btn.setStyleSheet("background-color: #2196F3; color: white; font-weight: bold; padding: 5px;")
        self.reset_btn.setToolTip("Reset")
        self.reset_btn.clicked.connect(self.reset_sim.emit)

        control_layout.addWidget(self.start_btn)
        control_layout.addWidget(self.stop_btn)
        control_layout.addWidget(self.reset_btn)
        control_layout.addStretch()

        control_group.setLayout(control_layout)
        layout.addWidget(control_group)

        # Simulation Parameters (compact)
        sim_group = QGroupBox("Simulation")
        sim_layout = QVBoxLayout()
        sim_layout.setSpacing(2)

        # Playback speed
        pb_layout = QHBoxLayout()
        pb_layout.addWidget(QLabel("Play:"))
        self.speed_label = QLabel("1.0x")
        self.speed_label.setMinimumWidth(30)
        self.speed_slider = QSlider(Qt.Horizontal)
        self.speed_slider.setMinimum(1)
        self.speed_slider.setMaximum(50)
        self.speed_slider.setValue(10)
        self.speed_slider.valueChanged.connect(self.on_speed_changed)
        pb_layout.addWidget(self.speed_slider)
        pb_layout.addWidget(self.speed_label)
        sim_layout.addLayout(pb_layout)

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
        sim_layout.addLayout(steps_layout)

        sim_group.setLayout(sim_layout)
        layout.addWidget(sim_group)

        # Agent Speeds (compact)
        agent_group = QGroupBox("Agent Speed")
        agent_layout = QVBoxLayout()
        agent_layout.setSpacing(2)

        # Dog speed
        dog_layout = QHBoxLayout()
        dog_layout.addWidget(QLabel("Dog:"))
        self.dog_speed_label = QLabel("40.0")
        self.dog_speed_label.setMinimumWidth(30)
        self.dog_speed_slider = QSlider(Qt.Horizontal)
        self.dog_speed_slider.setMinimum(10)
        self.dog_speed_slider.setMaximum(100)
        self.dog_speed_slider.setValue(40)
        self.dog_speed_slider.valueChanged.connect(self.on_dog_speed_changed)
        dog_layout.addWidget(self.dog_speed_slider)
        dog_layout.addWidget(self.dog_speed_label)
        agent_layout.addLayout(dog_layout)

        # Sheep speed
        sheep_layout = QHBoxLayout()
        sheep_layout.addWidget(QLabel("Sheep:"))
        self.sheep_speed_label = QLabel("10.0")
        self.sheep_speed_label.setMinimumWidth(30)
        self.sheep_speed_slider = QSlider(Qt.Horizontal)
        self.sheep_speed_slider.setMinimum(5)
        self.sheep_speed_slider.setMaximum(50)
        self.sheep_speed_slider.setValue(10)
        self.sheep_speed_slider.valueChanged.connect(self.on_sheep_speed_changed)
        sheep_layout.addWidget(self.sheep_speed_slider)
        sheep_layout.addWidget(self.sheep_speed_label)
        agent_layout.addLayout(sheep_layout)

        agent_group.setLayout(agent_layout)
        layout.addWidget(agent_group)

        # BOIDS Parameters (compact)
        boids_group = QGroupBox("BOIDS")
        boids_layout = QVBoxLayout()
        boids_layout.setSpacing(2)

        # Helper to create compact slider
        def create_slider(label, default_val):
            h_layout = QHBoxLayout()
            h_layout.addWidget(QLabel(label))
            value_label = QLabel(f"{default_val/10:.1f}")
            value_label.setMinimumWidth(25)
            slider = QSlider(Qt.Horizontal)
            slider.setMinimum(0)
            slider.setMaximum(50)
            slider.setValue(int(default_val))
            slider.setMinimumWidth(100)  # Ensure slider is wide enough to operate
            h_layout.addWidget(slider)
            h_layout.addWidget(value_label)
            return h_layout, slider, value_label

        # Create sliders
        sep_l, self.sep_slider, self.sep_label = create_slider("Sep:", 30)
        ali_l, self.ali_slider, self.ali_label = create_slider("Ali:", 10)
        coh_l, self.coh_slider, self.coh_label = create_slider("Coh:", 10)
        flee_l, self.flee_slider, self.flee_label = create_slider("Flee:", 30)

        boids_layout.addLayout(sep_l)
        boids_layout.addLayout(ali_l)
        boids_layout.addLayout(coh_l)
        boids_layout.addLayout(flee_l)

        # Connect sliders
        self.sep_slider.valueChanged.connect(lambda v: self.on_boids_param_changed('sep', v))
        self.ali_slider.valueChanged.connect(lambda v: self.on_boids_param_changed('ali', v))
        self.coh_slider.valueChanged.connect(lambda v: self.on_boids_param_changed('coh', v))
        self.flee_slider.valueChanged.connect(lambda v: self.on_boids_param_changed('flee', v))

        boids_group.setLayout(boids_layout)
        layout.addWidget(boids_group)

        # Config (compact)
        config_group = QGroupBox("Config")
        config_layout = QVBoxLayout()
        config_layout.setSpacing(2)

        self.save_btn = QPushButton("💾")
        self.save_btn.setStyleSheet("background-color: #4CAF50; color: white; padding: 3px;")
        self.save_btn.setToolTip("Save configuration")
        self.save_btn.clicked.connect(self.save_config.emit)

        self.load_btn = QPushButton("📂")
        self.load_btn.setStyleSheet("background-color: #2196F3; color: white; padding: 3px;")
        self.load_btn.setToolTip("Load configuration")
        self.load_btn.clicked.connect(self.load_config.emit)

        config_layout.addWidget(self.save_btn)
        config_layout.addWidget(self.load_btn)
        config_layout.addStretch()
        config_group.setLayout(config_layout)
        layout.addWidget(config_group)

        # Status Label (minimal)
        self.status_label = QLabel("Ready")
        self.status_label.setStyleSheet("padding: 2px; font-size: 9px;")
        self.status_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(self.status_label)

    def on_speed_changed(self, value):
        speed = value / 10.0
        self.speed_label.setText(f"Speed: {speed:.1f}x")
        self.speed_changed.emit(speed)

    def on_dog_speed_changed(self, value):
        speed = float(value)
        self.dog_speed_label.setText(f"{speed:.1f}")
        self.dog_speed_changed.emit(speed)

    def on_sheep_speed_changed(self, value):
        speed = float(value)
        self.sheep_speed_label.setText(f"{speed:.1f}")
        self.sheep_speed_changed.emit(speed)

    def on_boids_param_changed(self, param_name, value):
        """Handle BOIDS parameter slider changes."""
        float_value = value / 10.0

        # Update label
        if param_name == 'sep':
            self.sep_label.setText(f"{float_value:.1f}")
        elif param_name == 'ali':
            self.ali_label.setText(f"{float_value:.1f}")
        elif param_name == 'coh':
            self.coh_label.setText(f"{float_value:.1f}")
        elif param_name == 'flee':
            self.flee_label.setText(f"{float_value:.1f}")

        # Emit all current BOIDS params
        params = {
            'w_separation': self.sep_slider.value() / 10.0,
            'w_alignment': self.ali_slider.value() / 10.0,
            'w_cohesion': self.coh_slider.value() / 10.0,
            'flee_weight': self.flee_slider.value() / 10.0
        }
        self.boids_params_changed.emit(params)

    def get_all_params(self):
        """Get all current parameter values for saving."""
        return {
            'dog_speed': self.dog_speed_slider.value(),
            'sheep_speed': self.sheep_speed_slider.value(),
            'playback_speed': self.speed_slider.value(),
            'max_steps': self.steps_spinbox.value(),
            'boids': {
                'w_separation': self.sep_slider.value() / 10.0,
                'w_alignment': self.ali_slider.value() / 10.0,
                'w_cohesion': self.coh_slider.value() / 10.0,
                'flee_weight': self.flee_slider.value() / 10.0
            }
        }

    def set_all_params(self, params):
        """Set all parameter values from loaded config."""
        if 'dog_speed' in params:
            self.dog_speed_slider.setValue(int(params['dog_speed']))
        if 'sheep_speed' in params:
            self.sheep_speed_slider.setValue(int(params['sheep_speed']))
        if 'playback_speed' in params:
            self.speed_slider.setValue(int(params['playback_speed']))
        if 'max_steps' in params:
            self.steps_spinbox.setValue(int(params['max_steps']))
        if 'boids' in params:
            boids = params['boids']
            if 'w_separation' in boids:
                self.sep_slider.setValue(int(boids['w_separation'] * 10))
            if 'w_alignment' in boids:
                self.ali_slider.setValue(int(boids['w_alignment'] * 10))
            if 'w_cohesion' in boids:
                self.coh_slider.setValue(int(boids['w_cohesion'] * 10))
            if 'flee_weight' in boids:
                self.flee_slider.setValue(int(boids['flee_weight'] * 10))

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
    def __init__(self, parent=None, control_socket=None, socket_lock=None, zmq_context=None):
        super().__init__(parent)
        self.control_socket = control_socket
        self.socket_lock = socket_lock
        self.context = zmq_context  # ZMQ context for socket recreation
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
        # Middle row: Gradient Norm (1 plot), Haze Tensor Editor (interactive), Self-Haze (1 plot)
        # Bottom row: SPM Heatmaps (3 plots)
        gs = self.figure.add_gridspec(3, 3, height_ratios=[1, 1, 1.2], hspace=0.4, wspace=0.3)

        self.ax_efe = self.figure.add_subplot(gs[0, 0])
        self.ax_ent = self.figure.add_subplot(gs[0, 1])
        self.ax_surprise = self.figure.add_subplot(gs[0, 2])

        self.ax_grad = self.figure.add_subplot(gs[1, 0])  # Changed: half size (1 column)
        self.ax_haze_editor = self.figure.add_subplot(gs[1, 1])  # New: Haze tensor editor
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

        # Note: ax_haze_editor is styled separately for interactive use
        
        for ax, title in zip(self.axes, titles):
            ax.set_title(title, fontsize=10, pad=10)
            ax.grid(True, linestyle='--', alpha=0.6)
            ax.set_facecolor('white')
            ax.tick_params(labelsize=8)

        self.figure.tight_layout()

        # Initialize Haze Tensor Editor (2x2 interactive grid)
        self.haze_tensor_size = 6  # 6x6 grid (matching SPM size)
        self.haze_active_pos = (2, 2)  # Center position of 2x2 active region
        self.haze_tensor = np.zeros((self.haze_tensor_size, self.haze_tensor_size))
        self._update_haze_tensor()  # Set initial 2x2 region to 1.0
        self._draw_haze_editor()

        # Connect mouse event for interactive editing
        self.canvas.mpl_connect('button_press_event', self._on_haze_editor_click)

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

    def _update_haze_tensor(self):
        """Update haze tensor: 2x2 region at active_pos = 1.0, rest = 0.0"""
        self.haze_tensor.fill(0.0)
        r, c = self.haze_active_pos
        # Set 2x2 region to 1.0 (with boundary check)
        for dr in range(2):
            for dc in range(2):
                nr, nc = r + dr, c + dc
                if 0 <= nr < self.haze_tensor_size and 0 <= nc < self.haze_tensor_size:
                    self.haze_tensor[nr, nc] = 1.0

    def _draw_haze_editor(self):
        """Draw the Haze tensor editor as a heatmap."""
        self.ax_haze_editor.clear()
        self.ax_haze_editor.set_title('Haze Tensor Editor (Click to Move)', fontsize=10, pad=10)

        # Draw heatmap
        im = self.ax_haze_editor.imshow(self.haze_tensor, cmap='Reds', vmin=0, vmax=1,
                                        interpolation='nearest', aspect='auto')

        # Add grid lines
        for i in range(self.haze_tensor_size + 1):
            self.ax_haze_editor.axhline(i - 0.5, color='gray', linewidth=0.5)
            self.ax_haze_editor.axvline(i - 0.5, color='gray', linewidth=0.5)

        # Set ticks
        self.ax_haze_editor.set_xticks(range(self.haze_tensor_size))
        self.ax_haze_editor.set_yticks(range(self.haze_tensor_size))
        self.ax_haze_editor.set_xticklabels(range(self.haze_tensor_size), fontsize=8)
        self.ax_haze_editor.set_yticklabels(range(self.haze_tensor_size), fontsize=8)

        # Add instruction text
        self.ax_haze_editor.text(0.5, -0.15, 'Click to reposition 2x2 active region',
                                 transform=self.ax_haze_editor.transAxes,
                                 ha='center', fontsize=8, style='italic')

    def _on_haze_editor_click(self, event):
        """Handle mouse click on Haze editor to reposition 2x2 active region."""
        if event.inaxes == self.ax_haze_editor and event.xdata is not None and event.ydata is not None:
            # Convert click coordinates to grid indices
            col = int(np.round(event.xdata))
            row = int(np.round(event.ydata))

            # Ensure 2x2 region fits within bounds
            if 0 <= row < self.haze_tensor_size - 1 and 0 <= col < self.haze_tensor_size - 1:
                self.haze_active_pos = (row, col)
                self._update_haze_tensor()
                self._draw_haze_editor()
                self.canvas.draw_idle()

                print(f"Haze tensor active position updated to: ({row}, {col})")

                # Send haze update to Julia via ZMQ REQ socket
                self._send_haze_update()

    def _send_haze_update(self):
        """Send current haze tensor to Julia server via ZMQ REQ socket."""
        if self.control_socket is None or self.socket_lock is None:
            print("Warning: Control socket not initialized, cannot send haze update")
            return

        try:
            # Prepare haze update message
            message = {
                "type": "set_haze_tensor",
                "haze_tensor": self.haze_tensor.tolist()  # Convert numpy array to list
            }

            with self.socket_lock:
                # Send request
                self.control_socket.send_json(message)
                print(f"Sent haze update: active_pos={self.haze_active_pos}")

                # Wait for acknowledgment
                try:
                    response = self.control_socket.recv_json()
                    if response.get("status") == "ok":
                        print(f"✓ Haze update acknowledged by Julia server")
                    else:
                        print(f"Warning: Unexpected response from Julia: {response}")
                except zmq.Again:
                    print("Warning: No response from Julia server (timeout)")
                    # REQ socket becomes invalid after timeout - must reset
                    self._reset_control_socket()
        except zmq.ZMQError as e:
            print(f"ZMQ error sending haze update: {e}")
            # Reset socket on any ZMQ error (e.g., "Operation cannot be accomplished")
            self._reset_control_socket()
        except Exception as e:
            print(f"Error sending haze update: {e}")

    def _reset_control_socket(self):
        """Reset control socket after error or timeout.

        REQ sockets have strict send-recv-send-recv ordering.
        If recv times out or errors, the socket becomes invalid and must be recreated.
        """
        try:
            if self.control_socket is not None:
                self.control_socket.close()

            # Recreate REQ socket with same settings
            import zmq
            self.control_socket = self.context.socket(zmq.REQ)
            self.control_socket.connect("tcp://localhost:5556")
            self.control_socket.setsockopt(zmq.LINGER, 0)
            self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)
            print("✓ Control socket reset")
        except Exception as e:
            print(f"Error resetting control socket: {e}")

    def clear_plots(self):
        """Clear all plot history and redraw empty plots."""
        # Clear history
        for key in self.history:
            self.history[key].clear()

        # Clear all axes
        for ax in self.axes:
            ax.clear()
            ax.grid(True, linestyle='--', alpha=0.6)

        self.canvas.draw()
        print("Dashboard plots cleared")

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

        plot_hm(self.ax_spm_occ, spm_occ, 'SPM: Occupancy', 'hot', vmin=0, vmax=10)
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

        # DashboardWidget will be initialized after ZMQ sockets are created
        self.dashboard_widget = None

        layout.addWidget(left_panel, stretch=4)

        # Connect control signals
        self.control_panel.start_sim.connect(self.on_start)
        self.control_panel.stop_sim.connect(self.on_stop)
        self.control_panel.reset_sim.connect(self.on_reset)
        self.control_panel.speed_changed.connect(self.on_speed_changed)
        self.control_panel.dog_speed_changed.connect(self.on_dog_speed_changed)
        self.control_panel.sheep_speed_changed.connect(self.on_sheep_speed_changed)
        self.control_panel.boids_params_changed.connect(self.on_boids_params_changed)
        self.control_panel.save_config.connect(self.on_save_config)
        self.control_panel.load_config.connect(self.on_load_config)

        self.is_paused = False
        self.speed_multiplier = 1.0
        self.dog_max_speed = 40.0
        self.sheep_max_speed = 10.0
        self.config_file = "shepherding_config.json"

        # Goal position (default: 75% of world size, will be updated from Julia)
        self.goal_position = [300.0, 300.0]  # [x, y] in world coordinates
        self.world_size = 400.0
        self.sim_widget.goal_position = self.goal_position  # Sync with sim widget
        self.goal_position_user_controlled = False  # Flag: has user set goal position?

        # Enable mouse tracking for goal position updates
        self.sim_widget.setMouseTracking(True)
        self.sim_widget.mousePressEvent = self.on_sim_mouse_press
        self.sim_widget.mouseMoveEvent = self.on_sim_mouse_move
        self.sim_widget.mouseReleaseEvent = self.on_sim_mouse_release
        self.goal_drag_active = False

        # Enable keyboard input for goal position
        self.setFocusPolicy(Qt.StrongFocus)

        # ZeroMQ Setup
        self.context = zmq.Context()

        # SUB socket for receiving simulation data
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect("tcp://localhost:5555")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, '')

        # REQ socket for sending control commands
        self.control_socket = self.context.socket(zmq.REQ)
        self.control_socket.connect("tcp://localhost:5556")
        self.control_socket.setsockopt(zmq.LINGER, 0)
        self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)  # Default 1s timeout
        print("✓ Connected to Julia control socket (tcp://localhost:5556)")

        # Lock for thread-safe socket access
        self.control_socket_lock = threading.Lock()

        # Now create DashboardWidget with control socket
        self.dashboard_widget = DashboardWidget(
            parent=None,
            control_socket=self.control_socket,
            socket_lock=self.control_socket_lock,
            zmq_context=self.context
        )
        layout.addWidget(self.dashboard_widget, stretch=6)

        # Timer for polling ZMQ
        self.base_interval = 16  # ~60 FPS base
        self.timer = QTimer()
        self.timer.timeout.connect(self.poll_zmq)
        self.timer.start(self.base_interval)

    def on_start(self):
        """Start/Resume simulation."""
        self.is_paused = False
        self.control_panel.set_running(True)
        print("Simulation started/resumed")

    def on_stop(self):
        """Stop/Pause simulation."""
        self.is_paused = True
        self.control_panel.set_running(False)
        print("Simulation paused")

    def send_control_command(self, command, value=None):
        """Send control command to Julia server and get response (thread-safe)."""
        with self.control_socket_lock:
            try:
                cmd = {"command": command}
                if value is not None:
                    cmd["value"] = value

                self.control_socket.send_json(cmd)
                response = self.control_socket.recv_json()
                return response
            except zmq.error.Again:
                print(f"Timeout waiting for response to command: {command}")
                # REQ socket is now in invalid state, must recreate
                self._recreate_control_socket()
                return None
            except zmq.ZMQError as e:
                print(f"ZMQ error sending control command: {e}")
                # Socket may be in invalid state, recreate
                self._recreate_control_socket()
                return None
            except Exception as e:
                print(f"Error sending control command: {e}")
                return None

    def _recreate_control_socket(self):
        """Recreate control socket after error (must hold lock)."""
        try:
            self.control_socket.close()
        except:
            pass

        self.control_socket = self.context.socket(zmq.REQ)
        self.control_socket.connect("tcp://localhost:5556")
        self.control_socket.setsockopt(zmq.LINGER, 0)
        self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1s timeout
        print("✓ Control socket recreated after error")

    def on_reset(self):
        """Reset simulation by sending reset command to Julia server (async)."""
        print("Sending RESET command to Julia server...")
        self.dashboard_widget.clear_plots()

        # Send command in background thread to avoid blocking UI
        def send_cmd():
            response = self.send_control_command("reset")
            if response:
                print(f"✓ Reset response: {response.get('status')}")
            else:
                print("✗ Failed to send reset command")

        threading.Thread(target=send_cmd, daemon=True).start()

    def on_speed_changed(self, speed):
        """Adjust polling rate based on speed multiplier."""
        self.speed_multiplier = speed
        # Faster speed = shorter interval (poll more frequently to keep up)
        # Slower speed = longer interval (poll less frequently)
        new_interval = max(1, int(self.base_interval / speed))
        self.timer.setInterval(new_interval)
        print(f"Playback speed changed to {speed:.1f}x")

    def on_dog_speed_changed(self, speed):
        """Update dog max speed via Julia control channel (async)."""
        self.dog_max_speed = speed
        print(f"Setting dog max speed to {speed:.1f}...")

        # Send command in background thread to avoid blocking UI
        def send_cmd():
            response = self.send_control_command("set_dog_speed", speed)
            if response and response.get("status") == "ok":
                print(f"✓ Dog max speed updated to {response.get('dog_speed'):.1f}")
            else:
                print(f"✗ Failed to update dog speed: {response}")

        threading.Thread(target=send_cmd, daemon=True).start()

    def on_sheep_speed_changed(self, speed):
        """Update sheep max speed via Julia control channel (async)."""
        self.sheep_max_speed = speed
        print(f"Setting sheep max speed to {speed:.1f}...")

        # Send command in background thread to avoid blocking UI
        def send_cmd():
            response = self.send_control_command("set_sheep_speed", speed)
            if response and response.get("status") == "ok":
                print(f"✓ Sheep max speed updated to {response.get('sheep_speed'):.1f}")
            else:
                print(f"✗ Failed to update sheep speed: {response}")

        threading.Thread(target=send_cmd, daemon=True).start()

    def on_boids_params_changed(self, params):
        """Update BOIDS parameters via Julia control channel (async)."""
        print(f"Setting BOIDS params: {params}")

        def send_cmd():
            response = self.send_control_command("set_boids_params", params)
            if response and response.get("status") == "ok":
                print(f"✓ BOIDS parameters updated")
            else:
                print(f"✗ Failed to update BOIDS params: {response}")

        threading.Thread(target=send_cmd, daemon=True).start()

    def on_save_config(self):
        """Save current configuration to JSON file."""
        import json

        config = self.control_panel.get_all_params()
        config['timestamp'] = str(QDateTime.currentDateTime().toString())

        try:
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            print(f"✓ Configuration saved to {self.config_file}")
            self.control_panel.status_label.setText("Config saved!")
            QTimer.singleShot(2000, lambda: self.control_panel.status_label.setText("Status: Ready"))
        except Exception as e:
            print(f"✗ Failed to save config: {e}")
            self.control_panel.status_label.setText(f"Save failed: {e}")

    def on_load_config(self):
        """Load configuration from JSON file."""
        import json
        import os

        if not os.path.exists(self.config_file):
            print(f"✗ Config file not found: {self.config_file}")
            self.control_panel.status_label.setText("No config file found")
            QTimer.singleShot(2000, lambda: self.control_panel.status_label.setText("Status: Ready"))
            return

        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)

            self.control_panel.set_all_params(config)
            print(f"✓ Configuration loaded from {self.config_file}")
            self.control_panel.status_label.setText("Config loaded!")
            QTimer.singleShot(2000, lambda: self.control_panel.status_label.setText("Status: Ready"))
        except Exception as e:
            print(f"✗ Failed to load config: {e}")
            self.control_panel.status_label.setText(f"Load failed: {e}")

    def on_sim_mouse_press(self, event):
        """Handle mouse press on simulation widget to move goal."""
        if event.button() == Qt.LeftButton:
            # Convert widget coordinates to world coordinates
            pos = event.pos()
            world_x, world_y = self.sim_widget.widget_to_world_coords(pos.x(), pos.y())

            # Check if click is near current goal position (within 30 world units)
            if self.goal_position:
                dx = world_x - self.goal_position[0]
                dy = world_y - self.goal_position[1]
                dist = (dx*dx + dy*dy)**0.5

                if dist < 30:
                    # Start dragging goal
                    self.goal_drag_active = True
                    return

            # Direct click: move goal immediately
            self.update_goal_position(world_x, world_y)

    def on_sim_mouse_move(self, event):
        """Handle mouse move to drag goal position."""
        if self.goal_drag_active:
            pos = event.pos()
            world_x, world_y = self.sim_widget.widget_to_world_coords(pos.x(), pos.y())
            self.update_goal_position(world_x, world_y)

    def keyPressEvent(self, event):
        """Handle keyboard input to move goal position."""
        if not self.goal_position:
            return

        move_step = 10.0  # pixels per key press
        x, y = self.goal_position

        if event.key() == Qt.Key_Left:
            self.update_goal_position(x - move_step, y)
        elif event.key() == Qt.Key_Right:
            self.update_goal_position(x + move_step, y)
        elif event.key() == Qt.Key_Up:
            self.update_goal_position(x, y - move_step)
        elif event.key() == Qt.Key_Down:
            self.update_goal_position(x, y + move_step)
        else:
            super().keyPressEvent(event)

    def on_sim_mouse_release(self, event):
        """Handle mouse release to stop dragging."""
        if event.button() == Qt.LeftButton:
            self.goal_drag_active = False

    def update_goal_position(self, x, y):
        """Update goal position and send to Julia server."""
        # Clamp to world bounds
        x = max(0, min(self.world_size, x))
        y = max(0, min(self.world_size, y))

        # Update locally FIRST for immediate visual feedback
        self.goal_position = [x, y]
        self.sim_widget.goal_position = [x, y]  # Update SimulationWidget too
        self.goal_position_user_controlled = True  # User has taken control

        self.sim_widget.update()  # Redraw immediately

        # Send to Julia server asynchronously (don't block UI)
        def send_cmd():
            try:
                with self.control_socket_lock:
                    # Send command with fire-and-forget approach
                    cmd = {"command": "set_goal_position", "value": [x, y]}
                    self.control_socket.send_json(cmd)

                    # Try to receive response with very short timeout
                    self.control_socket.setsockopt(zmq.RCVTIMEO, 50)
                    try:
                        self.control_socket.recv_json()
                        # Success - goal synced
                    except zmq.error.Again:
                        # Timeout: Julia is busy, but command was sent
                        # Recreate socket for next command (REQ-REP needs clean state)
                        self._recreate_control_socket()
                    finally:
                        # Restore normal timeout
                        self.control_socket.setsockopt(zmq.RCVTIMEO, 1000)
            except Exception:
                # Try to recover socket on error
                try:
                    self._recreate_control_socket()
                except:
                    pass

        threading.Thread(target=send_cmd, daemon=True).start()

    def poll_zmq(self):
        try:
            # If paused, drain the socket buffer to prevent buildup
            if self.is_paused:
                # Drain all pending messages (don't display them)
                while True:
                    try:
                        self.socket.recv_string(flags=zmq.NOBLOCK)
                    except zmq.Again:
                        break  # No more messages
                return

            # Poll multiple messages if speed > 1.0 to catch up
            max_msgs = max(1, int(self.speed_multiplier))
            for _ in range(max_msgs):
                try:
                    msg = self.socket.recv_string(flags=zmq.NOBLOCK)
                    data = json.loads(msg)

                    # Update world size and goal position from first message
                    if hasattr(data, 'get'):
                        world_size_data = data.get("world_size")
                        if world_size_data and isinstance(world_size_data, list) and len(world_size_data) == 2:
                            self.world_size = world_size_data[0]

                        # Update goal position if provided (ONLY on initial connection)
                        goal_data = data.get("goal_position")
                        if goal_data and isinstance(goal_data, list) and len(goal_data) == 2:
                            # Only accept Julia's goal position if user hasn't taken control yet
                            if not self.goal_position_user_controlled and not self.goal_drag_active:
                                self.goal_position = goal_data
                                self.sim_widget.goal_position = goal_data

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

        self.control_socket.setsockopt(zmq.LINGER, 0)
        self.control_socket.close()

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
