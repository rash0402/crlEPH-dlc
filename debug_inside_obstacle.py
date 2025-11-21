"""Debug script to analyze behavior inside obstacle."""
import numpy as np
import jax.numpy as jnp
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

def test_inside_obstacle():
    """Test gradient when agent is inside obstacle."""
    env = Environment(width=200, height=200)
    
    # Agent INSIDE obstacle
    agent = Agent(x=120, y=100, theta=0.0)
    agent.spm_module = SaliencyPolarMap()
    
    # Obstacle at same position
    env.add_obstacle({'x': 120, 'y': 100, 'radius': 20})
    env.add_agent(agent)
    
    # Compute SPM
    agent.sense(env)
    
    print("=== AGENT INSIDE OBSTACLE ===")
    print(f"Agent position: ({agent.position[0]:.1f}, {agent.position[1]:.1f})")
    print(f"Obstacle position: (120.0, 100.0), radius: 20.0")
    print(f"Distance to obstacle center: 0.0")
    
    print("\n=== SPM Analysis ===")
    print("Occupancy (all bins):")
    print(agent.current_spm[0])
    print(f"\nMax occupancy: {np.max(agent.current_spm[0])}")
    print(f"Sum occupancy: {np.sum(agent.current_spm[0])}")
    
    # Close bins (should be high if inside)
    print(f"\nClose bins (0-1): {agent.current_spm[0, :2, :]}")
    print(f"Close bins sum: {np.sum(agent.current_spm[0, :2, :])}")
    
    # Test gradient
    controller = GradientEPHController(agent)
    
    print("\n=== Cost Function Analysis ===")
    
    # Test different velocities
    test_vels = [
        (0, 0),
        (10, 0),
        (-10, 0),
        (0, 10),
        (0, -10),
    ]
    
    for vx, vy in test_vels:
        action = jnp.array([vx, vy], dtype=jnp.float32)
        spm_jax = jnp.array(agent.current_spm, dtype=jnp.float32)
        precision_jax = jnp.array(agent.current_precision, dtype=jnp.float32)
        
        # Random walk target
        pv_jax = jnp.array([25.0, 0.0], dtype=jnp.float32)
        
        cost = controller._cost_function(action, spm_jax, precision_jax, pv_jax, 0.0)
        grad = controller.grad_cost_fn(action, spm_jax, precision_jax, pv_jax, 0.0)
        
        print(f"\nVel ({vx:6.1f}, {vy:6.1f}):")
        print(f"  Cost: {cost:10.2f}")
        print(f"  Grad: ({grad[0]:8.2f}, {grad[1]:8.2f})")
        
    # Now test actual decision
    print("\n=== Actual Decision ===")
    action = controller.decide_action(agent.current_spm, agent.current_precision, 0.0)
    print(f"Decided action: ({action[0]:.2f}, {action[1]:.2f})")

if __name__ == "__main__":
    test_inside_obstacle()
