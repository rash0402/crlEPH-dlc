import numpy as np
import random
from src.core.environment import Environment
from src.core.agent import Agent
from src.core.simulator import Simulator
from src.perception.spm import SaliencyPolarMap
from src.control.eph import EPHController

def run_experiment(heterogeneous=False, num_steps=500):
    env = Environment(width=400, height=400)
    
    # Create narrow corridor or crowded space
    # 20 agents in small space
    num_agents = 20
    for i in range(num_agents):
        agent = Agent(x=random.uniform(100, 300), y=random.uniform(100, 300))
        
        # Heterogeneity
        if heterogeneous:
            agent.personal_space = random.uniform(10.0, 30.0)
        else:
            agent.personal_space = 20.0
            
        agent.spm_module = SaliencyPolarMap()
        agent.controller = EPHController(agent)
        env.add_agent(agent)
        
    sim = Simulator(env)
    
    total_speed = 0.0
    
    for _ in range(num_steps):
        sim.step()
        # Metric: Average speed of all agents
        speeds = [np.linalg.norm(a.velocity) for a in env.agents]
        total_speed += np.mean(speeds)
        
    avg_speed = total_speed / num_steps
    return avg_speed

if __name__ == "__main__":
    print("Running Homogeneous Swarm Experiment...")
    score_homo = run_experiment(heterogeneous=False)
    print(f"Homogeneous Average Speed: {score_homo:.2f}")
    
    print("Running Heterogeneous Swarm Experiment...")
    score_hetero = run_experiment(heterogeneous=True)
    print(f"Heterogeneous Average Speed: {score_hetero:.2f}")
    
    if score_hetero > score_homo:
        print("Result: Heterogeneity IMPROVED flow.")
    else:
        print("Result: Heterogeneity did NOT improve flow (or diff is negligible).")
