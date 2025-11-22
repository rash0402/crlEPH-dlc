import unittest
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph import EPHController

class TestEPH(unittest.TestCase):
    def test_action_selection(self):
        env = Environment(width=200, height=200)
        agent = Agent(x=100, y=100, theta=0.0)
        agent.spm_module = SaliencyPolarMap()
        agent.controller = EPHController(agent)
        env.add_agent(agent)
        
        # Add obstacle in front
        obstacle = Agent(x=110, y=100) # Very close in front
        env.add_agent(obstacle)
        
        # Compute SPM
        agent.sense(env)
        
        # Decide action
        # Should avoid moving forward (vx > 0, vy ~ 0)
        # Should prefer turning or stopping or moving backward?
        # My logic: minimize cost. Cost is high if moving towards obstacle.
        
        action = agent.controller.decide_action(agent.current_spm, agent.current_precision, 0.0)
        vx, vy = action
        
        # Check if action is safe(r)
        # Moving forward (vx > 0) should be penalized.
        # So vx should be small or negative, or vy large (turn).
        
        print(f"Action with obstacle in front: {action}")
        
        # If I remove obstacle, it should move forward (due to inertia or random/meta preference?)
        # My meta-eval prefers speed.
        
    def test_self_hazing(self):
        agent = Agent(0,0)
        controller = EPHController(agent)
        
        # Simulate stuck
        agent.velocity = np.array([0.0, 0.0])
        
        # Update many times
        for _ in range(60):
            controller.decide_action(np.zeros((3,10,10)), np.zeros((10,10)), 0.0)
            
        self.assertGreater(controller.haze_self, 0.0)
        print(f"Self Haze after stuck: {controller.haze_self}")

if __name__ == '__main__':
    unittest.main()
