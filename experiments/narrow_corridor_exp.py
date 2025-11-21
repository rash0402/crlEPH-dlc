import numpy as np
import random
import time
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.perception.spm import SaliencyPolarMap
from src.control.eph import EPHController

def run_narrow_corridor(heterogeneous=False, max_steps=2000):
    width, height = 800, 400
    env = Environment(width=width, height=height)
    
    # Create Walls to form a narrow corridor
    # Room A: [0, 300], Room B: [500, 800]
    # Wall at x=350-450?
    # Let's make a wall at x=400 with a gap.
    
    wall_x = 400
    gap_y = 200
    gap_width = 30 # Very narrow! 1.5 agents wide (radius 10 -> diam 20)
    
    # Top Wall
    env.add_obstacle({'x': wall_x, 'y': 0, 'width': 20, 'height': gap_y - gap_width/2}) 
    
    pillar_radius = 10
    # Top part
    for y in range(0, int(gap_y - gap_width/2), int(pillar_radius*1.5)): # Denser pillars
        env.add_obstacle({'x': wall_x, 'y': y, 'radius': pillar_radius})
        
    # Bottom part
    for y in range(int(gap_y + gap_width/2), height, int(pillar_radius*1.5)):
        env.add_obstacle({'x': wall_x, 'y': y, 'radius': pillar_radius})
        
    # Add Agents in Room A (Left)
    num_agents = 50
    agents = []
    for i in range(num_agents):
        # Random pos in left room
        x = random.uniform(50, 300)
        y = random.uniform(50, 350)
        agent = Agent(x, y)
        
        if heterogeneous:
            # Mix of "Shy" (Large PS) and "Bold" (Small PS)
            # or Continuous distribution
            agent.personal_space = random.uniform(10.0, 40.0)
        else:
            agent.personal_space = 20.0
            
        agent.spm_module = SaliencyPolarMap()
        agent.controller = EPHController(agent)
        
        # Set Goal to Room B (Right)
        agent.goal = (700, 200) # Target center of Room B
        
        env.add_agent(agent)
        agents.append(agent)
        
    sim = Simulator(env)
    
    # Run simulation
    start_time = time.time()
    completed_agents = 0
    
    for step in range(max_steps):
        sim.step()
        
        # Check completion
        current_completed = 0
        for agent in agents:
            if agent.position[0] > 600: # Passed the wall
                current_completed += 1
        
        if current_completed == num_agents:
            print(f"All agents completed at step {step}")
            return step
            
    print(f"Time's up. Completed: {current_completed}/{num_agents}")
    return max_steps

if __name__ == "__main__":
    print("--- Narrow Corridor Experiment ---")
    
    print("Running Homogeneous Swarm...")
    steps_homo = run_narrow_corridor(heterogeneous=False)
    print(f"Homogeneous Steps: {steps_homo}")
    
    print("Running Heterogeneous Swarm...")
    steps_hetero = run_narrow_corridor(heterogeneous=True)
    print(f"Heterogeneous Steps: {steps_hetero}")
    
    improvement = (steps_homo - steps_hetero) / steps_homo * 100
    print(f"Improvement: {improvement:.2f}%")
