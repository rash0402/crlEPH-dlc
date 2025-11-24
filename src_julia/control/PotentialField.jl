module PotentialField

using ..Types
using LinearAlgebra
using Statistics

export PotentialFieldController, decide_action

"""
Classical Potential Field Controller for baseline comparison.

Implements:
    F_total = F_attractive + F_repulsive

Where:
- F_attractive: Proportional to distance from goal
- F_repulsive: Inversely proportional to distance from obstacles
"""
struct PotentialFieldController
    params::EPHParams

    # Potential field specific parameters
    k_att::Float64   # Attractive force gain
    k_rep::Float64   # Repulsive force gain
    d_rep::Float64   # Repulsion influence distance

    function PotentialFieldController(params::EPHParams;
                                     k_att::Float64=1.0,
                                     k_rep::Float64=2000.0,
                                     d_rep::Float64=50.0)
        new(params, k_att, k_rep, d_rep)
    end
end

"""
    decide_action(controller, agent, spm_tensor, env, preferred_velocity) -> Vector{Float64}

Compute action using Potential Field method.

# Arguments
- `controller::PotentialFieldController`: Controller with parameters
- `agent::Agent`: Agent making the decision
- `spm_tensor::Array{Float64, 3}`: Current SPM observation (3, Nr, Nθ)
- `env::Environment`: Environment state
- `preferred_velocity::Union{Vector{Float64}, Nothing}`: Goal direction

# Returns
- `action::Vector{Float64}`: Desired velocity vector [vx, vy]
"""
function decide_action(controller::PotentialFieldController,
                      agent::Agent,
                      spm_tensor::Array{Float64, 3},
                      env::Environment,
                      preferred_velocity::Union{Vector{Float64}, Nothing})

    # --- 1. Attractive Force (Goal Seeking) ---
    F_att = zeros(2)
    if preferred_velocity !== nothing
        # Attractive force proportional to goal direction
        F_att = controller.k_att * preferred_velocity
    else
        # No goal: maintain forward motion for exploration
        F_att = controller.k_att * 20.0 * [cos(agent.orientation), sin(agent.orientation)]
    end

    # --- 2. Repulsive Force (Obstacle Avoidance) ---
    F_rep = compute_repulsive_force(controller, agent, spm_tensor, env)

    # --- 3. Total Force ---
    F_total = F_att + F_rep

    # Convert force to desired velocity
    desired_velocity = F_total

    # Enforce speed limits
    speed = norm(desired_velocity)
    if speed > controller.params.max_speed
        desired_velocity = (desired_velocity / speed) * controller.params.max_speed
    end

    # Smooth transition with previous velocity
    smoothing = 0.7
    smoothed_action = smoothing * desired_velocity + (1.0 - smoothing) * agent.velocity

    # Store dummy values for compatibility with logging
    agent.current_gradient = nothing
    agent.current_efe = 0.0
    agent.belief_entropy = 0.0

    return smoothed_action
end

"""
Compute repulsive force from all nearby obstacles detected in SPM.

Uses inverse-square law: F_rep ∝ 1/d² for d < d_rep
"""
function compute_repulsive_force(controller::PotentialFieldController,
                                agent::Agent,
                                spm_tensor::Array{Float64, 3},
                                env::Environment)

    F_rep = zeros(2)

    # Extract SPM dimensions
    Nr, Nθ = size(spm_tensor, 2), size(spm_tensor, 3)

    # Scan all SPM bins for occupancy
    for t in 1:Nθ
        for r in 1:Nr
            occupancy = spm_tensor[1, r, t]  # Occupancy channel

            if occupancy < 0.1  # Skip empty bins
                continue
            end

            # Compute bin's world position
            bin_angle_local = ((t - 1) / Nθ) * 2π - π
            bin_angle_global = bin_angle_local + agent.orientation

            # Estimate distance based on bin index
            # Bin 1 = personal space, bins 2-Nr = log-polar
            if r == 1
                bin_distance = agent.personal_space * 0.5
            else
                # Approximate log-polar mapping
                d_min = agent.personal_space
                d_max = controller.params.fov_range
                bin_distance = d_min * exp((r - 1) / (Nr - 1) * log(d_max / d_min))
            end

            # Skip if beyond repulsion range
            if bin_distance > controller.d_rep
                continue
            end

            # Direction from agent to obstacle
            obs_direction = [cos(bin_angle_global), sin(bin_angle_global)]

            # Repulsive force magnitude (inverse-square law)
            # F_rep = k_rep * (1/d_rep - 1/d) * (1/d²) * occupancy
            if bin_distance < 0.1
                bin_distance = 0.1  # Prevent division by zero
            end

            magnitude = controller.k_rep *
                       (1.0 / controller.d_rep - 1.0 / bin_distance) *
                       (1.0 / bin_distance^2) *
                       occupancy

            # Repulsive force points away from obstacle
            F_rep -= magnitude * obs_direction
        end
    end

    return F_rep
end

end
