"""
Shepherding-specific EPH controller for dog agents.

Extends the base EPH framework with shepherding-specific pragmatic terms:
- Target cost: Drive sheep towards target position
- Density cost: Maintain sheep group cohesion
- Work cost: Minimize unnecessary movement

EFE formulation:
G(a) = F_percept(a, H) + β·H[q(s|a)] - γ_info·I(o;s|a) + λ·M_meta(a)

where M_meta for shepherding:
M_meta = w_target·C_target + w_density·C_density + w_work·C_work
"""
module ShepherdingEPH

using LinearAlgebra
using Zygote
using ..Types
using ..MathUtils
using ..SPM

export ShepherdingController, decide_action, compute_shepherding_meta_cost, ShepherdingParams

"""
Shepherding-specific controller parameters.
"""
Base.@kwdef struct ShepherdingParams
    # Meta-cost weights
    w_target::Float64 = 1.0    # Weight for target cost
    w_density::Float64 = 0.5   # Weight for density cost
    w_work::Float64 = 0.1      # Weight for work cost

    # Target convergence parameters
    target_radius::Float64 = 50.0  # Acceptable radius around target
    density_radius::Float64 = 80.0  # Radius for measuring sheep density

    # Epistemic parameters (for future extension)
    use_temporal_prediction::Bool = false  # Enable H_temporal
    prediction_horizon::Float64 = 1.0      # Seconds ahead
end

"""
Shepherding controller combining EPH with shepherding-specific costs.
"""
struct ShepherdingController
    eph_params::EPHParams
    shepherding_params::ShepherdingParams
end

"""
Compute sheep center of mass.
"""
function compute_sheep_center(env::Environment)::Vector{Float64}
    if isnothing(env.sheep_agents) || isempty(env.sheep_agents)
        return [env.width / 2, env.height / 2]  # Default to center
    end

    center = zeros(2)
    for sheep in env.sheep_agents
        center += sheep.position
    end
    center /= length(env.sheep_agents)

    return center
end

"""
Compute sheep density around a given position.

Returns normalized density ∈ [0, 1] where:
- 0 = completely dispersed
- 1 = all sheep within density_radius
"""
function compute_sheep_density(
    position::Vector{Float64},
    env::Environment,
    density_radius::Float64
)::Float64

    if isnothing(env.sheep_agents) || isempty(env.sheep_agents)
        return 0.0
    end

    n_within_radius = 0
    for sheep in env.sheep_agents
        _, _, dist = MathUtils.toroidal_distance(
            position, sheep.position, env.width, env.height
        )
        if dist < density_radius
            n_within_radius += 1
        end
    end

    return n_within_radius / length(env.sheep_agents)
end

"""
Compute target cost: encourages moving sheep center towards target.

C_target = ||sheep_center - target||² / scale
"""
function compute_target_cost(env::Environment, params::ShepherdingParams)::Float64
    if isnothing(env.target_position)
        return 0.0  # No target specified
    end

    sheep_center = compute_sheep_center(env)
    dx, dy, dist = MathUtils.toroidal_distance(
        sheep_center, env.target_position, env.width, env.height
    )

    # Squared distance, normalized
    cost = (dist^2) / (params.target_radius^2)

    return cost
end

"""
Compute density cost: encourages keeping sheep grouped.

C_density = 1 - density(target_position)

Lower when sheep are densely grouped at target.
"""
function compute_density_cost(env::Environment, params::ShepherdingParams)::Float64
    if isnothing(env.target_position)
        return 0.0
    end

    density = compute_sheep_density(env.target_position, env, params.density_radius)

    # Cost is high when density is low (dispersed)
    cost = 1.0 - density

    return cost
end

"""
Compute work cost: penalizes large velocity changes (encourages smooth motion).

C_work = ||a - v_prev||² / max_speed²
"""
function compute_work_cost(
    action::Vector{Float64},
    agent::Agent,
    params::ShepherdingParams
)::Float64

    v_prev = agent.velocity
    velocity_change = action - v_prev
    cost = norm(velocity_change)^2 / (agent.max_speed^2)

    return cost
end

"""
Compute shepherding-specific meta-cost M_meta.

M_meta = w_target·C_target + w_density·C_density + w_work·C_work
"""
function compute_shepherding_meta_cost(
    action::Vector{Float64},
    agent::Agent,
    env::Environment,
    params::ShepherdingParams
)::Float64

    # Note: C_target and C_density are independent of action (state-only),
    # so they act as bias terms in the gradient
    C_target = compute_target_cost(env, params)
    C_density = compute_density_cost(env, params)
    C_work = compute_work_cost(action, agent, params)

    M_meta = params.w_target * C_target +
             params.w_density * C_density +
             params.w_work * C_work

    return M_meta
end

"""
Compute perceptual cost F_percept for collision avoidance.

Simplified version: uses SPM occupancy to compute collision risk.
"""
function compute_perceptual_cost(
    action::Vector{Float64},
    agent::Agent,
    spm::Array{Float64, 3},
    env::Environment,
    params::EPHParams
)::Float64

    # Extract occupancy channel from SPM
    occupancy = spm[1, :, :]  # (Nr, Nθ)

    # Compute collision risk as sum of occupancy weighted by distance
    # Closer obstacles (smaller radial bins) have higher weights
    Nr, Nθ = size(occupancy)

    risk = 0.0
    for r in 1:Nr
        # Weight decays with distance (closer = higher risk)
        weight = exp(-0.1 * (r - 1))
        for θ in 1:Nθ
            risk += weight * occupancy[r, θ]
        end
    end

    # Normalize by number of bins
    risk /= (Nr * Nθ)

    # Add penalty for high speed in occupied areas
    speed_penalty = norm(action) * risk * 0.1

    return risk + speed_penalty
end

"""
Decide action for dog agent using shepherding-enhanced EPH.

Uses gradient descent on:
J(a) = F_percept(a) + λ·M_meta(a)

where F_percept is perceptual cost (collision avoidance)
and M_meta is the shepherding-specific task cost.
"""
function decide_action(
    controller::ShepherdingController,
    agent::Agent,
    spm::Array{Float64, 3},
    env::Environment,
    predictor
)::Vector{Float64}

    eph_params = controller.eph_params
    shep_params = controller.shepherding_params

    # Initial action: continue previous velocity with small exploration
    a = copy(agent.velocity) + randn(2) * 1.0

    # Gradient descent optimization
    for iter in 1:eph_params.max_iter
        # Compute gradient using Zygote
        grad = gradient(a -> begin
            # Perceptual cost (F_percept)
            F_percept = compute_perceptual_cost(a, agent, spm, env, eph_params)

            # Shepherding meta-cost (M_meta)
            M_meta = compute_shepherding_meta_cost(a, agent, env, shep_params)

            # Total cost
            J = F_percept + eph_params.λ * M_meta

            return J
        end, a)[1]

        # Gradient descent step
        a -= eph_params.η * grad

        # Clamp to max speed
        speed = norm(a)
        if speed > agent.max_speed
            a = a / speed * agent.max_speed
        end
    end

    return a
end

"""
Compute epistemic value H[q(s|a)] for shepherding (future extension).

Currently returns 0.0. Will be extended to include:
- H_temporal: temporal prediction entropy for escape anticipation
- I(o;s|a): information gain for optimal positioning
"""
function compute_epistemic_value(
    action::Vector{Float64},
    agent::Agent,
    env::Environment,
    params::ShepherdingParams
)::Float64

    if !params.use_temporal_prediction
        return 0.0
    end

    # TODO: Implement temporal prediction using SPMPredictor
    # H_temporal = entropy(predicted_sheep_distribution)
    # I_obs = mutual_information(observation, hidden_state | action)

    return 0.0  # Placeholder
end

end  # module ShepherdingEPH
