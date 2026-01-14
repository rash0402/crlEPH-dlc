"""
SPM (Saliency Polar Map) Reconstructor for Python
Re-implements Julia's SPM generation logic for visualization

This module provides simplified SPM reconstruction for viewer purposes.
For training, use the Julia implementation in src/spm.jl.
"""

import numpy as np
from typing import Tuple, Optional


class SPMConfig:
    """SPM configuration parameters"""

    def __init__(
        self,
        n_rho: int = 16,
        n_theta: int = 16,
        sensing_ratio: float = 7.5,
        r_robot: float = 1.5,
        r_agent: float = 0.5,
        h_critical: float = 0.0,
        h_peripheral: float = 0.5,
        rho_index_critical: int = 6
    ):
        self.n_rho = n_rho
        self.n_theta = n_theta
        self.sensing_ratio = sensing_ratio
        self.r_robot = r_robot
        self.r_agent = r_agent
        self.d_max = sensing_ratio * (r_robot + r_agent)

        # Haze parameters
        self.h_critical = h_critical
        self.h_peripheral = h_peripheral
        self.rho_index_critical = rho_index_critical

        # Create log-polar grid
        self.rho_grid = self._create_rho_grid()
        self.theta_grid = np.linspace(0, 2*np.pi, n_theta, endpoint=False)

    def _create_rho_grid(self) -> np.ndarray:
        """
        Create logarithmic radial grid (bin edges) - Julia-compatible.

        Uses normalized distance: d_norm = d / r_total ∈ [1.0, sensing_ratio]
        Then applies log: rho = log(d_norm) ∈ [0, log(sensing_ratio)]
        """
        r_total = self.r_robot + self.r_agent

        # Normalized distance range: [1.0, sensing_ratio]
        # Log space: [0, log(sensing_ratio)]
        log_min = 0.0  # log(1.0)
        log_max = np.log(self.sensing_ratio)

        # Log-spaced bin edges in log space
        rho_log_edges = np.linspace(log_min, log_max, self.n_rho + 1)

        # Convert back to actual distance (unnormalized)
        # d = r_total * exp(rho)
        distances = r_total * np.exp(rho_log_edges)

        return distances


def relative_position_torus(pos1: np.ndarray, pos2: np.ndarray, world_size: Tuple[float, float]) -> np.ndarray:
    """
    Calculate relative position from pos1 to pos2 in toroidal world (shortest path).

    Args:
        pos1: [N, 2] or [2] - Source position(s)
        pos2: [2] - Target position
        world_size: (width, height) of toroidal world

    Returns:
        rel_pos: [N, 2] or [2] - Relative position vector
    """
    diff = pos2 - pos1  # [N, 2] or [2]

    # Handle both 1D and 2D arrays
    if diff.ndim == 1:
        # Single position: [2]
        for i, size in enumerate(world_size):
            if diff[i] > size / 2:
                diff[i] -= size
            elif diff[i] < -size / 2:
                diff[i] += size
    else:
        # Multiple positions: [N, 2]
        for i, size in enumerate(world_size):
            # Wrap around at boundaries
            mask_pos = diff[:, i] > size / 2
            mask_neg = diff[:, i] < -size / 2
            diff[mask_pos, i] -= size
            diff[mask_neg, i] += size

    return diff


def reconstruct_spm_3ch(
    ego_pos: np.ndarray,
    ego_heading: float,
    all_positions: np.ndarray,
    all_velocities: np.ndarray,
    obstacles: np.ndarray,
    config: SPMConfig,
    r_agent: float = 0.5,
    world_size: Optional[Tuple[float, float]] = None,
    ego_velocity: Optional[np.ndarray] = None
) -> np.ndarray:
    """
    Reconstruct 3-channel SPM for a single agent

    Args:
        ego_pos: [2] Ego agent position (x, y)
        ego_heading: Ego agent heading angle [rad]
        all_positions: [N, 2] All agent positions
        all_velocities: [N, 2] All agent velocities
        obstacles: [M, 2] Obstacle positions
        config: SPM configuration
        r_agent: Agent radius
        world_size: (width, height) for toroidal world
        ego_velocity: [2] Ego agent velocity (for obstacle collision risk calculation)

    Returns:
        spm: [n_rho, n_theta, 3] SPM tensor
            - Channel 0: Occupancy (binary)
            - Channel 1: Proximity saliency (1/d)
            - Channel 2: Collision hazard (TTC-based)
    """
    n_rho = config.n_rho
    n_theta = config.n_theta

    # Initialize SPM
    spm = np.zeros((n_rho, n_theta, 3), dtype=np.float32)

    # Transform to ego-centric frame (with toroidal boundary consideration)
    if world_size is not None:
        # Toroidal world: Calculate shortest distance considering boundary wrapping
        relative_positions = relative_position_torus(ego_pos, all_positions, world_size)
    else:
        # Non-toroidal world: Simple subtraction
        relative_positions = all_positions - ego_pos  # [N, 2]

    # Rotate to ego heading frame with forward direction pointing upward (Y+ direction)
    # 1. Rotate by -ego_heading to align heading direction with X+ axis
    # 2. Rotate by +90° to make heading direction point to Y+ (upward)
    rotation_angle = -ego_heading + np.pi / 2.0
    cos_h = np.cos(rotation_angle)
    sin_h = np.sin(rotation_angle)
    rotation_matrix = np.array([[cos_h, -sin_h], [sin_h, cos_h]])

    relative_positions = relative_positions @ rotation_matrix.T
    relative_velocities = all_velocities @ rotation_matrix.T

    # Filter agents within sensing range (exclude ego)
    distances = np.linalg.norm(relative_positions, axis=1)
    in_range = (distances < config.d_max) & (distances > 0.1)

    visible_positions = relative_positions[in_range, :]
    visible_velocities = relative_velocities[in_range, :]
    visible_distances = distances[in_range]

    # Convert to polar coordinates
    # Note: In ego-centric frame, forward direction is Y+ (upward)
    # Angle from Y-axis: atan2(x, y) gives angle from Y+ axis
    # This matches Julia's implementation: atan(p_rel[1], p_rel[2])
    angles_from_forward = np.arctan2(visible_positions[:, 0], visible_positions[:, 1])  # [-pi, pi]

    # FOV filtering: Keep only agents within ±FOV/2 from forward direction
    # FOV = 210° = 3.665 rad, so FOV/2 = 105° = 1.833 rad
    fov_rad = np.deg2rad(210.0)
    fov_half = fov_rad / 2.0

    # Filter by FOV
    in_fov = np.abs(angles_from_forward) <= fov_half

    visible_positions = visible_positions[in_fov, :]
    visible_velocities = visible_velocities[in_fov, :]
    visible_distances = visible_distances[in_fov]
    angles_from_forward = angles_from_forward[in_fov]

    # Bin agents into SPM cells
    rho_bin_edges = config.rho_grid  # [n_rho + 1] bin edges

    # Calculate normalized log distance (rho_val) and physical quantities for each agent
    r_total = config.r_robot + config.r_agent

    for i, (pos, vel, dist, angle_from_forward) in enumerate(zip(visible_positions, visible_velocities, visible_distances, angles_from_forward)):
        # Normalized log distance (Julia-compatible)
        rho_val = np.log(max(1.0, dist / r_total))

        # Ch2: Proximity saliency (exponential decay with distance)
        # Use fixed beta_r = 5.0 (matches Julia's DEFAULT_SPM.beta_r_fixed)
        beta_r = 5.0
        saliency = np.exp(-rho_val * beta_r)

        # Ch3: Collision risk (TTC-based with exponential response)
        # Calculate radial velocity (approach velocity)
        radial_vel = -np.dot(pos, vel) / (dist + 1e-6)

        # Inverse TTC (Julia-compatible: use normalized distance)
        # Julia: ttc_inv = radial_vel / exp(rho_val) = radial_vel * r_total / dist
        # This ensures consistent scaling across different agent/robot sizes
        ttc_inv = max(0.0, radial_vel) / (np.exp(rho_val) + 1e-6)

        # Use fixed beta_nu = 1.0 for now (Julia uses adaptive, but we simplify)
        beta_nu = 1.0
        risk = min(1.0, np.exp(beta_nu * ttc_inv) - 1.0)

        # Region projection with Gaussian blur (Julia-compatible)
        # sigma_spm = 0.25 (from DEFAULT_SPM)
        sigma_spm = 0.25

        for theta_idx in range(n_theta):
            for rho_idx in range(n_rho):
                # Calculate distance in log-polar space
                # Need to get rho_grid center values (bin centers, not edges)
                rho_center = (rho_bin_edges[rho_idx] + rho_bin_edges[rho_idx + 1]) / 2.0
                rho_center_log = np.log(max(1.0, rho_center / r_total))

                # Theta center: map from bin index to angle
                theta_center = -fov_half + (theta_idx + 0.5) * (fov_rad / n_theta)

                # Distance in log-polar space
                d_rh = rho_val - rho_center_log
                d_th = angle_from_forward - theta_center

                # Gaussian weight
                weight = np.exp(-(d_rh**2 + d_th**2) / (2 * sigma_spm**2))

                # Write to channels (Julia-compatible)
                if weight > 0.1:
                    spm[rho_idx, theta_idx, 0] += 1.0  # Ch1: Occupancy (count)

                # Ch2: Proximity saliency (max aggregation with Gaussian weight)
                spm[rho_idx, theta_idx, 1] = max(spm[rho_idx, theta_idx, 1], weight * saliency)

                # Ch3: Collision risk (max aggregation with Gaussian weight)
                spm[rho_idx, theta_idx, 2] = max(spm[rho_idx, theta_idx, 2], weight * risk)

    # Process obstacles (if any)
    if obstacles.shape[0] > 0:
        # Apply toroidal boundary consideration for obstacles too
        if world_size is not None:
            relative_obstacles = relative_position_torus(ego_pos, obstacles, world_size)
        else:
            relative_obstacles = obstacles - ego_pos
        relative_obstacles = relative_obstacles @ rotation_matrix.T

        obs_distances = np.linalg.norm(relative_obstacles, axis=1)
        obs_in_range = obs_distances < config.d_max

        visible_obstacles = relative_obstacles[obs_in_range, :]
        visible_obs_distances = obs_distances[obs_in_range]

        if len(visible_obstacles) > 0:
            # Angle from forward direction (Y+ axis)
            obs_angles_from_forward = np.arctan2(visible_obstacles[:, 0], visible_obstacles[:, 1])

            # FOV filtering for obstacles
            obs_in_fov = np.abs(obs_angles_from_forward) <= fov_half

            visible_obstacles = visible_obstacles[obs_in_fov, :]
            visible_obs_distances = visible_obs_distances[obs_in_fov]
            obs_angles_from_forward = obs_angles_from_forward[obs_in_fov]

            for obs_pos, obs_dist, obs_angle_from_forward in zip(visible_obstacles, visible_obs_distances, obs_angles_from_forward):
                # Normalized log distance
                rho_val = np.log(max(1.0, obs_dist / r_total))

                # Ch2: Proximity saliency - 障害物は常に高危険
                saliency = 1.0  # Maximum saliency for obstacles

                # Ch3: Collision risk - TTC-based calculation
                # 障害物は静止物体（速度ゼロ）
                # エージェントが障害物に接近している場合のみリスクあり
                if ego_velocity is not None:
                    # エゴエージェント速度を回転変換（同じ座標系に）
                    ego_vel_rotated = ego_velocity @ rotation_matrix.T

                    # 接近速度（radial velocity）を計算
                    # 障害物速度 = 0 → 相対速度 = エゴ速度
                    radial_vel = -np.dot(obs_pos, ego_vel_rotated) / (obs_dist + 1e-6)

                    # Inverse TTC (Julia-compatible: use normalized distance)
                    # Julia: ttc_inv = radial_vel / exp(rho_val) = radial_vel * r_total / dist
                    # 速い速度で接近するほどリスク高、近い距離ほどリスク高
                    ttc_inv = max(0.0, radial_vel) / (np.exp(rho_val) + 1e-6)

                    # 衝突リスク（Julia互換）
                    beta_nu = 1.0
                    risk = min(1.0, np.exp(beta_nu * ttc_inv) - 1.0)
                else:
                    # ego_velocityが提供されない場合は従来通り最大リスク
                    risk = 1.0

                # Gaussian blur for obstacles
                sigma_spm = 0.25

                for theta_idx in range(n_theta):
                    for rho_idx in range(n_rho):
                        rho_center = (rho_bin_edges[rho_idx] + rho_bin_edges[rho_idx + 1]) / 2.0
                        rho_center_log = np.log(max(1.0, rho_center / r_total))
                        theta_center = -fov_half + (theta_idx + 0.5) * (fov_rad / n_theta)

                        d_rh = rho_val - rho_center_log
                        d_th = obs_angle_from_forward - theta_center

                        weight = np.exp(-(d_rh**2 + d_th**2) / (2 * sigma_spm**2))

                        if weight > 0.1:
                            spm[rho_idx, theta_idx, 0] += 1.0

                        spm[rho_idx, theta_idx, 1] = max(spm[rho_idx, theta_idx, 1], weight * saliency)
                        spm[rho_idx, theta_idx, 2] = max(spm[rho_idx, theta_idx, 2], weight * risk)

    # Normalize channels (Julia-compatible)
    # Ch1: Occupancy - normalize by max expected agents per cell (5.0)
    spm[:, :, 0] = np.clip(spm[:, :, 0] / 5.0, 0, 1)

    # Ch2 and Ch3: Already in [0, 1] range due to exp(-rho*beta) and exp(beta*ttc)-1
    # No normalization needed (Julia doesn't normalize these either)

    return spm


def predict_spm_with_vae(
    spm_current: np.ndarray,
    action: np.ndarray,
    vae_model=None
) -> Optional[np.ndarray]:
    """
    Predict next SPM using VAE model

    Args:
        spm_current: [n_rho, n_theta, 3] Current SPM
        action: [2] Control input (v, omega)
        vae_model: Trained VAE model (optional)

    Returns:
        spm_pred: [n_rho, n_theta, 3] Predicted SPM (or None if no model)
    """
    if vae_model is None:
        return None

    # TODO: Implement VAE prediction
    # This requires loading the trained BSON model and running inference
    # For now, return None
    return None
