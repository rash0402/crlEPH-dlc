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

function decide_action(controller::GradientEPHController, agent::Agent, spm_tensor::Array{Float64, 3}, precision_matrix::Matrix{Float64}, env_haze::Float64, preferred_velocity::Union{Vector{Float64}, Nothing})
    
    # Initial guess: current velocity (for continuity)
    current_action = copy(agent.velocity)
    # If velocity is very small, initialize with small random perturbation for exploration
    if norm(current_action) < 1.0
        current_action = [randn() * 5.0, randn() * 5.0]
    end
    
    # Gradient Descent
    for i in 1:controller.n_iterations
        # Compute gradient
        grads = Zygote.gradient(a -> cost_function(a, agent, spm_tensor, precision_matrix, env_haze, preferred_velocity), current_action)
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

function cost_function(action::Vector{Float64}, agent::Agent, spm_tensor::Array{Float64, 3}, precision_matrix::Matrix{Float64}, env_haze::Float64, preferred_velocity::Union{Vector{Float64}, Nothing})
    
    # 1. Perceptual Free Energy (F_percept)
    # Simplified: Minimize collision risk based on SPM occupancy
    # We want to avoid directions where occupancy is high.
    # Predicted position change
    dt = 0.1 # Prediction horizon
    dx = action[1] * dt
    dy = action[2] * dt
    
    # Map action to SPM coordinates (approximate)
    # We check if the action vector points towards high occupancy bins
    action_angle = atan(action[2], action[1])
    rel_angle = normalize_angle(action_angle - agent.orientation)
    
    # Map to theta index (continuous)
    Ntheta = size(spm_tensor, 3)
    theta_idx = (rel_angle + π) / (2π) * Ntheta + 1.0
    
    # Gather occupancy from SPM based on direction
    # This is a simplified "forward model" in SPM space
    # We penalize velocity in directions of high occupancy
    
    # Differentiable lookup (soft indexing could be better, but simple interpolation for now)
    # For Zygote, we need to be careful with indexing.
    # Let's compute a "collision cost" by weighting occupancy with action alignment.
    
    collision_cost = 0.0
    
    # Vectorized calculation might be better for Zygote
    # But for now, let's loop (Zygote handles loops, though slower than vec)
    # Actually, let's use a dot product approach for efficiency if possible.
    
    # Simple repulsion:
    # Look at near bins (r=1, 2)
    # If occupancy is high, and we are moving towards it, penalty.
    
    # We can't easily index spm_tensor with continuous theta_idx in Zygote without custom adjoints.
    # So we iterate over all bins and weight them by alignment with action.
    
    # Pre-compute action direction vector
    speed = norm(action) + 1e-6
    dir_x = action[1] / speed
    dir_y = action[2] / speed
    
    # Iterate over SPM bins
    Nr, Nt = size(spm_tensor, 2), size(spm_tensor, 3)
    
    f_percept = 0.0
    
    # We can use sum() with a generator for Zygote
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
            
            # Occupancy
            occ = spm_tensor[1, r, t]
            
            # Precision
            prec = precision_matrix[r, t]
            
            # Distance factor (closer bins have higher weight)
            # r=1 is closest (0 distance), r=Nr is furthest
            dist_factor = 1.0 / r
            
            # Cost
            occ * prec * align_factor * dist_factor * speed * 10.0
        end
        for r in 1:3, t in 1:Nt # Only check close bins (r=1,2,3)
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
    
    # Haze avoidance (Stigmergy) - Strengthened
    m_meta += env_haze * 500.0
    
    return f_percept + m_meta
end

end
