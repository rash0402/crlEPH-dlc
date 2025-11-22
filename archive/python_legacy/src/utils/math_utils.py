import numpy as np

def normalize_angle(angle):
    """
    Normalize angle to be within [-pi, pi].
    """
    return (angle + np.pi) % (2 * np.pi) - np.pi

def cartesian_to_polar(x, y):
    """
    Convert Cartesian coordinates to Polar coordinates.
    Returns (r, theta).
    """
    r = np.sqrt(x**2 + y**2)
    theta = np.arctan2(y, x)
    return r, theta

def polar_to_cartesian(r, theta):
    """
    Convert Polar coordinates to Cartesian coordinates.
    Returns (x, y).
    """
    x = r * np.cos(theta)
    y = r * np.sin(theta)
    return x, y

def distance(p1, p2):
    """
    Euclidean distance between two points p1 and p2.
    p1, p2: numpy arrays or tuples (x, y)
    """
    return np.linalg.norm(np.array(p1) - np.array(p2))
