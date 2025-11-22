"""
PyQt5 Viewer for Julia EPH Simulation (Sparse Foraging Task).
Integrates simulation visualization and real-time data plots into a single window.
"""
import sys
import zmq
import json
import numpy as np
from collections import deque

from PyQt5.QtWidgets import QApplication, QMainWindow, QWidget, QHBoxLayout, QVBoxLayout
from PyQt5.QtCore import QTimer, Qt, QRectF, QPointF
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
        
        # Agent 1 is red (tracked), others are blue
        is_tracked = (agent_id == 1)
        
        # Draw FOV (Field of View)
        fov_angle = np.radians(210)
        fov_radius = 100
        
        fov_start_angle = -np.degrees(orientation + fov_angle/2) * 16
        fov_span_angle = np.degrees(fov_angle) * 16
        
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(200, 200, 200, 50))
        painter.drawPie(QRectF(x - fov_radius, y - fov_radius, fov_radius*2, fov_radius*2), 
                        int(fov_start_angle), int(fov_span_angle))

        # Draw Body
        if is_tracked:
            # Tracked agent: Red
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(255, 80, 80))
        else:
            # All other agents: Blue (all are goal-less)
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


class DashboardWidget(QWidget):
    """Widget to display real-time plots using Matplotlib."""
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        
        # Create Matplotlib Figure
        self.figure = Figure(figsize=(8, 8), facecolor='#F0F0F0')
        self.canvas = FigureCanvas(self.figure)
        layout.addWidget(self.canvas)

        # Setup Subplots
        # Top row: EFE, Entropy, Surprise (3 plots)
        # Middle row: Gradient Norm, Self-Haze (2 plots, wide)
        # Bottom row: SPM Heatmaps (3 plots)
        gs = self.figure.add_gridspec(3, 3, height_ratios=[1, 1, 1.2])

        self.ax_efe = self.figure.add_subplot(gs[0, 0])
        self.ax_ent = self.figure.add_subplot(gs[0, 1])
        self.ax_surprise = self.figure.add_subplot(gs[0, 2])  # New: Surprise plot
        
        self.ax_grad = self.figure.add_subplot(gs[1, 0:2])  # Gradient Norm (wide)
        self.ax_haze = self.figure.add_subplot(gs[1, 2])     # Self-Haze (moved here)

        self.ax_spm_occ = self.figure.add_subplot(gs[2, 0])
        self.ax_spm_rad = self.figure.add_subplot(gs[2, 1])
        self.ax_spm_tan = self.figure.add_subplot(gs[2, 2])

        self.axes = [self.ax_efe, self.ax_ent, self.ax_surprise, self.ax_grad, self.ax_haze,
                     self.ax_spm_occ, self.ax_spm_rad, self.ax_spm_tan]

        # Initial Styling
        self.ax_efe.set_title('Expected Free Energy')
        self.ax_ent.set_title('Belief Entropy')
        self.ax_surprise.set_title('Surprise (F_percept)')
        self.ax_grad.set_title('Gradient Norm')
        self.ax_haze.set_title('Self-Haze')
        
        self.ax_spm_occ.set_title('SPM: Occupancy')
        self.ax_spm_rad.set_title('SPM: Radial Vel')
        self.ax_spm_tan.set_title('SPM: Tangential Vel')

        for ax in self.axes:
            ax.grid(True, linestyle='--', alpha=0.6)
            ax.set_facecolor('white')

        self.figure.tight_layout()

        # Data History
        self.max_history = 200
        self.history = {
            'frame': deque(maxlen=self.max_history),
            'efe': deque(maxlen=self.max_history),
            'entropy': deque(maxlen=self.max_history),
            'surprise': deque(maxlen=self.max_history),  # New: Surprise
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
        self.history['surprise'].append(tracked_data.get("surprise", 0))  # New: Surprise
        self.history['haze'].append(tracked_data.get("self_haze", 0))
        
        grad = tracked_data.get("gradient", [0, 0])
        grad_norm = np.linalg.norm(grad) if grad else 0
        self.history['grad_norm'].append(grad_norm)

        # Redraw Time Series
        x = list(self.history['frame'])
        
        self.ax_efe.clear()
        self.ax_efe.set_title('Expected Free Energy')
        self.ax_efe.plot(x, self.history['efe'], 'b-')
        self.ax_efe.grid(True)

        self.ax_ent.clear()
        self.ax_ent.set_title('Belief Entropy')
        self.ax_ent.plot(x, self.history['entropy'], 'r-')
        self.ax_ent.grid(True)

        self.ax_surprise.clear()
        self.ax_surprise.set_title('Surprise (F_percept)')
        self.ax_surprise.plot(x, self.history['surprise'], 'orange')
        self.ax_surprise.grid(True)
        
        self.ax_grad.clear()
        self.ax_grad.set_title('Gradient Norm')
        self.ax_grad.plot(x, self.history['grad_norm'], 'k-')
        self.ax_grad.grid(True)

        self.ax_haze.clear()
        self.ax_haze.set_title('Self-Haze')
        self.ax_haze.plot(x, self.history['haze'], 'g-')
        self.ax_haze.set_ylim(0, 1.0)
        self.ax_haze.grid(True)

        # Update Heatmaps
        spm_occ = np.array(tracked_data.get("spm_occupancy", []))
        spm_rad = np.array(tracked_data.get("spm_radial", []))
        spm_tan = np.array(tracked_data.get("spm_tangential", []))

        # Check if SPM data is valid
        if spm_occ.size > 0 and spm_occ.ndim == 2:
            self.ax_spm_occ.clear()
            self.ax_spm_occ.set_title('SPM: Occupancy')
            self.ax_spm_occ.imshow(spm_occ, cmap='hot', aspect='auto', interpolation='nearest')
            
        if spm_rad.size > 0 and spm_rad.ndim == 2:
            self.ax_spm_rad.clear()
            self.ax_spm_rad.set_title('SPM: Radial Vel')
            self.ax_spm_rad.imshow(spm_rad, cmap='RdBu', aspect='auto', interpolation='nearest', vmin=-50, vmax=50)
            
        if spm_tan.size > 0 and spm_tan.ndim == 2:
            self.ax_spm_tan.clear()
            self.ax_spm_tan.set_title('SPM: Tangential Vel')
            self.ax_spm_tan.imshow(spm_tan, cmap='RdBu', aspect='auto', interpolation='nearest', vmin=-50, vmax=50)

        self.canvas.draw()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Julia EPH Viewer - Active Inference Dashboard")
        self.resize(WINDOW_WIDTH, WINDOW_HEIGHT)
        
        # Main Layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        central_widget.setStyleSheet(f"background-color: {BG_COLOR.name()};")
        
        layout = QHBoxLayout(central_widget)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(10)

        # Add Widgets
        self.sim_widget = SimulationWidget()
        self.dashboard_widget = DashboardWidget()
        
        layout.addWidget(self.sim_widget, stretch=4)
        layout.addWidget(self.dashboard_widget, stretch=6)

        # ZeroMQ Setup
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect("tcp://localhost:5555")
        self.socket.setsockopt_string(zmq.SUBSCRIBE, '')
        
        # Timer for polling ZMQ
        self.timer = QTimer()
        self.timer.timeout.connect(self.poll_zmq)
        self.timer.start(16) # ~60 FPS

    def poll_zmq(self):
        try:
            while True:
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
        self.socket.close()
        self.context.term()
        event.accept()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())
