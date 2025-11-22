"""
Python Viewer for Julia EPH Simulation (Sparse Foraging Task).
Receives agent data via ZeroMQ and renders using Pygame.

Displays:
- Agent positions, orientations, and FOV
- Self-haze levels (color intensity)
- Number of visible neighbors (text label)
- Coverage percentage
- Real-time plots for tracked agent (red agent)
"""
import sys
import zmq
import json
import pygame
import numpy as np
import matplotlib
matplotlib.use('TkAgg')  # Use TkAgg backend for separate window
import matplotlib.pyplot as plt
from collections import deque

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
    width, height = 800, 800  # Match simulation world size
    screen = pygame.display.set_mode((width, height))
    pygame.display.set_caption("Julia EPH Viewer - Sparse Foraging Task")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("Arial", 14)
    small_font = pygame.font.SysFont("Arial", 10)

    # Initialize real-time plots for tracked agent
    plt.ion()  # Interactive mode
    fig, axes = plt.subplots(2, 2, figsize=(10, 8))
    fig.suptitle('Agent 1 (Red) - Real-time Metrics', fontsize=14)

    # Data buffers (keep last 200 frames)
    max_history = 200
    history = {
        'frame': deque(maxlen=max_history),
        'efe': deque(maxlen=max_history),
        'self_haze': deque(maxlen=max_history),
        'belief_entropy': deque(maxlen=max_history),
        'num_visible': deque(maxlen=max_history),
        'spm_total': deque(maxlen=max_history),
        'speed': deque(maxlen=max_history)
    }

    # Configure subplots
    ax_efe = axes[0, 0]
    ax_efe.set_title('Expected Free Energy')
    ax_efe.set_xlabel('Frame')
    ax_efe.set_ylabel('EFE')
    ax_efe.grid(True, alpha=0.3)

    ax_haze = axes[0, 1]
    ax_haze.set_title('Self-Haze & Entropy')
    ax_haze.set_xlabel('Frame')
    ax_haze.set_ylabel('Value')
    ax_haze.grid(True, alpha=0.3)

    ax_spm = axes[1, 0]
    ax_spm.set_title('SPM Occupancy')
    ax_spm.set_xlabel('Frame')
    ax_spm.set_ylabel('Total Occupancy')
    ax_spm.grid(True, alpha=0.3)

    ax_metrics = axes[1, 1]
    ax_metrics.set_title('Visibility & Speed')
    ax_metrics.set_xlabel('Frame')
    ax_metrics.set_ylabel('Count / Speed')
    ax_metrics.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.show(block=False)

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
                # Render with light gray background
                screen.fill((200, 200, 200))
                
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
                    # Updated FOV parameters for sparse foraging task
                    fov_radius = 100  # Matches params.fov_range
                    fov_angle = np.radians(210)  # 210 degrees (matches Julia params)

                    # FOV color modulated by self-haze (if available)
                    self_haze = agent.get("self_haze", 0.7)  # Default to isolated state

                    # Color mapping:
                    # High self-haze (0.7-0.8, isolated) → Red/Pink
                    # Low self-haze (0.0-0.2, with neighbors) → Blue/Cyan

                    # Normalize self-haze to [0, 1] range for color calculation
                    # Assume h_max = 0.8
                    haze_normalized = min(1.0, self_haze / 0.8)

                    # Color interpolation: Blue (isolated=low haze) → Red (with neighbors=high haze)
                    # Wait, this is backwards. Let me fix it:
                    # High self-haze (isolated) → Red
                    # Low self-haze (with neighbors) → Blue

                    r = int(100 + haze_normalized * 155)  # 100 → 255
                    g = int(200 - haze_normalized * 200)  # 200 → 0
                    b = int(200 - haze_normalized * 200)  # 200 → 0

                    # Clamp to valid range
                    r = min(255, max(0, r))
                    g = min(255, max(0, g))
                    b = min(255, max(0, b))

                    fov_color = (r, g, b, 40)  # Slightly more opaque for visibility

                    draw_fov(screen, x, y, orientation, fov_radius, fov_angle, color=fov_color)

                for agent in agents:
                    x = int(agent["x"])
                    y = int(agent["y"])
                    radius = int(agent["radius"])
                    color = agent["color"]  # [r, g, b]
                    orientation = agent["orientation"]

                    # Modulate agent color by self-haze (brighter = higher haze)
                    self_haze = agent.get("self_haze", 0.0)
                    brightness = 1.0 + self_haze * 0.5  # 1.0 to 1.5
                    bright_color = tuple(min(255, int(c * brightness)) for c in color)

                    # Draw Agent
                    pygame.draw.circle(screen, bright_color, (x, y), radius)

                    # Draw Direction
                    end_x = int(x + np.cos(orientation) * radius * 1.5)
                    end_y = int(y + np.sin(orientation) * radius * 1.5)
                    pygame.draw.line(screen, (255, 255, 100), (x, y), (end_x, end_y), 2)

                    # Draw number of visible neighbors (if available)
                    num_visible = agent.get("num_visible", 0)
                    if num_visible > 0:
                        vis_text = small_font.render(str(num_visible), True, (0, 0, 0))
                        screen.blit(vis_text, (x + radius + 2, y - radius - 2))
                
                # Info (black text for light gray background)
                frame = message.get("frame", 0)
                fps = clock.get_fps()
                coverage = message.get("coverage", 0.0) * 100.0  # Convert to percentage
                info_text = f"Frame: {frame} | FPS: {fps:.1f} | Agents: {len(agents)} | Coverage: {coverage:.1f}%"
                text_surf = font.render(info_text, True, (0, 0, 0))
                screen.blit(text_surf, (10, 10))

                # Legend for self-haze visualization
                legend_text = "Self-Haze: Low (Blue FOV) → High (Red FOV)"
                legend_surf = font.render(legend_text, True, (60, 60, 60))
                screen.blit(legend_surf, (10, 30))

                pygame.display.flip()

                # Update real-time plots for tracked agent
                tracked = message.get("tracked_agent")
                if tracked is not None:
                    # Append new data
                    history['frame'].append(frame)
                    history['efe'].append(tracked.get('efe', 0))
                    history['self_haze'].append(tracked.get('self_haze', 0))
                    history['belief_entropy'].append(tracked.get('belief_entropy', 0))
                    history['num_visible'].append(tracked.get('num_visible', 0))
                    history['spm_total'].append(tracked.get('spm_total_occupancy', 0))
                    history['speed'].append(tracked.get('speed', 0))

                    # Update plots every 5 frames (for performance)
                    if frame % 5 == 0 and len(history['frame']) > 1:
                        frames = list(history['frame'])

                        # Clear and replot
                        ax_efe.clear()
                        ax_efe.plot(frames, list(history['efe']), 'b-', linewidth=2)
                        ax_efe.set_title('Expected Free Energy')
                        ax_efe.set_xlabel('Frame')
                        ax_efe.set_ylabel('EFE')
                        ax_efe.grid(True, alpha=0.3)

                        ax_haze.clear()
                        ax_haze.plot(frames, list(history['self_haze']), 'r-', label='Self-Haze', linewidth=2)
                        ax_haze.plot(frames, [h/50 for h in history['belief_entropy']], 'g-', label='Entropy/50', linewidth=2)
                        ax_haze.set_title('Self-Haze & Entropy')
                        ax_haze.set_xlabel('Frame')
                        ax_haze.set_ylabel('Value')
                        ax_haze.legend()
                        ax_haze.grid(True, alpha=0.3)

                        ax_spm.clear()
                        ax_spm.plot(frames, list(history['spm_total']), 'm-', linewidth=2)
                        ax_spm.set_title('SPM Total Occupancy')
                        ax_spm.set_xlabel('Frame')
                        ax_spm.set_ylabel('Total Occupancy')
                        ax_spm.grid(True, alpha=0.3)

                        ax_metrics.clear()
                        ax_metrics.plot(frames, list(history['num_visible']), 'c-', label='# Visible', linewidth=2)
                        ax_metrics.plot(frames, [s/10 for s in history['speed']], 'orange', label='Speed/10', linewidth=2)
                        ax_metrics.set_title('Visibility & Speed')
                        ax_metrics.set_xlabel('Frame')
                        ax_metrics.set_ylabel('Count / Speed')
                        ax_metrics.legend()
                        ax_metrics.grid(True, alpha=0.3)

                        plt.tight_layout()
                        plt.pause(0.001)  # Allow matplotlib to update
        
        except Exception as e:
            print(f"Error: {e}")
        
        clock.tick(60)

    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
