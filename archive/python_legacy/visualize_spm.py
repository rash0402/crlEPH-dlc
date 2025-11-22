"""Visualize SPM (Saliency Polar Map) for a specific agent."""
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Wedge
import sys
from src.core.environment import Environment
from src.core.agent import Agent
from src.perception.spm import SaliencyPolarMap
from src.control.eph_gradient import GradientEPHController

def visualize_spm(agent, spm_tensor, precision_matrix, title="SPM Visualization"):
    """Visualize SPM as polar heatmap."""
    Nr, Ntheta = spm_tensor.shape[1], spm_tensor.shape[2]
    
    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    fig.suptitle(title, fontsize=16)
    
    # Channel names
    channels = ['Occupancy', 'Radial Velocity', 'Tangential Velocity']
    
    # Plot each channel
    for idx, (ax, channel_name) in enumerate(zip(axes.flat[:3], channels)):
        data = spm_tensor[idx]
        
        # Create polar plot
        theta = np.linspace(-np.pi, np.pi, Ntheta + 1)
        r = np.arange(Nr + 1)
        
        # Plot as polar heatmap
        ax.set_title(f'{channel_name}')
        im = ax.pcolormesh(theta, r, data, cmap='hot', shading='auto')
        ax.set_xlabel('Angle (rad)')
        ax.set_ylabel('Radial bin')
        ax.set_xticks([-np.pi, -np.pi/2, 0, np.pi/2, np.pi])
        ax.set_xticklabels(['-π', '-π/2', '0', 'π/2', 'π'])
        plt.colorbar(im, ax=ax)
    
    # Plot precision matrix
    ax = axes.flat[3]
    ax.set_title('Precision Matrix')
    im = ax.pcolormesh(np.linspace(-np.pi, np.pi, Ntheta + 1), 
                       np.arange(Nr + 1), 
                       precision_matrix, 
                       cmap='viridis', 
                       shading='auto')
    ax.set_xlabel('Angle (rad)')
    ax.set_ylabel('Radial bin')
    ax.set_xticks([-np.pi, -np.pi/2, 0, np.pi/2, np.pi])
    ax.set_xticklabels(['-π', '-π/2', '0', 'π/2', 'π'])
    plt.colorbar(im, ax=ax)
    
    plt.tight_layout()
    return fig

def main():
    # Create scenario with multiple agents
    env = Environment(width=800, height=800)
    
    # Target agent (red)
    target = Agent(x=400, y=400, theta=0.0, color=(255, 0, 0))
    target.personal_space = 25.0
    target.spm_module = SaliencyPolarMap()
    target.controller = GradientEPHController(target)
    target.goal = (600, 400)
    env.add_agent(target)
    
    # Add surrounding agents
    positions = [
        (500, 400),  # Front
        (450, 350),  # Front-right
        (350, 400),  # Left
        (400, 500),  # Below
    ]
    
    for i, (x, y) in enumerate(positions):
        agent = Agent(x, y, color=(100, 100, 255))
        agent.personal_space = 20.0
        agent.spm_module = SaliencyPolarMap()
        agent.controller = GradientEPHController(agent)
        env.add_agent(agent)
    
    # Compute SPM for target agent
    target.sense(env)
    
    print("=== Target Agent SPM ===")
    print(f"Position: {target.position}")
    print(f"Orientation: {target.orientation:.2f} rad")
    print(f"Personal Space: {target.personal_space}")
    print(f"SPM shape: {target.current_spm.shape}")
    print(f"Occupancy sum: {np.sum(target.current_spm[0]):.4f}")
    
    # Visualize current SPM
    fig1 = visualize_spm(target, target.current_spm, target.current_precision, 
                         title=f"Current SPM (Agent at {target.position})")
    
    # Simulate action and predict SPM
    # For prediction, we would need to implement forward model
    # For now, just show what the SPM would look like after a small movement
    
    # Move target slightly
    target.position[0] += 20
    target.sense(env)
    
    fig2 = visualize_spm(target, target.current_spm, target.current_precision,
                         title=f"Predicted SPM (After moving +20 in x)")
    
    plt.show()

if __name__ == "__main__":
    main()
