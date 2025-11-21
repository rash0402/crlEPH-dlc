"""Scramble crossing with real-time SPM visualization."""
import sys
import random
import numpy as np
import pygame
import matplotlib.pyplot as plt
from matplotlib.backends.backend_agg import FigureCanvasAgg
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

class DualVisualizer:
    def __init__(self, environment, width=800, height=800):
        self.environment = environment
        self.width = width
        self.height = height
        
        # Pygame for main simulation
        pygame.init()
        # Main window + SPM visualization side by side
        self.screen = pygame.display.set_mode((self.width + 600, self.height))
        pygame.display.set_caption("Scramble Crossing + SPM Visualization")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("Arial", 14)
        
        # Matplotlib figure for SPM
        self.fig, self.axes = plt.subplots(2, 2, figsize=(6, 8))
        self.fig.tight_layout(pad=2.0)
        self.canvas = FigureCanvasAgg(self.fig)
        
        # Target agent (will be set to first red agent)
        self.target_agent = None
        
    def set_target_agent(self, agent):
        self.target_agent = agent
        
    def handle_events(self):
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return False
        return True
    
    def render(self):
        # Clear screen
        self.screen.fill((30, 30, 30))
        
        # Draw main simulation (left side)
        self._draw_simulation()
        
        # Draw SPM visualization (right side)
        if self.target_agent and self.target_agent.current_spm is not None:
            self._draw_spm_panel()
        
        # Update display
        pygame.display.flip()
        self.clock.tick(30)
    
    def _draw_simulation(self):
        """Draw the scramble crossing simulation."""
        # Draw agents
        for agent in self.environment.agents:
            scale_x = self.width / self.environment.width
            scale_y = self.height / self.environment.height
            
            x = int((agent.position[0] % self.environment.width) * scale_x)
            y = int((agent.position[1] % self.environment.height) * scale_y)
            
            # Target agent is red, others are blue
            if agent is self.target_agent:
                color = (255, 100, 100)  # Red
            else:
                color = (100, 100, 255)  # Blue
            
            pygame.draw.circle(self.screen, color, (x, y), int(agent.radius * scale_x))
            
            # Direction indicator
            end_x = int(x + np.cos(agent.orientation) * agent.radius * 1.5 * scale_x)
            end_y = int(y + np.sin(agent.orientation) * agent.radius * 1.5 * scale_y)
            pygame.draw.line(self.screen, (255, 255, 100), (x, y), (end_x, end_y), 2)
        
        # FPS
        fps = self.clock.get_fps()
        fps_text = self.font.render(f"FPS: {fps:.1f}", True, (255, 255, 255))
        self.screen.blit(fps_text, (10, 10))
    
    def _draw_spm_panel(self):
        """Draw SPM visualization on the right side."""
        # Clear previous plots
        for ax in self.axes.flat:
            ax.clear()
        
        spm = self.target_agent.current_spm
        precision = self.target_agent.current_precision
        Nr, Ntheta = spm.shape[1], spm.shape[2]
        
        # 1. Occupancy (polar)
        ax = self.axes[0, 0]
        theta = np.linspace(-np.pi, np.pi, Ntheta + 1)
        r = np.arange(Nr + 1)
        im = ax.pcolormesh(theta, r, spm[0], cmap='hot', shading='auto', vmin=0, vmax=1)
        ax.set_title('Occupancy (Polar)', fontsize=10)
        ax.set_xlabel('Angle', fontsize=8)
        ax.set_ylabel('Distance', fontsize=8)
        ax.tick_params(labelsize=7)
        
        # 2. Cartesian field of view
        ax = self.axes[0, 1]
        self._draw_cartesian_fov(ax)
        
        # 3. Precision Matrix
        ax = self.axes[1, 0]
        im = ax.pcolormesh(theta, r, precision, cmap='viridis', shading='auto')
        ax.set_title('Precision Matrix', fontsize=10)
        ax.set_xlabel('Angle', fontsize=8)
        ax.set_ylabel('Distance', fontsize=8)
        ax.tick_params(labelsize=7)
        
        # 4. Radial Velocity
        ax = self.axes[1, 1]
        im = ax.pcolormesh(theta, r, spm[1], cmap='RdBu_r', shading='auto', vmin=-1, vmax=1)
        ax.set_title('Radial Velocity', fontsize=10)
        ax.set_xlabel('Angle', fontsize=8)
        ax.set_ylabel('Distance', fontsize=8)
        ax.tick_params(labelsize=7)
        
        # Render matplotlib to pygame surface
        self.canvas.draw()
        
        # Get the RGBA buffer from the figure
        buf = self.canvas.buffer_rgba()
        size = self.canvas.get_width_height()
        
        # Convert to pygame surface
        surf = pygame.image.frombuffer(buf, size, "RGBA")
        # Scale to fit
        surf = pygame.transform.scale(surf, (600, self.height))
        self.screen.blit(surf, (self.width, 0))

    
    def _draw_cartesian_fov(self, ax):
        """Draw field of view in Cartesian coordinates."""
        # Create a 2D grid showing what the agent sees
        fov_size = 300  # Size of FOV in pixels
        grid_size = 60  # Grid resolution
        
        # Agent at center
        agent_x, agent_y = self.target_agent.position
        agent_theta = self.target_agent.orientation
        
        # Create grid
        x_range = np.linspace(-fov_size/2, fov_size/2, grid_size)
        y_range = np.linspace(-fov_size/2, fov_size/2, grid_size)
        occupancy_grid = np.zeros((grid_size, grid_size))
        
        # Fill grid based on other agents
        for other in self.environment.agents:
            if other is self.target_agent:
                continue
            
            # Relative position
            dx = other.position[0] - agent_x
            dy = other.position[1] - agent_y
            
            # Rotate to agent frame
            rel_x = dx * np.cos(-agent_theta) - dy * np.sin(-agent_theta)
            rel_y = dx * np.sin(-agent_theta) + dy * np.cos(-agent_theta)
            
            # Map to grid
            if abs(rel_x) < fov_size/2 and abs(rel_y) < fov_size/2:
                grid_x = int((rel_x + fov_size/2) / fov_size * grid_size)
                grid_y = int((rel_y + fov_size/2) / fov_size * grid_size)
                if 0 <= grid_x < grid_size and 0 <= grid_y < grid_size:
                    occupancy_grid[grid_size - 1 - grid_y, grid_x] = 1.0
        
        # Plot
        ax.imshow(occupancy_grid, cmap='hot', extent=[-fov_size/2, fov_size/2, -fov_size/2, fov_size/2], origin='lower')
        ax.plot(0, 0, 'r*', markersize=10)  # Agent position
        ax.arrow(0, 0, 30, 0, head_width=10, head_length=10, fc='yellow', ec='yellow')  # Direction
        ax.set_title('Cartesian FOV', fontsize=10)
        ax.set_xlabel('X (agent frame)', fontsize=8)
        ax.set_ylabel('Y (agent frame)', fontsize=8)
        ax.tick_params(labelsize=7)
        ax.set_xlim(-fov_size/2, fov_size/2)
        ax.set_ylim(-fov_size/2, fov_size/2)

def main():
    # Setup environment
    width, height = 800, 800
    env = Environment(width=width, height=height)
    
    center_x, center_y = width // 2, height // 2
    agents_per_direction = 5
    spawn_distance = 150
    
    directions = [
        {'name': 'North', 'spawn': (center_x, center_y - spawn_distance), 'goal': (center_x, center_y + spawn_distance)},
        {'name': 'South', 'spawn': (center_x, center_y + spawn_distance), 'goal': (center_x, center_y - spawn_distance)},
        {'name': 'East', 'spawn': (center_x + spawn_distance, center_y), 'goal': (center_x - spawn_distance, center_y)},
        {'name': 'West', 'spawn': (center_x - spawn_distance, center_y), 'goal': (center_x + spawn_distance, center_y)},
    ]
    
    target_agent = None
    
    # Add agents
    for direction in directions:
        for i in range(agents_per_direction):
            if direction['name'] in ['North', 'South']:
                x = direction['spawn'][0] + random.uniform(-30, 30)
                y = direction['spawn'][1] + random.uniform(-20, 20)
            else:
                x = direction['spawn'][0] + random.uniform(-20, 20)
                y = direction['spawn'][1] + random.uniform(-30, 30)
            
            agent = Agent(x, y, theta=random.uniform(-np.pi, np.pi))
            goal_x = direction['goal'][0] + random.uniform(-30, 30)
            goal_y = direction['goal'][1] + random.uniform(-30, 30)
            agent.goal = (goal_x, goal_y)
            agent.personal_space = random.uniform(15.0, 35.0)
            agent.spm_module = SaliencyPolarMap()
            agent.controller = GradientEPHController(agent, learning_rate=0.5, n_iterations=5)
            env.add_agent(agent)
            
            # First agent is target
            if target_agent is None:
                target_agent = agent
    
    # Initialize
    sim = Simulator(env)
    vis = DualVisualizer(env, width, height)
    vis.set_target_agent(target_agent)
    
    # Main loop
    running = True
    while running:
        if not vis.handle_events():
            running = False
            break
        
        sim.step()
        # Randomly vary personal space of target to see precision matrix update
        if vis.target_agent:
            vis.target_agent.personal_space = random.uniform(15.0, 35.0)
            # Recompute SPM and precision for the updated personal space
            vis.target_agent.sense(env)
            # Debug: print precision matrix summary
            print('Precision sum:', np.sum(vis.target_agent.current_precision))
        
        vis.render()
    
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()

