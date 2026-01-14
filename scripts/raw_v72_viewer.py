#!/usr/bin/env python3
"""
Raw V7.2 Trajectory Viewer for EPH (5D State Space with Heading)
Visualize HDF5 trajectory data with heading alignment dynamics

NEW in v7.2:
- 5D state space: (x, y, vx, vy, θ)
- Heading visualization (agent orientation arrow)
- Direction-based goals: d_goal unit vectors
- Omnidirectional force control: [Fx, Fy]
- Physical parameters: m=70kg, u_max=150N, k_align=4.0 rad/s

Features:
- Global map with all agent trajectories
- Heading arrows showing agent orientation
- Interactive agent selection (click on agent)
- Goal direction vectors
- Time slider for playback control
- Collision event highlighting
- v7.2 parameter display

Usage:
  python scripts/raw_v72_viewer.py data/vae_training/raw_v72/v72_scramble_d10_s1_*.h5
"""

import h5py
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.patches import Circle, FancyArrow, Wedge
from matplotlib.widgets import Slider, Button
import argparse
import os
import sys
from pathlib import Path
import tkinter as tk
from tkinter import filedialog


class RawV72Viewer:
    """Interactive viewer for raw v7.2 trajectory data (5D state space)"""

    def __init__(self, h5_file_path=None):
        """
        Initialize viewer

        Args:
            h5_file_path: Path to HDF5 trajectory file (optional, will show dialog if None)
        """
        # If no file specified, show file selection dialog
        if h5_file_path is None:
            h5_file_path = self.select_file()
            if h5_file_path is None:
                print("No file selected. Exiting.")
                sys.exit(0)

        self.h5_file_path = h5_file_path

        # Load data
        self.load_data()

        # Viewer state
        self.current_step = 0
        self.selected_agent_idx = 0  # Default to first agent
        self.playing = False

        # Setup GUI
        self.setup_figure()
        self.setup_widgets()

        # Initial render
        self.update_display()

    @staticmethod
    def select_file(initial_dir=None):
        """
        Show file selection dialog

        Args:
            initial_dir: Initial directory to open (optional)

        Returns:
            Selected file path or None if cancelled
        """
        # Create temporary root window (will be hidden)
        root = tk.Tk()
        root.withdraw()  # Hide the root window

        # Determine initial directory
        if initial_dir is None:
            # Try to use default data directory
            script_dir = Path(__file__).parent.parent
            default_dir = script_dir / "data" / "vae_training" / "raw_v72"
            if default_dir.exists():
                initial_dir = str(default_dir)
            else:
                initial_dir = str(script_dir)

        # Show file dialog
        file_path = filedialog.askopenfilename(
            title="Select V7.2 Raw Trajectory HDF5 File",
            initialdir=initial_dir,
            filetypes=[("HDF5 files", "*.h5"), ("All files", "*.*")]
        )

        root.destroy()

        return file_path if file_path else None

    def load_data(self):
        """Load trajectory data from HDF5 file"""
        print(f"Loading: {self.h5_file_path}")

        with h5py.File(self.h5_file_path, 'r') as f:
            # Trajectory data (v7.2: includes heading)
            # Julia saves as [dims, N, T], need to transpose to [T, N, dims]
            pos_raw = f['trajectory/pos'][:]  # Julia: [2, N, T]
            vel_raw = f['trajectory/vel'][:]  # Julia: [2, N, T]
            u_raw = f['trajectory/u'][:]      # Julia: [2, N, T]

            self.pos = np.transpose(pos_raw, (2, 1, 0))  # [T, N, 2]
            self.vel = np.transpose(vel_raw, (2, 1, 0))  # [T, N, 2]
            self.u = np.transpose(u_raw, (2, 1, 0))      # [T, N, 2]

            heading_raw = f['trajectory/heading'][:]     # Julia: [N, T]
            self.heading = np.transpose(heading_raw)     # [T, N]

            d_goal_raw = f['trajectory/d_goal'][:]       # Julia: [2, N]
            self.d_goal = np.transpose(d_goal_raw)       # [N, 2]

            self.group = f['trajectory/group'][:]        # [N]

            # Events - Julia: [N, T], need to transpose to [T, N]
            collision_raw = f['events/collision'][:]
            near_collision_raw = f['events/near_collision'][:]

            self.collision = np.transpose(collision_raw)           # [T, N]
            self.near_collision = np.transpose(near_collision_raw) # [T, N]

            # Metadata
            self.scenario = f['metadata/scenario'][()].decode('utf-8')
            self.version = f['metadata/version'][()].decode('utf-8')
            self.density = f['metadata/density'][()]
            self.seed = f['metadata/seed'][()]
            self.max_steps = f['metadata/max_steps'][()]
            self.dt = f['metadata/dt'][()]
            self.n_agents = f['metadata/n_agents'][()]
            self.collision_rate = f['metadata/collision_rate'][()]

            # v7.2 specific parameters
            if 'v72_params' in f:
                self.mass = f['v72_params/mass'][()]
                self.k_align = f['v72_params/k_align'][()]
                self.u_max = f['v72_params/u_max'][()]
            else:
                # Fallback for older files
                self.mass = 70.0
                self.k_align = 4.0
                self.u_max = 150.0

        # Data shapes
        self.T, self.N, _ = self.pos.shape

        print(f"  Scenario: {self.scenario} (v{self.version})")
        print(f"  Agents: {self.N}, Steps: {self.T}, dt: {self.dt}s")
        print(f"  Density: {self.density}, Seed: {self.seed}")
        print(f"  Physical model: m={self.mass}kg, u_max={self.u_max}N, k_align={self.k_align} rad/s")
        print(f"  Collision rate: {self.collision_rate:.3f}%")
        print(f"  State space: 5D (x, y, vx, vy, θ)")

    def setup_figure(self):
        """Setup matplotlib figure with subplots"""
        self.fig = plt.figure(figsize=(16, 9))
        self.fig.canvas.manager.set_window_title(f"V7.2 Raw Trajectory Viewer - {Path(self.h5_file_path).name}")

        # Create grid layout
        gs = GridSpec(3, 3, figure=self.fig, hspace=0.3, wspace=0.3,
                      left=0.05, right=0.95, top=0.95, bottom=0.12)

        # Main global map (larger, top-left)
        self.ax_global = self.fig.add_subplot(gs[0:2, 0:2])
        self.ax_global.set_title("Global View (All Agents)")
        self.ax_global.set_xlabel("X [m]")
        self.ax_global.set_ylabel("Y [m]")
        self.ax_global.set_aspect('equal')
        self.ax_global.grid(True, alpha=0.3)

        # Agent detail view (top-right)
        self.ax_detail = self.fig.add_subplot(gs[0, 2])
        self.ax_detail.set_title("Agent Detail")
        self.ax_detail.axis('off')

        # Heading plot (middle-right)
        self.ax_heading = self.fig.add_subplot(gs[1, 2])
        self.ax_heading.set_title("Heading vs Velocity Direction")
        self.ax_heading.set_xlabel("Time Step")
        self.ax_heading.set_ylabel("Angle [rad]")
        self.ax_heading.grid(True, alpha=0.3)

        # Statistics (bottom-left)
        self.ax_stats = self.fig.add_subplot(gs[2, 0])
        self.ax_stats.set_title("Statistics")
        self.ax_stats.axis('off')

        # Control forces (bottom-middle)
        self.ax_control = self.fig.add_subplot(gs[2, 1])
        self.ax_control.set_title("Control Forces (Selected Agent)")
        self.ax_control.set_xlabel("Time Step")
        self.ax_control.set_ylabel("Force [N]")
        self.ax_control.grid(True, alpha=0.3)

        # Collision events (bottom-right)
        self.ax_collision = self.fig.add_subplot(gs[2, 2])
        self.ax_collision.set_title("Collision Events")
        self.ax_collision.set_xlabel("Time Step")
        self.ax_collision.set_ylabel("Agent Index")
        self.ax_collision.grid(True, alpha=0.3)

    def setup_widgets(self):
        """Setup interactive widgets"""
        # Time slider
        ax_slider = plt.axes([0.15, 0.05, 0.65, 0.03])
        self.slider = Slider(
            ax_slider, 'Time Step',
            0, self.T - 1,
            valinit=0,
            valstep=1
        )
        self.slider.on_changed(self.on_slider_change)

        # Play/Pause button
        ax_play = plt.axes([0.82, 0.05, 0.08, 0.03])
        self.btn_play = Button(ax_play, 'Play')
        self.btn_play.on_clicked(self.toggle_play)

        # Mouse click handler for agent selection
        self.fig.canvas.mpl_connect('button_press_event', self.on_click)

    def on_slider_change(self, val):
        """Handle slider value change"""
        self.current_step = int(val)
        self.update_display()

    def toggle_play(self, event):
        """Toggle play/pause"""
        self.playing = not self.playing
        self.btn_play.label.set_text('Pause' if self.playing else 'Play')

        if self.playing:
            self.play_animation()

    def play_animation(self):
        """Play animation"""
        while self.playing and self.current_step < self.T - 1:
            self.current_step += 1
            self.slider.set_val(self.current_step)
            plt.pause(self.dt)  # Pause for dt seconds

    def on_click(self, event):
        """Handle mouse click for agent selection"""
        if event.inaxes == self.ax_global:
            # Get click coordinates
            x_click, y_click = event.xdata, event.ydata

            # Find nearest agent
            pos_current = self.pos[self.current_step, :, :]  # [N, 2]
            distances = np.sqrt((pos_current[:, 0] - x_click)**2 + (pos_current[:, 1] - y_click)**2)
            nearest_idx = np.argmin(distances)

            if distances[nearest_idx] < 2.0:  # Within 2m
                self.selected_agent_idx = nearest_idx
                print(f"Selected agent {nearest_idx} (Group {self.group[nearest_idx]})")
                self.update_display()

    def update_display(self):
        """Update all display elements"""
        t = self.current_step

        # Clear axes
        self.ax_global.clear()
        self.ax_detail.clear()
        self.ax_heading.clear()
        self.ax_stats.clear()
        self.ax_control.clear()
        self.ax_collision.clear()

        # === Global View ===
        self.ax_global.set_title(f"Global View (Step {t}/{self.T-1}, t={t*self.dt:.2f}s)")
        self.ax_global.set_xlabel("X [m]")
        self.ax_global.set_ylabel("Y [m]")
        self.ax_global.set_aspect('equal')
        self.ax_global.grid(True, alpha=0.3)

        # Group colors
        group_colors = {0: 'blue', 1: 'red', 2: 'green', 3: 'orange'}

        # Draw all agents
        for i in range(self.N):
            pos_i = self.pos[t, i, :]
            heading_i = self.heading[t, i]
            group_i = int(self.group[i])
            color = group_colors.get(group_i, 'gray')

            # Draw agent circle
            is_selected = (i == self.selected_agent_idx)
            circle = Circle(pos_i, 0.5,
                           facecolor=color, alpha=0.7 if is_selected else 0.3,
                           linewidth=2 if is_selected else 0.5,
                           edgecolor='black' if is_selected else color)
            self.ax_global.add_patch(circle)

            # Draw heading arrow (v7.2 NEW)
            arrow_length = 1.0
            dx = arrow_length * np.cos(heading_i)
            dy = arrow_length * np.sin(heading_i)
            arrow = FancyArrow(pos_i[0], pos_i[1], dx, dy,
                              width=0.2, head_width=0.4, head_length=0.3,
                              color='black', alpha=0.8 if is_selected else 0.4)
            self.ax_global.add_patch(arrow)

            # Highlight collision
            if self.collision[t, i]:
                circle_collision = Circle(pos_i, 0.7, fill=False, edgecolor='red',
                                         linewidth=3, linestyle='--')
                self.ax_global.add_patch(circle_collision)

        # Draw goal directions for selected agent
        selected_pos = self.pos[t, self.selected_agent_idx, :]
        selected_d_goal = self.d_goal[self.selected_agent_idx, :]
        goal_arrow_length = 3.0
        goal_arrow = FancyArrow(
            selected_pos[0], selected_pos[1],
            selected_d_goal[0] * goal_arrow_length,
            selected_d_goal[1] * goal_arrow_length,
            width=0.3, head_width=0.6, head_length=0.5,
            color='purple', alpha=0.5, linestyle='--'
        )
        self.ax_global.add_patch(goal_arrow)

        # Set limits
        x_min, x_max = self.pos[:, :, 0].min() - 5, self.pos[:, :, 0].max() + 5
        y_min, y_max = self.pos[:, :, 1].min() - 5, self.pos[:, :, 1].max() + 5
        self.ax_global.set_xlim(x_min, x_max)
        self.ax_global.set_ylim(y_min, y_max)

        # === Agent Detail ===
        self.ax_detail.set_title(f"Agent {self.selected_agent_idx} (Group {int(self.group[self.selected_agent_idx])})")
        self.ax_detail.axis('off')

        selected_vel = self.vel[t, self.selected_agent_idx, :]
        selected_heading = self.heading[t, self.selected_agent_idx]
        selected_u = self.u[t, self.selected_agent_idx, :]

        vel_mag = np.linalg.norm(selected_vel)
        vel_dir = np.arctan2(selected_vel[1], selected_vel[0])
        u_mag = np.linalg.norm(selected_u)

        detail_text = (
            f"Position: ({selected_pos[0]:.2f}, {selected_pos[1]:.2f}) m\n"
            f"Velocity: ({selected_vel[0]:.2f}, {selected_vel[1]:.2f}) m/s\n"
            f"  ├─ Magnitude: {vel_mag:.2f} m/s\n"
            f"  └─ Direction: {np.rad2deg(vel_dir):.1f}°\n"
            f"Heading θ: {np.rad2deg(selected_heading):.1f}°\n"
            f"Heading Error: {np.rad2deg(vel_dir - selected_heading):.1f}°\n"
            f"Control Force: ({selected_u[0]:.1f}, {selected_u[1]:.1f}) N\n"
            f"  └─ Magnitude: {u_mag:.1f} N\n"
            f"Goal Direction: ({selected_d_goal[0]:.2f}, {selected_d_goal[1]:.2f})\n"
            f"Progress: {np.dot(selected_vel, selected_d_goal):.2f} m/s"
        )
        self.ax_detail.text(0.05, 0.95, detail_text, transform=self.ax_detail.transAxes,
                           fontsize=9, verticalalignment='top', family='monospace')

        # === Heading Plot ===
        self.ax_heading.set_title("Heading vs Velocity Direction")
        self.ax_heading.set_xlabel("Time Step")
        self.ax_heading.set_ylabel("Angle [rad]")
        self.ax_heading.grid(True, alpha=0.3)

        # Plot heading and velocity direction over time
        vel_angles = np.arctan2(self.vel[:t+1, self.selected_agent_idx, 1],
                               self.vel[:t+1, self.selected_agent_idx, 0])
        heading_angles = self.heading[:t+1, self.selected_agent_idx]

        self.ax_heading.plot(range(t+1), heading_angles, 'b-', label='Heading θ', linewidth=1.5)
        self.ax_heading.plot(range(t+1), vel_angles, 'r--', label='Velocity Direction', linewidth=1.5, alpha=0.7)
        self.ax_heading.axvline(t, color='gray', linestyle=':', alpha=0.5)
        self.ax_heading.legend(fontsize=8)
        self.ax_heading.set_xlim(0, self.T)

        # === Statistics ===
        self.ax_stats.set_title("Statistics")
        self.ax_stats.axis('off')

        collision_count = np.sum(self.collision[:t+1, :])
        collision_rate_current = collision_count / ((t+1) * self.N) * 100 if t > 0 else 0.0

        stats_text = (
            f"Scenario: {self.scenario}\n"
            f"Version: {self.version}\n"
            f"Physical Model:\n"
            f"  ├─ Mass: {self.mass:.1f} kg\n"
            f"  ├─ u_max: {self.u_max:.1f} N\n"
            f"  └─ k_align: {self.k_align:.1f} rad/s\n"
            f"Agents: {self.N} (Density: {self.density})\n"
            f"Time: {t*self.dt:.2f}s / {(self.T-1)*self.dt:.2f}s\n"
            f"Collisions: {collision_count} ({collision_rate_current:.2f}%)\n"
            f"Overall Rate: {self.collision_rate:.3f}%"
        )
        self.ax_stats.text(0.05, 0.95, stats_text, transform=self.ax_stats.transAxes,
                          fontsize=9, verticalalignment='top', family='monospace')

        # === Control Forces ===
        self.ax_control.set_title(f"Control Forces (Agent {self.selected_agent_idx})")
        self.ax_control.set_xlabel("Time Step")
        self.ax_control.set_ylabel("Force [N]")
        self.ax_control.grid(True, alpha=0.3)

        u_x = self.u[:t+1, self.selected_agent_idx, 0]
        u_y = self.u[:t+1, self.selected_agent_idx, 1]
        u_mag_history = np.sqrt(u_x**2 + u_y**2)

        self.ax_control.plot(range(t+1), u_x, 'b-', label='Fx', linewidth=1, alpha=0.7)
        self.ax_control.plot(range(t+1), u_y, 'r-', label='Fy', linewidth=1, alpha=0.7)
        self.ax_control.plot(range(t+1), u_mag_history, 'k-', label='|F|', linewidth=1.5)
        self.ax_control.axhline(self.u_max, color='gray', linestyle='--', alpha=0.5, label=f'u_max={self.u_max}N')
        self.ax_control.axvline(t, color='gray', linestyle=':', alpha=0.5)
        self.ax_control.legend(fontsize=8)
        self.ax_control.set_xlim(0, self.T)
        self.ax_control.set_ylim(-self.u_max*1.1, self.u_max*1.1)

        # === Collision Events ===
        self.ax_collision.set_title("Collision Events")
        self.ax_collision.set_xlabel("Time Step")
        self.ax_collision.set_ylabel("Agent Index")
        self.ax_collision.grid(True, alpha=0.3)

        # Show collision events as scatter plot
        collision_times, collision_agents = np.where(self.collision[:t+1, :])
        if len(collision_times) > 0:
            self.ax_collision.scatter(collision_times, collision_agents, c='red', s=10, alpha=0.6)

        self.ax_collision.set_xlim(0, self.T)
        self.ax_collision.set_ylim(-0.5, self.N - 0.5)

        # Refresh canvas
        self.fig.canvas.draw_idle()

    def run(self):
        """Run the viewer"""
        plt.show()


def main():
    parser = argparse.ArgumentParser(description='V7.2 Raw Trajectory Viewer (5D State Space)')
    parser.add_argument('h5_file', nargs='?', default=None,
                       help='Path to HDF5 trajectory file (optional, will show dialog if omitted)')
    args = parser.parse_args()

    viewer = RawV72Viewer(args.h5_file)
    viewer.run()


if __name__ == '__main__':
    main()
