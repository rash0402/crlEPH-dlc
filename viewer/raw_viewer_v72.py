#!/usr/bin/env python3
"""
Raw V7.2 Trajectory Viewer for EPH (5D State Space with Heading Alignment)
Visualize HDF5 trajectory data with 5D state space

NEW in v7.2:
- 5D state space: (x, y, vx, vy, θ)
- Heading alignment dynamics (k_align=4.0 rad/s)
- Direction-based goals (d_goal unit vectors)
- Force control: [Fx, Fy] instead of [v, ω]
- Pedestrian model: m=70kg, u_max=150N

Features:
- Global map with all agent trajectories
- Interactive agent selection (click on agent)
- FOV visualization (210° wedge aligned with heading)
- Local view showing selected agent's ego-centric view
- SPM visualization (3 channels: Occupancy, Proximity, Risk)
- Collision flag display (red border when collision detected)
- Time slider for playback control

Performance:
- Python-based SPM reconstruction (no Julia server needed)
- Real-time playback at 60+ FPS
- TkAgg backend for lightweight GUI

Usage:
    ~/local/venv/bin/python viewer/raw_viewer_v72.py [--file path/to/file.h5]
"""

import h5py
import numpy as np
import matplotlib
matplotlib.use('Qt5Agg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.patches import Wedge, Rectangle
from matplotlib.widgets import Slider, Button
import argparse
import os
import sys
from pathlib import Path
import tkinter as tk
from tkinter import filedialog

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import SPM reconstructor
from viewer.spm_reconstructor import SPMConfig, reconstruct_spm_3ch


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
        self.spm_update_counter = 0  # For frame skipping during playback
        self.colorbars = {}  # Cache colorbars to avoid recreation
        self.frame_skip = 1  # Number of frames to skip during playback (default: 1 = no skip)

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
            title="Select Raw V7.2 Trajectory File",
            initialdir=initial_dir,
            filetypes=[
                ("HDF5 files", "*.h5"),
                ("All files", "*.*")
            ]
        )

        root.destroy()

        return file_path if file_path else None

    def load_data(self):
        """Load trajectory data from HDF5 file"""
        print(f"Loading: {self.h5_file_path}")

        with h5py.File(self.h5_file_path, 'r') as f:
            # Load trajectory data (v7.2 format from Julia: column-major storage)
            # Julia saves as [dim, N, T], we need [T, N, dim]
            pos_raw = np.array(f['trajectory/pos'])       # [2, N, T]
            vel_raw = np.array(f['trajectory/vel'])       # [2, N, T]
            heading_raw = np.array(f['trajectory/heading']) # [N, T]
            u_raw = np.array(f['trajectory/u'])           # [2, N, T]

            # Transpose to [T, N, 2] or [T, N]
            self.pos = np.transpose(pos_raw, (2, 1, 0))   # [2, N, T] -> [T, N, 2]
            self.vel = np.transpose(vel_raw, (2, 1, 0))   # [2, N, T] -> [T, N, 2]
            self.heading = np.transpose(heading_raw)       # [N, T] -> [T, N]
            self.u = np.transpose(u_raw, (2, 1, 0))       # [2, N, T] -> [T, N, 2]

            # Load d_goal (direction vectors, constant per agent)
            d_goal_raw = np.array(f['trajectory/d_goal'])  # [2, N]
            self.d_goal = d_goal_raw.T  # [2, N] -> [N, 2]

            # Load group IDs
            self.group = np.array(f['trajectory/group'])  # [N]

            # Load obstacles (v7.2 format: [M, 3] for circular, [M, 4] for rectangular, [M, 2] for points)
            if 'obstacles/data' in f:
                obs_raw = np.array(f['obstacles/data'])
                # Julia stores as (3, M), Python reads as (M, 3) after transpose
                # But HDF5 might not auto-transpose, so check shape
                if obs_raw.shape[0] == 3 and obs_raw.shape[1] > 3:
                    # Julia format: (3, M) -> need to transpose
                    obs_raw = obs_raw.T  # Now (M, 3)

                if obs_raw.shape[0] > 0:
                    if obs_raw.shape[1] == 3:
                        # v7.2: Circular obstacles - (x_center, y_center, radius)
                        self.obstacle_centers = obs_raw[:, :2]  # [M, 2]
                        self.obstacle_radii = obs_raw[:, 2]     # [M]
                        self.obstacles_are_circular = True
                    elif obs_raw.shape[1] == 4:
                        # Legacy: Rectangular obstacles - xmin, xmax, ymin, ymax
                        self.obstacle_centers = np.column_stack([
                            (obs_raw[:, 0] + obs_raw[:, 1]) / 2,  # x_center
                            (obs_raw[:, 2] + obs_raw[:, 3]) / 2   # y_center
                        ])
                        self.obstacle_radii = np.ones(len(self.obstacle_centers)) * 0.5
                        self.obstacles_are_circular = False
                    elif obs_raw.shape[1] == 2:
                        # Legacy: Point obstacles
                        self.obstacle_centers = obs_raw
                        self.obstacle_radii = np.ones(len(self.obstacle_centers)) * 0.5
                        self.obstacles_are_circular = False
                    else:
                        print(f"Warning: Unexpected obstacle shape {obs_raw.shape}, using empty array")
                        self.obstacle_centers = np.zeros((0, 2))
                        self.obstacle_radii = np.zeros(0)
                        self.obstacles_are_circular = False
                else:
                    self.obstacle_centers = np.zeros((0, 2))
                    self.obstacle_radii = np.zeros(0)
                    self.obstacles_are_circular = False
            else:
                self.obstacle_centers = np.zeros((0, 2))
                self.obstacle_radii = np.zeros(0)
                self.obstacles_are_circular = False

            # Load events (Julia: [N, T], need [T, N])
            collision_raw = np.array(f['events/collision'])           # [N, T]
            near_collision_raw = np.array(f['events/near_collision']) # [N, T]
            self.collision = collision_raw.T           # [N, T] -> [T, N]
            self.near_collision = near_collision_raw.T # [N, T] -> [T, N]

            # Load metadata (decode bytes to strings)
            self.metadata = {}
            for key in f['metadata'].keys():
                val = f['metadata'][key][()]
                if isinstance(val, bytes):
                    val = val.decode('utf-8')
                self.metadata[key] = val

            # Load SPM parameters
            self.spm_params = {key: f['spm_params'][key][()] for key in f['spm_params'].keys()}

        self.n_steps, self.n_agents, _ = self.pos.shape

        # Backward compatibility: self.obstacles as alias for obstacle_centers
        self.obstacles = self.obstacle_centers

        # v7.2: sensing_ratio = 3.0, r_robot=0.5, r_agent=0.5 -> D_max = 3.0 * 1.0 = 3.0m
        # But according to scripts, D_max=6.0m, so r_robot should be 1.5m
        # Let's use the values from spm_params
        r_robot = float(self.spm_params.get('r_robot', 1.5))
        r_agent = float(self.spm_params.get('r_agent', 0.5))
        sensing_ratio = float(self.spm_params['sensing_ratio'])
        self.max_sensing_distance = sensing_ratio * (r_robot + r_agent)

        # Initialize SPM configuration
        self.spm_config = SPMConfig(
            n_rho=int(self.spm_params['n_rho']),
            n_theta=int(self.spm_params['n_theta']),
            sensing_ratio=sensing_ratio,
            r_robot=r_robot,
            r_agent=r_agent,
            h_critical=0.0,      # No Haze for visualization
            h_peripheral=0.0,
            rho_index_critical=6
        )

        # Keep world_size for reference (from metadata)
        self.world_size = (
            float(self.metadata.get('world_width', 100.0)),
            float(self.metadata.get('world_height', 100.0))
        )

        # Calculate agent position percentiles for statistics
        pos_p05 = np.percentile(self.pos, 5, axis=(0, 1))   # 5th percentile [x, y]
        pos_p95 = np.percentile(self.pos, 95, axis=(0, 1))  # 95th percentile [x, y]

        # Determine display range based on scenario type
        scenario = self.metadata.get('scenario', 'unknown')

        if scenario == 'corridor' or len(self.obstacles) > 100:
            # For corridor scenarios or scenarios with many obstacles,
            # use obstacle range to determine world size
            if len(self.obstacles) > 0:
                obs_x_min = np.min(self.obstacles[:, 0])
                obs_x_max = np.max(self.obstacles[:, 0])
                obs_y_min = np.min(self.obstacles[:, 1])
                obs_y_max = np.max(self.obstacles[:, 1])

                # Display range is obstacle range with small margin
                self.display_xlim = (obs_x_min - 2.0, obs_x_max + 2.0)
                self.display_ylim = (obs_y_min - 2.0, obs_y_max + 2.0)
            else:
                # Fallback to world_size from metadata
                self.display_xlim = (0, self.world_size[0])
                self.display_ylim = (0, self.world_size[1])
        else:
            # For other scenarios, use percentile-based range
            # This automatically detects if agents are in 50×50 or 100×100 active area
            # Add margin (10% of active range, minimum 5m)
            x_range = pos_p95[0] - pos_p05[0]
            y_range = pos_p95[1] - pos_p05[1]
            margin_x = max(x_range * 0.1, 5.0)
            margin_y = max(y_range * 0.1, 5.0)

            self.display_xlim = (pos_p05[0] - margin_x, pos_p95[0] + margin_x)
            self.display_ylim = (pos_p05[1] - margin_y, pos_p95[1] + margin_y)

        print(f"  Loaded: {self.n_steps} steps, {self.n_agents} agents")
        print(f"  Scenario: {self.metadata.get('scenario', 'Unknown')}")
        print(f"  Density: {self.metadata.get('density', 'Unknown')}")
        print(f"  Controller: {self.metadata.get('controller_type', 'Unknown')}")
        print(f"  Sensing distance: {self.max_sensing_distance:.1f}m")
        print(f"  SPM: {self.spm_config.n_rho}x{self.spm_config.n_theta}")
        print(f"  World size: {self.world_size[0]:.0f}x{self.world_size[1]:.0f}m")
        print(f"  Active area (p5-p95): X=[{pos_p05[0]:.1f}, {pos_p95[0]:.1f}], Y=[{pos_p05[1]:.1f}, {pos_p95[1]:.1f}]")
        print(f"  Display range: X=[{self.display_xlim[0]:.1f}, {self.display_xlim[1]:.1f}], Y=[{self.display_ylim[0]:.1f}, {self.display_ylim[1]:.1f}]")
        print(f"  Obstacles: {len(self.obstacles)} points")

        # Collision statistics
        total_collisions = np.sum(self.collision)
        total_samples = self.n_steps * self.n_agents
        collision_rate = 100.0 * total_collisions / total_samples
        print(f"  Collision rate: {collision_rate:.3f}% ({int(total_collisions)}/{total_samples} frames)")

    def setup_figure(self):
        """Setup matplotlib figure with subplots"""
        self.fig = plt.figure(figsize=(18, 10))
        self.fig.canvas.manager.set_window_title(f"EPH v7.2 Viewer - {Path(self.h5_file_path).name}")

        # Create grid layout
        gs = GridSpec(3, 4, figure=self.fig, hspace=0.3, wspace=0.4,
                     left=0.05, right=0.98, top=0.95, bottom=0.12)

        # Top row: Global map (left) and Local view (right)
        self.ax_global = self.fig.add_subplot(gs[0:2, 0:2])
        self.ax_local = self.fig.add_subplot(gs[0:2, 2:4])

        # Bottom row: SPM 3 channels
        self.ax_spm_ch1 = self.fig.add_subplot(gs[2, 0])
        self.ax_spm_ch2 = self.fig.add_subplot(gs[2, 1])
        self.ax_spm_ch3 = self.fig.add_subplot(gs[2, 2])

        # Info panel
        self.ax_info = self.fig.add_subplot(gs[2, 3])
        self.ax_info.axis('off')

        # Enable click on global map to select agent
        self.fig.canvas.mpl_connect('button_press_event', self.on_click)

    def setup_widgets(self):
        """Setup interactive widgets (slider, buttons)"""
        # Time slider
        ax_slider = plt.axes([0.15, 0.04, 0.50, 0.03])
        self.time_slider = Slider(
            ax_slider, 'Time',
            0, self.n_steps - 1,
            valinit=0,
            valstep=1,
            valfmt='%d'
        )
        self.time_slider.on_changed(self.on_time_change)

        # Frame skip label
        self.ax_skip_label = plt.axes([0.67, 0.04, 0.06, 0.03])
        self.ax_skip_label.axis('off')
        self.ax_skip_label.text(0.0, 0.5, 'Skip:', fontsize=10, va='center')

        # Frame skip selector (SpinBox-like using Button)
        ax_skip = plt.axes([0.73, 0.04, 0.05, 0.03])
        self.btn_skip = Button(ax_skip, '1')
        self.btn_skip.on_clicked(self.cycle_frame_skip)

        # Play/Pause button
        ax_play = plt.axes([0.82, 0.04, 0.08, 0.03])
        self.btn_play = Button(ax_play, 'Play')
        self.btn_play.on_clicked(self.toggle_play)

        # Speed display axes
        self.ax_speed = plt.axes([0.91, 0.04, 0.07, 0.03])
        self.ax_speed.axis('off')
        self.speed_text = self.ax_speed.text(0.0, 0.5, '1x', fontsize=10,
                                              va='center', fontweight='bold',
                                              transform=self.ax_speed.transAxes)

        # Timer for playback
        self.timer = None

    def on_click(self, event):
        """Handle mouse click on global map to select agent"""
        if event.inaxes != self.ax_global:
            return

        click_x, click_y = event.xdata, event.ydata
        if click_x is None or click_y is None:
            return

        # Find nearest agent
        pos_t = self.pos[self.current_step]
        distances = np.linalg.norm(pos_t - np.array([click_x, click_y]), axis=1)
        nearest_idx = np.argmin(distances)

        if distances[nearest_idx] < 2.0:  # Within 2m
            self.selected_agent_idx = nearest_idx
            # Clear colorbar cache when changing agent
            self.colorbars = {}
            self.update_display()

    def on_time_change(self, val):
        """Handle time slider change"""
        self.current_step = int(val)
        self.update_display()

    def cycle_frame_skip(self, event):
        """Cycle through frame skip values: 1, 5, 10, 20, 50"""
        skip_values = [1, 5, 10, 20, 50]
        current_idx = skip_values.index(self.frame_skip) if self.frame_skip in skip_values else 0
        next_idx = (current_idx + 1) % len(skip_values)
        self.frame_skip = skip_values[next_idx]

        # Update button label
        self.btn_skip.label.set_text(str(self.frame_skip))

        # Update speed display - clear and redraw
        self.ax_speed.clear()
        self.ax_speed.axis('off')
        self.speed_text = self.ax_speed.text(0.0, 0.5, f'{self.frame_skip}x',
                                              fontsize=10, va='center',
                                              fontweight='bold',
                                              transform=self.ax_speed.transAxes)

        # Force immediate redraw
        self.fig.canvas.draw()

    def toggle_play(self, event):
        """Toggle play/pause"""
        if self.playing:
            # Stop
            if self.timer:
                self.timer.stop()
                self.timer = None
            self.btn_play.label.set_text('Play')
            self.playing = False
        else:
            # Start
            self.btn_play.label.set_text('Pause')
            self.playing = True
            # Use slower interval for stability (30 FPS instead of 60)
            self.timer = self.fig.canvas.new_timer(interval=33)
            self.timer.add_callback(self.advance_time)
            self.timer.start()

    def advance_time(self):
        """Advance time by frame_skip steps (for playback)"""
        if not self.playing:
            return

        # Update frame counter for SPM frame skipping
        self.spm_update_counter += 1

        # Advance by frame_skip steps
        next_step = (self.current_step + self.frame_skip) % self.n_steps
        self.time_slider.set_val(next_step)

    def update_display(self):
        """Update all visualization panels"""
        t = self.current_step
        agent_idx = self.selected_agent_idx

        # During playback, skip SPM updates for performance
        # If frame_skip >= 5, always update SPM (user expects to see changes)
        # If frame_skip < 5, update every 5 frames
        if self.frame_skip >= 5:
            skip_spm = False  # Always update when skipping multiple frames
        else:
            skip_spm = self.playing and (self.spm_update_counter % 5 != 0)

        # Clear axes
        self.ax_global.clear()

        # CRITICAL: Immediately after clear(), set fixed limits and disable autoscale
        # This MUST be done before any other operations on ax_global
        self.ax_global.set_xlim(self.display_xlim)
        self.ax_global.set_ylim(self.display_ylim)
        self.ax_global.autoscale(enable=False)

        self.ax_local.clear()
        if not skip_spm:
            self.ax_spm_ch1.clear()
            self.ax_spm_ch2.clear()
            self.ax_spm_ch3.clear()
        self.ax_info.clear()
        self.ax_info.axis('off')

        # Draw global map
        self.draw_global_map(t, agent_idx)

        # Draw local view
        self.draw_local_view(t, agent_idx)

        # Draw SPM (skip during playback for better performance)
        if not skip_spm:
            self.draw_spm(t, agent_idx)

        # Draw info panel
        self.draw_info(t, agent_idx)

        # Redraw - use draw() instead of draw_idle() to avoid timer conflicts
        if self.playing:
            # During playback, use immediate draw with flush
            self.fig.canvas.draw()
            self.fig.canvas.flush_events()
        else:
            # When not playing, use draw_idle for efficiency
            self.fig.canvas.draw_idle()

    def draw_global_map(self, t, selected_idx):
        """Draw global map with all agents"""
        ax = self.ax_global

        # CRITICAL: Set limits and disable autoscale FIRST, before ANY other operations
        # This must be done immediately after clear() to prevent matplotlib from
        # automatically determining the axis range based on data
        ax.set_xlim(self.display_xlim)
        ax.set_ylim(self.display_ylim)
        ax.autoscale(enable=False)

        # Now set other axis properties
        ax.set_title(f"Global Map (t={t}/{self.n_steps-1})")
        ax.set_xlabel("X [m]")
        ax.set_ylabel("Y [m]")
        ax.set_aspect('equal', adjustable='box')  # Maintain 1:1 aspect ratio
        ax.grid(True, alpha=0.3)

        # Draw obstacles (v7.2: circular obstacles)
        if len(self.obstacle_centers) > 0:
            if self.obstacles_are_circular:
                # Draw as circles
                for i in range(len(self.obstacle_centers)):
                    circle = plt.Circle(
                        self.obstacle_centers[i],
                        self.obstacle_radii[i],
                        color='gray', alpha=0.4, zorder=1, linewidth=1, edgecolor='darkgray'
                    )
                    ax.add_patch(circle)
            else:
                # Legacy: draw as points
                ax.scatter(self.obstacle_centers[:, 0], self.obstacle_centers[:, 1],
                          c='gray', s=100, marker='s', alpha=0.5, label='Obstacles')

        # Draw agents
        pos = self.pos[t]
        vel = self.vel[t]
        heading = self.heading[t]

        for i in range(self.n_agents):
            x, y = pos[i]
            vx, vy = vel[i]
            h = heading[i]

            # Color by group
            group_id = self.group[i]
            colors = ['blue', 'green', 'orange', 'purple']
            color = colors[int(group_id) % len(colors)]

            if i == selected_idx:
                color = 'red'
                size = 200
                # Draw FOV wedge
                fov_deg = 210.0
                fov_r = self.max_sensing_distance
                h_deg = np.rad2deg(h)
                wedge = Wedge((x, y), fov_r, h_deg - fov_deg/2, h_deg + fov_deg/2,
                            alpha=0.15, color='red', zorder=1)
                ax.add_patch(wedge)
            else:
                size = 80

            # Draw agent
            ax.scatter(x, y, c=color, s=size, zorder=3, edgecolors='black', linewidths=0.5)

            # Draw velocity arrow
            speed = np.sqrt(vx**2 + vy**2)
            if speed > 0.1:
                ax.arrow(x, y, vx*0.4, vy*0.4,
                        head_width=0.3, head_length=0.2,
                        fc=color, ec=color, alpha=0.7, zorder=2)

            # Draw heading direction (small arrow)
            hx = np.cos(h) * 0.8
            hy = np.sin(h) * 0.8
            ax.arrow(x, y, hx, hy,
                    head_width=0.25, head_length=0.15,
                    fc='black', ec='black', alpha=0.8, zorder=4, linewidth=1.5)

        # CRITICAL: Re-apply limits AFTER all plotting operations
        # Some matplotlib operations may have triggered limit adjustments
        ax.set_xlim(self.display_xlim)
        ax.set_ylim(self.display_ylim)

        # Highlight collision
        if self.collision[t, selected_idx]:
            for spine in ax.spines.values():
                spine.set_edgecolor('red')
                spine.set_linewidth(3)
        else:
            # Reset spine color when no collision
            for spine in ax.spines.values():
                spine.set_edgecolor('black')
                spine.set_linewidth(1.0)

    def draw_local_view(self, t, agent_idx):
        """Draw local ego-centric view"""
        ax = self.ax_local
        ax.set_title(f"Local View (Agent {agent_idx+1})")
        ax.set_xlabel("X' [m] (Right)")
        ax.set_ylabel("Y' [m] (Forward)")
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.3)

        ego_pos = self.pos[t, agent_idx]
        ego_vel = self.vel[t, agent_idx]
        ego_h = self.heading[t, agent_idx]

        # Rotation matrix: align heading to Y+ axis (forward)
        rotation_angle = -ego_h + np.pi / 2.0
        c, s = np.cos(rotation_angle), np.sin(rotation_angle)
        R = np.array([[c, -s], [s, c]])

        # Draw ego agent at origin
        ax.scatter(0, 0, c='red', s=300, zorder=5, edgecolors='black', linewidths=2)
        # Forward direction arrow
        ax.arrow(0, 0, 0, 1.2, head_width=0.3, head_length=0.2,
                fc='red', ec='red', zorder=4, linewidth=2)

        # Draw FOV wedge
        fov_deg = 210.0
        fov_r = self.max_sensing_distance
        wedge = Wedge((0, 0), fov_r, 90 - fov_deg/2, 90 + fov_deg/2,
                     alpha=0.15, color='red', zorder=1)
        ax.add_patch(wedge)

        # Transform and draw other agents
        for i in range(self.n_agents):
            if i == agent_idx:
                continue

            rel_pos = self.pos[t, i] - ego_pos
            rel_vel = self.vel[t, i] - ego_vel

            # Check if within sensing range (before rotation)
            dist = np.linalg.norm(rel_pos)
            if dist > fov_r * 1.2:
                continue

            # Rotate to ego frame
            rel_pos_ego = R @ rel_pos
            rel_vel_ego = R @ rel_vel

            # Check if in FOV
            angle = np.arctan2(rel_pos_ego[0], rel_pos_ego[1])
            in_fov = abs(angle) <= np.deg2rad(fov_deg / 2)

            color = 'blue' if in_fov else 'gray'
            alpha = 1.0 if in_fov else 0.3

            ax.scatter(rel_pos_ego[0], rel_pos_ego[1],
                      c=color, s=100, alpha=alpha, zorder=3,
                      edgecolors='black', linewidths=0.5)

            # Draw velocity arrow
            speed = np.linalg.norm(rel_vel_ego)
            if speed > 0.1:
                ax.arrow(rel_pos_ego[0], rel_pos_ego[1],
                        rel_vel_ego[0]*0.3, rel_vel_ego[1]*0.3,
                        head_width=0.2, head_length=0.1,
                        fc=color, ec=color, alpha=alpha*0.7, zorder=2)

        # Draw obstacles in ego frame (v7.2: circular obstacles)
        if len(self.obstacle_centers) > 0:
            for i in range(len(self.obstacle_centers)):
                obs_pos = self.obstacle_centers[i]
                obs_radius = self.obstacle_radii[i]
                rel_obs = obs_pos - ego_pos
                dist_obs = np.linalg.norm(rel_obs)
                if dist_obs > fov_r * 1.2:
                    continue
                rel_obs_ego = R @ rel_obs
                if self.obstacles_are_circular:
                    # Draw as circle
                    circle = plt.Circle(
                        rel_obs_ego,
                        obs_radius,
                        color='gray', alpha=0.5, zorder=2, linewidth=1, edgecolor='darkgray'
                    )
                    ax.add_patch(circle)
                else:
                    # Legacy: draw as square marker
                    ax.scatter(rel_obs_ego[0], rel_obs_ego[1],
                              c='gray', s=150, marker='s', alpha=0.6, zorder=2)

        ax.set_xlim(-fov_r*1.1, fov_r*1.1)
        ax.set_ylim(-fov_r*0.3, fov_r*1.1)

    def draw_spm(self, t, agent_idx):
        """Draw 3-channel SPM"""
        # Reconstruct SPM
        ego_pos = self.pos[t, agent_idx]
        ego_heading = self.heading[t, agent_idx]
        ego_vel = self.vel[t, agent_idx]
        all_pos = self.pos[t]
        all_vel = self.vel[t]

        spm = reconstruct_spm_3ch(
            ego_pos=ego_pos,
            ego_heading=ego_heading,
            all_positions=all_pos,
            all_velocities=all_vel,
            obstacles=self.obstacles,
            config=self.spm_config,
            r_agent=self.spm_config.r_agent,
            world_size=self.world_size,
            ego_velocity=ego_vel
        )

        # Draw each channel
        ch_names = ["Occupancy", "Proximity", "Risk"]
        axes = [self.ax_spm_ch1, self.ax_spm_ch2, self.ax_spm_ch3]

        for ch, (ax, name) in enumerate(zip(axes, ch_names)):
            vmax = max(np.max(spm[:, :, ch]), 0.01)
            im = ax.imshow(spm[:, :, ch], cmap='viridis', origin='lower',
                          vmin=0, vmax=vmax, aspect='auto')
            ax.set_title(f"Ch{ch+1}: {name}", fontsize=10)
            ax.set_xlabel("θ (Angle)", fontsize=8)
            ax.set_ylabel("ρ (Distance)", fontsize=8)
            ax.tick_params(labelsize=7)

            # Add or update colorbar (cache to avoid recreation overhead)
            cbar_key = f'spm_ch{ch}'
            if cbar_key not in self.colorbars or self.colorbars[cbar_key] is None:
                # Create new colorbar
                cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
                cbar.ax.tick_params(labelsize=7)
                # Limit to 5 ticks maximum
                cbar.locator = plt.MaxNLocator(nbins=5)
                cbar.formatter = plt.FuncFormatter(lambda x, p: f'{x:.2f}')
                self.colorbars[cbar_key] = cbar
            else:
                # Update existing colorbar
                cbar = self.colorbars[cbar_key]
                cbar.update_normal(im)
            cbar.update_ticks()

    def draw_info(self, t, agent_idx):
        """Draw info panel"""
        ax = self.ax_info

        pos = self.pos[t, agent_idx]
        vel = self.vel[t, agent_idx]
        heading = self.heading[t, agent_idx]
        u = self.u[t, agent_idx]
        d_goal = self.d_goal[agent_idx]
        speed = np.linalg.norm(vel)
        force = np.linalg.norm(u)

        collision = self.collision[t, agent_idx]
        near_collision = self.near_collision[t, agent_idx]

        info_text = f"""
Agent: {agent_idx + 1} / {self.n_agents}
Group: {int(self.group[agent_idx])}

Position: ({pos[0]:.2f}, {pos[1]:.2f}) m
Velocity: ({vel[0]:.2f}, {vel[1]:.2f}) m/s
Speed: {speed:.2f} m/s
Heading: {np.rad2deg(heading):.1f}°

Control Force: ({u[0]:.1f}, {u[1]:.1f}) N
Force Mag: {force:.1f} N

Goal Dir: ({d_goal[0]:.2f}, {d_goal[1]:.2f})

Collision: {'YES' if collision else 'No'}
Near Coll: {'YES' if near_collision else 'No'}

Time: {t} / {self.n_steps - 1}
"""
        ax.text(0.1, 0.5, info_text, fontsize=10, verticalalignment='center',
               family='monospace', transform=ax.transAxes)

    def show(self):
        """Show the viewer window"""
        plt.show()


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Raw V7.2 Trajectory Viewer")
    parser.add_argument('--file', type=str, default=None,
                       help='Path to HDF5 trajectory file')
    args = parser.parse_args()

    viewer = RawV72Viewer(args.file)
    viewer.show()


if __name__ == "__main__":
    main()
