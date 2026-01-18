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
- V6.3-style interface with SPM visualization

Features:
- Global map with all agent trajectories
- Local View showing selected agent's sensing range
- SPM 3-channel visualization (Real)
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

# Import SPM reconstructor (v6.3-compatible)
parent_dir = Path(__file__).parent.parent
if str(parent_dir) not in sys.path:
    sys.path.insert(0, str(parent_dir))

from viewer.spm_reconstructor import SPMConfig, reconstruct_spm_3ch, relative_position_torus


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
        self.window_open = True  # Track window state
        self.animation_timer = None  # Timer for animation
        self.spm_update_counter = 0  # Counter for SPM update throttling

        # Setup GUI
        self.setup_figure()
        self.setup_widgets()

        # Connect close event handler
        self.fig.canvas.mpl_connect('close_event', self.on_close)

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

            # World parameters
            if 'world' in f:
                self.world_size = (float(f['world/width'][()]), float(f['world/height'][()]))
            else:
                # Default world size
                self.world_size = (100.0, 100.0)

            # Obstacles (if any)
            if 'obstacles/positions' in f:
                obstacles_raw = f['obstacles/positions'][:]  # Julia: [2, M]
                self.obstacles = np.transpose(obstacles_raw)  # [M, 2]
            else:
                self.obstacles = np.zeros((0, 2))

            # SPM parameters
            if 'spm_params' in f:
                self.spm_params = {
                    'n_rho': int(f['spm_params/n_rho'][()]),
                    'n_theta': int(f['spm_params/n_theta'][()]),
                    'sensing_ratio': float(f['spm_params/sensing_ratio'][()]),
                    # v7.2: r_robot and r_agent are the same (all agents are 0.5m radius)
                    'r_agent': float(f['spm_params/r_robot'][()])
                }
            else:
                # Default SPM parameters (v7.2: 12×12 bins)
                self.spm_params = {
                    'n_rho': 12,
                    'n_theta': 12,
                    'sensing_ratio': 3.0,
                    'r_agent': 0.5
                }

        # Data shapes
        self.T, self.N, _ = self.pos.shape

        # Initialize SPM config (v7.2: 12×12 bins, sensing_ratio=3.0)
        r_robot = self.spm_params['r_agent']  # v7.2: agents are all the same
        r_agent = self.spm_params['r_agent']

        self.spm_config = SPMConfig(
            n_rho=self.spm_params['n_rho'],
            n_theta=self.spm_params['n_theta'],
            sensing_ratio=self.spm_params['sensing_ratio'],
            r_robot=r_robot,
            r_agent=r_agent,
            h_critical=0.0,
            h_peripheral=0.0,
            rho_index_critical=6
        )

        self.max_sensing_distance = self.spm_config.d_max

        print(f"  Scenario: {self.scenario} (v{self.version})")
        print(f"  Agents: {self.N}, Steps: {self.T}, dt: {self.dt}s")
        print(f"  Density: {self.density}, Seed: {self.seed}")
        print(f"  Physical model: m={self.mass}kg, u_max={self.u_max}N, k_align={self.k_align} rad/s")
        print(f"  Collision rate: {self.collision_rate:.3f}%")
        print(f"  State space: 5D (x, y, vx, vy, θ)")
        print(f"  SPM: {self.spm_config.n_rho}×{self.spm_config.n_theta} bins, sensing={self.max_sensing_distance:.1f}m")
        print(f"  Obstacles: {len(self.obstacles)}")

    def setup_figure(self):
        """Setup matplotlib figure with subplots (v6.3-style 4×4 layout)"""
        self.fig = plt.figure(figsize=(16, 10))
        self.fig.canvas.manager.set_window_title(f"V7.2 Raw Trajectory Viewer - {Path(self.h5_file_path).name}")

        # Create 4×4 grid layout (v6.3-compatible)
        gs = GridSpec(4, 4, figure=self.fig, hspace=0.35, wspace=0.35,
                      left=0.05, right=0.95, top=0.92, bottom=0.06)

        # Row 0-1: Large plots (2×2 each)
        self.ax_global = self.fig.add_subplot(gs[0:2, 0:2])
        self.ax_global.set_title("Global View (All Agents)")
        self.ax_global.set_xlabel("X [m]")
        self.ax_global.set_ylabel("Y [m]")
        self.ax_global.set_aspect('equal')
        self.ax_global.grid(True, alpha=0.3)

        self.ax_local = self.fig.add_subplot(gs[0:2, 2:4])
        self.ax_local.set_title("Local View (Selected Agent)")
        self.ax_local.set_xlabel("X [m]")
        self.ax_local.set_ylabel("Y [m]")
        self.ax_local.set_aspect('equal')
        self.ax_local.grid(True, alpha=0.3)

        # Row 2: SPM Real channels (4 columns)
        self.ax_spm1_real = self.fig.add_subplot(gs[2, 0])
        self.ax_spm1_real.set_title("SPM Ch1: Occupancy")
        self.ax_spm1_real.set_xticks([])
        self.ax_spm1_real.set_yticks([])

        self.ax_spm2_real = self.fig.add_subplot(gs[2, 1])
        self.ax_spm2_real.set_title("SPM Ch2: Proximity")
        self.ax_spm2_real.set_xticks([])
        self.ax_spm2_real.set_yticks([])

        self.ax_spm3_real = self.fig.add_subplot(gs[2, 2])
        self.ax_spm3_real.set_title("SPM Ch3: Collision Risk")
        self.ax_spm3_real.set_xticks([])
        self.ax_spm3_real.set_yticks([])

        self.ax_spm_info = self.fig.add_subplot(gs[2, 3])
        self.ax_spm_info.set_title("SPM Info")
        self.ax_spm_info.axis('off')

        # Row 3: Controls and additional info (4 columns)
        self.ax_heading = self.fig.add_subplot(gs[3, 0])
        self.ax_heading.set_title("Heading Alignment")
        self.ax_heading.set_xlabel("Time [s]")
        self.ax_heading.set_ylabel("Angle [rad]")
        self.ax_heading.grid(True, alpha=0.3)

        self.ax_control = self.fig.add_subplot(gs[3, 1])
        self.ax_control.set_title("Control Forces")
        self.ax_control.set_xlabel("Time [s]")
        self.ax_control.set_ylabel("Force [N]")
        self.ax_control.grid(True, alpha=0.3)

        self.ax_collision = self.fig.add_subplot(gs[3, 2])
        self.ax_collision.set_title("Collision Events")
        self.ax_collision.set_xlabel("Time Step")
        self.ax_collision.set_ylabel("Agent Index")
        self.ax_collision.grid(True, alpha=0.3)

        self.ax_controls = self.fig.add_subplot(gs[3, 3])
        self.ax_controls.set_title("Statistics")
        self.ax_controls.axis('off')

        # Initialize SPM image containers
        self.spm_real_axes = [
            (self.ax_spm1_real, "Ch1: Occupancy"),
            (self.ax_spm2_real, "Ch2: Proximity"),
            (self.ax_spm3_real, "Ch3: Collision Risk")
        ]
        self.spm_real_images = [None, None, None]

    def setup_widgets(self):
        """Setup interactive widgets (v6.3-style)"""
        # Time slider - raised to y=0.04 to avoid overlap
        ax_slider = plt.axes([0.15, 0.04, 0.60, 0.03])
        self.time_slider = Slider(
            ax_slider, 'Time Step',
            0, self.T - 1,
            valinit=0,
            valstep=1
        )
        self.time_slider.on_changed(self.on_slider_change)

        # Open File button (v6.3) - raised to y=0.04
        ax_open = plt.axes([0.05, 0.04, 0.08, 0.03])
        self.open_button = Button(ax_open, 'Open File')
        self.open_button.on_clicked(self.on_open_button)

        # Play button - raised to y=0.04
        ax_play = plt.axes([0.77, 0.04, 0.05, 0.03])
        self.play_button = Button(ax_play, 'Play')
        self.play_button.on_clicked(self.on_play_button)

        # Reset button (v6.3) - raised to y=0.04
        ax_reset = plt.axes([0.83, 0.04, 0.05, 0.03])
        self.reset_button = Button(ax_reset, 'Reset')
        self.reset_button.on_clicked(self.on_reset_button)

        # Mouse click handler for agent selection
        self.fig.canvas.mpl_connect('button_press_event', self.on_click)

    def on_slider_change(self, val):
        """Handle slider value change"""
        self.current_step = int(val)
        self.update_display()

    def on_open_button(self, event):
        """Handle open file button click (v6.3)"""
        # Stop playback
        self.playing = False
        self.play_button.label.set_text('Play')

        # Get current directory from current file
        current_dir = str(Path(self.h5_file_path).parent)

        # Show file dialog
        new_file_path = self.select_file(initial_dir=current_dir)

        if new_file_path and new_file_path != self.h5_file_path:
            # Load new file
            self.h5_file_path = new_file_path
            self.load_data()

            # Reset visualization state
            self.reset_visualization_state()

            # Update time slider range
            self.time_slider.valmax = self.T - 1
            self.time_slider.ax.set_xlim(0, self.T - 1)

            # Reset to first frame
            self.current_step = 0
            self.time_slider.set_val(0)

            # Update window title
            self.fig.canvas.manager.set_window_title(f"V7.2 Raw Trajectory Viewer - {Path(self.h5_file_path).name}")

            # Update display
            self.update_display()

    def on_play_button(self, event):
        """Handle play button click"""
        self.playing = not self.playing
        self.play_button.label.set_text('Pause' if self.playing else 'Play')

        if self.playing:
            self.start_animation()
        else:
            self.stop_animation()

    def on_reset_button(self, event):
        """Handle reset button click (v6.3)"""
        self.playing = False
        self.stop_animation()
        self.current_step = 0
        self.time_slider.set_val(0)
        self.play_button.label.set_text('Play')
        self.update_display()

    def reset_visualization_state(self):
        """Reset visualization state when loading new file"""
        # Reset SPM image handles (will be recreated on next update)
        self.spm_real_images = [None, None, None]

        # Clear all axes
        for ax, _ in self.spm_real_axes:
            ax.clear()

        self.ax_global.clear()
        self.ax_local.clear()
        self.ax_heading.clear()
        self.ax_control.clear()
        self.ax_collision.clear()
        self.ax_spm_info.clear()
        self.ax_controls.clear()

    def start_animation(self):
        """Start timer-based animation"""
        if self.animation_timer is None:
            # Fast playback: 10x speed (dt * 100ms instead of dt * 1000ms)
            interval_ms = max(10, int(self.dt * 100))  # Minimum 10ms to avoid too fast updates
            self.animation_timer = self.fig.canvas.new_timer(interval=interval_ms)
            self.animation_timer.add_callback(self.animation_step)

        try:
            self.animation_timer.start()
        except RuntimeError:
            # Timer already running, ignore
            pass

    def stop_animation(self):
        """Stop timer-based animation"""
        if self.animation_timer is not None:
            try:
                self.animation_timer.stop()
            except (RuntimeError, AttributeError):
                # Timer not running or already stopped, ignore
                pass

    def animation_step(self):
        """Single step of animation (called by timer)"""
        if not self.playing or not self.window_open:
            self.stop_animation()
            return

        # Update SPM counter for throttling
        self.spm_update_counter += 1

        if self.current_step < self.T - 1:
            self.current_step += 1
            self.time_slider.set_val(self.current_step)
        else:
            # Reached end
            self.playing = False
            self.play_button.label.set_text('Play')
            self.stop_animation()

    def on_close(self, event):
        """Handle window close event"""
        print("Closing viewer...")
        self.window_open = False
        self.playing = False
        # Stop animation timer
        self.stop_animation()
        # Don't call plt.close() here - let matplotlib handle it

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
        """Update all display elements (v6.3-style with SPM)"""
        t = self.current_step

        # During playback, skip SPM updates for performance and GIL safety
        # Update SPM every 5 frames during playback
        skip_spm = self.playing and (self.spm_update_counter % 5 != 0)

        # Clear axes
        self.ax_global.clear()
        self.ax_local.clear()
        self.ax_heading.clear()
        self.ax_control.clear()
        self.ax_collision.clear()
        self.ax_spm_info.clear()
        self.ax_controls.clear()

        # Clear SPM channel axes only if updating (avoid GIL issues during playback)
        if not skip_spm:
            for ax, _ in self.spm_real_axes:
                ax.clear()
            # Reset SPM images after clearing axes (they are now invalid)
            self.spm_real_images = [None, None, None]

        # === Global View ===
        self.ax_global.set_title(f"Global View (Step {t}/{self.T-1}, t={t*self.dt:.2f}s)")
        self.ax_global.set_xlabel("X [m]")
        self.ax_global.set_ylabel("Y [m]")
        self.ax_global.set_aspect('equal')
        self.ax_global.grid(True, alpha=0.3)

        # Group colors
        group_colors = {0: 'blue', 1: 'red', 2: 'green', 3: 'orange'}

        # Draw trajectory trails (last 30 frames, fading, v6.3 style: subtle)
        trail_length = min(30, t)
        if trail_length > 0:
            for i in range(self.N):
                group_i = int(self.group[i])
                color = group_colors.get(group_i, 'gray')

                # Get trail positions
                trail_pos = self.pos[max(0, t-trail_length):t, i, :]

                # Draw trail with fading alpha (v6.3: subtle)
                for j in range(len(trail_pos)-1):
                    alpha = 0.05 * (j+1) / trail_length  # Fade from 0.05 to 0.05
                    self.ax_global.plot(trail_pos[j:j+2, 0], trail_pos[j:j+2, 1],
                                       color=color, alpha=alpha, linewidth=0.8, zorder=1)

        # Draw all agents
        for i in range(self.N):
            pos_i = self.pos[t, i, :]
            heading_i = self.heading[t, i]
            group_i = int(self.group[i])
            color = group_colors.get(group_i, 'gray')

            # Draw agent circle (v6.3 style: radius 0.5m)
            is_selected = (i == self.selected_agent_idx)
            radius = 0.5  # v6.3: 0.5m radius
            circle = Circle(pos_i, radius,
                           facecolor=color, alpha=0.8 if is_selected else 0.5,
                           linewidth=3 if is_selected else 1.5,
                           edgecolor='black' if is_selected else color,
                           zorder=10 if is_selected else 5)
            self.ax_global.add_patch(circle)

            # Draw heading arrow (v6.3 style: 1.0m length)
            arrow_length = 1.0  # v6.3: 1.0m arrow
            dx = arrow_length * np.cos(heading_i)
            dy = arrow_length * np.sin(heading_i)
            arrow = FancyArrow(pos_i[0], pos_i[1], dx, dy,
                              width=0.2, head_width=0.4, head_length=0.3,
                              color='white', alpha=1.0 if is_selected else 0.7,
                              edgecolor='black', linewidth=1.5 if is_selected else 1,
                              zorder=11 if is_selected else 6)
            self.ax_global.add_patch(arrow)

            # Highlight collision
            if self.collision[t, i]:
                circle_collision = Circle(pos_i, radius+0.2, fill=False, edgecolor='red',
                                         linewidth=3, linestyle='--', zorder=12)
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

        # === Local View (v6.3-style) ===
        self.ax_local.set_title(f"Local View (Agent {self.selected_agent_idx}, Group {int(self.group[self.selected_agent_idx])})")
        self.ax_local.set_xlabel("X [m]")
        self.ax_local.set_ylabel("Y [m]")
        self.ax_local.set_aspect('equal')
        self.ax_local.grid(True, alpha=0.3)

        # Get selected agent data
        selected_vel = self.vel[t, self.selected_agent_idx, :]
        selected_heading = self.heading[t, self.selected_agent_idx]
        selected_u = self.u[t, self.selected_agent_idx, :]

        # Center view on selected agent
        view_range = self.max_sensing_distance * 1.2
        self.ax_local.set_xlim(selected_pos[0] - view_range, selected_pos[0] + view_range)
        self.ax_local.set_ylim(selected_pos[1] - view_range, selected_pos[1] + view_range)

        # Draw sensing range circle
        sensing_circle = Circle(selected_pos, self.max_sensing_distance,
                               fill=False, edgecolor='cyan', linewidth=2, linestyle='--', alpha=0.5)
        self.ax_local.add_patch(sensing_circle)

        # Draw FOV wedge (210° = 3.665 rad)
        fov_deg = 210.0
        fov_half = fov_deg / 2.0
        heading_deg = np.rad2deg(selected_heading)
        fov_start = heading_deg - fov_half
        fov_wedge = Wedge(selected_pos, self.max_sensing_distance,
                         fov_start, fov_start + fov_deg,
                         facecolor='yellow', alpha=0.1, edgecolor='orange', linewidth=1.5)
        self.ax_local.add_patch(fov_wedge)

        # Draw all agents in sensing range
        for i in range(self.N):
            pos_i = self.pos[t, i, :]
            heading_i = self.heading[t, i]
            group_i = int(self.group[i])
            color = group_colors.get(group_i, 'gray')

            # Calculate distance (considering toroidal boundary)
            rel_pos = relative_position_torus(selected_pos, pos_i, self.world_size)
            dist = np.linalg.norm(rel_pos)

            if dist < self.max_sensing_distance or i == self.selected_agent_idx:
                is_selected = (i == self.selected_agent_idx)
                circle = Circle(pos_i, 0.5,
                               facecolor=color, alpha=0.8 if is_selected else 0.4,
                               linewidth=2 if is_selected else 1,
                               edgecolor='black' if is_selected else color)
                self.ax_local.add_patch(circle)

                # Draw heading arrow
                arrow_length = 1.0
                dx = arrow_length * np.cos(heading_i)
                dy = arrow_length * np.sin(heading_i)
                arrow = FancyArrow(pos_i[0], pos_i[1], dx, dy,
                                  width=0.2, head_width=0.4, head_length=0.3,
                                  color='black', alpha=0.8 if is_selected else 0.5)
                self.ax_local.add_patch(arrow)

        # Draw obstacles in sensing range
        if len(self.obstacles) > 0:
            for obs_pos in self.obstacles:
                rel_pos_obs = relative_position_torus(selected_pos, obs_pos, self.world_size)
                dist_obs = np.linalg.norm(rel_pos_obs)
                if dist_obs < self.max_sensing_distance:
                    obs_circle = Circle(obs_pos, 0.5, facecolor='black', alpha=0.6)
                    self.ax_local.add_patch(obs_circle)

        # Draw goal direction arrow
        goal_arrow_length = 3.0
        goal_arrow = FancyArrow(
            selected_pos[0], selected_pos[1],
            selected_d_goal[0] * goal_arrow_length,
            selected_d_goal[1] * goal_arrow_length,
            width=0.3, head_width=0.6, head_length=0.5,
            color='purple', alpha=0.6, linestyle='--'
        )
        self.ax_local.add_patch(goal_arrow)

        # === SPM Reconstruction (v6.3-style) ===
        # Skip SPM during playback for performance and GIL safety
        if not skip_spm:
            # Reconstruct SPM for selected agent
            all_positions_t = self.pos[t, :, :]  # [N, 2]
            all_velocities_t = self.vel[t, :, :]  # [N, 2]
            ego_velocity = selected_vel

            spm = reconstruct_spm_3ch(
                selected_pos,
                selected_heading,
                all_positions_t,
                all_velocities_t,
                self.obstacles,
                self.spm_config,
                r_agent=self.spm_config.r_agent,
                world_size=self.world_size,
                ego_velocity=ego_velocity
            )

            # Display SPM channels
            for ch_idx, (ax, title) in enumerate(self.spm_real_axes):
                channel_data = spm[:, :, ch_idx]

                # Use consistent colormaps
                if ch_idx == 0:
                    cmap = 'gray'  # Occupancy: binary
                elif ch_idx == 1:
                    cmap = 'hot'   # Proximity: distance-based
                else:
                    cmap = 'Reds'  # Collision Risk: danger

                if self.spm_real_images[ch_idx] is None:
                    # Create initial image
                    im = ax.imshow(channel_data, cmap=cmap, vmin=0, vmax=1,
                                  origin='lower', aspect='auto', interpolation='nearest')
                    self.spm_real_images[ch_idx] = im
                    self.fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
                else:
                    # Update existing image
                    self.spm_real_images[ch_idx].set_data(channel_data)

                ax.set_title(f"{title}")
                ax.set_xticks([])
                ax.set_yticks([])

        # === SPM Info Panel ===
        self.ax_spm_info.set_title("SPM Info")
        self.ax_spm_info.axis('off')

        # Calculate SPM statistics (only if SPM was updated)
        if not skip_spm:
            spm_occupancy_sum = np.sum(spm[:, :, 0])
            spm_proximity_max = np.max(spm[:, :, 1])
            spm_risk_max = np.max(spm[:, :, 2])

            spm_info_text = (
                f"Agent {self.selected_agent_idx}\n"
                f"Group: {int(self.group[self.selected_agent_idx])}\n"
                f"Position:\n"
                f"  ({selected_pos[0]:.2f}, {selected_pos[1]:.2f}) m\n"
                f"Velocity:\n"
                f"  ({selected_vel[0]:.2f}, {selected_vel[1]:.2f}) m/s\n"
                f"Heading:\n"
                f"  {np.rad2deg(selected_heading):.1f}°\n"
                f"\nSPM Stats:\n"
                f"  Occupancy: {spm_occupancy_sum:.1f}\n"
                f"  Max Proximity: {spm_proximity_max:.2f}\n"
                f"  Max Risk: {spm_risk_max:.2f}\n"
            )
            self.ax_spm_info.text(0.05, 0.95, spm_info_text,
                                 transform=self.ax_spm_info.transAxes,
                                 fontsize=9, verticalalignment='top', family='monospace')

        # === Heading Plot ===
        self.ax_heading.set_title("Heading Alignment")
        self.ax_heading.set_xlabel("Time [s]")
        self.ax_heading.set_ylabel("Angle [rad]")
        self.ax_heading.grid(True, alpha=0.3)

        # Plot heading and velocity direction over time
        time_axis = np.arange(t+1) * self.dt
        vel_angles = np.arctan2(self.vel[:t+1, self.selected_agent_idx, 1],
                               self.vel[:t+1, self.selected_agent_idx, 0])
        heading_angles = self.heading[:t+1, self.selected_agent_idx]

        self.ax_heading.plot(time_axis, heading_angles, 'b-', label='Heading θ', linewidth=1.5)
        self.ax_heading.plot(time_axis, vel_angles, 'r--', label='Velocity Dir', linewidth=1.5, alpha=0.7)
        self.ax_heading.axvline(t * self.dt, color='gray', linestyle=':', alpha=0.5)
        self.ax_heading.legend(fontsize=8, loc='upper right')
        self.ax_heading.set_xlim(0, (self.T-1) * self.dt)

        # === Control Forces ===
        self.ax_control.set_title(f"Control Forces")
        self.ax_control.set_xlabel("Time [s]")
        self.ax_control.set_ylabel("Force [N]")
        self.ax_control.grid(True, alpha=0.3)

        u_x = self.u[:t+1, self.selected_agent_idx, 0]
        u_y = self.u[:t+1, self.selected_agent_idx, 1]
        u_mag_history = np.sqrt(u_x**2 + u_y**2)

        self.ax_control.plot(time_axis, u_x, 'b-', label='Fx', linewidth=1, alpha=0.7)
        self.ax_control.plot(time_axis, u_y, 'r-', label='Fy', linewidth=1, alpha=0.7)
        self.ax_control.plot(time_axis, u_mag_history, 'k-', label='|F|', linewidth=1.5)
        self.ax_control.axhline(self.u_max, color='gray', linestyle='--', alpha=0.5, label=f'u_max')
        self.ax_control.axvline(t * self.dt, color='gray', linestyle=':', alpha=0.5)
        self.ax_control.legend(fontsize=8, loc='upper right')
        self.ax_control.set_xlim(0, (self.T-1) * self.dt)
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

        # Highlight selected agent's collisions
        selected_collision_times = np.where(self.collision[:t+1, self.selected_agent_idx])[0]
        if len(selected_collision_times) > 0:
            self.ax_collision.scatter(selected_collision_times,
                                     [self.selected_agent_idx] * len(selected_collision_times),
                                     c='darkred', s=20, alpha=0.8, marker='x', linewidths=2)

        self.ax_collision.set_xlim(0, self.T)
        self.ax_collision.set_ylim(-0.5, self.N - 0.5)

        # === Statistics Panel ===
        self.ax_controls.set_title("Statistics")
        self.ax_controls.axis('off')

        collision_count = np.sum(self.collision[:t+1, :])
        collision_rate_current = collision_count / ((t+1) * self.N) * 100 if t > 0 else 0.0

        vel_mag = np.linalg.norm(selected_vel)
        vel_dir = np.arctan2(selected_vel[1], selected_vel[0])
        u_mag = np.linalg.norm(selected_u)
        progress = np.dot(selected_vel, selected_d_goal)

        stats_text = (
            f"V7.2: {self.scenario}\n"
            f"Density: {self.density}\n"
            f"Seed: {self.seed}\n"
            f"\nPhysical Model:\n"
            f"  m={self.mass:.0f}kg\n"
            f"  u_max={self.u_max:.0f}N\n"
            f"  k_align={self.k_align:.1f} rad/s\n"
            f"\nAgent {self.selected_agent_idx}:\n"
            f"  v={vel_mag:.2f} m/s\n"
            f"  θ={np.rad2deg(selected_heading):.1f}°\n"
            f"  Δθ={np.rad2deg(vel_dir - selected_heading):.1f}°\n"
            f"  |F|={u_mag:.1f}N\n"
            f"  Progress={progress:.2f}m/s\n"
            f"\nTime: {t*self.dt:.2f}s\n"
            f"Collisions: {collision_count}\n"
            f"Rate: {collision_rate_current:.2f}%\n"
            f"Overall: {self.collision_rate:.3f}%"
        )
        self.ax_controls.text(0.05, 0.95, stats_text,
                             transform=self.ax_controls.transAxes,
                             fontsize=9, verticalalignment='top', family='monospace')

        # Refresh canvas - CRITICAL: use draw() + flush during playback
        if self.playing:
            # During playback, use immediate draw with flush to avoid GIL issues
            self.fig.canvas.draw()
            self.fig.canvas.flush_events()
        else:
            # When not playing, use draw_idle for efficiency
            self.fig.canvas.draw_idle()

    def run(self):
        """Run the viewer"""
        try:
            plt.show(block=True)
        except KeyboardInterrupt:
            print("\nViewer interrupted by user")
        finally:
            # Ensure cleanup happens even if there's an error
            self.window_open = False
            self.playing = False
            self.stop_animation()


def main():
    parser = argparse.ArgumentParser(description='V7.2 Raw Trajectory Viewer (5D State Space)')
    parser.add_argument('h5_file', nargs='?', default=None,
                       help='Path to HDF5 trajectory file (optional, will show dialog if omitted)')
    args = parser.parse_args()

    viewer = RawV72Viewer(args.h5_file)
    viewer.run()


if __name__ == '__main__':
    main()
