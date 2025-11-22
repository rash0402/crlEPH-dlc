import unittest
import numpy as np
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap

class TestSPM(unittest.TestCase):
    def test_spm_mapping(self):
        env = Environment(width=200, height=200)
        agent = Agent(x=100, y=100, theta=0.0)
        agent.personal_space = 20.0
        env.add_agent(agent)
        
        # Add another agent very close (Intimate zone)
        other1 = Agent(x=110, y=100) # dist 10 < 20
        env.add_agent(other1)
        
        # Add another agent far away
        other2 = Agent(x=180, y=100) # dist 80 > 20
        env.add_agent(other2)
        
        spm = SaliencyPolarMap(Nr=10, Ntheta=12, d_max=100.0)
        tensor = spm.compute_spm(agent, env)
        
        # Check shape
        self.assertEqual(tensor.shape, (3, 10, 12))
        
        # Check Intimate Zone (Bin 0)
        # angle 0 maps to index 6
        self.assertGreater(tensor[0, 0, 6], 0.1)
        
        # Check Far object
        # dist 80.
        occupancy_far = np.sum(tensor[0, 5:, 6])
        self.assertGreater(occupancy_far, 0.0)

    def test_precision_matrix(self):
        spm = SaliencyPolarMap(Nr=10, Ntheta=12)
        agent = Agent(0,0)
        agent.personal_space = 20.0
        
        precision = spm.get_precision_matrix(agent)
        
        # Bin 0 (dist < ps) should have high precision (~1.0)
        self.assertAlmostEqual(precision[0, 0], 1.0, delta=0.1)
        
        # Bin -1 (dist > ps) should have low precision (~0.0)
        self.assertAlmostEqual(precision[-1, 0], 0.0, delta=0.1)

if __name__ == '__main__':
    unittest.main()
