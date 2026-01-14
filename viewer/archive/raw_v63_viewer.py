#!/usr/bin/env python3
"""
Raw V6.3 Trajectory Viewer for EPH (Controller-Bias-Free)
Visualize HDF5 trajectory data with extended logs

NEW in v6.3:
- Extended logs: goal, d_pref, group, collision flags
- Controller type display
- Collision event highlighting

Features:
- Global map with all agent trajectories
- Interactive agent selection (click on agent)
- FOV visualization (210° field of view shown as semi-transparent wedge)
- Local view showing selected agent's sensing range
- SPM visualization (3 channels)
- Collision flag display (red border when collision detected)
- Time slider for playback control
"""

import h5py
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.patches import Circle, Rectangle, Wedge, Polygon
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


class RawV63Viewer:
    """Interactive viewer for raw v6.3 trajectory data (controller-bias-free)"""

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
            default_dir = script_dir / "data" / "vae_training" / "raw_v63"
            if default_dir.exists():
                initial_dir = str(default_dir)
            else:
                initial_dir = str(script_dir)

        # Show file dialog
        file_path = filedialog.askopenfilename(
            title="Select Raw V6.3 Trajectory File",
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
            # Load trajectory data
            # v6.3 HDF5 structure: Already [T, N, 2] or [T, N] - no transpose needed!
            # (Different from v6.2 which was [2, N, T])
            self.pos = np.array(f['trajectory/pos'])  # [T, N, 2]
            self.vel = np.array(f['trajectory/vel'])  # [T, N, 2]
            self.u = np.array(f['trajectory/u'])      # [T, N, 2]
            self.heading = np.array(f['trajectory/heading'])  # [T, N]

            # Load obstacles - still [M, 2] format
            obs_raw = np.array(f['obstacles/data'])
            if obs_raw.shape[0] == 2 and obs_raw.shape[1] != 2:
                # Format: [2, M] -> transpose to [M, 2]
                self.obstacles = obs_raw.T
            else:
                # Already [M, 2]
                self.obstacles = obs_raw

            # Load metadata
            self.metadata = {key: f['metadata'][key][()] for key in f['metadata'].keys()}
            self.spm_params = {key: f['spm_params'][key][()] for key in f['spm_params'].keys()}

            # NEW in v6.3: Load extended logs (already in correct format)
            goal_raw = np.array(f['trajectory/goal'])
            if goal_raw.shape[0] == 2:
                self.goal = goal_raw.T  # [2, N] -> [N, 2]
            else:
                self.goal = goal_raw  # Already [N, 2]

            self.d_pref = np.array(f['trajectory/d_pref'])  # [T, N, 2]
            self.group = np.array(f['trajectory/group'])  # [N]
            self.collision = np.array(f['events/collision'])  # [T, N]
            self.near_collision = np.array(f['events/near_collision'])  # [T, N]
            self.controller_type = self.metadata.get('controller_type', b'Unknown')
            if isinstance(self.controller_type, bytes):
                self.controller_type = self.controller_type.decode('utf-8')

        self.n_steps, self.n_agents, _ = self.pos.shape
        # Correct: D_max = sensing_ratio * (r_robot + r_agent) = sensing_ratio * 2.0
        # v6.3: r_robot=1.5m, r_agent=0.5m → r_total=2.0m
        self.max_sensing_distance = self.spm_params['sensing_ratio'] * 2.0

        # Initialize SPM configuration
        # v6.3: Haze parameters may not exist (controller-bias-free), use defaults for visualization
        # r_robot and r_agent: Use values from HDF5 if available, otherwise use v6.3 defaults
        r_robot = float(self.spm_params.get('r_robot', 1.5))
        r_agent = float(self.spm_params.get('r_agent', 0.5))

        self.spm_config = SPMConfig(
            n_rho=int(self.spm_params['n_rho']),
            n_theta=int(self.spm_params['n_theta']),
            sensing_ratio=float(self.spm_params['sensing_ratio']),
            r_robot=r_robot,
            r_agent=r_agent,
            h_critical=float(self.spm_params.get('h_critical', 0.0)),  # Default: no Haze
            h_peripheral=float(self.spm_params.get('h_peripheral', 0.0)),
            rho_index_critical=int(self.spm_params.get('rho_index_critical', 6))
        )

        print(f"  Loaded: {self.n_steps} steps, {self.n_agents} agents")
        print(f"  Scenario: {self.metadata['scenario']}")
        print(f"  Density: {self.metadata['density']}")
        print(f"  Controller: {self.controller_type}")
        print(f"  Sensing distance: {self.max_sensing_distance:.1f}m")
        print(f"  SPM: {self.spm_config.n_rho}x{self.spm_config.n_theta}")

        # Collision statistics
        total_collisions = np.sum(self.collision)
        total_samples = self.n_steps * self.n_agents
        collision_rate = 100.0 * total_collisions / total_samples
        print(f"  Collision rate: {collision_rate:.3f}% ({int(total_collisions)}/{total_samples} frames)")

    def setup_figure(self):
        """Setup matplotlib figure with subplots"""
        self.fig = plt.figure(figsize=(16, 10))

        # Suppress system bell
        try:
            self.fig.canvas.manager.window.bell = lambda: None
        except:
            pass

        scenario_name = self.metadata['scenario']
        if isinstance(scenario_name, bytes):
            scenario_name = scenario_name.decode('utf-8')

        self.fig.suptitle(
            f"Raw V6.3 Trajectory Viewer - {scenario_name} (Density: {self.metadata['density']})",
            fontsize=14, fontweight='bold'
        )

        # Create grid layout: 3 rows x 4 columns
        # Top row: Global map (spans 2x2) + Local map (2x2)
        # Middle row: SPM Real channels (1x1 each, 4 columns)
        # Bottom row: SPM Pred channels (1x1 each, 4 columns) + Controls
        gs = GridSpec(4, 4, figure=self.fig, hspace=0.35, wspace=0.35,
                     left=0.05, right=0.95, top=0.92, bottom=0.08)

        # Row 0-1: Large plots
        self.ax_global = self.fig.add_subplot(gs[0:2, 0:2])
        self.ax_local = self.fig.add_subplot(gs[0:2, 2:4])

        # Row 2: SPM Real channels
        self.ax_spm1_real = self.fig.add_subplot(gs[2, 0])
        self.ax_spm2_real = self.fig.add_subplot(gs[2, 1])
        self.ax_spm3_real = self.fig.add_subplot(gs[2, 2])
        self.ax_spm_info = self.fig.add_subplot(gs[2, 3])

        # Row 3: SPM Pred channels + Controls
        self.ax_spm1_pred = self.fig.add_subplot(gs[3, 0])
        self.ax_spm2_pred = self.fig.add_subplot(gs[3, 1])
        self.ax_spm3_pred = self.fig.add_subplot(gs[3, 2])
        self.ax_controls = self.fig.add_subplot(gs[3, 3])

        self.setup_global_map()
        self.setup_local_map()
        self.setup_spm_axes()

    def setup_global_map(self):
        """Setup global map axis"""
        self.ax_global.set_title('Global Map (Click to select agent)', fontsize=11, fontweight='bold')
        self.ax_global.set_xlabel('X [m]')
        self.ax_global.set_ylabel('Y [m]')
        self.ax_global.set_aspect('equal')
        self.ax_global.grid(True, alpha=0.3)

        # Plot obstacles
        if self.obstacles.shape[0] > 0:
            self.ax_global.scatter(self.obstacles[:, 0], self.obstacles[:, 1],
                                  c='gray', s=100, marker='s', alpha=0.5, label='Obstacles')

        # Determine world boundaries
        # Priority 1: Use world_size from metadata (for toroidal worlds)
        if 'world_size' in self.metadata:
            world_size = self.metadata['world_size']
            if isinstance(world_size, (np.ndarray, list, tuple)) and len(world_size) >= 2:
                # Use world_size directly (toroidal boundary)
                world_x = float(world_size[0])
                world_y = float(world_size[1])
                self.world_xlim = (0, world_x)
                self.world_ylim = (0, world_y)
                # Store world_size for SPM reconstruction (toroidal distance calculation)
                self.world_size = (world_x, world_y)
                print(f"  Using world_size: ({world_x:.1f}, {world_y:.1f})")
            else:
                # Fallback to auto-detect
                all_x = self.pos[:, :, 0].flatten()
                all_y = self.pos[:, :, 1].flatten()
                margin = 5
                self.world_xlim = (0, all_x.max() + margin)
                self.world_ylim = (0, all_y.max() + margin)
                self.world_size = None  # Non-toroidal
        else:
            # Priority 2: Auto-detect from data (no metadata)
            all_x = self.pos[:, :, 0].flatten()
            all_y = self.pos[:, :, 1].flatten()

            # Include obstacles
            if self.obstacles.shape[0] > 0:
                obs_x = self.obstacles[:, 0]
                obs_y = self.obstacles[:, 1]
                all_x = np.concatenate([all_x, obs_x])
                all_y = np.concatenate([all_y, obs_y])

            margin = 5
            self.world_xlim = (0, all_x.max() + margin)
            self.world_ylim = (0, all_y.max() + margin)
            self.world_size = None  # Non-toroidal (no metadata)

        self.ax_global.set_xlim(self.world_xlim)
        self.ax_global.set_ylim(self.world_ylim)

        # Plot initial agent positions (will be updated in update_display)
        self.global_scatter = self.ax_global.scatter([], [], s=100, c='blue', alpha=0.6, zorder=5)

        # Agent direction triangles: Small white triangles inside circles
        self.agent_triangles = []  # List of Polygon patches

        # Selected agent marker: Red triangle (will be created in update_display)
        self.selected_marker = None

        # NEW in v6.3: Collision highlight (red border around colliding agents)
        self.collision_marker = self.ax_global.scatter([], [], s=300, facecolors='none',
                                                       edgecolors='red', linewidths=3, zorder=11)

        # FOV visualization (210° field of view)
        self.fov_wedge = None  # Will be created in update_display

        # Connect click event
        self.fig.canvas.mpl_connect('button_press_event', self.on_click)

    def setup_local_map(self):
        """Setup local map axis"""
        self.ax_local.set_title('Local View (Agent-centered)', fontsize=11, fontweight='bold')
        self.ax_local.set_xlabel('X (relative) [m]')
        self.ax_local.set_ylabel('Y (relative) [m]')
        self.ax_local.set_aspect('equal')
        self.ax_local.grid(True, alpha=0.3)

        # Set fixed limits based on sensing range
        limit = self.max_sensing_distance * 1.2
        self.ax_local.set_xlim(-limit, limit)
        self.ax_local.set_ylim(-limit, limit)

        # Draw sensing range circle
        sensing_circle = Circle((0, 0), self.max_sensing_distance,
                               fill=False, edgecolor='blue', linestyle='--', linewidth=2, alpha=0.5)
        self.ax_local.add_patch(sensing_circle)

        # Ego agent marker: Red circle + white triangle (same style as global map)
        # Red circle (same size as global map circles)
        self.ego_circle = Circle((0, 0), 0.5, facecolor='red', edgecolor='darkred',
                                linewidth=2, alpha=0.6, zorder=9, label='Ego Agent')
        self.ax_local.add_patch(self.ego_circle)

        # White triangle pointing upward (forward direction in ego-centric frame)
        size = 0.4  # Triangle size in meters (smaller than circle)
        ego_triangle = np.array([
            [0, size],           # Front vertex (pointing forward)
            [-size*0.6, -size*0.5],  # Left-back vertex
            [size*0.6, -size*0.5]    # Right-back vertex
        ])
        self.ego_marker = Polygon(ego_triangle, closed=True, facecolor='white',
                                 edgecolor='darkred', linewidth=2, zorder=10)
        self.ax_local.add_patch(self.ego_marker)

        # Other agents (will be updated)
        self.local_scatter = self.ax_local.scatter([], [], s=50, c='blue', alpha=0.6, label='Other Agents')

        # Obstacles (will be updated)
        self.local_obstacles_scatter = self.ax_local.scatter([], [], s=100, c='gray', marker='s', alpha=0.5, label='Obstacles')

        # Goal direction arrow (shows where agent is heading)
        self.goal_arrow = self.ax_local.arrow(0, 0, 0, 1,
                                              head_width=0.8, head_length=0.5,
                                              fc='green', ec='darkgreen',
                                              linewidth=2, alpha=0.7,
                                              zorder=9, label='Goal Direction')

        # FOV wedge (210° field of view, agent faces upward in local frame)
        fov_angle = 210.0
        forward_direction_deg = 90.0  # Agent faces upward (Y+) in local coordinates
        theta1 = forward_direction_deg - fov_angle / 2.0
        theta2 = forward_direction_deg + fov_angle / 2.0
        self.local_fov_wedge = Wedge(
            center=(0, 0),
            r=self.max_sensing_distance,
            theta1=theta1,
            theta2=theta2,
            facecolor='yellow',
            alpha=0.15,
            edgecolor='orange',
            linewidth=1.5,
            linestyle='--',
            zorder=2
        )
        self.ax_local.add_patch(self.local_fov_wedge)

        self.ax_local.legend(loc='upper right', fontsize=8)

    def setup_spm_axes(self):
        """Setup SPM visualization axes"""
        # Real SPM channels
        self.spm_real_axes = [
            (self.ax_spm1_real, 'Real Ch1: Occupancy'),
            (self.ax_spm2_real, 'Real Ch2: Proximity'),
            (self.ax_spm3_real, 'Real Ch3: Collision Risk')
        ]

        # Pred SPM channels
        self.spm_pred_axes = [
            (self.ax_spm1_pred, 'Pred Ch1: Occupancy'),
            (self.ax_spm2_pred, 'Pred Ch2: Proximity'),
            (self.ax_spm3_pred, 'Pred Ch3: Collision Risk')
        ]

        # Initialize image handles
        self.spm_real_images = [None, None, None]
        self.spm_pred_images = [None, None, None]

        for ax, title in self.spm_real_axes + self.spm_pred_axes:
            ax.set_title(title, fontsize=9, fontweight='bold')
            ax.set_xlabel('θ (angle)', fontsize=8)
            ax.set_ylabel('ρ (distance)', fontsize=8)
            ax.set_aspect('auto')

        # Info panel
        self.ax_spm_info.axis('off')
        self.info_text = self.ax_spm_info.text(0.05, 0.95, '', transform=self.ax_spm_info.transAxes,
                                               fontsize=9, verticalalignment='top', family='monospace')

        # Controls panel
        self.ax_controls.axis('off')

    def setup_widgets(self):
        """Setup interactive widgets (slider, buttons)"""
        # Time slider
        ax_slider = plt.axes([0.15, 0.02, 0.65, 0.02])
        self.time_slider = Slider(
            ax_slider, 'Time', 0, self.n_steps - 1,
            valinit=0, valstep=1, color='lightblue'
        )
        self.time_slider.on_changed(self.on_slider_change)

        # Open File button
        ax_open = plt.axes([0.05, 0.02, 0.08, 0.03])
        self.open_button = Button(ax_open, 'Open File')
        self.open_button.on_clicked(self.on_open_button)

        # Play button
        ax_play = plt.axes([0.82, 0.02, 0.05, 0.03])
        self.play_button = Button(ax_play, 'Play')
        self.play_button.on_clicked(self.on_play_button)

        # Reset button
        ax_reset = plt.axes([0.88, 0.02, 0.05, 0.03])
        self.reset_button = Button(ax_reset, 'Reset')
        self.reset_button.on_clicked(self.on_reset_button)

    def on_slider_change(self, val):
        """Handle slider value change"""
        self.current_step = int(val)
        self.update_display()

    def on_open_button(self, event):
        """Handle open file button click"""
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

            # Reset viewer state
            self.current_step = 0
            self.selected_agent_idx = 0

            # Update slider range
            self.time_slider.valmax = self.n_steps - 1
            self.time_slider.set_val(0)
            self.time_slider.ax.set_xlim(0, self.n_steps - 1)

            # Update figure title
            scenario_name = self.metadata['scenario']
            if isinstance(scenario_name, bytes):
                scenario_name = scenario_name.decode('utf-8')
            self.fig.suptitle(
                f"Raw V6.3 Trajectory Viewer - {scenario_name} (Density: {self.metadata['density']})",
                fontsize=14, fontweight='bold'
            )

            # IMPORTANT: Reconfigure global and local maps for new world_size
            self.ax_global.clear()
            self.ax_local.clear()
            self.setup_global_map()
            self.setup_local_map()

            # Clear and update display
            self.reset_visualization_state()
            self.update_display()

            print(f"✓ Loaded new file: {Path(new_file_path).name}")

    def on_play_button(self, event):
        """Handle play button click"""
        self.playing = not self.playing
        self.play_button.label.set_text('Pause' if self.playing else 'Play')

        if self.playing:
            self.play_animation()

    def on_reset_button(self, event):
        """Handle reset button click"""
        self.playing = False
        self.current_step = 0
        self.time_slider.set_val(0)
        self.play_button.label.set_text('Play')
        self.update_display()

    def reset_visualization_state(self):
        """Reset visualization state when loading new file"""
        # Reset SPM image handles (will be recreated on next update)
        self.spm_real_images = [None, None, None]
        self.spm_pred_images = [None, None, None]

        # Clear SPM axes completely (removes colorbars too)
        for ax, _ in self.spm_real_axes + self.spm_pred_axes:
            ax.clear()
            # Remove any existing colorbars
            if hasattr(ax, 'cbar') and ax.cbar is not None:
                ax.cbar.remove()
                ax.cbar = None

        # Reset axes properties
        for (ax, title) in self.spm_real_axes:
            ax.set_title(title, fontsize=9, fontweight='bold')
            ax.set_xlabel('θ (angle)', fontsize=8)
            ax.set_ylabel('ρ (distance)', fontsize=8)
            ax.set_xticks([])
            ax.set_yticks([])
            ax.set_aspect('auto')

        for (ax, title) in self.spm_pred_axes:
            ax.set_title(title, fontsize=9, fontweight='bold')
            ax.set_xlabel('θ (angle)', fontsize=8)
            ax.set_ylabel('ρ (distance)', fontsize=8)
            ax.set_xticks([])
            ax.set_yticks([])
            ax.set_aspect('auto')

    def play_animation(self):
        """Play animation loop"""
        if not self.playing:
            return

        # Skip frames for faster playback (1 = normal speed, 2 = 2x, 3 = 3x, etc.)
        frame_skip = 2  # 2x speed by default
        self.current_step = (self.current_step + frame_skip) % self.n_steps
        self.time_slider.set_val(self.current_step)

        # Schedule next frame (20ms = 50 FPS, faster than real-time)
        self.fig.canvas.manager.window.after(20, self.play_animation)  # 50 FPS

    def on_click(self, event):
        """Handle mouse click on global map to select agent"""
        if event.inaxes != self.ax_global:
            return

        # Find nearest agent to click position
        click_pos = np.array([event.xdata, event.ydata])
        agent_positions = self.pos[self.current_step, :, :]  # [N, 2]

        distances = np.linalg.norm(agent_positions - click_pos, axis=1)
        nearest_idx = np.argmin(distances)

        # Only select if within reasonable distance
        if distances[nearest_idx] < 5.0:
            self.selected_agent_idx = nearest_idx
            print(f"Selected agent {self.selected_agent_idx}")
            self.update_display()

    def update_display(self):
        """Update all visualization panels"""
        t = self.current_step

        # Update global map
        agent_positions = self.pos[t, :, :]  # [N, 2]
        agent_headings = self.heading[t, :]  # [N]
        self.global_scatter.set_offsets(agent_positions)

        # Set colors: Red for selected agent, blue for others
        colors = np.array(['blue'] * self.n_agents)
        colors[self.selected_agent_idx] = 'red'
        self.global_scatter.set_color(colors)

        # Remove old direction triangles
        for triangle in self.agent_triangles:
            triangle.remove()
        self.agent_triangles.clear()

        # Remove old selected marker if exists
        if self.selected_marker is not None and self.selected_marker in self.ax_global.patches:
            self.selected_marker.remove()

        # Draw direction triangles for all agents
        size = 0.6  # Triangle size in meters (smaller to fit inside circle)
        # Base triangle vertices (pointing right, X+)
        # heading=0 corresponds to X+ direction (east), so base triangle points right
        base_triangle = np.array([
            [size, 0],              # Front vertex (pointing right, X+)
            [-size*0.5, -size*0.6], # Left-back vertex
            [-size*0.5, size*0.6]   # Right-back vertex
        ])

        for agent_idx in range(self.n_agents):
            pos = agent_positions[agent_idx, :]
            heading = agent_headings[agent_idx]

            # Rotate triangle to match heading direction
            cos_h = np.cos(heading)
            sin_h = np.sin(heading)
            rotation_matrix = np.array([[cos_h, -sin_h], [sin_h, cos_h]])
            rotated_triangle = base_triangle @ rotation_matrix.T

            # Translate to agent position
            triangle_vertices = rotated_triangle + pos

            # Color: White triangle for all agents (selected will have red circle)
            facecolor = 'white'
            edgecolor = 'gray'
            linewidth = 1
            zorder = 6

            # Selected agent: white triangle with slightly thicker edge
            if agent_idx == self.selected_agent_idx:
                edgecolor = 'darkred'
                linewidth = 2
                zorder = 10

            # Create and add triangle marker
            triangle = Polygon(triangle_vertices, closed=True,
                             facecolor=facecolor, edgecolor=edgecolor,
                             linewidth=linewidth, zorder=zorder, alpha=0.9)
            self.ax_global.add_patch(triangle)
            self.agent_triangles.append(triangle)

            # Store selected marker for reference
            if agent_idx == self.selected_agent_idx:
                self.selected_marker = triangle

        # NEW in v6.3: Highlight colliding agents with red border
        collision_at_t = self.collision[t, :]  # [N]
        colliding_mask = collision_at_t > 0
        if colliding_mask.any():
            colliding_positions = agent_positions[colliding_mask, :]
            self.collision_marker.set_offsets(colliding_positions)
        else:
            self.collision_marker.set_offsets(np.empty((0, 2)))

        # FOV visualization for selected agent (210° field of view)
        if self.fov_wedge is not None:
            self.fov_wedge.remove()

        ego_pos = self.pos[t, self.selected_agent_idx, :]
        ego_heading = self.heading[t, self.selected_agent_idx]

        # FOV: 210° = ±105° from heading direction
        fov_angle = 210.0  # degrees
        heading_deg = np.degrees(ego_heading)
        theta1 = heading_deg - fov_angle / 2.0
        theta2 = heading_deg + fov_angle / 2.0

        # Create FOV wedge (semi-transparent)
        self.fov_wedge = Wedge(
            center=(ego_pos[0], ego_pos[1]),
            r=self.max_sensing_distance,
            theta1=theta1,
            theta2=theta2,
            facecolor='yellow',
            alpha=0.15,
            edgecolor='orange',
            linewidth=1.5,
            linestyle='--',
            zorder=5
        )
        self.ax_global.add_patch(self.fov_wedge)

        # Update local map
        self.update_local_map(t)

        # Update SPM visualization
        self.update_spm_display(t)

        # Update info panel
        self.update_info_panel(t)

        # Redraw
        self.fig.canvas.draw_idle()

    def update_local_map(self, t):
        """Update local (agent-centered) map"""
        # Get ego agent state
        ego_pos = self.pos[t, self.selected_agent_idx, :]
        ego_heading = self.heading[t, self.selected_agent_idx]
        ego_vel = self.vel[t, self.selected_agent_idx, :]

        # Transform other agents to ego frame
        other_positions = self.pos[t, :, :]  # [N, 2]
        relative_positions = other_positions - ego_pos  # [N, 2]

        # Rotate to ego heading frame with agent facing upward (Y+ direction)
        # 1. Rotate by -ego_heading to align heading direction with X+ axis
        # 2. Rotate by +90° to make heading direction point to Y+ (upward)
        rotation_angle = -ego_heading + np.pi / 2.0
        cos_h = np.cos(rotation_angle)
        sin_h = np.sin(rotation_angle)
        rotation_matrix = np.array([[cos_h, -sin_h], [sin_h, cos_h]])

        relative_positions_rotated = relative_positions @ rotation_matrix.T

        # Filter agents within sensing range
        distances = np.linalg.norm(relative_positions_rotated, axis=1)
        in_range = (distances < self.max_sensing_distance) & (distances > 0.1)  # Exclude ego

        visible_positions = relative_positions_rotated[in_range, :]
        self.local_scatter.set_offsets(visible_positions)

        # Transform obstacles to ego frame (use same rotation as agents)
        if self.obstacles.shape[0] > 0:
            relative_obstacles = self.obstacles - ego_pos
            relative_obstacles_rotated = relative_obstacles @ rotation_matrix.T

            # Filter obstacles within sensing range
            obs_distances = np.linalg.norm(relative_obstacles_rotated, axis=1)
            obs_in_range = obs_distances < self.max_sensing_distance

            visible_obstacles = relative_obstacles_rotated[obs_in_range, :]
            self.local_obstacles_scatter.set_offsets(visible_obstacles)
        else:
            self.local_obstacles_scatter.set_offsets(np.empty((0, 2)))

        # Update goal direction arrow
        # goal is a direction vector (unit vector) in world frame
        goal_direction_world = self.goal[self.selected_agent_idx, :]  # [2]

        # Transform goal direction to ego frame (rotate only, no translation for direction vectors)
        goal_direction_rotated = rotation_matrix @ goal_direction_world

        # Scale arrow for visibility (3m length)
        arrow_length = 3.0
        goal_arrow_end = goal_direction_rotated * arrow_length

        # Remove old arrow and add new one
        if hasattr(self, 'goal_arrow') and self.goal_arrow in self.ax_local.patches:
            self.goal_arrow.remove()

        self.goal_arrow = self.ax_local.arrow(0, 0, goal_arrow_end[0], goal_arrow_end[1],
                                              head_width=0.8, head_length=0.5,
                                              fc='green', ec='darkgreen',
                                              linewidth=2, alpha=0.7,
                                              zorder=9)

    def update_spm_display(self, t):
        """Reconstruct and display SPM for selected agent"""
        # Get ego agent state
        ego_pos = self.pos[t, self.selected_agent_idx, :]
        ego_heading = self.heading[t, self.selected_agent_idx]
        ego_velocity = self.vel[t, self.selected_agent_idx, :]  # For obstacle collision risk

        # Get all agent states at timestep t
        all_positions = self.pos[t, :, :]  # [N, 2]
        all_velocities = self.vel[t, :, :]  # [N, 2]

        # Reconstruct SPM with correct r_agent and world_size for toroidal distance calculation
        spm = reconstruct_spm_3ch(
            ego_pos,
            ego_heading,
            all_positions,
            all_velocities,
            self.obstacles,
            self.spm_config,
            r_agent=self.spm_config.r_agent,
            world_size=self.world_size,
            ego_velocity=ego_velocity  # Pass ego velocity for TTC-based obstacle risk
        )

        # Display real SPM channels
        for ch_idx, (ax, title) in enumerate(self.spm_real_axes):
            channel_data = spm[:, :, ch_idx]

            if self.spm_real_images[ch_idx] is None:
                # Create initial image
                im = ax.imshow(channel_data, aspect='auto', origin='lower',
                              cmap='hot', interpolation='nearest', vmin=0, vmax=1)
                self.spm_real_images[ch_idx] = im
                # Store colorbar reference to axis to avoid duplicates
                cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
                ax.cbar = cbar
            else:
                # Update existing image
                self.spm_real_images[ch_idx].set_data(channel_data)
                # Update colorbar limits if needed
                self.spm_real_images[ch_idx].set_clim(0, 1)

        # Predicted SPM (not yet implemented)
        for ch_idx, (ax, title) in enumerate(self.spm_pred_axes):
            if self.spm_pred_images[ch_idx] is None:
                # Show placeholder
                placeholder = np.zeros_like(spm[:, :, 0])
                im = ax.imshow(placeholder, aspect='auto', origin='lower',
                              cmap='hot', interpolation='nearest', vmin=0, vmax=1)
                self.spm_pred_images[ch_idx] = im
                ax.text(0.5, 0.5, 'VAE Prediction\nNot Available',
                       ha='center', va='center', transform=ax.transAxes,
                       fontsize=10, color='white', fontweight='bold')

    def update_info_panel(self, t):
        """Update info text panel"""
        ego_pos = self.pos[t, self.selected_agent_idx, :]
        ego_vel = self.vel[t, self.selected_agent_idx, :]
        ego_u = self.u[t, self.selected_agent_idx, :]
        ego_heading = self.heading[t, self.selected_agent_idx]

        speed = np.linalg.norm(ego_vel)

        # NEW in v6.3: Goal and collision status
        ego_goal = self.goal[self.selected_agent_idx, :]
        ego_group = self.group[self.selected_agent_idx]
        ego_collision = self.collision[t, self.selected_agent_idx]
        ego_near_collision = self.near_collision[t, self.selected_agent_idx]

        # Group IDs are 1-based in dynamics.jl: NORTH=1, SOUTH=2, EAST=3, WEST=4
        group_names = {1: "NORTH", 2: "SOUTH", 3: "EAST", 4: "WEST"}
        group_name = group_names.get(ego_group, f"Group{ego_group}")

        collision_status = "⚠️ COLLISION" if ego_collision else ("⚡ Near" if ego_near_collision else "✅ Safe")
        collision_color = 'red' if ego_collision else ('orange' if ego_near_collision else 'green')

        info_str = f"""Step: {t}/{self.n_steps-1}
Agent: {self.selected_agent_idx}/{self.n_agents-1}
Group: {group_name}

Position:
  x: {ego_pos[0]:7.2f} m
  y: {ego_pos[1]:7.2f} m

Goal:
  x: {ego_goal[0]:7.2f} m
  y: {ego_goal[1]:7.2f} m

Velocity:
  vx: {ego_vel[0]:6.2f} m/s
  vy: {ego_vel[1]:6.2f} m/s
  |v|: {speed:5.2f} m/s

Control:
  v: {ego_u[0]:6.2f} m/s
  ω: {ego_u[1]:6.2f} rad/s

Heading: {np.degrees(ego_heading):6.1f}°

Status: {collision_status}
"""
        self.info_text.set_text(info_str)
        self.info_text.set_color(collision_color)

    def run(self):
        """Run the viewer"""
        plt.show()


def main():
    parser = argparse.ArgumentParser(
        description='Raw V6.3 Trajectory Viewer (Controller-Bias-Free)',
        epilog='If no file is specified, a GUI file selector will open.'
    )
    parser.add_argument('h5_file', type=str, nargs='?', default=None,
                       help='Path to HDF5 trajectory file (optional)')
    parser.add_argument('--no-gui', action='store_true',
                       help='Disable GUI file selector (use default file if no path given)')

    args = parser.parse_args()

    h5_file_path = None

    # If file specified via command line
    if args.h5_file:
        # Resolve path
        if not os.path.isabs(args.h5_file):
            script_dir = Path(__file__).parent.parent
            h5_file_path = script_dir / args.h5_file
        else:
            h5_file_path = Path(args.h5_file)

        if not h5_file_path.exists():
            print(f"Error: File not found: {h5_file_path}")
            sys.exit(1)

        h5_file_path = str(h5_file_path)
    elif args.no_gui:
        # Use default file without GUI
        script_dir = Path(__file__).parent.parent
        # Look for the first v6.3 sample file
        default_files = [
            'data/vae_training/raw_v63/v63_scramble_d10_s1_*.h5',
            'data/vae_training/raw_v63/v63_corridor_w40_d15_s1_*.h5'
        ]
        h5_file_path = None
        for pattern in default_files:
            import glob
            matches = glob.glob(str(script_dir / pattern))
            if matches:
                h5_file_path = Path(matches[0])
                break

        if h5_file_path is None or not h5_file_path.exists():
            print(f"Error: No default v6.3 files found in data/vae_training/raw_v63/")
            print("Please specify a file path or use GUI file selector (omit --no-gui)")
            sys.exit(1)

        h5_file_path = str(h5_file_path)
    # else: h5_file_path remains None, will trigger GUI file selector in viewer

    # Launch viewer (will show file selector if h5_file_path is None)
    viewer = RawV63Viewer(h5_file_path)
    viewer.run()


if __name__ == '__main__':
    main()
