"""Debug collision avoidance behavior."""
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

# Create simple scenario: 2 agents approaching each other
env = Environment(width=400, height=400)

# Agent 1: Moving right
agent1 = Agent(x=100, y=200, theta=0.0, color=(255, 0, 0))
agent1.set_velocity(20, 0)
agent1.personal_space = 20.0
agent1.spm_module = SaliencyPolarMap()
agent1.controller = GradientEPHController(agent1)
env.add_agent(agent1)

# Agent 2: Moving left (collision course)
agent2 = Agent(x=300, y=200, theta=np.pi, color=(0, 0, 255))
agent2.set_velocity(-20, 0)
agent2.personal_space = 20.0
agent2.spm_module = SaliencyPolarMap()
agent2.controller = GradientEPHController(agent2)
env.add_agent(agent2)

print("=== Initial Setup ===")
print(f"Agent 1: pos={agent1.position}, vel={agent1.velocity}")
print(f"Agent 2: pos={agent2.position}, vel={agent2.velocity}")
print(f"Distance: {np.linalg.norm(agent1.position - agent2.position):.1f}")

# Sense
agent1.sense(env)
agent2.sense(env)

print("\n=== Agent 1 SPM ===")
print(f"Occupancy sum: {np.sum(agent1.current_spm[0]):.4f}")
print(f"Max occupancy: {np.max(agent1.current_spm[0]):.4f}")
print("Occupancy grid:")
print(agent1.current_spm[0])

print("\n=== Agent 2 SPM ===")
print(f"Occupancy sum: {np.sum(agent2.current_spm[0]):.4f}")
print(f"Max occupancy: {np.max(agent2.current_spm[0]):.4f}")

# Decide action
agent1.decide_action(env)
agent2.decide_action(env)

print("\n=== Actions ===")
print(f"Agent 1 new velocity: {agent1.velocity}")
print(f"Agent 2 new velocity: {agent2.velocity}")

# Check if they're avoiding
vel1_towards = agent1.velocity[0]
vel2_towards = agent2.velocity[0]

print(f"\nAgent 1 moving {'TOWARDS' if vel1_towards > 0 else 'AWAY'} agent 2")
print(f"Agent 2 moving {'TOWARDS' if vel2_towards < 0 else 'AWAY'} agent 1")

if vel1_towards > 10 and vel2_towards < -10:
    print("\n⚠️  WARNING: Agents NOT avoiding collision!")
else:
    print("\n✓ Agents attempting to avoid")
