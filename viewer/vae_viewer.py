#!/usr/bin/env python3
"""
Interactive VAE SPM Viewer - EPH v7.2

Features:
- Global Map: All agents with velocity vectors
- FOV wedge display for selected agent
- Local View (Ego-centric)
- 3-channel SPM comparison (Actual vs Predicted vs Diff)
- Playback controls

Usage:
    ~/local/venv/bin/python viewer/interactive_vae_viewer.py
"""

import sys
import json
import subprocess
import numpy as np
import h5py
import matplotlib
matplotlib.use('Qt5Agg')
import matplotlib.pyplot as plt

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.patches import Wedge
from matplotlib.figure import Figure
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QPushButton, QSlider, QLabel, 
                             QComboBox, QFileDialog, QSpinBox, QSplitter,
                             QFrame)
from PyQt5.QtCore import Qt, QTimer
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent

# SPM Parameters
FOV_DEG = 210.0
FOV_RAD = np.deg2rad(FOV_DEG)
SENSING_RATIO = 3.0
R_AGENT = 0.5


class JuliaServer:
    def __init__(self):
        self.process = None
        self.ready = False
        
    def start(self):
        script_path = PROJECT_ROOT / "scripts" / "vae_server.jl"
        self.process = subprocess.Popen(
            ["julia", str(script_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(PROJECT_ROOT),
            text=True,
            bufsize=1
        )
        while True:
            line = self.process.stdout.readline().strip()
            if line == "READY":
                self.ready = True
                print("Julia server ready.")
                break
            elif not line:
                err = self.process.stderr.read()
                raise RuntimeError(f"Julia server failed: {err}")
    
    def stop(self):
        if self.process:
            try:
                self._send({"cmd": "EXIT"})
            except:
                pass
            self.process.terminate()
            self.process = None
    
    def _send(self, request):
        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()
    
    def _recv(self):
        return json.loads(self.process.stdout.readline())
    
    def reconstruct_spm(self, pos, vel, heading, obstacles, agent_idx):
        request = {
            "cmd": "reconstruct_spm",
            "pos": pos.tolist(),
            "vel": vel.tolist(),
            "heading": heading.tolist(),
            "obstacles": obstacles.tolist() if len(obstacles) > 0 else [],
            "agent_idx": int(agent_idx) + 1  # Convert to 1-based indexing for Julia
        }
        self._send(request)
        response = self._recv()
        if response["status"] == "ok":
            # Julia sends vec(spm) in column-major order, use order='F' to interpret correctly
            return np.array(response["spm"]).reshape(12, 12, 3, order='F')
        raise RuntimeError(response["message"])
    
    def predict(self, spm, action):
        request = {
            "cmd": "predict",
            # Flatten in Fortran order (column-major) to match Julia's reshape expectation
            "spm": spm.flatten(order='F').tolist(),
            "action": action.tolist()
        }
        self._send(request)
        response = self._recv()
        if response["status"] == "ok":
            # Julia sends vec(pred) in column-major order (shape [12,12,3,1])
            pred = np.array(response["prediction"]).reshape(12, 12, 3, 1, order='F')
            return pred[:, :, :, 0], response["haze"]
        raise RuntimeError(response["message"])


class DataLoader:
    def __init__(self, filepath):
        self.file = h5py.File(filepath, "r")
        self.pos = np.transpose(self.file["trajectory/pos"][:], (2, 1, 0))
        self.vel = np.transpose(self.file["trajectory/vel"][:], (2, 1, 0))
        self.heading = np.transpose(self.file["trajectory/heading"][:])
        self.u = np.transpose(self.file["trajectory/u"][:], (2, 1, 0))
        
        if "obstacles/data" in self.file:
            self.obstacles = self.file["obstacles/data"][:]
        else:
            self.obstacles = np.zeros((0, 4))
        
        self.T, self.N, _ = self.pos.shape
    
    def close(self):
        self.file.close()
    
    def get_state(self, t, agent_idx):
        return {
            "pos": self.pos[t, :, :],
            "vel": self.vel[t, :, :],
            "heading": self.heading[t, :],
            "action": self.u[t, agent_idx, :],
            "obstacles": self.obstacles
        }


class MapCanvas(FigureCanvas):
    """Canvas for Global and Local maps"""
    def __init__(self, parent=None):
        self.fig, (self.ax_global, self.ax_local) = plt.subplots(1, 2, figsize=(10, 5))
        super().__init__(self.fig)
        self.setParent(parent)


class SPMCanvas(FigureCanvas):
    """Canvas for 3-channel SPM comparison (3 rows x 3 cols)"""
    def __init__(self, parent=None):
        self.fig, self.axes = plt.subplots(3, 3, figsize=(12, 10))
        super().__init__(self.fig)
        self.setParent(parent)


class VAEViewer(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("VAE SPM Viewer - EPH v7.2")
        self.setGeometry(50, 50, 1800, 1000)
        
        self.server = None
        self.data = None
        self.current_t = 0
        self.current_agent = 0
        self.is_playing = False
        self.spm_update_interval = 5  # Update SPM every N frames
        self.last_spm_update = -1  # Last frame where SPM was updated
        self.cached_spm_actual = None
        self.cached_spm_pred = None
        self.cached_haze = 0.0
        
        self.timer = QTimer()
        self.timer.timeout.connect(self._on_timer_tick)
        self.playback_fps = 30
        
        self._setup_ui()
    
    def _setup_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        
        # Controls
        ctrl = QHBoxLayout()
        self.btn_open = QPushButton("Open File")
        self.btn_open.clicked.connect(self._ask_open_file)
        ctrl.addWidget(self.btn_open)
        self.lbl_file = QLabel("No file")
        ctrl.addWidget(self.lbl_file)
        ctrl.addStretch()
        ctrl.addWidget(QLabel("Agent:"))
        self.combo_agent = QComboBox()
        self.combo_agent.setEnabled(False)
        self.combo_agent.currentIndexChanged.connect(self._on_agent_change)
        ctrl.addWidget(self.combo_agent)
        layout.addLayout(ctrl)
        
        # Playback
        play = QHBoxLayout()
        self.btn_play = QPushButton("▶ Play")
        self.btn_play.setEnabled(False)
        self.btn_play.clicked.connect(self._toggle_play)
        play.addWidget(self.btn_play)
        play.addWidget(QLabel("FPS:"))
        self.spin_fps = QSpinBox()
        self.spin_fps.setRange(1, 300)
        self.spin_fps.setValue(60)
        self.spin_fps.valueChanged.connect(self._on_fps_change)
        play.addWidget(self.spin_fps)
        play.addWidget(QLabel("Step:"))
        self.slider_time = QSlider(Qt.Horizontal)
        self.slider_time.setEnabled(False)
        self.slider_time.valueChanged.connect(self._on_time_change)
        play.addWidget(self.slider_time)
        self.lbl_time = QLabel("0 / 0")
        play.addWidget(self.lbl_time)
        layout.addLayout(play)
        
        # Splitter for maps and SPM
        splitter = QSplitter(Qt.Horizontal)
        
        # Left: Maps
        map_frame = QFrame()
        map_layout = QVBoxLayout(map_frame)
        self.map_canvas = MapCanvas(self)
        map_layout.addWidget(self.map_canvas)
        splitter.addWidget(map_frame)
        
        # Right: SPM comparison
        spm_frame = QFrame()
        spm_layout = QVBoxLayout(spm_frame)
        self.spm_canvas = SPMCanvas(self)
        spm_layout.addWidget(self.spm_canvas)
        splitter.addWidget(spm_frame)
        
        splitter.setSizes([600, 1200])
        layout.addWidget(splitter)
        
        # Info
        info = QHBoxLayout()
        self.lbl_info = QLabel("")
        info.addWidget(self.lbl_info)
        info.addStretch()
        self.lbl_haze = QLabel("Haze: -")
        self.lbl_haze.setStyleSheet("color: blue; font-weight: bold; font-size: 14px;")
        info.addWidget(self.lbl_haze)
        layout.addLayout(info)
        
        self.statusBar().showMessage("Ready")
    
    def _ask_open_file(self):
        # Default directory for v7.2 training data
        default_dir = str(Path(__file__).parent.parent / "data" / "vae_training" / "raw_v72")
        
        filepath, _ = QFileDialog.getOpenFileName(
            self, "Select HDF5 File", default_dir, "HDF5 files (*.h5)"
        )
        if filepath:
            self._load_file(filepath)
    
    def _load_file(self, filepath):
        self.statusBar().showMessage("Loading...")
        QApplication.processEvents()
        try:
            if self.server is None:
                self.server = JuliaServer()
                self.server.start()
            if self.data:
                self.data.close()
            self.data = DataLoader(filepath)
            self.lbl_file.setText(Path(filepath).name)
            self.combo_agent.clear()
            self.combo_agent.addItems([str(i+1) for i in range(self.data.N)])
            self.combo_agent.setEnabled(True)
            self.slider_time.setMaximum(max(0, self.data.T - 6))
            self.slider_time.setValue(0)
            self.slider_time.setEnabled(True)
            self.btn_play.setEnabled(True)
            self.current_t = 0
            self.current_agent = 0
            self.statusBar().showMessage(f"Loaded: T={self.data.T}, N={self.data.N}")
            self._update_visualization()
        except Exception as e:
            self.statusBar().showMessage(f"Error: {e}")
            import traceback
            traceback.print_exc()
    
    def _toggle_play(self):
        if self.is_playing:
            self.timer.stop()
            self.is_playing = False
            self.btn_play.setText("▶ Play")
        else:
            self.timer.start(1000 // self.playback_fps)
            self.is_playing = True
            self.btn_play.setText("⏸ Pause")
    
    def _on_timer_tick(self):
        if self.data is None:
            return
        new_t = self.current_t + 1
        if new_t > self.slider_time.maximum():
            new_t = 0
        self.slider_time.setValue(new_t)
    
    def _on_fps_change(self, value):
        self.playback_fps = value
        if self.is_playing:
            self.timer.setInterval(1000 // self.playback_fps)
    
    def _on_time_change(self, value):
        if self.data is None:
            return
        self.current_t = value
        self.lbl_time.setText(f"{self.current_t} / {self.data.T - 1}")
        self._update_visualization()
    
    def _on_agent_change(self, index):
        if self.data is None or index < 0:
            return
        self.current_agent = index
        self.last_spm_update = -1  # Force SPM update on agent change
        self._update_visualization()
    
    def _draw_global_map(self, ax, t, selected):
        ax.clear()
        ax.set_title("Global Map")
        ax.set_xlabel("X [m]")
        ax.set_ylabel("Y [m]")
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.3)
        
        # Draw obstacles first (so agents render on top)
        if self.data.obstacles.shape[0] > 0:
            for i in range(self.data.obstacles.shape[0]):
                xmin, xmax, ymin, ymax = self.data.obstacles[i]
                width = xmax - xmin
                height = ymax - ymin
                rect = plt.Rectangle((xmin, ymin), width, height,
                                    facecolor='gray', edgecolor='black',
                                    alpha=0.5, zorder=0)
                ax.add_patch(rect)
        
        pos = self.data.pos[t]
        vel = self.data.vel[t]
        heading = self.data.heading[t]
        
        for i in range(self.data.N):
            x, y = pos[i]
            vx, vy = vel[i]
            h = heading[i]
            
            if i == selected:
                color = 'red'
                size = 150
                fov_r = SENSING_RATIO * R_AGENT * 2
                h_deg = np.rad2deg(h)
                wedge = Wedge((x, y), fov_r, h_deg - FOV_DEG/2, h_deg + FOV_DEG/2,
                             alpha=0.2, color='red', zorder=1)
                ax.add_patch(wedge)
            else:
                color = 'blue'
                size = 50
            
            ax.scatter(x, y, c=color, s=size, zorder=3)
            speed = np.sqrt(vx**2 + vy**2)
            if speed > 0.01:
                ax.arrow(x, y, vx*0.5, vy*0.5, head_width=0.3, head_length=0.15,
                        fc=color, ec=color, alpha=0.7, zorder=2)
        
        margin = 5
        ax.set_xlim(pos[:,0].min()-margin, pos[:,0].max()+margin)
        ax.set_ylim(pos[:,1].min()-margin, pos[:,1].max()+margin)
    
    def _draw_local_view(self, ax, t, agent_idx):
        ax.clear()
        ax.set_title("Local View (Ego)")
        ax.set_xlabel("X' [m]")
        ax.set_ylabel("Y' [m] (Fwd)")
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.3)
        
        ego_pos = self.data.pos[t, agent_idx]
        ego_h = self.data.heading[t, agent_idx]
        
        c, s = np.cos(-ego_h + np.pi/2), np.sin(-ego_h + np.pi/2)
        R = np.array([[c, -s], [s, c]])
        
        ax.scatter(0, 0, c='red', s=200, zorder=5)
        ax.arrow(0, 0, 0, 1.0, head_width=0.2, head_length=0.1, fc='red', ec='red', zorder=4)
        
        fov_r = SENSING_RATIO * R_AGENT * 2
        wedge = Wedge((0, 0), fov_r, 90-FOV_DEG/2, 90+FOV_DEG/2, alpha=0.15, color='red', zorder=1)
        ax.add_patch(wedge)
        
        for i in range(self.data.N):
            if i == agent_idx:
                continue
            rel = self.data.pos[t, i] - ego_pos
            if np.linalg.norm(rel) > fov_r * 1.5:
                continue
            rel_ego = R @ rel
            vel_ego = R @ self.data.vel[t, i]
            angle = np.arctan2(rel_ego[0], rel_ego[1])
            in_fov = abs(angle) <= FOV_RAD / 2
            color = 'blue' if in_fov else 'gray'
            alpha = 1.0 if in_fov else 0.3
            ax.scatter(rel_ego[0], rel_ego[1], c=color, s=80, alpha=alpha, zorder=3)
            if np.linalg.norm(vel_ego) > 0.01:
                ax.arrow(rel_ego[0], rel_ego[1], vel_ego[0]*0.3, vel_ego[1]*0.3,
                        head_width=0.15, head_length=0.08, fc=color, ec=color, alpha=alpha*0.7, zorder=2)
        
        ax.set_xlim(-fov_r*1.1, fov_r*1.1)
        ax.set_ylim(-fov_r*0.3, fov_r*1.1)
    
    def _update_visualization(self):
        if self.data is None:
            return
        
        try:
            t = self.current_t
            agent_idx = self.current_agent
            agent_julia = agent_idx + 1
            state = self.data.get_state(t, agent_idx)
            
            # Maps - always update
            self._draw_global_map(self.map_canvas.ax_global, t, agent_idx)
            self._draw_local_view(self.map_canvas.ax_local, t, agent_idx)
            self.map_canvas.fig.tight_layout()
            self.map_canvas.draw()
            
            # SPM - update only every N frames or on agent change
            should_update_spm = (
                self.last_spm_update < 0 or
                abs(t - self.last_spm_update) >= self.spm_update_interval or
                self.cached_spm_actual is None
            )
            
            try:
                if should_update_spm:
                    spm_current = self.server.reconstruct_spm(
                        state["pos"], state["vel"], state["heading"],
                        state["obstacles"], agent_julia
                    )
                    
                    next_t = min(t + 5, self.data.T - 1)
                    state_next = self.data.get_state(next_t, agent_idx)
                    spm_actual = self.server.reconstruct_spm(
                        state_next["pos"], state_next["vel"], state_next["heading"],
                        state_next["obstacles"], agent_julia
                    )
                    
                    spm_pred, haze = self.server.predict(spm_current, state["action"])
                    
                    # Cache results
                    self.cached_spm_actual = spm_actual
                    self.cached_spm_pred = spm_pred
                    self.cached_haze = haze
                    self.last_spm_update = t
                else:
                    # Use cached values
                    spm_actual = self.cached_spm_actual
                    spm_pred = self.cached_spm_pred
                    haze = self.cached_haze
                
                spm_diff = np.abs(spm_actual - spm_pred)
                
                ch_names = ["Occupancy", "Proximity", "Risk"]
                col_names = ["Actual (t+5)", "Predicted", "Difference"]
                
                for ch in range(3):
                    vmax = max(np.max(spm_actual[:,:,ch]), np.max(spm_pred[:,:,ch]), 0.1)
                    
                    # Actual
                    self.spm_canvas.axes[ch, 0].clear()
                    self.spm_canvas.axes[ch, 0].imshow(spm_actual[:,:,ch], vmin=0, vmax=vmax,
                                                       cmap='viridis', origin='lower', aspect='auto')
                    self.spm_canvas.axes[ch, 0].set_ylabel(ch_names[ch])
                    if ch == 0:
                        self.spm_canvas.axes[ch, 0].set_title(col_names[0])
                    
                    # Predicted
                    self.spm_canvas.axes[ch, 1].clear()
                    self.spm_canvas.axes[ch, 1].imshow(spm_pred[:,:,ch], vmin=0, vmax=vmax,
                                                       cmap='viridis', origin='lower', aspect='auto')
                    if ch == 0:
                        self.spm_canvas.axes[ch, 1].set_title(col_names[1])
                    
                    # Diff
                    self.spm_canvas.axes[ch, 2].clear()
                    self.spm_canvas.axes[ch, 2].imshow(spm_diff[:,:,ch], vmin=0, vmax=vmax*0.5,
                                                       cmap='Reds', origin='lower', aspect='auto')
                    if ch == 0:
                        self.spm_canvas.axes[ch, 2].set_title(col_names[2])
                
                self.spm_canvas.fig.tight_layout()
                self.spm_canvas.draw()
                
                mse = np.mean(spm_diff**2)
                speed = np.linalg.norm(self.data.vel[t, agent_idx])
                pos = self.data.pos[t, agent_idx]
                action = state["action"]
                
                self.lbl_info.setText(
                    f"t={t} | Agent={agent_julia} | Pos=({pos[0]:.1f},{pos[1]:.1f}) | "
                    f"Speed={speed:.2f}m/s | Action=[{action[0]:.1f},{action[1]:.1f}] | MSE={mse:.4f}"
                )
                self.lbl_haze.setText(f"Haze: {haze:.4f}")
                
            except Exception as e:
                self.lbl_haze.setText(f"Error: {e}")
                
        except Exception as e:
            self.statusBar().showMessage(f"Error: {e}")
            import traceback
            traceback.print_exc()
    
    def closeEvent(self, event):
        if self.timer.isActive():
            self.timer.stop()
        if self.server:
            self.server.stop()
        if self.data:
            self.data.close()
        plt.close('all')
        event.accept()


def main():
    app = QApplication(sys.argv)
    viewer = VAEViewer()
    viewer.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
