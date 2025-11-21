import sys
import random
import numpy as np
import pygame
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.utils.visualization import Visualizer
from src.perception.spm import SaliencyPolarMap
from src.control.eph import EPHController

def main():
    width, height = 800, 400
    env = Environment(width=width, height=height)
    
    # Create Narrow Corridor
    wall_x = 400
    gap_y = 200
    gap_width = 40  # Slightly wider for visualization
    
    pillar_radius = 10
    # Top wall
    for y in range(0, int(gap_y - gap_width/2), int(pillar_radius*1.5)):
        env.add_obstacle({'x': wall_x, 'y': y, 'radius': pillar_radius})
        
    # Bottom wall
    for y in range(int(gap_y + gap_width/2), height, int(pillar_radius*1.5)):
        env.add_obstacle({'x': wall_x, 'y': y, 'radius': pillar_radius})
    
    # Add Agents in Room A
    num_agents = 20  # Reduced for visualization
    heterogeneous = True  # Toggle this to test
    
    for i in range(num_agents):
        x = random.uniform(50, 300)
        y = random.uniform(50, 350)
        agent = Agent(x, y)
        
        if heterogeneous:
            agent.personal_space = random.uniform(10.0, 40.0)
        else:
            agent.personal_space = 20.0
            
        agent.spm_module = SaliencyPolarMap()
        agent.controller = EPHController(agent)
        agent.goal = (700, 200)  # Goal in Room B
        
        env.add_agent(agent)
    
    # Initialize Simulator and Visualizer
    sim = Simulator(env)
    vis = Visualizer(env, width, height, title="Narrow Corridor - AI-DLC")
    
    # Main Loop
    running = True
    step_count = 0
    completed = 0
    
    while running:
        if not vis.handle_events():
            running = False
            break
        
        sim.step()
        step_count += 1
        
        # Count completed agents
        completed = sum(1 for a in env.agents if a.position[0] > 600)
        
        # Display info
        pygame.display.set_caption(
            f"Narrow Corridor - Step: {step_count}, Completed: {completed}/{num_agents}"
        )
        
        vis.render()
        
        if completed == num_agents:
            print(f"All agents completed in {step_count} steps!")
            # Keep window open for a moment
            pygame.time.wait(2000)
            running = False
    
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    try:
        import pygame
    except ImportError:
        print("Pygame not found. Please install dependencies.")
        sys.exit(1)
        
    main()
