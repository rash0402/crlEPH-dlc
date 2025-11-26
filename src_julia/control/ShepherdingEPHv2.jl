"""
Shepherding EPH Controller v2 (SPM-based Social Value).

Implements Phase 4 Shepherding with:
- SPM-based perceptual grounding (not omniscient)
- Social Value from SPM Occupancy channel
- Integration with GRU predictor (Phase 2)
- Full gradient ∇_a G(a) via Zygote

EFE formulation:
G(a) = F_percept(a, H) + M_social(a)

where:
- F_percept: Haze-modulated surprise cost (Epistemic)
- M_social: SPM-based social value (Pragmatic)
  - Angular Compactness (entropy)
  - Goal Pushing (cosine weighting)

References:
- doc/technical_notes/SocialValue_ActiveInference.md v1.2
"""
module ShepherdingEPHv2

using LinearAlgebra
using Zygote
using ..Types
using ..MathUtils
using ..SPM
using ..SelfHaze
using ..SocialValue

export ShepherdingDog, ShepherdingParams
export update_shepherding_dog!, compute_efe_shepherding

"""
Shepherding-specific parameters.
"""
Base.@kwdef mutable struct ShepherdingParams
    # Social Value weights (adaptive)
    λ_compact::Float64 = 1.0    # Compactness weight
    λ_goal::Float64 = 0.5        # Goal pushing weight

    # Adaptive weight thresholds
    # Entropy thresholds for adaptive weight switching (TUNED for better herding)
    # Lower thresholds = earlier transition to goal-pushing mode
    H_threshold_high::Float64 = 1.8  # High entropy → focus on compactness (reduced from 2.0)
    H_threshold_low::Float64 = 0.8   # Low entropy → focus on goal (reduced from 1.0)

    # Haze parameters
    use_self_haze::Bool = true
    h_max::Float64 = 0.8
    α::Float64 = 10.0
    Ω_threshold::Float64 = 0.12
    γ::Float64 = 2.0

    # Action optimization
    max_iter::Int = 5
    η::Float64 = 0.1
    max_speed::Float64 = 50.0

    # SPM parameters
    Nr::Int = 6
    Nθ::Int = 6
    Nc::Int = 3

    # Goal tracking
    goal_position::Union{Vector{Float64}, Nothing} = nothing
end

"""
Shepherding dog agent.

Minimal structure - uses SPM for perception (not omniscient).
"""
mutable struct ShepherdingDog
    id::Int
    position::Vector{Float64}
    velocity::Vector{Float64}
    radius::Float64

    # SPM state
    current_spm::Union{Array{Float64, 3}, Nothing}
    spm_history::Vector{Array{Float64, 3}}  # For GRU prediction

    # Haze state
    self_haze::Float64
    haze_matrix::Matrix{Float64}  # (Nr, Nθ)

    # Social Value weights (adaptive)
    λ_compact::Float64
    λ_goal::Float64

    # Active Inference metrics (for visualization)
    last_efe::Float64
    last_entropy::Float64
    last_surprise::Float64
    last_gradient::Vector{Float64}

    function ShepherdingDog(id::Int, x::Float64, y::Float64;
                            radius::Float64=4.8,
                            Nr::Int=6, Nθ::Int=6)
        new(id, [x, y], [0.0, 0.0], radius,
            nothing, [],
            0.7, ones(Nr, Nθ),
            1.0, 0.5,
            0.0, 0.0, 0.0, [0.0, 0.0])
    end
end

"""
Compute EFE for Shepherding with SPM-based Social Value.

G(a) = F_percept(a, H) + M_social(a)

# Arguments
- `action::Vector{Float64}`: Candidate action (velocity)
- `dog::ShepherdingDog`: Dog agent
- `spm_predicted::Array{Float64, 3}`: Predicted SPM from action
- `goal_position::Vector{Float64}`: Target position (world coordinates)
- `params::ShepherdingParams`: Parameters

# Returns
- `Float64`: Total EFE (minimize)
"""
function compute_efe_shepherding(
    action::Vector{Float64},
    dog::ShepherdingDog,
    spm_predicted::Array{Float64, 3},
    goal_position::Vector{Float64},
    params::ShepherdingParams,
    world_size::Float64
)::Float64

    # === 1. Epistemic Term: F_percept (Haze-modulated) ===
    F_percept = compute_surprise_cost_with_haze(
        spm_predicted,
        dog.haze_matrix,
        params
    )

    # === 2. Pragmatic Term: M_social (SPM-based) ===
    # Compute goal direction in dog's reference frame
    goal_vec = goal_position - dog.position
    θ_goal = atan(goal_vec[2], goal_vec[1])  # World frame
    heading = atan(dog.velocity[2], dog.velocity[1])  # Dog heading
    θ_goal_relative = mod(θ_goal - heading, 2π)  # Dog-relative [0, 2π]

    # Compute M_social using soft-binning (Zygote-compatible)
    M_social = SocialValue.compute_social_value_shepherding_soft(
        spm_predicted,
        θ_goal_relative,
        params.Nθ,
        λ_compact=dog.λ_compact,
        λ_goal=dog.λ_goal,
        σ=0.5  # Gaussian kernel width
    )

    # === 3. Action-dependent goal-seeking cost (for gradient flow) ===
    # CRITICAL: This ensures gradients flow even when SPM is empty
    # Cost proportional to misalignment between action and goal direction
    action_angle = atan(action[2], action[1])
    goal_angle = atan(goal_vec[2], goal_vec[1])
    angle_diff = mod(goal_angle - action_angle + π, 2π) - π  # Wrap to [-π, π]

    # Cosine similarity cost: higher cost when action points away from goal
    # Range: [-1, 1] where -1 = aligned, +1 = opposite
    M_action_goal = 10.0 * (1.0 - cos(angle_diff))  # Range: [0, 20]

    # === 4. Total EFE ===
    G = F_percept + M_social + M_action_goal

    return G
end

"""
Compute surprise cost with haze modulation.
"""
function compute_surprise_cost_with_haze(
    spm::Array{Float64, 3},
    haze_matrix::Matrix{Float64},
    params::ShepherdingParams
)::Float64

    Nr, Nθ, Nc = size(spm)
    F = 0.0

    for r in 1:Nr, θ in 1:Nθ
        # Haze modulation
        h = haze_matrix[r, θ]
        precision_modulated = 1.0 * (1.0 - h)^params.γ

        # Occupancy-based surprise (simple version)
        # Higher occupancy = higher surprise (collision risk)
        occupancy = spm[1, r, θ]

        # Distance weighting (closer = higher cost)
        weight = exp(-0.2 * (r - 1))

        F += precision_modulated * weight * occupancy^2
    end

    return F / (Nr * Nθ)
end

"""
Compute entropy of SPM occupancy distribution.

H = -Σ p(x) log p(x)

where p(x) is the normalized occupancy probability.
"""
function compute_spm_entropy(spm::Array{Float64, 3})::Float64
    occupancy = spm[1, :, :]
    total = sum(occupancy)

    if total < 1e-6
        return 0.0  # No occupancy, no entropy
    end

    # Normalize to probability distribution
    p = occupancy / total

    # Compute entropy
    H = 0.0
    for prob in p
        if prob > 1e-10
            H -= prob * log(prob)
        end
    end

    return H
end

"""
Convert angle (radians) to SPM angular index.

Note: Uses Int(round(...)) instead of floor for Zygote compatibility.
The gradient will pass through, though it's technically discontinuous.
For accurate gradients, consider soft-binning in future versions.
"""
function angle_to_spm_index(θ::Float64, Nθ::Int)::Int
    # Normalize to [0, 2π]
    θ_norm = mod(θ, 2π)

    # Convert to bin index [1, Nθ]
    # Use round instead of floor for Zygote (still not ideal, but works)
    idx_float = θ_norm / (2π / Nθ) + 1.0
    idx = Int(round(idx_float))

    # Clamp to valid range
    return clamp(idx, 1, Nθ)
end

"""
Update shepherding dog agent.

# Steps
1. Compute SPM (current perception)
2. Update self-haze (adaptive)
3. Adjust Social Value weights (adaptive)
4. Compute haze matrix (spatial modulation)
5. Select action via gradient descent on EFE
6. Update position and velocity
"""
function update_shepherding_dog!(
    dog::ShepherdingDog,
    sheep_list::Vector,  # SheepAgent.Sheep
    params::ShepherdingParams,
    world_size::Float64;
    other_dogs::Vector{ShepherdingDog}=ShepherdingDog[]  # For dog-dog collision avoidance
)
    # === 1. Compute SPM (perception) ===
    # Convert sheep to "other agents" for SPM computation
    # (Simplified: treat sheep as obstacles)
    dog.current_spm = compute_spm_for_dog(dog, sheep_list, params, world_size)

    # Store in history for GRU prediction (future)
    push!(dog.spm_history, copy(dog.current_spm))
    if length(dog.spm_history) > 10
        popfirst!(dog.spm_history)  # Keep last 10
    end

    # === 2. Update self-haze (adaptive) ===
    if params.use_self_haze
        # Create temporary EPHParams for SelfHaze computation
        eph_params_temp = EPHParams(
            h_max=params.h_max,
            α=params.α,
            Ω_threshold=params.Ω_threshold,
            γ=params.γ
        )
        dog.self_haze = SelfHaze.compute_self_haze(dog.current_spm, eph_params_temp)
    end

    # === 2b. Compute entropy ===
    dog.last_entropy = compute_spm_entropy(dog.current_spm)

    # === 3. Adjust Social Value weights (adaptive) ===
    adjust_social_value_weights!(dog, params)

    # === 4. Compute haze matrix (DIRECTIONAL for herding) ===
    # Use spatial haze matrix for directional precision control
    eph_params_temp = EPHParams(
        h_max=params.h_max,
        α=params.α,
        Ω_threshold=params.Ω_threshold,
        γ=params.γ
    )

    # Base spatial haze from SPM occupancy
    dog.haze_matrix .= SelfHaze.compute_self_haze_matrix(dog.current_spm, eph_params_temp)

    # Goal-aware modulation: Reduce haze in goal direction to encourage forward pushing
    # This makes dogs more sensitive to sheep in the goal direction (stronger herding)
    goal_pos = something(params.goal_position, [world_size/2, world_size/2])
    dx_goal, dy_goal, _ = MathUtils.toroidal_distance(
        dog.position, goal_pos,
        world_size, world_size
    )

    # Dog's heading
    if norm(dog.velocity) < 1e-6
        heading = 0.0
    else
        heading = atan(dog.velocity[2], dog.velocity[1])
    end

    # Goal angle in agent-relative coordinates
    angle_goal_world = atan(dy_goal, dx_goal)
    angle_goal_relative = mod(angle_goal_world - heading, 2π)

    # Reduce haze in bins facing the goal (stronger repulsion → better herding)
    for θ in 1:params.Nθ
        θ_center = (θ - 0.5) * (2π / params.Nθ)
        angle_diff = mod(θ_center - angle_goal_relative + π, 2π) - π

        # Gaussian weight centered on goal direction
        goal_weight = exp(-(angle_diff / 0.8)^2)  # σ = 0.8 rad ≈ 45°

        # Reduce haze by up to 50% in goal direction (all radial bins)
        for r in 1:params.Nr
            dog.haze_matrix[r, θ] *= (1.0 - 0.5 * goal_weight)
        end
    end

    # === 5. Select action via gradient descent ===
    goal_pos = something(params.goal_position, [world_size/2, world_size/2])

    action = select_action_gradient_descent(
        dog,
        goal_pos,
        params,
        world_size
    )

    # === 6. Collision avoidance with sheep AND other dogs ===
    collision_avoidance = zeros(2)

    # Dog-Sheep collision avoidance
    for sheep in sheep_list
        dx, dy, dist = MathUtils.toroidal_distance(
            dog.position, sheep.position,
            world_size, world_size
        )

        # IMPORTANT: Effective distance = actual distance - sum of radii
        # This prevents overlapping by considering body sizes
        min_dist = dog.radius + sheep.radius
        effective_dist = dist - min_dist  # Negative if overlapping!

        # Avoid division by zero
        if dist < 1e-6
            continue
        end

        # Direction away from sheep
        repulsion_dir = [-dx, -dy] / dist

        # Multi-tier collision avoidance based on effective distance
        if effective_dist < 0.0
            # CRITICAL: Already overlapping! Strong force to separate
            overlap = -effective_dist  # Positive value
            repulsion_strength = 200.0 * (1.0 + overlap / min_dist)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 0.5
            # Very close: moderate repulsion
            repulsion_strength = 100.0 / (effective_dist + 0.5)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 1.5
            # Close: mild repulsion
            repulsion_strength = 40.0 / (effective_dist + 1.0)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 3.0
            # Nearby: very weak repulsion
            repulsion_strength = 15.0 / (effective_dist + 2.0)
            collision_avoidance += repulsion_dir * repulsion_strength
        end
    end

    # Dog-Dog collision avoidance (STRONGER than dog-sheep)
    for other in other_dogs
        if other.id == dog.id
            continue  # Skip self
        end

        dx, dy, dist = MathUtils.toroidal_distance(
            dog.position, other.position,
            world_size, world_size
        )

        # IMPORTANT: Effective distance = actual distance - sum of radii
        min_dist = dog.radius + other.radius
        effective_dist = dist - min_dist  # Negative if overlapping!

        # Avoid division by zero
        if dist < 1e-6
            continue
        end

        # Direction away from other dog
        repulsion_dir = [-dx, -dy] / dist

        # Multi-tier collision avoidance (STRONGER than dog-sheep)
        if effective_dist < 0.0
            # CRITICAL: Already overlapping! Strong force
            overlap = -effective_dist
            repulsion_strength = 300.0 * (1.0 + overlap / min_dist)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 0.5
            # Very close: strong repulsion
            repulsion_strength = 150.0 / (effective_dist + 0.5)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 1.5
            # Close: moderate repulsion
            repulsion_strength = 60.0 / (effective_dist + 1.0)
            collision_avoidance += repulsion_dir * repulsion_strength
        elseif effective_dist < min_dist * 3.0
            # Nearby: weak repulsion
            repulsion_strength = 25.0 / (effective_dist + 2.0)
            collision_avoidance += repulsion_dir * repulsion_strength
        end
    end

    # === 7. Update velocity and position ===
    # Combine action with collision avoidance (very high weight for avoidance)
    desired_action = action + collision_avoidance * 0.5

    # Smooth velocity transition (more responsive to avoid collisions)
    dog.velocity = 0.9 * desired_action + 0.1 * dog.velocity

    # Speed limit
    if norm(dog.velocity) > params.max_speed
        dog.velocity = params.max_speed * normalize(dog.velocity)
    end

    # Update position
    dog.position += dog.velocity * 0.1  # dt = 0.1

    # Toroidal wrap
    dog.position = mod.(dog.position, world_size)

    nothing
end

"""
Compute SPM for dog (treating sheep as obstacles).

IMPORTANT: Considers sheep body radius for accurate occupancy detection.
Uses center-to-center distance but accounts for physical extent.
"""
function compute_spm_for_dog(
    dog::ShepherdingDog,
    sheep_list::Vector,
    params::ShepherdingParams,
    world_size::Float64
)::Array{Float64, 3}

    spm = zeros(Float64, params.Nc, params.Nr, params.Nθ)

    # Dog's heading (use [1, 0] if velocity is zero)
    if norm(dog.velocity) < 1e-6
        heading = 0.0
    else
        heading = atan(dog.velocity[2], dog.velocity[1])
    end

    for sheep in sheep_list
        # Relative position (toroidal, center-to-center)
        dx, dy, dist_center = MathUtils.toroidal_distance(
            dog.position, sheep.position,
            world_size, world_size
        )

        # CRITICAL: Account for body radii
        # Effective distance = center-to-center - radii
        dist_surface = max(dist_center - sheep.radius, 0.0)

        # Skip if too far (from surface)
        if dist_surface > 100.0  # Max perception range (narrowed from 200.0)
            continue
        end

        # Relative angle (to center)
        angle_world = atan(dy, dx)
        angle_relative = angle_world - heading

        # Normalize to [0, 2π]
        angle_relative = mod(angle_relative, 2π)

        # Convert to SPM coordinates
        θ_idx = angle_to_spm_index(angle_relative, params.Nθ)

        # Radial bin (based on surface distance, not center distance)
        # Personal space threshold (sum of radii)
        personal_space = dog.radius + sheep.radius

        if dist_surface < 10.0  # Very close (almost touching)
            r_idx = 1
        elseif dist_surface < 20.0  # Close
            r_idx = 2
        elseif dist_surface < 35.0  # Medium
            r_idx = 3
        elseif dist_surface < 55.0  # Far
            r_idx = 4
        elseif dist_surface < 80.0  # Very far
            r_idx = 5
        else
            r_idx = 6  # Max range (80-100)
        end

        r_idx = min(r_idx, params.Nr)

        # Occupancy (weighted by body size)
        # Larger sheep = stronger occupancy signal
        size_weight = (sheep.radius / 4.0)^2  # Normalize by typical radius
        spm[1, r_idx, θ_idx] += size_weight

        # Radial velocity (relative)
        if dist_center > 1e-6
            v_radial = dot([dx, dy] / dist_center, sheep.velocity - dog.velocity)
            spm[2, r_idx, θ_idx] += v_radial
        end

        # Tangential velocity
        if dist_center > 1e-6
            tangent_dir = [-dy, dx] / dist_center
            v_tangent = dot(tangent_dir, sheep.velocity - dog.velocity)
            spm[3, r_idx, θ_idx] += v_tangent
        end
    end

    return spm
end

"""
Adjust Social Value weights based on current compactness.

IMPROVED for better herding (追い込み動作):
- More aggressive goal pushing when compact
- Stronger compactness priority when dispersed
- Tighter thresholds for faster adaptation
"""
function adjust_social_value_weights!(
    dog::ShepherdingDog,
    params::ShepherdingParams
)
    # Compute current angular compactness (entropy)
    if !isnothing(dog.current_spm)
        H = SocialValue.compute_angular_compactness(dog.current_spm)

        if H > params.H_threshold_high
            # High entropy (dispersed) → STRONGLY focus on compactness
            # Increased from 2.0 to 3.0 for more aggressive gathering
            dog.λ_compact = 3.0
            dog.λ_goal = 0.3
        elseif H < params.H_threshold_low
            # Low entropy (compact) → AGGRESSIVELY push toward goal
            # Increased from 2.0 to 3.0 for stronger herding drive
            dog.λ_compact = 0.3
            dog.λ_goal = 3.0
        else
            # Balanced (but still favor goal pushing slightly)
            dog.λ_compact = 0.8
            dog.λ_goal = 1.5
        end
    end

    nothing
end

"""
Simple 1-step SPM prediction (forward simulation).

Predicts how SPM changes if dog takes action `a`.
Note: This is a simplified predictor. In full system, use GRU.

Current implementation: Use current SPM (no prediction yet)
This breaks gradient flow but allows basic testing.
"""
function predict_spm_simple(
    dog::ShepherdingDog,
    action::Vector{Float64},
    params::ShepherdingParams
)::Array{Float64, 3}
    # CRITICAL: This must be action-dependent AND non-mutating for Zygote!
    #
    # Current approach: Add simple action-dependent noise to SPM
    # This is a placeholder until GRU forward model is implemented
    #
    # Key insight: Even simple action-dependency creates useful gradients
    # for collision avoidance through EFE minimization

    # Action magnitude (fully differentiable)
    action_mag = sqrt(action[1]^2 + action[2]^2 + 1e-8)  # Add epsilon for stability

    # Create action-dependent perturbation
    # Approach: Scale current occupancy by action magnitude
    # Higher action → higher perceived collision risk
    perturbation_scale = 0.03 * action_mag

    # NON-MUTATING: Use broadcasting with proper array shapes
    # SPM shape is (Nc=3, Nr, Nθ)
    # Apply perturbation only to occupancy channel (channel 1)

    # Build channel-wise perturbation using reshape for broadcasting
    # Channels: [occupancy, radial_vel, tangential_vel]
    channel_scales = reshape([1.0 + perturbation_scale, 1.0, 1.0], 3, 1, 1)

    # Element-wise multiplication (fully differentiable, non-mutating)
    spm_perturbed = dog.current_spm .* channel_scales

    return spm_perturbed
end

"""
Select action via gradient descent on EFE.

Also stores EFE, gradient, and surprise in dog structure for visualization.
"""
function select_action_gradient_descent(
    dog::ShepherdingDog,
    goal_position::Vector{Float64},
    params::ShepherdingParams,
    world_size::Float64
)::Vector{Float64}

    # Initialize with current velocity + small noise
    a = copy(dog.velocity) + randn(2) * 2.0

    # Store metrics for visualization
    best_efe = Inf
    best_grad = [0.0, 0.0]
    best_surprise = 0.0

    # Gradient descent
    for iter in 1:params.max_iter
        # Compute gradient via Zygote
        grad_result = gradient(a -> begin
            # Predict future SPM (action-dependent)
            spm_predicted = predict_spm_simple(dog, a, params)

            # Compute EFE
            G = compute_efe_shepherding(
                a, dog, spm_predicted, goal_position, params, world_size
            )

            return G
        end, a)

        grad = grad_result[1]

        # Debug: print values AFTER gradient computation (outside Zygote)
        if dog.id == 1 && iter == 1 && get(ENV, "EPH_DEBUG_GRADIENT", "0") == "1"
            spm_predicted_debug = predict_spm_simple(dog, a, params)
            G_debug = compute_efe_shepherding(
                a, dog, spm_predicted_debug, goal_position, params, world_size
            )
            spm_max = maximum(spm_predicted_debug[1, :, :])
            grad_norm = norm(grad)
            println("[DEBUG] Dog 1, Iter 1: G = $G_debug, grad_norm = $grad_norm, SPM_max = $spm_max")
        end

        # Compute current EFE and surprise for tracking
        spm_pred = predict_spm_simple(dog, a, params)
        current_efe = compute_efe_shepherding(
            a, dog, spm_pred, goal_position, params, world_size
        )
        current_surprise = compute_surprise_cost_with_haze(
            spm_pred, dog.haze_matrix, params
        )

        # Update best metrics
        if current_efe < best_efe
            best_efe = current_efe
            best_grad = grad !== nothing ? copy(grad) : [0.0, 0.0]
            best_surprise = current_surprise
        end

        # Handle zero gradient (can happen if SPM is independent of action)
        if grad === nothing || !all(isfinite.(grad))
            # Fallback: simple goal-seeking
            to_goal = goal_position - dog.position
            to_goal_norm = normalize(to_goal)
            grad = -to_goal_norm * 10.0  # Move towards goal
        end

        # Gradient descent step
        a = a - params.η * grad

        # Speed limit
        if norm(a) > params.max_speed
            a = params.max_speed * normalize(a)
        end
    end

    # Store metrics in dog structure
    dog.last_efe = best_efe
    dog.last_gradient = best_grad
    dog.last_surprise = best_surprise

    return a
end

end  # module ShepherdingEPHv2
