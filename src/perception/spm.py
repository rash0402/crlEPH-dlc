import numpy as np
from src.utils.math_utils import cartesian_to_polar, normalize_angle
from src.utils.toroidal import toroidal_distance

class SaliencyPolarMap:
    def __init__(self, Nr=6, Ntheta=6, d_max=300.0, sigma_r=0.5, sigma_theta=0.5):
        self.Nr = Nr
        self.Ntheta = Ntheta
        self.d_max = d_max
        self.sigma_r = sigma_r # Softness of radial mapping
        self.sigma_theta = sigma_theta # Softness of angular mapping
        
        # Pre-compute bin centers if needed, or just use dynamic mapping
        self.angle_bins = np.linspace(-np.pi, np.pi, Ntheta + 1)

    def compute_spm(self, agent, environment):
        """
        Compute the SPM tensor for the given agent in the environment.
        Returns: numpy.ndarray of shape (Channels, Nr, Ntheta)
        Channels: 0: Occupancy, 1: Radial Vel, 2: Tangential Vel
        """
        # Initialize tensor
        spm_tensor = np.zeros((3, self.Nr, self.Ntheta))
        
        # Get relative state of all entities
        entities = environment.get_entities()
        
        # World dimensions for toroidal distance
        world_width = environment.width
        world_height = environment.height
        
        for entity in entities:
            if entity is agent:
                continue
                
            # Relative position using toroidal distance
            if isinstance(entity, dict):
                # Obstacle dict {'x':..., 'y':...}
                ex, ey = entity['x'], entity['y']
                has_vel = False
            else:
                ex, ey = entity.position[0], entity.position[1]
                has_vel = hasattr(entity, 'velocity')

            # Use toroidal distance
            dx, dy, dist = toroidal_distance(
                agent.position, 
                (ex, ey), 
                world_width, 
                world_height
            )
            angle = np.arctan2(dy, dx)
            
            # Relative angle in agent's frame
            rel_angle = normalize_angle(angle - agent.orientation)
            
            if dist > self.d_max:
                continue
                
            # Relative velocity
            if has_vel:
                vx_rel = entity.velocity[0] - agent.velocity[0]
                vy_rel = entity.velocity[1] - agent.velocity[1]
                
                # Project to radial and tangential components
                # Radial unit vector at entity position
                er_x, er_y = np.cos(angle), np.sin(angle)
                # Tangential unit vector
                et_x, et_y = -np.sin(angle), np.cos(angle)
                
                v_radial = vx_rel * er_x + vy_rel * er_y
                v_tangential = vx_rel * et_x + vy_rel * et_y
            else:
                # Static obstacle
                v_radial = 0.0
                v_tangential = 0.0
                # If agent is moving, static obstacle has relative velocity
                vx_rel = -agent.velocity[0]
                vy_rel = -agent.velocity[1]
                er_x, er_y = np.cos(angle), np.sin(angle)
                et_x, et_y = -np.sin(angle), np.cos(angle)
                v_radial = vx_rel * er_x + vy_rel * er_y
                v_tangential = vx_rel * et_x + vy_rel * et_y

            # Map to SPM bins (Soft Mapping)
            self._add_to_tensor(spm_tensor, dist, rel_angle, v_radial, v_tangential, agent)
            
        return spm_tensor

    def _add_to_tensor(self, tensor, dist, angle, v_r, v_t, agent):
        """
        Add a single entity to the tensor using Gaussian Kernel (Soft Mapping).
        """
        # 1. Radial Mapping
        ps = getattr(agent, 'personal_space', 20.0) # Default ps
        
        if dist <= ps:
            # Intimate zone.
            r_center = 0.0
        else:
            # Logarithmic mapping from ps to d_max
            if self.d_max <= ps:
                return 
            
            log_ps = np.log(ps)
            log_dm = np.log(self.d_max)
            scale = (self.Nr - 2) / (log_dm - log_ps + 1e-6)
            
            r_center = 1.0 + scale * (np.log(dist) - log_ps)
            
        # 2. Angular Mapping
        # Map [-pi, pi] to [0, Ntheta]
        theta_center = (angle + np.pi) / (2 * np.pi) * self.Ntheta
        
        # 3. Gaussian Splatting
        r_idx_base = int(np.round(r_center))
        t_idx_base = int(np.round(theta_center))
        
        # Kernel range
        k_size = 2
        for r in range(r_idx_base - k_size, r_idx_base + k_size + 1):
            for t in range(t_idx_base - k_size, t_idx_base + k_size + 1):
                if 0 <= r < self.Nr:
                    # Handle angular wrap-around
                    t_wrapped = t % self.Ntheta
                    
                    # Calculate weight
                    dr = r - r_center
                    
                    # Re-compute angular diff properly
                    # angle of bin center
                    bin_angle = (t_wrapped / self.Ntheta) * 2 * np.pi - np.pi
                    diff_angle = normalize_angle(bin_angle - angle)
                    # Convert diff_angle to bin units
                    dt_eff = (diff_angle / (2 * np.pi)) * self.Ntheta
                    
                    weight = np.exp(-(dr**2)/(2*self.sigma_r**2) - (dt_eff**2)/(2*self.sigma_theta**2))
                    
                    # Add to tensor
                    tensor[0, r, t_wrapped] += weight
                    tensor[1, r, t_wrapped] += weight * v_r
                    tensor[2, r, t_wrapped] += weight * v_t

    def get_precision_matrix(self, agent):
        """
        Compute Precision Matrix based on Personal Space.
        Returns: numpy.ndarray of shape (Nr, Ntheta)
        """
        ps = getattr(agent, 'personal_space', 20.0)
        tau = 5.0 # Transition width
        
        precision = np.zeros((self.Nr, self.Ntheta))
        
        for r in range(self.Nr):
            # Inverse mapping r -> dist
            if r == 0:
                dist = 0.0 
            else:
                log_ps = np.log(ps)
                log_dm = np.log(self.d_max)
                scale = (self.Nr - 2) / (log_dm - log_ps + 1e-6)
                
                log_d = (r - 1) / scale + log_ps
                dist = np.exp(log_d)
            
            # Sigmoid
            val = 1.0 / (1.0 + np.exp(-(ps - dist) / tau))
            precision[r, :] = val
            
        return precision
