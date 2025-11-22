import unittest
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent

class TestCoreSimulation(unittest.TestCase):
    def test_environment_initialization(self):
        env = Environment(width=100, height=100)
        self.assertEqual(env.width, 100)
        self.assertEqual(env.height, 100)
        self.assertEqual(len(env.agents), 0)

    def test_agent_movement(self):
        env = Environment(width=100, height=100)
        agent = Agent(x=50, y=50)
        agent.set_velocity(vx=10, vy=0)
        env.add_agent(agent)
        
        # Update for 1 second
        env.dt = 1.0
        env.update()
        
        self.assertEqual(agent.position[0], 60)
        self.assertEqual(agent.position[1], 50)

    def test_boundary_collision(self):
        env = Environment(width=100, height=100)
        agent = Agent(x=95, y=50)
        agent.set_velocity(vx=10, vy=0) # Will cross boundary in 1s
        env.add_agent(agent)
        
        env.dt = 1.0
        env.update()
        
        # Toroidal world: should wrap around
        # x = 95 + 10 = 105. 105 % 100 = 5
        self.assertEqual(agent.position[0], 5)
        # Velocity should remain unchanged (no bounce)
        self.assertEqual(agent.velocity[0], 10)

if __name__ == '__main__':
    unittest.main()
