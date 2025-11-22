import sys
import random
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.utils.visualization import Visualizer
from src.perception.spm import SaliencyPolarMap
from src.control.eph import EPHController

def main():
    # Initialize Environment
    width, height = 800, 600
    env = Environment(width=width, height=height)

    # Add Agents
    num_agents = 10
    for _ in range(num_agents):
        x = random.uniform(50, width - 50)
        y = random.uniform(50, height - 50)
        theta = random.uniform(-np.pi, np.pi)
        agent = Agent(x, y, theta)
        # Give random initial velocity
        vx = random.uniform(-20, 20)
        vy = random.uniform(-20, 20)
        agent.set_velocity(vx, vy)
        
        # Inject Modules
        agent.spm_module = SaliencyPolarMap()
        agent.controller = EPHController(agent)
        
        env.add_agent(agent)

    # Add Obstacles
    env.add_obstacle({'x': 400, 'y': 300, 'radius': 50})

    # Initialize Simulator and Visualizer
    sim = Simulator(env)
    vis = Visualizer(env, width, height)

    # Main Loop
    running = True
    while running:
        # Handle Events
        if not vis.handle_events():
            running = False
            break

        # Update Simulation
        sim.step()

        # Render
        vis.render()

    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    # Check if pygame is available (it should be if requirements are installed)
    try:
        import pygame
    except ImportError:
        print("Pygame not found. Please install dependencies.")
        sys.exit(1)
        
    main()
