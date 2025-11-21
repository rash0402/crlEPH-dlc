"""Test for gradient-based EPH controller."""
import unittest
import numpy as np
import jax.numpy as jnp
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

class TestGradientEPH(unittest.TestCase):
    def test_cost_function_differentiable(self):
        """Test that cost function is differentiable."""
        import jax
        
        # Create dummy inputs
        action = jnp.array([10.0, 5.0])
        spm = jnp.zeros((3, 6, 6))
        spm = spm.at[0, 0, 3].set(1.0)  # Add obstacle in front
        precision = jnp.ones((6, 6))
        preferred_vel = jnp.array([20.0, 0.0])
        orientation = 0.0
        
        # Compute gradient
        grad_fn = jax.grad(GradientEPHController._cost_function, argnums=0)
        grad = grad_fn(action, spm, precision, preferred_vel, orientation)
        
        # Gradient should exist and be non-zero
        self.assertEqual(grad.shape, (2,))
        self.assertTrue(jnp.any(grad != 0))
        print(f"Gradient: {grad}")
    
    def test_action_selection_with_obstacle(self):
        """Test that gradient-based controller avoids obstacles."""
        env = Environment(width=200, height=200)
        agent = Agent(x=100, y=100, theta=0.0)
        agent.spm_module = SaliencyPolarMap()
        agent.controller = GradientEPHController(agent)
        env.add_agent(agent)
        
        # Add obstacle directly in front
        obstacle = Agent(x=110, y=100)
        env.add_agent(obstacle)
        
        # Compute SPM
        agent.sense(env)
        
        # Decide action
        action = agent.controller.decide_action(
            agent.current_spm, 
            agent.current_precision, 
            0.0
        )
        vx, vy = action
        
        print(f"Action with obstacle in front (gradient): vx={vx:.2f}, vy={vy:.2f}")
        
        # Should avoid moving straight forward (vx should be small or negative, or vy large)
        # Not moving purely forward at max speed
        self.assertTrue(abs(vx) < agent.max_speed * 0.9 or abs(vy) > 5.0)
    
    def test_goal_seeking(self):
        """Test that controller moves towards goal."""
        env = Environment(width=200, height=200)
        agent = Agent(x=100, y=100, theta=0.0)
        agent.spm_module = SaliencyPolarMap()
        agent.controller = GradientEPHController(agent, learning_rate=1.0, n_iterations=10)
        agent.goal = (150, 100)  # Goal to the right
        env.add_agent(agent)
        
        # Sense and decide
        agent.sense(env)
        agent.decide_action(env)
        
        vx, vy = agent.velocity
        
        print(f"Goal-seeking action: vx={vx:.2f}, vy={vy:.2f}")
        
        # Should move towards goal (positive vx)
        self.assertGreater(vx, 0)

if __name__ == '__main__':
    unittest.main()
