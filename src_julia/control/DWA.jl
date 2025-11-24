module DWA

using ..Types
using ..MathUtils
using LinearAlgebra
using Statistics

export DWAController, decide_action

"""
Dynamic Window Approach (DWA) Controller for baseline comparison.

Implements local trajectory planning with dynamic constraints.

Algorithm:
1. Compute dynamic window of achievable velocities
2. Sample velocity space within window
3. Simulate forward trajectories for each velocity
4. Evaluate trajectories with cost function
5. Select best velocity

Cost function:
    G(v, ω) = α·heading(v,ω) + β·clearance(v,ω) + γ·velocity(v,ω)
"""
struct DWAController
    params::EPHParams

    # DWA specific parameters
    v_resolution::Float64  # Linear velocity sampling resolution
    ω_resolution::Float64  # Angular velocity sampling resolution
    prediction_time::Float64  # Trajectory prediction horizon (seconds)
    prediction_dt::Float64    # Simulation timestep for trajectory

    # Cost function weights
    α::Float64  # Heading weight (goal direction)
    β::Float64  # Clearance weight (obstacle avoidance)
    γ::Float64  # Velocity weight (prefer higher speed)

    function DWAController(params::EPHParams;
                          v_resolution::Float64=5.0,
                          ω_resolution::Float64=0.2,
                          prediction_time::Float64=1.0,
                          prediction_dt::Float64=0.1,
                          α::Float64=1.0,
                          β::Float64=2.0,
                          γ::Float64=0.5)
        new(params, v_resolution, ω_resolution, prediction_time, prediction_dt,
            α, β, γ)
    end
end

"""
    decide_action(controller, agent, spm_tensor, env, preferred_velocity) -> Vector{Float64}

Compute action using Dynamic Window Approach.

# Arguments
- `controller::DWAController`: Controller with parameters
- `agent::Agent`: Agent making the decision
- `spm_tensor::Array{Float64, 3}`: Current SPM observation (3, Nr, Nθ)
- `env::Environment`: Environment state
- `preferred_velocity::Union{Vector{Float64}, Nothing}`: Goal direction

# Returns
- `action::Vector{Float64}`: Optimal velocity vector [vx, vy]
"""
function decide_action(controller::DWAController,
                      agent::Agent,
                      spm_tensor::Array{Float64, 3},
                      env::Environment,
                      preferred_velocity::Union{Vector{Float64}, Nothing})

    # Current velocity in polar form
    current_speed = norm(agent.velocity)

    # Compute dynamic window
    v_min, v_max, ω_min, ω_max = compute_dynamic_window(controller, current_speed)

    # Sample velocity space
    velocities = sample_velocity_space(controller, v_min, v_max, ω_min, ω_max)

    # Evaluate each velocity candidate
    best_cost = Inf
    best_velocity = agent.velocity  # Default: maintain current velocity

    for (v, ω) in velocities
        # Simulate trajectory
        trajectory = simulate_trajectory(controller, agent, v, ω)

        # Evaluate trajectory
        cost = evaluate_trajectory(controller, agent, spm_tensor, env,
                                  trajectory, v, ω, preferred_velocity)

        if cost < best_cost
            best_cost = cost
            # Convert (v, ω) to Cartesian velocity
            # Agent moves in orientation direction with speed v, turning with ω
            # For simplicity: velocity in current heading direction
            best_velocity = v * [cos(agent.orientation), sin(agent.orientation)]
        end
    end

    # Enforce speed limits
    speed = norm(best_velocity)
    if speed > controller.params.max_speed
        best_velocity = (best_velocity / speed) * controller.params.max_speed
    end

    # Smooth transition
    smoothing = 0.7
    smoothed_action = smoothing * best_velocity + (1.0 - smoothing) * agent.velocity

    # Store dummy values for compatibility
    agent.current_gradient = nothing
    agent.current_efe = best_cost  # Store DWA cost as EFE equivalent
    agent.belief_entropy = 0.0

    return smoothed_action
end

"""
Compute dynamic window of achievable velocities given current state and constraints.

Returns: (v_min, v_max, ω_min, ω_max)
"""
function compute_dynamic_window(controller::DWAController, current_speed::Float64)
    dt = 0.1  # Standard timestep (from Environment)
    max_accel = controller.params.max_accel
    max_speed = controller.params.max_speed

    # Velocity limits
    v_min = max(0.0, current_speed - max_accel * dt)
    v_max = min(max_speed, current_speed + max_accel * dt)

    # Angular velocity limits (rad/s)
    # Assuming max turning rate ≈ max_accel / typical_radius
    max_ω = 2.0  # rad/s (≈ 114 deg/s)
    ω_min = -max_ω
    ω_max = max_ω

    return v_min, v_max, ω_min, ω_max
end

"""
Sample velocity space within dynamic window.

Returns: Vector of (v, ω) tuples
"""
function sample_velocity_space(controller::DWAController,
                               v_min::Float64, v_max::Float64,
                               ω_min::Float64, ω_max::Float64)
    velocities = Tuple{Float64, Float64}[]

    # Sample linear velocity
    v_samples = v_min:controller.v_resolution:v_max
    if isempty(v_samples)
        v_samples = [v_min]
    end

    # Sample angular velocity
    ω_samples = ω_min:controller.ω_resolution:ω_max
    if isempty(ω_samples)
        ω_samples = [0.0]
    end

    for v in v_samples
        for ω in ω_samples
            push!(velocities, (v, ω))
        end
    end

    return velocities
end

"""
Simulate forward trajectory for given velocity (v, ω).

Returns: Vector of positions [[x1, y1], [x2, y2], ...]
"""
function simulate_trajectory(controller::DWAController,
                            agent::Agent,
                            v::Float64,
                            ω::Float64)
    trajectory = Vector{Vector{Float64}}()

    # Initial state
    pos = copy(agent.position)
    orientation = agent.orientation

    num_steps = ceil(Int, controller.prediction_time / controller.prediction_dt)

    for _ in 1:num_steps
        # Update orientation
        orientation += ω * controller.prediction_dt

        # Update position
        pos += v * controller.prediction_dt * [cos(orientation), sin(orientation)]

        push!(trajectory, copy(pos))
    end

    return trajectory
end

"""
Evaluate trajectory with cost function.

Cost = α·heading + β·(1/clearance) + γ·(1/velocity)

Lower cost is better.
"""
function evaluate_trajectory(controller::DWAController,
                            agent::Agent,
                            spm_tensor::Array{Float64, 3},
                            env::Environment,
                            trajectory::Vector{Vector{Float64}},
                            v::Float64,
                            ω::Float64,
                            preferred_velocity::Union{Vector{Float64}, Nothing})

    # --- 1. Heading Cost (lower if aligned with goal) ---
    heading_cost = 0.0
    if preferred_velocity !== nothing
        # Final trajectory direction
        if length(trajectory) >= 2
            final_dir = trajectory[end] - trajectory[1]
            final_dir_norm = norm(final_dir)
            if final_dir_norm > 1e-6
                final_dir = final_dir / final_dir_norm
                pref_dir_norm = norm(preferred_velocity)
                if pref_dir_norm > 1e-6
                    pref_dir = preferred_velocity / pref_dir_norm
                    # Cost inversely proportional to alignment (0 = perfect, 2 = opposite)
                    heading_cost = 1.0 - dot(final_dir, pref_dir)
                end
            end
        end
    else
        # No goal: prefer straight motion (ω ≈ 0)
        heading_cost = abs(ω) * 0.5
    end

    # --- 2. Clearance Cost (higher if trajectory passes near obstacles) ---
    clearance_cost = compute_clearance_cost(agent, spm_tensor, trajectory, env)

    # --- 3. Velocity Cost (prefer higher speed) ---
    velocity_cost = (controller.params.max_speed - v) / controller.params.max_speed

    # --- Total Cost ---
    total_cost = controller.α * heading_cost +
                 controller.β * clearance_cost +
                 controller.γ * velocity_cost

    return total_cost
end

"""
Compute clearance cost by checking trajectory points against SPM occupancy.
"""
function compute_clearance_cost(agent::Agent,
                               spm_tensor::Array{Float64, 3},
                               trajectory::Vector{Vector{Float64}},
                               env::Environment)

    if isempty(trajectory)
        return 0.0
    end

    total_risk = 0.0
    Nr, Nθ = size(spm_tensor, 2), size(spm_tensor, 3)

    for traj_point in trajectory
        # Compute relative position from agent
        rel_pos = traj_point - agent.position

        # Convert to polar coordinates
        rel_dist = norm(rel_pos)
        if rel_dist < 1e-6
            continue
        end

        rel_angle = atan(rel_pos[2], rel_pos[1]) - agent.orientation
        # Normalize angle to [-π, π]
        while rel_angle > π
            rel_angle -= 2π
        end
        while rel_angle < -π
            rel_angle += 2π
        end

        # Map to SPM bins (simplified)
        t_bin = floor(Int, (rel_angle + π) / (2π) * Nθ) + 1
        t_bin = clamp(t_bin, 1, Nθ)

        # Approximate r_bin based on distance
        if rel_dist < agent.personal_space
            r_bin = 1
        else
            # Log-polar approximation
            d_max = 100.0  # Assume FOV range
            log_ratio = log(rel_dist / agent.personal_space) / log(d_max / agent.personal_space)
            r_bin = floor(Int, log_ratio * (Nr - 1)) + 2
            r_bin = clamp(r_bin, 1, Nr)
        end

        # Add risk from SPM occupancy
        occupancy = spm_tensor[1, r_bin, t_bin]
        # Risk inversely proportional to distance
        risk = occupancy / (rel_dist + 1.0)
        total_risk += risk
    end

    return total_risk
end

end
