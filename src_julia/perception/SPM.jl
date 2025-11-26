module SPM

using ..Types
using ..MathUtils
using LinearAlgebra

export compute_spm, get_precision_matrix

struct SPMParams
    Nr::Int
    Ntheta::Int
    d_max::Float64
    sigma_r::Float64
    sigma_theta::Float64
    fov_angle::Float64  # Field of view angle (radians)

    function SPMParams(;Nr=6, Ntheta=6, d_max=300.0, sigma_r=0.5, sigma_theta=0.5, fov_angle=210.0*π/180.0)
        new(Nr, Ntheta, d_max, sigma_r, sigma_theta, fov_angle)
    end
end

function compute_spm(agent::Agent, env::Environment, params::SPMParams)
    # Initialize tensor (3 channels: Occupancy, Radial Vel, Tangential Vel)
    spm_tensor = zeros(3, params.Nr, params.Ntheta)
    
    for other in env.agents
        if other === agent
            continue
        end
        
        # Relative position
        dx, dy, dist = toroidal_distance(agent.position, other.position, env.width, env.height)

        if dist > params.d_max
            continue
        end

        angle = atan(dy, dx)
        rel_angle = normalize_angle(angle - agent.orientation)

        # FOV check: only include agents within the field of view
        if abs(rel_angle) > params.fov_angle / 2.0
            continue
        end
        
        # Relative velocity
        vx_rel = other.velocity[1] - agent.velocity[1]
        vy_rel = other.velocity[2] - agent.velocity[2]
        
        # Project to radial and tangential
        er_x, er_y = cos(angle), sin(angle)
        et_x, et_y = -sin(angle), cos(angle)
        
        v_radial = vx_rel * er_x + vy_rel * er_y
        v_tangential = vx_rel * et_x + vy_rel * et_y
        
        _add_to_tensor!(spm_tensor, dist, rel_angle, v_radial, v_tangential, agent.personal_space, params)
    end
    
    return spm_tensor
end

function _add_to_tensor!(tensor, dist, angle, v_r, v_t, ps, params)
    # 1. Radial Mapping
    r_center = 0.0
    if dist <= ps
        r_center = 0.0
    else
        if params.d_max <= ps
            return
        end
        
        log_ps = log(ps)
        log_dm = log(params.d_max)
        scale = (params.Nr - 2) / (log_dm - log_ps + 1e-6)
        
        r_center = 1.0 + scale * (log(dist) - log_ps)
    end
    
    # 2. Angular Mapping within FOV range
    # angle is in range [-fov_angle/2, +fov_angle/2]
    # Map to [0, Ntheta] range, then add 1 for Julia 1-based indexing
    # Normalized position within FOV: (angle + fov_angle/2) / fov_angle gives [0, 1]
    half_fov = params.fov_angle / 2.0
    theta_normalized = (angle + half_fov) / params.fov_angle  # [0, 1] within FOV
    theta_center = theta_normalized * params.Ntheta + 0.5  # [0.5, Ntheta+0.5], center of bins
    
    # 3. Gaussian Splatting
    r_idx_base = round(Int, r_center) + 1 # +1 because r_center starts from 0.0 (bin 0 in Python is index 1 in Julia)
    # Wait, let's align with Python logic:
    # Python r indices: 0 to Nr-1.
    # Julia r indices: 1 to Nr.
    # If r_center is 0.0, that means index 1.
    r_idx_base = round(Int, r_center) + 1
    
    t_idx_base = round(Int, theta_center)
    
    k_size = 2
    
    for r in (r_idx_base - k_size):(r_idx_base + k_size)
        for t in (t_idx_base - k_size):(t_idx_base + k_size)
            if 1 <= r <= params.Nr
                # Handle angular wrap-around
                # t is 1-based index.
                # If t=0 -> Ntheta, t=Ntheta+1 -> 1
                t_wrapped = mod1(t, params.Ntheta)
                
                # Calculate weight
                # r is 1-based, so dr should be (r-1) - r_center
                dr = (r - 1) - r_center
                
                # Angular diff within FOV range
                # t_wrapped ranges from 1 to Ntheta
                # Map back to angle in FOV range [-fov_angle/2, +fov_angle/2]
                # Bin center: t_wrapped=1 -> -fov_angle/2, t_wrapped=Ntheta -> +fov_angle/2
                bin_normalized = (t_wrapped - 0.5) / params.Ntheta  # [0, 1]
                bin_angle = bin_normalized * params.fov_angle - half_fov
                diff_angle = bin_angle - angle
                
                # Convert diff_angle to bin units (within FOV range)
                dt_eff = (diff_angle / params.fov_angle) * params.Ntheta
                
                weight = exp(-(dr^2)/(2*params.sigma_r^2) - (dt_eff^2)/(2*params.sigma_theta^2))
                
                tensor[1, r, t_wrapped] += weight
                tensor[2, r, t_wrapped] += weight * v_r
                tensor[3, r, t_wrapped] += weight * v_t
            end
        end
    end
end

function get_precision_matrix(agent::Agent, params::SPMParams)
    ps = agent.personal_space
    tau = 5.0
    
    precision = zeros(params.Nr, params.Ntheta)
    
    for r in 1:params.Nr
        dist = 0.0
        if r == 1
            dist = 0.0
        else
            log_ps = log(ps)
            log_dm = log(params.d_max)
            scale = (params.Nr - 2) / (log_dm - log_ps + 1e-6)
            
            # r is 1-based. Python r=1 is Julia r=2.
            # Formula: log_d = (r_0based - 1) / scale + log_ps
            # Julia: r_0based = r - 1
            log_d = ((r - 1) - 1) / scale + log_ps
            dist = exp(log_d)
        end
        
        val = 1.0 / (1.0 + exp(-(ps - dist) / tau))
        precision[r, :] .= val
    end
    
    return precision
end

end
