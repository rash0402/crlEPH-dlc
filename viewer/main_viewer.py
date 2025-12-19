#!/usr/bin/env python3
"""
Main Viewer for EPH Simulation
Displays 4-group scramble crossing in torus world
"""

import zmq
import msgpack
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.patches import Circle, Rectangle
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from viewer.zmq_client import ZMQClient


class MainViewer:
    """Main visualization for 4-group simulation"""
    
    def __init__(self, world_width=100.0, world_height=100.0):
        """
        Initialize viewer
        
        Args:
            world_width: Torus world width
            world_height: Torus world height
        """
        self.world_width = world_width
        self.world_height = world_height
        
        # ZMQ client
        self.client = ZMQClient()
        self.client.subscribe("global")
        
        # Define colors for each group
        self.group_colors = {
            1: 'blue',
            2: 'red',
            3: 'green',
            4: 'magenta' 
        }
        
        # Data storage
        self.positions = []
        self.colors = [] # This will store the actual matplotlib colors for each agent
        self.step = 0
        
        # Setup plot
        self.fig, self.ax = plt.subplots(figsize=(10, 10))
        self.fig.suptitle("EPH Simulation - 4-Group Scramble Crossing", fontsize=14, fontweight='bold')
        
        self.ax.set_xlim(0, world_width)
        self.ax.set_ylim(0, world_height)
        self.ax.set_aspect('equal')
        self.ax.set_xlabel('X Position')
        self.ax.set_ylabel('Y Position')
        self.ax.grid(True, alpha=0.3)
        
        # Add corner obstacles (15x15 squares)
        obstacle_size = 15.0
        obstacle_color = 'gray'
        obstacle_alpha = 0.5
        
        from matplotlib.patches import Rectangle
        
        # Bottom-left
        self.ax.add_patch(Rectangle((0, 0), obstacle_size, obstacle_size, 
                                    facecolor=obstacle_color, alpha=obstacle_alpha, edgecolor='black'))
        # Bottom-right
        self.ax.add_patch(Rectangle((world_width - obstacle_size, 0), obstacle_size, obstacle_size,
                                    facecolor=obstacle_color, alpha=obstacle_alpha, edgecolor='black'))
        # Top-left
        self.ax.add_patch(Rectangle((0, world_height - obstacle_size), obstacle_size, obstacle_size,
                                    facecolor=obstacle_color, alpha=obstacle_alpha, edgecolor='black'))
        # Top-right
        self.ax.add_patch(Rectangle((world_width - obstacle_size, world_height - obstacle_size), 
                                    obstacle_size, obstacle_size,
                                    facecolor=obstacle_color, alpha=obstacle_alpha, edgecolor='black'))
        
        # Add group labels
        self.ax.text(world_width/2, world_height*0.95, 'NORTH (Blue) ↓', 
                    ha='center', va='top', fontsize=10, color='blue', fontweight='bold')
        self.ax.text(world_width/2, world_height*0.05, 'SOUTH (Red) ↑', 
                    ha='center', va='bottom', fontsize=10, color='red', fontweight='bold')
        self.ax.text(world_width*0.05, world_height/2, 'EAST (Green) →', 
                    ha='left', va='center', fontsize=10, color='green', fontweight='bold', rotation=90)
        self.ax.text(world_width*0.95, world_height/2, 'WEST (Magenta) ←', 
                    ha='right', va='center', fontsize=10, color='magenta', fontweight='bold', rotation=90)
        
        # Scatter plot for agents
        self.scatter = self.ax.scatter([], [], s=100, alpha=0.7, edgecolors='black', linewidths=0.5)
        
        # Highlight for detail agent
        self.detail_agent_id = 1  # Agent being monitored in detail viewer
        self.detail_highlight = Circle((0, 0), 2.0, fill=False, edgecolor='red', linewidth=3, linestyle='--', visible=False)
        self.ax.add_patch(self.detail_highlight)
        
        # FOV wedge for detail agent
        from matplotlib.patches import Wedge
        self.fov_wedge = Wedge((0, 0), 20.0, 0, 210, alpha=0.15, facecolor='cyan', edgecolor='cyan', linewidth=2, visible=False)
        self.ax.add_patch(self.fov_wedge)
        
        # Step counter
        self.step_text = self.ax.text(0.02, 0.98, '', transform=self.ax.transAxes,
                                     fontsize=12, verticalalignment='top',
                                     bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
        
        print("🎨 Main Viewer initialized")
    
    def update(self, frame):
        """Update animation frame"""
        # Receive data
        msg = self.client.receive()
        
        if msg:
            topic, data = msg
            
            if topic == "global":
                self.step = data['step']
                self.positions = data['positions']
                self.velocities = data.get('velocities', [])
                self.colors = data['colors']
                
                # Update scatter plot
                if self.positions:
                    pos_array = np.array(self.positions)
                    self.scatter.set_offsets(pos_array)
                    self.scatter.set_color(self.colors)
                    
                    # Update detail agent highlight and FOV
                    if len(self.positions) >= self.detail_agent_id:
                        detail_pos = self.positions[self.detail_agent_id - 1]
                        self.detail_highlight.center = detail_pos
                        self.detail_highlight.set_visible(True)
                        
                        # Update FOV wedge with velocity-based orientation
                        self.fov_wedge.center = detail_pos
                        
                        # Calculate orientation from velocity
                        if len(self.velocities) >= self.detail_agent_id:
                            detail_vel = self.velocities[self.detail_agent_id - 1]
                            if np.linalg.norm(detail_vel) > 0.001:  # Only if moving
                                # Calculate angle in degrees (0 = right, counterclockwise)
                                angle_rad = np.arctan2(detail_vel[1], detail_vel[0])
                                angle_deg = np.degrees(angle_rad)
                                
                                # FOV is 210 degrees, centered on velocity direction
                                # theta1 = angle - 105, theta2 = angle + 105
                                theta1 = angle_deg - 105
                                theta2 = angle_deg + 105
                                
                                self.fov_wedge.set_theta1(theta1)
                                self.fov_wedge.set_theta2(theta2)
                        
                        self.fov_wedge.set_visible(True)
                
                # Update step counter
                self.step_text.set_text(f'Step: {self.step}\nAgents: {len(self.positions)}\nDetail: Agent #{self.detail_agent_id}')
        
        return self.scatter, self.step_text, self.detail_highlight, self.fov_wedge
    
    def run(self):
        """Start animation"""
        print("▶️  Starting main viewer...")
        print("   Close window to exit\n")
        
        # Create animation
        anim = FuncAnimation(
            self.fig,
            self.update,
            interval=33,  # ~30 FPS
            blit=True,
            cache_frame_data=False
        )
        
        plt.tight_layout()
        plt.show()
        
        # Cleanup
        self.client.close()
        print("✅ Main viewer closed")


if __name__ == "__main__":
    viewer = MainViewer()
    viewer.run()
