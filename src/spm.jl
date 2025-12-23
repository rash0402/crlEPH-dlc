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
- ch2: Proximity Saliency (surface distance based, fixed β softmin)
- ch3: Dynamic Collision Risk (TTC based)

Returns: Array{Float64, 3} of shape (n_rho, n_theta, 3)
"""
function generate_spm_3ch(
    config::SPMConfig,
    agents_rel_pos::Vector{Vector{Float64}},
    agents_rel_vel::Vector{Vector{Float64}},
    r_agent::Float64
)
    params = config.params
    spm = zeros(Float64, params.n_rho, params.n_theta, 3)
    r_total = params.r_robot + r_agent
    
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
        saliency = exp(-rho_val)
        
        # Collision risk: TTC approximation
        v_rel = agents_rel_vel[idx]
        radial_vel = -dot(p_rel, v_rel) / (norm(p_rel) + 1e-6)  # Approach velocity
        ttc_inv = max(0.0, radial_vel) / (exp(rho_val) + 1e-6)  # Inverse TTC
        risk = min(1.0, ttc_inv)
        
        # 3. Region projection (Blurred Gaussian)
        for j in 1:params.n_theta, i in 1:params.n_rho
            d_rh = rho_val - config.rho_grid[i]
            d_th = theta_val - config.theta_grid[j]
            
            # Gaussian weight
            weight = exp(-(d_rh^2 + d_th^2) / (2 * params.sigma_spm^2))
            
            # Write to channels (max aggregation)
            spm[i, j, 1] = max(spm[i, j, 1], weight)              # Occupancy
            spm[i, j, 2] = max(spm[i, j, 2], weight * saliency)   # Saliency
            spm[i, j, 3] = max(spm[i, j, 3], weight * risk)       # Risk
        end
    end
    
    return spm
end

end # module
