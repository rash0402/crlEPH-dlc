"""Gradient-based EPH controller using JAX for automatic differentiation."""
import jax
import jax.numpy as jnp
import numpy as np

class GradientEPHController:
    def __init__(self, agent, learning_rate=0.5, n_iterations=5):
        self.agent = agent
        self.learning_rate = learning_rate
        self.n_iterations = n_iterations
        self.haze_self = 0.0
        self.stuck_counter = 0
        
        # Random walk when no goal
        self.random_target_angle = np.random.uniform(0, 2 * np.pi)
        self.random_target_timer = 0
        self.random_target_duration = 50  # Change direction every 50 steps
        
        # JIT compile the gradient function for speed
        self.grad_cost_fn = jax.jit(jax.grad(self._cost_function, argnums=0))
        
    def decide_action(self, spm_tensor, precision_matrix, env_haze_value, preferred_velocity=None):
        """
        Decide velocity using gradient descent on cost function.
        """
        # 1. Update Self-Hazing
        speed = np.linalg.norm(self.agent.velocity)
        if speed < 5.0:
            self.stuck_counter += 1
        else:
            self.stuck_counter = max(0, self.stuck_counter - 1)
            
        if self.stuck_counter > 50:
            self.haze_self = min(1.0, self.haze_self + 0.05)
        else:
            self.haze_self = max(0.0, self.haze_self - 0.01)
        
        # 2. Modulate precision with Haze
        modulated_precision = self._apply_haze(precision_matrix, env_haze_value)
        
        # 3. Initialize action
        if preferred_velocity is not None:
            # Start from preferred direction
            action = jnp.array(preferred_velocity, dtype=jnp.float32)
            pv_jax = jnp.array(preferred_velocity, dtype=jnp.float32)
        else:
            # Check if inside obstacle (high occupancy in close bins)
            close_occupancy = np.sum(spm_tensor[0, :2, :])
            is_inside_obstacle = close_occupancy > 0.5  # Threshold
            
            if is_inside_obstacle:
                # EMERGENCY: No random walk, pure repulsion to escape
                pv_jax = jnp.array([0.0, 0.0], dtype=jnp.float32)
            else:
                # Random walk: generate random target direction
                self.random_target_timer += 1
                if self.random_target_timer > self.random_target_duration:
                    self.random_target_angle = np.random.uniform(0, 2 * np.pi)
                    self.random_target_timer = 0
                
                # Random target velocity
                random_speed = self.agent.max_speed * 0.5
                random_vx = random_speed * np.cos(self.random_target_angle)
                random_vy = random_speed * np.sin(self.random_target_angle)
                pv_jax = jnp.array([random_vx, random_vy], dtype=jnp.float32)
            
            # Start from current velocity
            action = jnp.array(self.agent.velocity, dtype=jnp.float32)
        
        # Convert to JAX arrays
        spm_jax = jnp.array(spm_tensor, dtype=jnp.float32)
        precision_jax = jnp.array(modulated_precision, dtype=jnp.float32)
        
        # 4. Gradient descent
        for _ in range(self.n_iterations):
            # Compute gradient
            grad = self.grad_cost_fn(action, spm_jax, precision_jax, pv_jax, self.agent.orientation)
            
            # Clip gradient to prevent instability
            grad = jnp.clip(grad, -10.0, 10.0)
            
            # Update action with gradient descent
            action = action - self.learning_rate * grad
            
            # Clip to max speed
            speed = jnp.linalg.norm(action) + 1e-8  # Epsilon to prevent division by zero
            if speed > self.agent.max_speed:
                action = action / speed * self.agent.max_speed
        
        # Convert back to numpy
        return (float(action[0]), float(action[1]))
    
    def _apply_haze(self, precision_matrix, env_haze_value):
        """Apply Haze modulation to precision matrix."""
        modulated = precision_matrix.copy()
        
        # Apply Self Haze to frontal sector
        if self.haze_self > 0:
            Ntheta = precision_matrix.shape[1]
            center_idx = int(Ntheta / 2)
            width = int(Ntheta / 6)
            start = center_idx - width
            end = center_idx + width
            
            attenuation = (1.0 - self.haze_self)**2
            for t in range(start, end+1):
                t_idx = t % Ntheta
                modulated[:, t_idx] *= attenuation
        
        # Apply Environmental Haze
        modulated *= (1.0 - env_haze_value)**2
        
        return modulated
    
    @staticmethod
    @jax.jit
    def _cost_function(action, spm_tensor, precision, preferred_vel, agent_orientation):
        """
        Compute cost J(a) = F_percept + lambda * M_meta.
        
        This function must be pure (no side effects) for JAX autodiff.
        """
        vx, vy = action
        
        # 1. Perceptual Free Energy (Risk from obstacles)
        Nr, Ntheta = spm_tensor.shape[1], spm_tensor.shape[2]
        
        # Compute bin angles
        angles = jnp.linspace(-jnp.pi, jnp.pi, Ntheta + 1)[:-1]
        angles = angles + (angles[1] - angles[0]) / 2.0
        
        # Rotate action to agent frame
        ax = vx * jnp.cos(-agent_orientation) - vy * jnp.sin(-agent_orientation)
        ay = vx * jnp.sin(-agent_orientation) + vy * jnp.cos(-agent_orientation)
        
        # Radial velocity towards each bin
        v_rads = ax * jnp.cos(angles) + ay * jnp.sin(angles)
        
        # Occupancy (channel 0)
        occupancy = spm_tensor[0]
        
        # Broadcast v_rads
        v_rads_grid = jnp.tile(v_rads, (Nr, 1))
        
        # Risk: moving towards occupied cells
        risk = occupancy * precision * jnp.maximum(0, v_rads_grid)
        
        # Add penalty for being in occupied space (high occupancy at close range)
        # This creates strong repulsion force
        close_occupancy = spm_tensor[0, :2, :]  # First 2 radial bins (intimate zone)
        being_inside_penalty = jnp.sum(close_occupancy * precision[:2, :]) * 100.0  # Strong penalty
        
        F_percept = jnp.sum(risk) + being_inside_penalty
        
        # 2. Instrumental Value (Goal-seeking)
        pvx, pvy = preferred_vel
        has_goal = jnp.linalg.norm(preferred_vel) > 1.0
        
        # If goal exists, minimize distance to preferred velocity
        # Otherwise, maximize speed (with small regularization)
        M_meta = jax.lax.cond(
            has_goal,
            lambda: (vx - pvx)**2 + (vy - pvy)**2,  # Goal-seeking
            lambda: -0.1 * jnp.sqrt(vx**2 + vy**2 + 1e-8)   # Speed reward with epsilon
        )
        
        # Total cost
        lambda_weight = 0.5
        J = F_percept + lambda_weight * M_meta
        
        return J
