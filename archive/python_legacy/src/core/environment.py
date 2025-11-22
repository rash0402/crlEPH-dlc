import numpy as np
from src.utils.toroidal import toroidal_distance

class Environment:
    def __init__(self, width=800, height=600):
        self.width = width
        self.height = height
        self.agents = []
        self.obstacles = [] # List of dictionaries or objects representing obstacles
        self.time = 0.0
        self.dt = 0.1 # Time step
        
        # Environmental Haze (Stigmergy)
        # Coarse grid: 1 cell = 20x20 pixels
        self.grid_size = 20
        self.haze_grid = np.zeros((int(width/self.grid_size)+1, int(height/self.grid_size)+1))

    def add_agent(self, agent):
        self.agents.append(agent)

    def add_obstacle(self, obstacle):
        """
        obstacle: dict with keys 'x', 'y', 'radius' (for circular obstacles)
                  or 'x', 'y', 'width', 'height' (for rectangular)
        For now, let's assume circular obstacles for simplicity in SPM.
        """
        self.obstacles.append(obstacle)

    def update(self):
        """
        Update the state of the environment.
        """
        self.time += self.dt
        
        # Decay Haze
        self.haze_grid *= 0.99 # Simple decay
        
        # 1. Clamp velocities to prevent obstacle penetration
        for agent in self.agents:
            self._clamp_velocity_for_obstacles(agent)
        
        # 2. Update Agents (Kinematics)
        for agent in self.agents:
            agent.update(self.dt)
            self._enforce_boundaries(agent)
            
        # 3. Resolve Collisions (Physics)
        self._resolve_collisions()

    def _clamp_velocity_for_obstacles(self, agent):
        """Prevent agent from entering obstacles by clamping velocity."""
        for obstacle in self.obstacles:
            ox, oy = obstacle['x'], obstacle['y']
            orad = obstacle.get('radius', 10)
            
            # Current position
            dx, dy, dist = toroidal_distance(agent.position, (ox, oy), self.width, self.height)
            
            # Minimum allowed distance
            min_dist = agent.radius + orad
            
            if dist < min_dist * 1.1:  # Safety margin
                # Already too close, check if moving towards it
                # Velocity towards obstacle
                v_towards = (agent.velocity[0] * dx + agent.velocity[1] * dy) / (dist + 1e-8)
                
                if v_towards > 0:  # Moving towards obstacle
                    # Remove velocity component towards obstacle
                    nx, ny = dx / (dist + 1e-8), dy / (dist + 1e-8)
                    agent.velocity[0] -= v_towards * nx
                    agent.velocity[1] -= v_towards * ny

    def _resolve_collisions(self):
        # Simple elastic collision or repulsion
        # O(N^2) for now
        n = len(self.agents)
        for i in range(n):
            for j in range(i + 1, n):
                a1 = self.agents[i]
                a2 = self.agents[j]
                
                # Use toroidal distance
                dx, dy, dist = toroidal_distance(a1.position, a2.position, self.width, self.height)
                min_dist = a1.radius + a2.radius
                
                if dist < min_dist and dist > 0:
                    # Overlap! Push apart.
                    overlap = min_dist - dist
                    nx = dx / dist
                    ny = dy / dist
                    
                    # Move each by half overlap
                    # (Should consider mass, but assume equal)
                    push = overlap / 2.0
                    a1.position[0] -= nx * push
                    a1.position[1] -= ny * push
                    a2.position[0] += nx * push
                    a2.position[1] += ny * push
                    
                    # Exchange velocity (Elastic)?
                    # Or just kill velocity component towards each other (Inelastic/Friction)
                    # Let's do simple inelastic for stability in swarm
                    # v1_n = v1 dot n
                    # v2_n = v2 dot n
                    # v1_new = v1 - v1_n * n
                    # v2_new = v2 - v2_n * n
                    # Actually, let's just add some friction/damping
                    
                    # Simple repulsion force is enough for position update, 
                    # but for velocity, we should probably average them or bounce.
                    # Let's just leave position correction for now, it simulates "cannot pass".
        
        # Resolve Obstacle Collisions
        for agent in self.agents:
            for obstacle in self.obstacles:
                # Assume circular obstacles for now
                ox, oy = obstacle['x'], obstacle['y']
                orad = obstacle.get('radius', 10)
                
                # Use toroidal distance
                dx, dy, dist = toroidal_distance(agent.position, (ox, oy), self.width, self.height)
                min_dist = agent.radius + orad
                
                if dist < min_dist and dist > 0:
                    # Push agent out
                    overlap = min_dist - dist
                    nx = dx / dist
                    ny = dy / dist
                    
                    agent.position[0] += nx * overlap
                    agent.position[1] += ny * overlap
                    
                    # Kill velocity into obstacle
                    # v_n = v dot n
                    v_n = agent.velocity[0] * nx + agent.velocity[1] * ny
                    if v_n < 0: # Moving towards obstacle
                        agent.velocity[0] -= v_n * nx
                        agent.velocity[1] -= v_n * ny

    def _enforce_boundaries(self, agent):
        # Toroidal world: wrap around
        agent.position[0] = agent.position[0] % self.width
        agent.position[1] = agent.position[1] % self.height

    def get_entities(self):
        return self.agents + self.obstacles
