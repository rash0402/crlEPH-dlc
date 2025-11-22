module EPH

using ..Types
using ..SelfHaze
using ..MathUtils
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

    function GradientEPHController(params::EPHParams)
        new(params)
    end
end

"""
    decide_action(controller, agent, spm_tensor, preferred_velocity) -> Vector{Float64}

Compute optimal action by minimizing Expected Free Energy G(a).

# Arguments
- `controller::GradientEPHController`: Controller with EPHParams
- `agent::Agent`: Agent making the decision
- `spm_tensor::Array{Float64, 3}`: Current SPM observation (3, Nr, Nθ)
- `preferred_velocity::Union{Vector{Float64}, Nothing}`: Goal direction (if any)

# Returns
- `action::Vector{Float64}`: Optimal velocity vector [vx, vy]
"""
function decide_action(controller::GradientEPHController, agent::Agent,
                      spm_tensor::Array{Float64, 3},
                      preferred_velocity::Union{Vector{Float64}, Nothing})

    # Initial guess: current velocity (for continuity)
    current_action = copy(agent.velocity)

    # If velocity is very small, initialize with small random perturbation for exploration
    if norm(current_action) < 1.0
        current_action = [randn() * 5.0, randn() * 5.0]
    end

    # Gradient Descent on Expected Free Energy
    for i in 1:controller.params.max_iter
        # Compute gradient: ∇_a G(a)
        grads = Zygote.gradient(a -> expected_free_energy(a, agent, spm_tensor,
                                                         preferred_velocity,
                                                         controller.params),
                               current_action)
        grad = grads[1]

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
                               preferred_velocity::Union{Vector{Float64}, Nothing},
                               params::EPHParams)::Float64

    # --- 1. Compute Self-Haze from SPM ---
    h_self = SelfHaze.compute_self_haze(spm_tensor, params)

    # --- 2. Compute Haze-Modulated Precision Matrix ---
    Π = SelfHaze.compute_precision_matrix(spm_tensor, h_self, params)

    # --- 3. Compute Belief Entropy H[q(s)] ---
    H_belief = SelfHaze.compute_belief_entropy(Π)

    # --- 4. Perceptual Free Energy: F_percept(a, H) ---
    # Collision avoidance weighted by precision
    speed = norm(action) + 1e-6
    dir_x = action[1] / speed
    dir_y = action[2] / speed

    Nr, Nθ = size(spm_tensor, 2), size(spm_tensor, 3)

    f_percept = sum(
        let
            # Bin angle in agent-relative coordinates
            bin_angle = ((t - 1) / Nθ) * 2π - π

            # Global angle (agent's orientation + relative angle)
            global_bin_angle = bin_angle + agent.orientation
            bin_dir_x = cos(global_bin_angle)
            bin_dir_y = sin(global_bin_angle)

            # Alignment: how much action points towards this bin
            alignment = dir_x * bin_dir_x + dir_y * bin_dir_y

            # Only penalize moving towards occupied bins (alignment > 0)
            align_factor = max(0.0, alignment)

            # Occupancy from SPM
            occ = spm_tensor[1, r, t]

            # Precision weight (high precision → high cost for collision)
            prec = Π[r, t]

            # Distance decay (closer bins have higher cost)
            dist_factor = 1.0 / (r + 0.1)  # Avoid division by zero

            # Collision cost: occupancy × precision × alignment × distance × speed
            occ * prec * align_factor * dist_factor * speed * 10.0
        end
        for r in 1:min(3, Nr), t in 1:Nθ  # Focus on nearby bins (r ≤ 3)
    )

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
    # G(a) = F_percept + β·H[q] + λ·M_meta
    # When H[q] is high (uncertain), epistemic term dominates → exploration
    # When H[q] is low (certain), perceptual and pragmatic terms dominate → exploitation
    G = f_percept + params.β * H_belief + params.λ * m_meta

    return G
end

end
