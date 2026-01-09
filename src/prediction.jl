"""
Prediction Module for EPH M4
Handles predictive SPM generation and Expected Free Energy (EFE) calculation.
"""

module Prediction

using LinearAlgebra
using ..SPM

export predict_next_spm, predict_next_spm_warp

"""
Predict execution of next SPM based on current SPM and action u=(v, omega).
This uses a simple egocentric warp (homography-like) assuming a static environment.
Future versions might use VAE latent dynamics.

Args:
    current_spm: Array{Float64, 3} (n_rho, n_theta, n_channels)
    u: Tuple{Float64, Float64} (v, omega)
    config: SPMConfig
    dt: Time step duration

Returns:
    predicted_spm: Array{Float64, 3}
"""
function predict_next_spm(
    current_spm::Array{Float64, 3},
    u::Tuple{Float64, Float64},
    config::SPMConfig,
    dt::Float64
)
    return predict_next_spm_warp(current_spm, u, config, dt)
end

"""
Implementation of simple warp prediction.
Back-projects each pixel of the target (next) image to the source (current) image
based on the robot's motion.
"""
function predict_next_spm_warp(
    current_spm::Array{Float64, 3},
    u::Tuple{Float64, Float64},
    config::SPMConfig,
    dt::Float64
)
    # Dimensions
    n_rho, n_theta, n_channels = size(current_spm)
    predicted_spm = zeros(Float64, n_rho, n_theta, n_channels)
    
    v, omega = u
    
    # Pre-calculate grids for efficiency could be done, but for 16x16 it's fast enough.
    
    # Iterate over every pixel in the *predicted* (next) image
    for i_next in 1:n_rho
        rho_next = config.rho_grid[i_next]
        dist_next = exp(rho_next)
        
        for j_next in 1:n_theta
            theta_next = config.theta_grid[j_next]
            
            # 1. Next Polar -> Next Cartesian via Robot Frame
            # theta=0 is +Y (Forward), theta>0 is Right (+X)
            # x = d * sin(theta), y = d * cos(theta)
            x_next = dist_next * sin(theta_next)
            y_next = dist_next * cos(theta_next)
            
            # 2. Next Cartesian -> Current Cartesian (Inverse Motion)
            # P_curr = Rot(w*dt) * P_next + [0, v*dt]
            # Rotation by +omega*dt
            d_rot = omega * dt
            c_rot = cos(d_rot)
            s_rot = sin(d_rot)
            
            x_rot = x_next * c_rot - y_next * s_rot
            y_rot = x_next * s_rot + y_next * c_rot
            
            x_curr = x_rot
            y_curr = y_rot + v * dt
            
            # 3. Current Cartesian -> Current Polar
            dist_curr = sqrt(x_curr^2 + y_curr^2 + 1e-6) # Avoid 0
            # atan(x, y) gives angle from Y-axis
            theta_curr = atan(x_curr, y_curr)
            rho_curr = log(max(1e-6, dist_curr))
            
            # 4. Bilinear Sampling
            # Get grid bounds
            rho_min = config.rho_grid[1]
            rho_max = config.rho_grid[end]
            rho_step = (rho_max - rho_min) / (n_rho - 1)
            
            theta_min = config.theta_grid[1]
            theta_max = config.theta_grid[end]
            theta_step = (theta_max - theta_min) / (n_theta - 1)
            
            # Float indices (1-based)
            u_coord = 1.0 + (rho_curr - rho_min) / rho_step
            v_coord = 1.0 + (theta_curr - theta_min) / theta_step
            
            # Check bounds (soft margins?)
            # For simplicity, if out of bounds, value is 0
            if u_coord >= 1.0 && u_coord <= n_rho &&
               v_coord >= 1.0 && v_coord <= n_theta
               
                # Bilinear Interpolation
                u0 = floor(Int, u_coord)
                u1 = u0 + 1
                v0 = floor(Int, v_coord)
                v1 = v0 + 1
                
                # Weights
                wu = u_coord - u0
                wv = v_coord - v0
                
                # Clamp indices for safety (though check above handles most)
                u1 = min(u1, n_rho)
                v1 = min(v1, n_theta)
                
                for c in 1:n_channels
                    val00 = current_spm[u0, v0, c]
                    val01 = current_spm[u0, v1, c]
                    val10 = current_spm[u1, v0, c]
                    val11 = current_spm[u1, v1, c]
                    
                    # Interpolate
                    val0 = val00 * (1 - wv) + val01 * wv
                    val1 = val10 * (1 - wv) + val11 * wv
                    val = val0 * (1 - wu) + val1 * wu
                    
                    predicted_spm[i_next, j_next, c] = val
                end
            else
                # Out of bounds -> 0
                for c in 1:n_channels
                    predicted_spm[i_next, j_next, c] = 0.0
                end
            end
        end
    end
    
    return predicted_spm
end

"""
Wrapper for generic arrays (e.g. Dual numbers)
"""
function predict_next_spm(
    current_spm::AbstractArray{T, 3},
    u::AbstractVector, # Might be Vector{Dual}
    config::SPMConfig,
    dt::Float64
) where T
    # Convert vector u to tuple for consistency
    u_tuple = (u[1], u[2])
    # Create output array of correct type (promoting T and u types)
    # Using specific implementation for differentiability
    
    # We need to define a differentiable version.
    # The existing predict_next_spm_warp needs to handle T being Dual.
    # We should make predict_next_spm_warp generic first.
    return predict_next_spm_warp_generic(current_spm, u_tuple, config, dt)
end

function predict_next_spm_warp_generic(
    current_spm::AbstractArray{T, 3},
    u::Tuple{Any, Any},
    config::SPMConfig,
    dt::Float64
) where T
    n_rho, n_theta, n_channels = size(current_spm)
    # Determine output type (might be Dual)
    OutT = promote_type(T, typeof(u[1]), typeof(u[2]))
    predicted_spm = zeros(OutT, n_rho, n_theta, n_channels)
    
    v, omega = u
    
    # ... Same logic as above but generic ...
    # To avoid duplication, I will put the generic logic in one function
    # and call it.
    
    # Iterate over predicted pixels
    for i_next in 1:n_rho
        rho_next = config.rho_grid[i_next]
        dist_next = exp(rho_next)
        
        for j_next in 1:n_theta
            theta_next = config.theta_grid[j_next]
            
            x_next = dist_next * sin(theta_next)
            y_next = dist_next * cos(theta_next)
            
            d_rot = omega * dt
            c_rot = cos(d_rot)
            s_rot = sin(d_rot)
            
            x_rot = x_next * c_rot - y_next * s_rot
            y_rot = x_next * s_rot + y_next * c_rot
            
            x_curr = x_rot
            y_curr = y_rot + v * dt
            
            dist_curr = sqrt(x_curr^2 + y_curr^2 + 1e-6)
            theta_curr = atan(x_curr, y_curr)
            rho_curr = log(max(1e-6, dist_curr))
            
            rho_min = config.rho_grid[1]
            rho_max = config.rho_grid[end]
            rho_step = (rho_max - rho_min) / (n_rho - 1)
            
            theta_min = config.theta_grid[1]
            theta_max = config.theta_grid[end]
            theta_step = (theta_max - theta_min) / (n_theta - 1)
            
            u_coord = 1.0 + (rho_curr - rho_min) / rho_step
            v_coord = 1.0 + (theta_curr - theta_min) / theta_step
            
            if u_coord >= 1.0 && u_coord <= n_rho &&
               v_coord >= 1.0 && v_coord <= n_theta
               
                u0 = floor(Int, u_coord)
                u1 = min(u0 + 1, n_rho)
                v0 = floor(Int, v_coord)
                v1 = min(v0 + 1, n_theta)
                
                wu = u_coord - u0
                wv = v_coord - v0
                
                for c in 1:n_channels
                     val00 = current_spm[u0, v0, c]
                     val01 = current_spm[u0, v1, c]
                     val10 = current_spm[u1, v0, c]
                     val11 = current_spm[u1, v1, c]
                     
                     val0 = val00 * (1 - wv) + val01 * wv
                     val1 = val10 * (1 - wv) + val11 * wv
                     val = val0 * (1 - wu) + val1 * wu
                     
                     predicted_spm[i_next, j_next, c] = val
                end
            else
                for c in 1:n_channels
                    predicted_spm[i_next, j_next, c] = 0.0
                end
            end
        end
    end
    
    return predicted_spm
end

end # module
