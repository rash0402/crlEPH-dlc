module EPH

using ..Types
using ..SelfHaze
using ..MathUtils
using ..SPM
using ..SPMPredictor
using Zygote
using LinearAlgebra
using Statistics

export GradientEPHController, decide_action

"""
Gradient-based EPH Controller using Expected Free Energy minimization.

Implements Active Inference formulation:
    G(a) = F_percept(a, H) + β·H[q(s|a)] + λ·M_meta(a)

Where:
- F_percept: Perceptual surprise (collision avoidance)
- H[q(s|a)]: Belief entropy (epistemic value, information gain)
- M_meta: Pragmatic value (goal seeking or exploration maintenance)
"""
struct GradientEPHController
    params::EPHParams
    predictor::Predictor

    function GradientEPHController(params::EPHParams, predictor::Predictor)
        new(params, predictor)
    end
end

"""
    decide_action(controller, agent, spm_tensor, preferred_velocity) -> Vector{Float64}

Compute optimal action by minimizing Expected Free Energy G(a).

# Arguments
- `controller::GradientEPHController`: Controller with EPHParams
- `agent::Agent`: Agent making the decision
- `spm_tensor::Array{Float64, 3}`: Current SPM observation (3, Nr, Nθ)
- `env::Environment`: Environment state (for prediction)
- `preferred_velocity::Union{Vector{Float64}, Nothing}`: Goal direction (if any)

# Returns
- `action::Vector{Float64}`: Optimal velocity vector [vx, vy]
"""
function decide_action(controller::GradientEPHController, agent::Agent,
                      spm_tensor::Array{Float64, 3},
                      env::Environment,
                      preferred_velocity::Union{Vector{Float64}, Nothing})

    # Initial guess: current velocity (for continuity)
    current_action = copy(agent.velocity)

    # If velocity is very small, initialize with small random perturbation for exploration
    if norm(current_action) < 1.0
        current_action = [randn() * 5.0, randn() * 5.0]
    end

    # Gradient Descent on Expected Free Energy
    final_grad = nothing
    for i in 1:controller.params.max_iter
        # Compute gradient: ∇_a G(a)
        grads = Zygote.gradient(a -> expected_free_energy(a, agent, spm_tensor, env,
                                                         preferred_velocity,
                                                         controller.params,
                                                         controller.predictor),
                               current_action)
        grad = grads[1]

        # Store final gradient for visualization
        if i == controller.params.max_iter
            final_grad = copy(grad)
        end

        # Clip gradient for stability
        grad = clamp.(grad, -10.0, 10.0)

        # Gradient descent update: a ← a - η·∇G
        current_action -= controller.params.η * grad

        # Enforce physical constraints
        speed = norm(current_action)
        if speed > controller.params.max_speed
            current_action = (current_action / speed) * controller.params.max_speed
        end
    end

    # Store gradient in agent for visualization
    agent.current_gradient = final_grad

    # Smooth transition: blend with previous velocity for continuity
    smoothing = 0.7  # 70% new action, 30% old velocity
    smoothed_action = smoothing * current_action + (1.0 - smoothing) * agent.velocity

    return smoothed_action
end

"""
    expected_free_energy(action, agent, spm_tensor, preferred_velocity, params) -> Float64

Compute Expected Free Energy G(a) for action selection.

# Theory
G(a) = F_percept(a, H) + β·H[q(s|a)] + λ·M_meta(a)

Where:
1. F_percept: Perceptual surprise (collision avoidance with precision weighting)
2. β·H[q(s|a)]: Epistemic value (belief entropy, drives exploration)
3. λ·M_meta: Pragmatic value (goal seeking or speed maintenance)

# Causal Chain (Self-Hazing → Exploration)
No agents visible → Low occupancy Ω → High self-haze h_self → Low precision Π
→ High covariance Σ → High entropy H[q] → Epistemic term dominates → Exploration

# Arguments
- `action::Vector{Float64}`: Candidate action [vx, vy]
- `agent::Agent`: Agent state
- `spm_tensor::Array{Float64, 3}`: Current SPM observation
- `preferred_velocity::Union{Vector{Float64}, Nothing}`: Goal direction
- `params::EPHParams`: EPH parameters
"""
function expected_free_energy(action::Vector{Float64}, agent::Agent,
                               spm_tensor::Array{Float64, 3},
                               env::Environment,
                               preferred_velocity::Union{Vector{Float64}, Nothing},
                               params::EPHParams,
                               predictor::Predictor)::Float64

    # --- 1. Compute Self-Haze from SPM ---
    h_self = SelfHaze.compute_self_haze(spm_tensor, params)

    # --- 2. Compute Haze-Modulated Precision Matrix (Current) ---
    Π_current = SelfHaze.compute_precision_matrix(spm_tensor, h_self, params)

    # --- 3. Compute Future Belief Entropy & Information Gain ---
    # Predict future SPM based on action
    spm_params = SPM.SPMParams(d_max=params.fov_range)
    # Predict future SPM based on action
    spm_params = SPM.SPMParams(d_max=params.fov_range)
    # Predict SPM (differentiable for NeuralPredictor, ignored for LinearPredictor)
    spm_pred = SPMPredictor.predict_spm(predictor, agent, action, env, spm_params)
    
    # Compute future entropy H[q(s_{t+1}|a)]
    h_self_pred = SelfHaze.compute_self_haze(spm_pred, params)
    Π_pred = SelfHaze.compute_precision_matrix(spm_pred, h_self_pred, params)
    H_future = SelfHaze.compute_belief_entropy(Π_pred)
    
    # Compute Information Gain I(o; s|a)
    # Approximation: Variance of predicted SPM (occupancy channel)
    # High variance = high information potential
    I_gain = var(spm_pred[1, :, :])

    # --- 4. Perceptual Free Energy: F_percept(a, H) ---
    # Collision avoidance weighted by precision
    speed = norm(action) + 1e-6
    dir_x = action[1] / speed
    dir_y = action[2] / speed

    Nr, Nθ = size(spm_tensor, 2), size(spm_tensor, 3)

    # Vectorized f_percept calculation
    # 1. Compute alignment for all angles (t dimension)
    t_indices = collect(1:Nθ)
    bin_angles = ((t_indices .- 1) ./ Nθ) .* 2π .- π
    global_bin_angles = bin_angles .+ agent.orientation
    bin_dir_x = cos.(global_bin_angles)
    bin_dir_y = sin.(global_bin_angles)
    
    alignment = dir_x .* bin_dir_x .+ dir_y .* bin_dir_y
    align_factor = max.(0.0, alignment)  # (Nθ,) vector
    
    # 2. Extract relevant SPM and Precision data (r dimension: 1 to 3)
    r_max_idx = min(3, Nr)
    r_indices = collect(1:r_max_idx)
    
    occ_sub = spm_tensor[1, 1:r_max_idx, :]  # (r_max, Nθ)
    prec_sub = Π_current[1:r_max_idx, :]     # (r_max, Nθ)
    
    # 3. Distance decay
    dist_factor = 1.0 ./ (r_indices .+ 0.1)  # (r_max,) vector
    
    # 4. Compute cost
    # Broadcast: (r, t) * (r, t) * (1, t) * (r, 1) * scalar
    # align_factor is (Nθ,), reshape to (1, Nθ)
    align_factor_row = reshape(align_factor, 1, Nθ)
    
    cost_grid = occ_sub .* prec_sub .* align_factor_row .* dist_factor .* speed .* 10.0
    
    f_percept = sum(cost_grid)

    # --- 5. Pragmatic Value: M_meta(a) ---
    m_meta = 0.0

    if preferred_velocity !== nothing
        # Goal seeking: MSE between action and preferred direction
        m_meta = sum((action .- preferred_velocity).^2)
    else
        # No goal: maintain moderate speed for exploration
        target_speed = 20.0
        m_meta = (speed - target_speed)^2 * 0.1
    end

    # --- 6. Total Expected Free Energy ---
    # G(a) = F_percept + β·H[q(s_{t+1}|a)] - γ·I(o;s|a) + λ·M_meta
    G = f_percept + params.β * H_future - params.γ_info * I_gain + params.λ * m_meta

    return G
end

end
