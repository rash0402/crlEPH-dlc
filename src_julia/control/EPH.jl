module EPH

using ..Types
using ..MathUtils
using Zygote
using LinearAlgebra
using Statistics

export GradientEPHController, decide_action

struct GradientEPHController
    learning_rate::Float64
    n_iterations::Int
    
    function GradientEPHController(;learning_rate=0.5, n_iterations=5)
        new(learning_rate, n_iterations)
    end
end

function decide_action(controller::GradientEPHController, agent::Agent, spm_tensor::Array{Float64, 3}, precision_matrix::Matrix{Float64}, haze_grid::Matrix{Float64}, env_width::Float64, env_height::Float64, grid_size::Int, preferred_velocity::Union{Vector{Float64}, Nothing})
    
    # Initial guess: current velocity (for continuity)
    current_action = copy(agent.velocity)
    # If velocity is very small, initialize with small random perturbation for exploration
    if norm(current_action) < 1.0
        current_action = [randn() * 5.0, randn() * 5.0]
    end
    
    # Gradient Descent
    for i in 1:controller.n_iterations
        # Compute gradient with haze-modulated SPM
        grads = Zygote.gradient(a -> cost_function(a, agent, spm_tensor, precision_matrix, haze_grid, env_width, env_height, grid_size, preferred_velocity), current_action)
        grad = grads[1]
        
        # Clip gradient
        grad = clamp.(grad, -10.0, 10.0)
        
        # Update action
        current_action -= controller.learning_rate * grad
        
        # Clamp velocity magnitude
        speed = norm(current_action)
        if speed > agent.max_speed
            current_action = (current_action / speed) * agent.max_speed
        end
    end
    
    # Smooth transition: blend with previous velocity for continuity
    # This prevents sudden jumps
    smoothing = 0.7  # 0.7 = 70% new, 30% old
    smoothed_action = smoothing * current_action + (1.0 - smoothing) * agent.velocity
    
    return smoothed_action
end

function cost_function(action::Vector{Float64}, agent::Agent, spm_tensor::Array{Float64, 3}, precision_matrix::Matrix{Float64}, haze_grid::Matrix{Float64}, env_width::Float64, env_height::Float64, grid_size::Int, preferred_velocity::Union{Vector{Float64}, Nothing})
    
    # 1. Perceptual Free Energy (F_percept)
    # SPM with haze-modulated uncertainty
    dt = 0.1 # Prediction horizon
    dx = action[1] * dt
    dy = action[2] * dt
    
    # Sample haze at predicted position (used as noise magnitude)
    predicted_x = mod(agent.position[1] + dx, env_width)
    predicted_y = mod(agent.position[2] + dy, env_height)
    
    gx = clamp(floor(Int, predicted_x / grid_size) + 1, 1, size(haze_grid, 2))
    gy = clamp(floor(Int, predicted_y / grid_size) + 1, 1, size(haze_grid, 1))
    haze_at_predicted = haze_grid[gy, gx]

    # Add deterministic noise to the SPM based on haze magnitude
    noise_factor = 0.05  # tunable
    spm_noisy = spm_tensor .+ (haze_at_predicted * noise_factor)
    
    # Pre-compute action direction vector
    speed = norm(action) + 1e-6
    dir_x = action[1] / speed
    dir_y = action[2] / speed
    
    # Iterate over SPM bins
    Nr, Nt = size(spm_tensor, 2), size(spm_tensor, 3)
    
    f_percept = 0.0
    
    # Compute perceptual cost with haze-modulated precision
    f_percept = sum(
        let
            # Bin angle
            bin_angle = ((t - 1) / Nt) * 2π - π
            # Relative angle to global
            global_bin_angle = bin_angle + agent.orientation
            bin_dir_x = cos(global_bin_angle)
            bin_dir_y = sin(global_bin_angle)
            
            # Alignment (dot product)
            alignment = dir_x * bin_dir_x + dir_y * bin_dir_y
            
            # Only penalize if moving towards (alignment > 0)
            align_factor = max(0.0, alignment)
            
            # Occupancy from SPM
            occ = spm_noisy[1, r, t]
            
            # Base precision
            base_prec = precision_matrix[r, t]
            
            # Haze-modulated precision (Lubricant Haze)
            # High haze = known area = higher certainty = LOWER effective uncertainty
            # We reduce the collision cost in high-haze areas
            # uncertainty_factor: 1.0 (no haze) -> 0.2 (max haze)
            uncertainty_factor = 1.0 - haze_at_predicted * 0.8
            
            # Effective precision (lower in high-haze areas for lubricant effect)
            effective_prec = base_prec * uncertainty_factor
            
            # Distance factor (closer bins have higher weight)
            dist_factor = 1.0 / r
            
            # Cost: collision avoidance weighted by effective precision
            occ * effective_prec * align_factor * dist_factor * speed * 10.0
        end
        for r in 1:3, t in 1:Nt # Only check close bins
    )
    
    # 2. Instrumental Value (M_meta)
    m_meta = 0.0
    
    # Goal seeking
    if preferred_velocity !== nothing
        # MSE between action and preferred
        m_meta += sum((action .- preferred_velocity).^2) * 1.0
    else
        # Random walk / Exploration if no goal
        # Just maintain some speed
        target_speed = 20.0
        m_meta += (speed - target_speed)^2 * 0.1
    end
    
    return f_percept + m_meta
end

end
