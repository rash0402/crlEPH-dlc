import numpy as np
from src.utils.math_utils import normalize_angle
from src.utils.toroidal import toroidal_distance

class Agent:
    def __init__(self, x, y, theta=0.0, radius=10.0, color=None):
        self.position = np.array([x, y], dtype=float)
        self.velocity = np.array([0.0, 0.0], dtype=float)
        self.orientation = theta  # Heading angle
        self.radius = radius
        self.max_speed = 50.0 # pixels per second?
        self.personal_space = 20.0
        self.color = color if color else (100, 150, 255)  # Default blue
        
        # Perception and Control modules
        self.spm_module = None
        self.controller = None
        
        # State
        self.current_spm = None
        self.current_precision = None
        
        # Goal
        self.goal = None # (x, y) tuple

    def update(self, dt):
        # Update position
        self.position += self.velocity * dt
        
        # Update orientation based on velocity if moving
        if np.linalg.norm(self.velocity) > 0.1:
            target_angle = np.arctan2(self.velocity[1], self.velocity[0])
            # Simple smoothing or instant turn? Let's do instant for now
            self.orientation = target_angle

    def set_velocity(self, vx, vy):
        self.velocity = np.array([vx, vy])
        speed = np.linalg.norm(self.velocity)
        if speed > self.max_speed:
            self.velocity = (self.velocity / speed) * self.max_speed

    def sense(self, environment):
        """
        Generate SPM from environment.
        """
        if self.spm_module:
            self.current_spm = self.spm_module.compute_spm(self, environment)
            self.current_precision = self.spm_module.get_precision_matrix(self)

    def decide_action(self, environment):
        """
        Decide next velocity based on SPM and Haze.
        """
        if self.controller and self.current_spm is not None:
            # Get local haze from environment
            # Map position to grid index
            grid_x = int(self.position[0] / environment.grid_size)
            grid_y = int(self.position[1] / environment.grid_size)
            
            # Boundary check for grid
            w, h = environment.haze_grid.shape
            grid_x = max(0, min(grid_x, w-1))
            grid_y = max(0, min(grid_y, h-1))
            
            env_haze = environment.haze_grid[grid_x, grid_y]
            
            # Calculate preferred velocity based on goal
            preferred_velocity = None
            if self.goal:
                # Use toroidal distance to goal
                dx, dy, dist = toroidal_distance(
                    self.position, 
                    self.goal, 
                    environment.width, 
                    environment.height
                )
                if dist > 0:
                    # Normalize and scale to max speed
                    preferred_velocity = (dx / dist * self.max_speed, dy / dist * self.max_speed)
            
            action = self.controller.decide_action(self.current_spm, self.current_precision, env_haze, preferred_velocity)
            self.set_velocity(action[0], action[1])
            
            # Stigmergy: Leave Haze trace?
            # If moving fast, leave "Lubricant" (Low Haze? Or specific type).
            # For now, let's say we leave a trail of Haze (Repellent) to avoid backtracking?
            # Or maybe we clear Haze (Lubricant).
            # Let's implement "Repellent Haze" (Pheromone) for exploration.
            environment.haze_grid[grid_x, grid_y] = min(1.0, environment.haze_grid[grid_x, grid_y] + 0.1)
