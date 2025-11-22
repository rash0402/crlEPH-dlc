"""Scramble crossing simulation with gradient-based EPH controller."""
import sys
import random
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.utils.visualization import Visualizer
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

def main():
    # Initialize Environment (Scramble Crossing)
    width, height = 800, 800
    env = Environment(width=width, height=height)
    
    # NO OBSTACLES - just agents crossing each other
    
    # Center of crossing
    center_x, center_y = width // 2, height // 2
    
    # Agent spawn settings
    agents_per_direction = 5
    spawn_distance = 150
    
    # Four directions: North, South, East, West with different colors
    directions = [
        {'name': 'North', 'spawn': (center_x, center_y - spawn_distance), 'goal': (center_x, center_y + spawn_distance), 'color': (255, 100, 100)},  # Red
        {'name': 'South', 'spawn': (center_x, center_y + spawn_distance), 'goal': (center_x, center_y - spawn_distance), 'color': (100, 255, 100)},  # Green
        {'name': 'East', 'spawn': (center_x + spawn_distance, center_y), 'goal': (center_x - spawn_distance, center_y), 'color': (100, 100, 255)},  # Blue
        {'name': 'West', 'spawn': (center_x - spawn_distance, center_y), 'goal': (center_x + spawn_distance, center_y), 'color': (255, 255, 100)},  # Yellow
    ]
    
    # Add agents from each direction
    for direction in directions:
        for i in range(agents_per_direction):
            # Spawn position with some randomness (perpendicular to movement direction)
            if direction['name'] in ['North', 'South']:
                # Horizontal spread
                x = direction['spawn'][0] + random.uniform(-30, 30)
                y = direction['spawn'][1] + random.uniform(-20, 20)
            else:
                # Vertical spread
                x = direction['spawn'][0] + random.uniform(-20, 20)
                y = direction['spawn'][1] + random.uniform(-30, 30)
            
            agent = Agent(x, y, theta=random.uniform(-np.pi, np.pi), color=direction['color'])
            
            # Set goal to opposite side
            goal_x = direction['goal'][0] + random.uniform(-30, 30)
            goal_y = direction['goal'][1] + random.uniform(-30, 30)
            agent.goal = (goal_x, goal_y)
            
            # Random personal space (heterogeneity)
            agent.personal_space = random.uniform(15.0, 35.0)
            
            # Inject Gradient-Based EPH Controller
            agent.spm_module = SaliencyPolarMap()
            agent.controller = GradientEPHController(agent, learning_rate=0.5, n_iterations=5)
            
            env.add_agent(agent)

    
    # Initialize Simulator and Visualizer
    sim = Simulator(env)
    vis = Visualizer(env, width, height, title="Scramble Crossing - Gradient EPH")
    
    # Main Loop
    running = True
    while running:
        # Handle Events
        if not vis.handle_events():
            running = False
            break
        
        # Update Simulation
        sim.step()
        
        # Optionally respawn agents that reached their goal
        for agent in list(env.agents):
            if agent.goal:
                dx = agent.goal[0] - agent.position[0]
                dy = agent.goal[1] - agent.position[1]
                dist = np.sqrt(dx**2 + dy**2)
                
                # If reached goal, remove agent
                if dist < 20:
                    env.agents.remove(agent)
        
        # Respawn to maintain population
        if len(env.agents) < agents_per_direction * 4:
            # Randomly pick a direction
            direction = random.choice(directions)
            
            if direction['name'] in ['North', 'South']:
                x = direction['spawn'][0] + random.uniform(-30, 30)
                y = direction['spawn'][1] + random.uniform(-20, 20)
            else:
                x = direction['spawn'][0] + random.uniform(-20, 20)
                y = direction['spawn'][1] + random.uniform(-30, 30)
            
            agent = Agent(x, y, theta=random.uniform(-np.pi, np.pi), color=direction['color'])
            goal_x = direction['goal'][0] + random.uniform(-30, 30)
            goal_y = direction['goal'][1] + random.uniform(-30, 30)
            agent.goal = (goal_x, goal_y)
            agent.personal_space = random.uniform(15.0, 35.0)
            agent.spm_module = SaliencyPolarMap()
            agent.controller = GradientEPHController(agent, learning_rate=0.5, n_iterations=5)
            env.add_agent(agent)

        
        # Render
        vis.render()
    
    import pygame
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    try:
        import pygame
    except ImportError:
        print("Pygame not found. Please install dependencies.")
        sys.exit(1)
        
    main()
