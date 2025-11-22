"""Toroidal distance calculation utilities."""
import numpy as np

def toroidal_distance(p1, p2, width, height):
    """
    Calculate the shortest distance between two points in a toroidal world.
    
    Args:
        p1: (x, y) position 1
        p2: (x, y) position 2
        width: World width
        height: World height
    
    Returns:
        (dx, dy, distance) - shortest displacement vector and distance
    """
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    
    # Consider wrap-around
    if abs(dx) > width / 2:
        dx = dx - np.sign(dx) * width
    
    if abs(dy) > height / 2:
        dy = dy - np.sign(dy) * height
    
    distance = np.sqrt(dx**2 + dy**2)
    
    return dx, dy, distance
