import pygame
import numpy as np

class Visualizer:
    def __init__(self, environment, width=800, height=600, title="AI-DLC Simulation"):
        self.environment = environment
        self.width = width
        self.height = height
        
        pygame.init()
        self.screen = pygame.display.set_mode((self.width, self.height))
        pygame.display.set_caption(title)
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("Arial", 14)

        # Colors
        self.COLOR_BG = (30, 30, 30)
        self.COLOR_AGENT = (0, 200, 255)
        self.COLOR_AGENT_DIR = (255, 255, 0)
        self.COLOR_OBSTACLE = (200, 50, 50)

    def handle_events(self):
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return False
        return True

    def render(self):
        self.screen.fill(self.COLOR_BG)
        
        # Draw Obstacles
        for obstacle in self.environment.obstacles:
            # Assuming circular obstacles for now as per environment.py comments
            if 'radius' in obstacle:
                pygame.draw.circle(self.screen, self.COLOR_OBSTACLE, 
                                   (int(obstacle['x']), int(obstacle['y'])), 
                                   int(obstacle['radius']))
        
        # Draw Agents
        for agent in self.environment.agents:
            # Scale from environment coordinates to window coordinates
            scale_x = self.width / self.environment.width
            scale_y = self.height / self.environment.height
            
            # Apply scaling and wrapping
            x = int((agent.position[0] % self.environment.width) * scale_x)
            y = int((agent.position[1] % self.environment.height) * scale_y)
            
            color = agent.color if hasattr(agent, 'color') and agent.color else (100, 150, 255)
            pygame.draw.circle(self.screen, color, (x, y), int(agent.radius * scale_x))
            
            # Draw direction indicator (scaled)
            end_x = int(x + np.cos(agent.orientation) * agent.radius * 1.5 * scale_x)
            end_y = int(y + np.sin(agent.orientation) * agent.radius * 1.5 * scale_y)
            pygame.draw.line(self.screen, self.COLOR_AGENT_DIR, (x, y), (end_x, end_y), 2)



        # Draw Info
        fps = self.clock.get_fps()
        fps_text = self.font.render(f"FPS: {fps:.1f}", True, (255, 255, 255))
        self.screen.blit(fps_text, (10, 10))

        pygame.display.flip()
        self.clock.tick(60) # Limit to 60 FPS
