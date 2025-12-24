#!/usr/bin/env python3
"""
Detail Viewer for EPH Simulation
Displays SPM 3-channel visualization and metrics for selected agent
"""

import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.gridspec import GridSpec
import sys
import os
import traceback

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from viewer.zmq_client import ZMQClient

# Configuration constants (must match backend config in src/config.jl)
SENSING_RATIO = 7.5  # Changed from 15.0 to 7.5 (halved)
R_ROBOT = 1.5
R_AGENT = 1.5
MAX_SENSING_DISTANCE = SENSING_RATIO * (R_ROBOT + R_AGENT)  # 7.5 * 3.0 = 22.5


class DetailViewer:
    """Detail visualization for selected agent"""
    
    def __init__(self, history_length=200):
        """
        Initialize detail viewer
        
        Args:
            history_length: Number of steps to keep in history plots
        """
        self.history_length = history_length
        
        # ZMQ client
        self.client = ZMQClient()
        self.client.subscribe("detail")
        
        # Data storage
        self.step = 0
        self.agent_id = None
        self.spm = None
        
        # History buffers
        self.step_history = []
        self.fe_history = []
        self.action_x_history = []
        self.action_y_history = []
        self.vae_error_history = []  # Stores Precision (Π = 1/H) values
        
        # Group colors matches MainViewer
        self.group_colors = {
            1: 'blue',      # North
            2: 'red',       # South
            3: 'green',     # East
            4: 'magenta'    # West
        }
        
        # Setup plot
        self.fig = plt.figure(figsize=(12, 9))  # Reduced from (16, 12) for compact display
        self.fig.suptitle("EPH Detail Viewer - Agent SPM & Metrics", fontsize=14, fontweight='bold')
        
        # Create grid layout: 4 rows x 4 columns
        gs = GridSpec(4, 4, figure=self.fig, hspace=0.4, wspace=0.3)
        
        # Row 1: Visualization Dashboard (Local Map + 3 SPMs)
        # Column 0: Local Map
        self.ax_local_map = self.fig.add_subplot(gs[0, 0])
        # Column 1-3: SPM Channels
        self.ax_spm1 = self.fig.add_subplot(gs[0, 1])
        self.ax_spm2 = self.fig.add_subplot(gs[0, 2])
        self.ax_spm3 = self.fig.add_subplot(gs[0, 3])
        
        # Row 2: Free Energy plot (full width)
        self.ax_fe = self.fig.add_subplot(gs[1, :])
        
        # Row 3: Control Action plot (full width)
        self.ax_action = self.fig.add_subplot(gs[2, :])
        
        # Row 4: VAE Prediction Error plot (full width)
        self.ax_vae = self.fig.add_subplot(gs[3, :])
        
        # Configure SPM axes
        for ax, title in zip(
            [self.ax_spm1, self.ax_spm2, self.ax_spm3],
            ['Ch1: Occupancy', 'Ch2: Proximity Saliency', 'Ch3: Collision Risk']
        ):
            ax.set_title(title, fontsize=9, fontweight='bold')
            ax.set_xlabel('θ (angle)', fontsize=8)
            ax.set_ylabel('ρ (log distance)', fontsize=8)
            ax.set_aspect('equal')
        
        # Configure local map
        self.ax_local_map.set_title('Local View (Forward=Up)', fontsize=9, fontweight='bold')
        self.ax_local_map.set_xlabel('X (local)', fontsize=8)
        self.ax_local_map.set_ylabel('Y (local)', fontsize=8)
        self.ax_local_map.set_xlim(-25, 25)
        self.ax_local_map.set_ylim(-10, 40)
        self.ax_local_map.set_aspect('equal')
        self.ax_local_map.grid(True, alpha=0.3)
        self.ax_local_map.axhline(0, color='k', linewidth=0.5)
        self.ax_local_map.axvline(0, color='k', linewidth=0.5)
        
        # Configure metrics axes
        self.ax_fe.set_title('Free Energy', fontsize=9, fontweight='bold')
        self.ax_fe.set_xlabel('Step', fontsize=8)
        self.ax_fe.set_ylabel('F', fontsize=8)
        self.ax_fe.grid(True, alpha=0.3)
        
        self.ax_action.set_title('Control Action', fontsize=9, fontweight='bold')
        self.ax_action.set_xlabel('Step', fontsize=8)
        self.ax_action.set_ylabel('u', fontsize=8)
        self.ax_action.grid(True, alpha=0.3)
        
        self.ax_vae.set_title('Precision (Π = 1/H)', fontsize=9, fontweight='bold')
        self.ax_vae.set_xlabel('Step', fontsize=8)
        self.ax_vae.set_ylabel('Precision', fontsize=8)
        self.ax_vae.grid(True, alpha=0.3)
        
        # Initialize plots
        self.im1 = None
        self.im2 = None
        self.im3 = None
        self.local_scatter = None
        self.ego_marker = None
        self.line_fe = None
        self.line_ux = None
        self.line_uy = None
        self.line_vae = None
        
        print("🎨 Detail Viewer initialized")
    
    def update(self, frame):
        """Update plot animation"""
        try:
            # Receive data
            msg = self.client.receive()
            
            if msg is not None:
                topic, data = msg
                
                self.agent_id = data["agent_id"]
                self.spm = data["spm"]
                self.step = data["step"]
                
                # DEBUG: Check data reception
                if frame % 30 == 0:
                    print(f"Viewer received step {self.step}, SPM shape {np.shape(self.spm)}")

                # SPM Visualization
                # theta_grid: -105° (index 0, right) to +105° (index 15, left)
                # Display: Left side of plot should show left (+105°), right side should show right (-105°)
                # Therefore: extent = [-105, 105] and NO flip needed
                spm_array = np.array(self.spm)
                
                # (Removed debug SPM statistics logging)
                
                action = data["action"]
                fe = data["free_energy"]
                haze = data.get("haze", 0.0)  # Default to 0.0 if not present
                # Compute Precision from Haze: Π = 1/(H + ε)
                epsilon = 1e-6
                precision = 1.0 / (haze + epsilon) if haze > 0 else 1.0 / epsilon
                
                # Extent: [Left_Val, Right_Val, Bottom, Top]
                # Left side of plot = -105° (right in ego frame)
                # Right side of plot = +105° (left in ego frame)
                extent_args = [-105, 105, 0, 15]

                # Update channel 1
                if self.im1 is None:
                    self.im1 = self.ax_spm1.imshow(spm_array[:, :, 0], 
                                                   cmap='hot', origin='lower', 
                                                   extent=extent_args,
                                                   vmin=0, vmax=1, aspect='auto')
                    self.fig.colorbar(self.im1, ax=self.ax_spm1, fraction=0.046)
                else:
                    self.im1.set_data(spm_array[:, :, 0])
                
                # Update channel 2
                if self.im2 is None:
                    self.im2 = self.ax_spm2.imshow(spm_array[:, :, 1], 
                                                   cmap='viridis', origin='lower', 
                                                   extent=[105, -105, 0, 15],
                                                   vmin=0, vmax=1, aspect='auto')
                    self.fig.colorbar(self.im2, ax=self.ax_spm2, fraction=0.046)
                else:
                    self.im2.set_data(spm_array[:, :, 1])
                
                # Update channel 3
                if self.im3 is None:
                    self.im3 = self.ax_spm3.imshow(spm_array[:, :, 2], 
                                                   cmap='plasma', origin='lower', 
                                                   extent=[105, -105, 0, 15],
                                                   vmin=0, vmax=1, aspect='auto')
                    self.fig.colorbar(self.im3, ax=self.ax_spm3, fraction=0.046)
                else:
                    self.im3.set_data(spm_array[:, :, 2])
            
                # Update local map (agent-centric view)
                # Get other agents' positions in local coordinates
                if 'local_agents' in data:
                    local_agents = data['local_agents']  # List of [x, y] in local frame
                    
                    # DEBUG: Log received data - use print with flush for immediate output
                    if self.step % 100 == 0:
                        print(f"DEBUG: Step {self.step}: Received {len(local_agents)} local_agents", flush=True)
                    
                    # Clear and redraw
                    self.ax_local_map.clear()
                    self.ax_local_map.set_title('Local View (Forward=Up)', fontsize=9, fontweight='bold')
                    self.ax_local_map.set_xlabel('X (local)', fontsize=8)
                    self.ax_local_map.set_ylabel('Y (local)', fontsize=8)
                    self.ax_local_map.set_xlim(-25, 25)
                    self.ax_local_map.set_ylim(-10, 40)
                    self.ax_local_map.set_aspect('equal')
                    self.ax_local_map.grid(True, alpha=0.3)
                    self.ax_local_map.axhline(0, color='k', linewidth=0.5)
                    self.ax_local_map.axvline(0, color='k', linewidth=0.5)
                    
                    # Plot ego agent at origin
                    self.ax_local_map.plot(0, 0, 'ro', markersize=10, label='Ego')
                    
                    # Plot all agents (already filtered by backend for FOV and sensing range)
                    if len(local_agents) > 0:
                        visible_colors = []
                        visible_xs = []
                        visible_ys = []
                        
                        for agent_data in local_agents:
                            try:
                                # Parse data (includes group id)
                                if len(agent_data) >= 3:
                                    x, y, group_id = agent_data[0], agent_data[1], int(agent_data[2])
                                else:
                                    x, y = agent_data[0], agent_data[1]
                                    group_id = 1  # Default
                                
                                visible_xs.append(x)
                                visible_ys.append(y)
                                visible_colors.append(self.group_colors.get(group_id, 'grey'))
                            except Exception as e:
                                print(f"Error processing agent data: {e}")
                                continue
                        
                        if len(visible_xs) > 0:
                            self.ax_local_map.scatter(visible_xs, visible_ys, 
                                                     c=visible_colors, s=50, alpha=0.8, edgecolors='white', linewidth=0.5, label='Others')
                    
                    # Draw FOV cone (210 degrees, centered on +Y axis = 90 degrees in matplotlib)
                    # Matplotlib Wedge: 0 degrees = +X (right), counterclockwise
                    # +Y axis = 90 degrees
                    # FOV: 90 - 105 = -15 to 90 + 105 = 195 degrees
                    from matplotlib.patches import Wedge
                    fov_cone = Wedge((0, 0), MAX_SENSING_DISTANCE, -15, 195, alpha=0.1, facecolor='cyan', edgecolor='cyan', linewidth=1)
                    self.ax_local_map.add_patch(fov_cone)
                    
                    self.ax_local_map.legend(fontsize=8)
                
                # Update history
                self.step_history.append(self.step)
                self.fe_history.append(fe)
                self.action_x_history.append(action[0])
                self.action_y_history.append(action[1])
                self.vae_error_history.append(precision)  # Now stores Precision values (Π = 1/H)
                
                # Trim history
                if len(self.step_history) > self.history_length:
                    self.step_history = self.step_history[-self.history_length:]
                    self.fe_history = self.fe_history[-self.history_length:]
                    self.action_x_history = self.action_x_history[-self.history_length:]
                    self.action_y_history = self.action_y_history[-self.history_length:]
                    self.vae_error_history = self.vae_error_history[-self.history_length:]
                
                # Update free energy plot
                if self.line_fe is None:
                    self.line_fe, = self.ax_fe.plot(self.step_history, self.fe_history, 
                                                     'b-', linewidth=1.5, label='F')
                    self.ax_fe.legend(fontsize=8)
                else:
                    self.line_fe.set_data(self.step_history, self.fe_history)
                    self.ax_fe.relim()
                    self.ax_fe.autoscale_view()
                
                # Update action plot
                if self.line_ux is None:
                    self.line_ux, = self.ax_action.plot(self.step_history, self.action_x_history, 
                                                         'r-', linewidth=1.5, label='u_x')
                    self.line_uy, = self.ax_action.plot(self.step_history, self.action_y_history, 
                                                         'g-', linewidth=1.5, label='u_y')
                    self.ax_action.legend(fontsize=8)
                else:
                    self.line_ux.set_data(self.step_history, self.action_x_history)
                    self.line_uy.set_data(self.step_history, self.action_y_history)
                    self.ax_action.relim()
                    self.ax_action.autoscale_view()
                
                # Update Precision plot
                if self.line_vae is None:
                    self.line_vae, = self.ax_vae.plot(self.step_history, self.vae_error_history,
                                                      'm-', linewidth=1.5, label='Precision')
                    self.ax_vae.legend(fontsize=8)
                else:
                    self.line_vae.set_data(self.step_history, self.vae_error_history)
                    self.ax_vae.relim()
                    self.ax_vae.autoscale_view()
                
                # Update title with agent info
                self.fig.suptitle(f"EPH Detail Viewer - Agent {self.agent_id} | Step {self.step}", 
                                 fontsize=14, fontweight='bold')
        except Exception as e:
            print(f"Error in update loop: {e}")
            traceback.print_exc()
        
        artists = []
        if self.im1: artists.append(self.im1)
        if self.im2: artists.append(self.im2)
        if self.im3: artists.append(self.im3)
        if self.line_fe: artists.append(self.line_fe)
        if self.line_ux: artists.append(self.line_ux)
        if self.line_uy: artists.append(self.line_uy)
        if self.line_vae: artists.append(self.line_vae)
        
        return artists
    
    def run(self):
        """Start animation"""
        print("▶️  Starting detail viewer...")
        print("   Close window to exit\n")
        
        # Create animation
        anim = FuncAnimation(
            self.fig,
            self.update,
            interval=33,  # ~30 FPS
            blit=False,  # Disable blit for complex updates
            cache_frame_data=False
        )
        
        plt.tight_layout()
        plt.show()
        
        # Cleanup
        self.client.close()
        print("✅ Detail viewer closed")


if __name__ == "__main__":
    viewer = DetailViewer()
    viewer.run()
