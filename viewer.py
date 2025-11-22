"""
Python Viewer for Julia EPH Simulation.
Receives agent data via ZeroMQ and renders using Pygame.
"""
import sys
import zmq
import json
import pygame
import numpy as np

def draw_fov(surface, x, y, orientation, radius, fov_angle, color=(255, 255, 255, 50)):
    """Draws a semi-transparent field of view sector."""
    # Create a surface for transparency
    fov_surf = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
    
    # Calculate start and end angles (pygame uses degrees, 0 is right, clockwise)
    # Orientation is radians, 0 is right, counter-clockwise usually in math, but pygame y is down.
    # Let's assume orientation is standard math (0=Right, pi/2=Down in screen coords if y increases down)
    
    start_angle = -np.degrees(orientation + fov_angle / 2)
    end_angle = -np.degrees(orientation - fov_angle / 2)
    
    # Draw pie slice
    rect = (0, 0, radius * 2, radius * 2)
    
    # Pygame draw.arc draws just the line. We need a polygon for filled sector.
    points = [(radius, radius)]
    
    # Steps for smooth arc
    steps = 20
    start_rad = orientation - fov_angle / 2
    end_rad = orientation + fov_angle / 2
    
    for i in range(steps + 1):
        angle = start_rad + (end_rad - start_rad) * (i / steps)
        px = radius + np.cos(angle) * radius
        py = radius + np.sin(angle) * radius
        points.append((px, py))
        
    pygame.draw.polygon(fov_surf, color, points)
    
    # Blit to main screen centered
    surface.blit(fov_surf, (x - radius, y - radius))

def main():
    # Initialize ZeroMQ
    context = zmq.Context()
    socket = context.socket(zmq.SUB)
    socket.connect("tcp://localhost:5555")
    socket.setsockopt_string(zmq.SUBSCRIBE, '')
    
    print("Connected to Julia Server at tcp://localhost:5555")
    
    # Initialize Pygame
    pygame.init()
    width, height = 800, 800
    screen = pygame.display.set_mode((width, height))
    pygame.display.set_caption("Julia EPH Viewer")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("Arial", 14)
    
    running = True
    while running:
        # Handle Pygame Events
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
        
        # Receive Data (Non-blocking)
        try:
            # Process all available messages to get the latest one
            message = None
            while True:
                try:
                    msg = socket.recv_string(flags=zmq.NOBLOCK)
                    message = json.loads(msg)
                except zmq.Again:
                    break
            
            if message:
                # Render
                screen.fill((30, 30, 30))
                
                # Draw Haze Grid (if present)
                haze_grid = message.get("haze_grid", None)
                if haze_grid is not None:
                    haze_array = np.array(haze_grid)
                    grid_h, grid_w = haze_array.shape
                    cell_width = width / grid_w
                    cell_height = height / grid_h
                    
                    for i in range(grid_h):
                        for j in range(grid_w):
                            haze_val = haze_array[i, j]
                            if haze_val > 0.01:  # Only draw visible haze
                                # Color: green for lubricant haze (attractive)
                                intensity = int(min(255, haze_val * 255))
                                color = (0, intensity, 0, int(intensity * 0.3))  # Semi-transparent green
                                
                                # Create surface for transparency
                                haze_surf = pygame.Surface((int(cell_width), int(cell_height)), pygame.SRCALPHA)
                                haze_surf.fill(color)
                                screen.blit(haze_surf, (j * cell_width, i * cell_height))
                
                agents = message.get("agents", [])
                
                # Draw FOV first (so it's behind agents)
                for agent in agents:
                    x = int(agent["x"])
                    y = int(agent["y"])
                    orientation = agent["orientation"]
                    # FOV parameters (could be dynamic, but fixed for now)
                    fov_radius = 100 # Visual radius (not full d_max=300 to avoid clutter)
                    fov_angle = np.radians(210) # 210 degrees
                    draw_fov(screen, x, y, orientation, fov_radius, fov_angle, color=(200, 200, 200, 30))

                for agent in agents:
                    x = int(agent["x"])
                    y = int(agent["y"])
                    radius = int(agent["radius"])
                    color = agent["color"] # [r, g, b]
                    orientation = agent["orientation"]
                    
                    # Draw Agent
                    pygame.draw.circle(screen, color, (x, y), radius)
                    
                    # Draw Direction
                    end_x = int(x + np.cos(orientation) * radius * 1.5)
                    end_y = int(y + np.sin(orientation) * radius * 1.5)
                    pygame.draw.line(screen, (255, 255, 100), (x, y), (end_x, end_y), 2)
                
                # Info
                frame = message.get("frame", 0)
                fps = clock.get_fps()
                info_text = f"Frame: {frame} | FPS: {fps:.1f} | Agents: {len(agents)}"
                text_surf = font.render(info_text, True, (255, 255, 255))
                screen.blit(text_surf, (10, 10))
                
                pygame.display.flip()
        
        except Exception as e:
            print(f"Error: {e}")
        
        clock.tick(60)

    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
