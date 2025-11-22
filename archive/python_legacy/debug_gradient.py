"""Debug script to visualize gradient behavior near obstacle."""
import numpy as np
import jax.numpy as jnp
import matplotlib.pyplot as plt
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

def analyze_gradient_field():
    """Analyze gradient field around obstacle."""
    env = Environment(width=200, height=200)
    
    # Agent at various positions
    agent = Agent(x=100, y=100, theta=0.0)
    agent.spm_module = SaliencyPolarMap()
    
    # Single obstacle
    env.add_obstacle({'x': 120, 'y': 100, 'radius': 20})
    env.add_agent(agent)
    
    # Compute SPM
    agent.sense(env)
    
    print("=== SPM Analysis ===")
    print(f"SPM shape: {agent.current_spm.shape}")
    print(f"SPM Occupancy channel max: {np.max(agent.current_spm[0])}")
    print(f"SPM Occupancy sum: {np.sum(agent.current_spm[0])}")
    print("\nOccupancy grid:")
    print(agent.current_spm[0])
    
    print("\n=== Precision Matrix ===")
    print(agent.current_precision)
    
    # Test gradient for different velocities
    controller = GradientEPHController(agent)
    
    print("\n=== Gradient Test ===")
    test_velocities = [
        (0, 0),      # Stopped
        (10, 0),     # Moving towards obstacle
        (-10, 0),    # Moving away from obstacle
        (0, 10),     # Moving perpendicular
        (7, 7),      # Diagonal
    ]
    
    for vx, vy in test_velocities:
        action = jnp.array([vx, vy], dtype=jnp.float32)
        spm_jax = jnp.array(agent.current_spm, dtype=jnp.float32)
        precision_jax = jnp.array(agent.current_precision, dtype=jnp.float32)
        pv_jax = jnp.array([0.0, 0.0], dtype=jnp.float32)
        
        # Compute cost
        cost = controller._cost_function(action, spm_jax, precision_jax, pv_jax, agent.orientation)
        
        # Compute gradient
        grad = controller.grad_cost_fn(action, spm_jax, precision_jax, pv_jax, agent.orientation)
        
        print(f"\nVelocity ({vx:6.1f}, {vy:6.1f}):")
        print(f"  Cost: {cost:10.4f}")
        print(f"  Gradient: ({grad[0]:8.4f}, {grad[1]:8.4f})")
        print(f"  Grad magnitude: {jnp.linalg.norm(grad):.4f}")

if __name__ == "__main__":
    analyze_gradient_field()
