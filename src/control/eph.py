import numpy as np
from src.utils.math_utils import cartesian_to_polar, polar_to_cartesian

class EPHController:
    def __init__(self, agent):
        self.agent = agent
        self.haze_self = 0.0 # Scalar or Tensor? Doc says Tensor. Let's start with scalar intensity for front sector.
        self.stuck_counter = 0
        
    def decide_action(self, spm_tensor, precision_matrix, env_haze_value, preferred_velocity=None):
        """
        Decide velocity (vx, vy) based on SPM and Haze.
        env_haze_value: Haze intensity at agent's current location (or surrounding).
        preferred_velocity: (vx, vy) tuple indicating desired direction/speed (Instrumental Value).
        """
        # 1. Update Self-Hazing (Deadlock detection)
        speed = np.linalg.norm(self.agent.velocity)
        if speed < 5.0: # Threshold
            self.stuck_counter += 1
        else:
            self.stuck_counter = max(0, self.stuck_counter - 1)
            
        if self.stuck_counter > 50: # 5 seconds at 10Hz
            self.haze_self = min(1.0, self.haze_self + 0.05)
        else:
            self.haze_self = max(0.0, self.haze_self - 0.01)
            
        # 2. Combine Haze
        # Haze affects Precision.
        # H_total = H_self + H_env
        # We assume H_self affects the "Front" direction mostly (ignoring obstacles in front to push through or turn)
        # Or H_self is global "boredom".
        # Doc says: "If stuck, increase haze in direction of movement".
        
        # Let's modulate precision matrix
        # Pi_modulated = Pi_base * (1 - Haze)^gamma
        
        modulated_precision = precision_matrix.copy()
        
        # Apply Self Haze (Frontal sector)
        if self.haze_self > 0:
            # Indices corresponding to front (angle ~ 0)
            # In SPM, angle 0 is usually center of angular bins if aligned with agent orientation?
            # My SPM implementation: rel_angle = angle - agent.orientation.
            # So 0 is front.
            # Map 0 to bin index.
            Ntheta = precision_matrix.shape[1]
            center_idx = int(Ntheta / 2) # If range is [-pi, pi], 0 is center?
            # np.linspace(-pi, pi, Ntheta+1). 0 is at index Ntheta/2.
            
            width = int(Ntheta / 6) # 60 degrees
            start = center_idx - width
            end = center_idx + width
            
            # Apply haze attenuation
            attenuation = (1.0 - self.haze_self)**2
            for t in range(start, end+1):
                t_idx = t % Ntheta
                modulated_precision[:, t_idx] *= attenuation

        # Apply Env Haze (Scalar for now, assuming uniform local haze)
        # If Env Haze is high, we ignore everything (High exploration?)
        # Or Env Haze is spatial.
        # For now simple scalar attenuation
        modulated_precision *= (1.0 - env_haze_value)**2

        # 3. Action Selection (Sampling)
        # Sample candidate velocities
        candidates = []
        n_samples = 16
        max_speed = self.agent.max_speed
        
        for i in range(n_samples):
            angle = (i / n_samples) * 2 * np.pi
            vx = max_speed * np.cos(angle)
            vy = max_speed * np.sin(angle)
            candidates.append((vx, vy))
        
        # Add Stop
        candidates.append((0.0, 0.0))
        # Add Current
        candidates.append((self.agent.velocity[0], self.agent.velocity[1]))
        
        best_action = (0,0)
        min_cost = float('inf')
        
        for action in candidates:
            cost = self._evaluate_action(action, spm_tensor, modulated_precision, preferred_velocity)
            if cost < min_cost:
                min_cost = cost
                best_action = action
                
        return best_action

    def _evaluate_action(self, action, spm_tensor, precision, preferred_velocity=None):
        """
        Evaluate cost J(a).
        J = Sum( Precision * (Target - Pred)^2 )
        Target = 0 (Empty space preference)
        Pred = Shifted SPM based on action.
        """
        vx, vy = action
        
        # Predict SPM shift
        # If I move with (vx, vy), relative velocity of static world is (-vx, -vy).
        # Objects move closer if I move towards them.
        # Radial velocity component: v_rad = -v_agent dot e_r
        
        # Simplified prediction:
        # We don't fully reconstruct the new SPM (expensive).
        # Instead, we evaluate the "Risk" of the current SPM if we take this action.
        # Risk ~ Sum( Occupancy * Precision * (Approaching Speed) )
        
        # If I move towards an occupied cell, cost is high.
        # v_approach = v_agent dot e_r (positive if moving towards bin)
        
        # Let's calculate v_radial for each bin given action
        # bin_angle
        Nr, Ntheta = spm_tensor.shape[1], spm_tensor.shape[2]
        
        cost = 0.0
        
        # Vectorized calculation?
        # Angles of bins
        angles = np.linspace(-np.pi, np.pi, Ntheta+1)[:-1] # Centers approx
        # Adjust for bin centers
        angles += (angles[1] - angles[0]) / 2.0
        
        # Action in polar (relative to agent orientation 0)
        # Action is in global frame (vx, vy).
        # Need to convert to agent frame?
        # My SPM is in Agent Frame (rel_angle).
        # So action should be rotated to Agent Frame.
        
        # Wait, decide_action returns global velocity.
        # But SPM is relative.
        # So we need to rotate action to relative frame to match SPM angles.
        
        # Agent orientation
        agent_theta = self.agent.orientation
        
        # Rotate action vector by -agent_theta
        ax = vx * np.cos(-agent_theta) - vy * np.sin(-agent_theta)
        ay = vx * np.sin(-agent_theta) + vy * np.cos(-agent_theta)
        
        # Now compute radial component for each bin angle
        # v_rad_bin = ax * cos(theta_bin) + ay * sin(theta_bin)
        
        cos_angles = np.cos(angles)
        sin_angles = np.sin(angles)
        
        v_rads = ax * cos_angles + ay * sin_angles
        
        # Cost function:
        # We want to avoid moving towards occupied bins (Occupancy > 0).
        # Especially if they are close (High Precision).
        # Cost += Occupancy * Precision * max(0, v_rads)
        
        # spm_tensor[0] is Occupancy
        occupancy = spm_tensor[0]
        
        # We only care if we are moving TOWARDS it (v_rads > 0)
        # Broadcast v_rads to (Nr, Ntheta)
        v_rads_grid = np.tile(v_rads, (Nr, 1))
        
        risk = occupancy * precision * np.maximum(0, v_rads_grid)
        
        cost = np.sum(risk)
        
        # Add Meta-evaluation (Instrumental Value)
        # If preferred_velocity is given, minimize distance to it.
        # J_meta = || v - v_pref ||^2
        
        if preferred_velocity is not None:
            pvx, pvy = preferred_velocity
            # Normalize preferred velocity to max speed for fair comparison? 
            # Or just use raw difference.
            diff_v = (vx - pvx)**2 + (vy - pvy)**2
            cost += 0.5 * diff_v # Weight for goal seeking
        else:
            # Default: Prefer moving forward (high speed)
            speed = np.sqrt(vx**2 + vy**2)
            cost -= 0.1 * speed # Reward speed
        
        return cost
