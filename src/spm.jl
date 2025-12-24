"""
SPM (Saliency Polar Map) Generation Module
Based on doc/spm_generator.jl with 3-channel output
"""

module SPM

using LinearAlgebra
using ..Config

export SPMConfig, init_spm, generate_spm_3ch

"""
SPM grid configuration
"""
struct SPMConfig
    rho_grid::Vector{Float64}    # Radial grid (log-scale)
    theta_grid::Vector{Float64}  # Angular grid
    d_max_log::Float64           # Maximum log distance
    params::SPMParams            # System parameters
end

"""
Initialize SPM grid with log-scale radial and angular coordinates
"""
function init_spm(params::SPMParams=DEFAULT_SPM)
    d_max_log = log(params.sensing_ratio)
    
    # Cell centers as sampling points
    rho_grid = collect(range(
        d_max_log / (2 * params.n_rho),
        d_max_log * (1 - 1 / (2 * params.n_rho)),
        length=params.n_rho
    ))
    
    theta_grid = collect(range(
        -params.fov_rad / 2 * (1 - 1 / params.n_theta),
        params.fov_rad / 2 * (1 - 1 / params.n_theta),
        length=params.n_theta
    ))
    
    return SPMConfig(rho_grid, theta_grid, d_max_log, params)
end

"""
Calculate normalized log distance based on surface distance
d = log(||r|| / r_total)
"""
function calc_log_dist(rel_p::Vector{Float64}, r_total::Float64)
    d_center = norm(rel_p)
    # Surface distance: 0 at contact, positive when far
    return log(max(1.0, d_center / (r_total + 1e-6)))
end

"""
Softmin aggregation for proximity saliency (fixed β for M1)
"""
function softmin_proximity(distances::Vector{Float64}, beta::Float64)
    if isempty(distances)
        return Inf
    end
    # softmin: -1/β * log(Σ exp(-β * d))
    return -1.0 / beta * log(sum(exp.(-beta .* distances)))
end

"""
Softmax aggregation for velocity (fixed β for M1)
"""
function softmax_velocity(velocities::Vector{Float64}, beta::Float64)
    if isempty(velocities)
        return 0.0
    end
    # softmax: 1/β * log(Σ exp(β * v))
    return 1.0 / beta * log(sum(exp.(beta .* velocities)))
end

"""
Generate 3-channel SPM image
- ch1: Occupancy (density)
- ch2: Proximity Saliency (surface distance based, adaptive β softmin)
- ch3: Dynamic Collision Risk (TTC based, adaptive β softmax)

Args:
    precision: Precision (Π = 1/H) for adaptive β modulation (default 1.0 = no modulation)

Returns: Array{Float64, 3} of shape (n_rho, n_theta, 3)
"""
function generate_spm_3ch(
    config::SPMConfig,
    agents_rel_pos::Vector{Vector{Float64}},
    agents_rel_vel::Vector{Vector{Float64}},
    r_agent::Float64,
    precision::Float64 = 1.0  # Default: no modulation (baseline mode)
)
    params = config.params
    spm = zeros(Float64, params.n_rho, params.n_theta, 3)
    r_total = params.r_robot + r_agent
    
    # Adaptive β modulation (EPH proposal equations 3.3.2 and 3.3.3)
    # Clamp precision to avoid extreme values
    precision_clamped = clamp(precision, 0.01, 100.0)
    
    # β_r[k] = β_r^min + (β_r^max - β_r^min) * Π[k]
    beta_r = params.beta_r_min + (params.beta_r_max - params.beta_r_min) * precision_clamped
    
    # β_ν[k] = β_ν^min + (β_ν^max - β_ν^min) * Π[k]
    beta_nu = params.beta_nu_min + (params.beta_nu_max - params.beta_nu_min) * precision_clamped
    
    for (idx, p_rel) in enumerate(agents_rel_pos)
        # 1. Basic coordinates
        rho_val = calc_log_dist(p_rel, r_total)
        
        # Calculate angle in ego-centric frame
        # theta_grid is defined from -FOV/2 to +FOV/2, where 0° = forward (+Y axis)
        # So we need angle from Y-axis: atan(x, y)
        # Right (x>0) → positive theta, Left (x<0) → negative theta
        theta_val = atan(p_rel[1], p_rel[2])

        # DEBUG: Log values specifically for debugging
        if idx == 1 # Always log for first agent to guarantee output
            open(joinpath("log", "debug_spm.log"), "a") do io
                println(io, "DEBUG_V3: p_rel=$(p_rel) rho=$(rho_val) theta=$(theta_val)")
                println(io, "DEBUG_V3: Grid th[1]=$(config.theta_grid[1]) th[end]=$(config.theta_grid[end]) rh[1]=$(config.rho_grid[1]) rh[end]=$(config.rho_grid[end])")
            end
        end
        
        # 2. Physical quantities
        # Proximity saliency: closer = higher value
        # Adaptive β_r modulation: high β_r → sharp decay (emphasize closest), low β_r → smooth decay (average)
        # Use β_r as temperature parameter: divide distance by β_r before exponential
        saliency = exp(-rho_val / max(beta_r, 0.1))
        
        # Collision risk: TTC approximation with adaptive β_ν modulation
        v_rel = agents_rel_vel[idx]
        radial_vel = -dot(p_rel, v_rel) / (norm(p_rel) + 1e-6)  # Approach velocity
        ttc_inv = max(0.0, radial_vel) / (exp(rho_val) + 1e-6)  # Inverse TTC
        # Adaptive β_ν modulation: high β_ν → sharp response, low β_ν → smooth averaging
        # Use β_ν as temperature parameter for consistency with Ch2
        risk = min(1.0, exp(beta_nu * ttc_inv) - 1.0)  # exp(β*x) - 1 for soft thresholding
        
        # 3. Region projection (Blurred Gaussian)
        for j in 1:params.n_theta, i in 1:params.n_rho
            d_rh = rho_val - config.rho_grid[i]
            d_th = theta_val - config.theta_grid[j]
            
            # Gaussian weight
            weight = exp(-(d_rh^2 + d_th^2) / (2 * params.sigma_spm^2))
            
            # Write to channels
            # Ch1: Occupancy (normalized count, binary presence in cell)
            # EPH proposal 3.3.1: clip(1/Z * Σ 1, 0, 1)
            # Count agent presence: if weight > threshold, agent contributes 1 to this cell
            if weight > 0.1
                spm[i, j, 1] += 1.0  # Count presence (will normalize later)
            end
            
            # Ch2: Proximity Saliency (distance-weighted)
            spm[i, j, 2] = max(spm[i, j, 2], weight * saliency)
            
            # Ch3: Collision Risk (velocity-weighted)
            spm[i, j, 3] = max(spm[i, j, 3], weight * risk)
        end
    end
    
    # Normalize and clip Ch1 to [0, 1]
    # Divide by a reasonable maximum count (e.g., 5 agents per cell)
    max_count = 5.0
    spm[:, :, 1] = min.(1.0, spm[:, :, 1] ./ max_count)
    
    return spm
end

end # module
