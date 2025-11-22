module Simulation

using ..Types
using ..MathUtils
using ..SPM
using ..EPH
using ..SelfHaze
using LinearAlgebra
using Random

export initialize_simulation, step!

"""
Initialize Sparse Foraging Task environment.

# Scenario
- 6 agents in toroidal world
- Sparse initial placement (agents far apart)
- No explicit goals (epistemic foraging only)
- FOV: 120° × 100px

# Objective
Test Active Inference hypothesis:
When agents see few neighbors (low Ω), self-haze increases → precision decreases
→ belief entropy increases → epistemic term dominates → exploration emerges
"""
function initialize_simulation(;width=800.0, height=600.0, n_agents=6)
    env = Environment(width, height, grid_size=30)

    # Sparse initial placement: divide world into regions
    # Scaled for variable world size
    margin = 0.15  # 15% margin from edges
    regions = [
        (x=width * margin, y=height * 0.25),        # Left-top
        (x=width * (1-margin), y=height * 0.25),    # Right-top
        (x=width * margin, y=height * 0.75),        # Left-bottom
        (x=width * (1-margin), y=height * 0.75),    # Right-bottom
        (x=width * 0.5, y=height * 0.15),           # Center-top
        (x=width * 0.5, y=height * 0.85),           # Center-bottom
    ]

    colors = [
        (255, 100, 100),  # Red
        (100, 255, 100),  # Green
        (100, 100, 255),  # Blue
        (255, 255, 100),  # Yellow
        (255, 100, 255),  # Magenta
        (100, 255, 255),  # Cyan
    ]

    for i in 1:n_agents
        region = regions[i]

        # Add small jitter to position (±20px)
        # Smaller jitter ensures agents start well outside each other's FOV
        x = region.x + (rand() - 0.5) * 40.0
        y = region.y + (rand() - 0.5) * 40.0

        # Random initial orientation
        theta = rand() * 2π - π

        agent = Agent(i, x, y, theta=theta, color=colors[i])

        # No explicit goals (epistemic foraging only)
        agent.goal = nothing

        # Moderate personal space for collision avoidance
        agent.personal_space = 20.0

        push!(env.agents, agent)
    end

    return env
end

"""
    step!(env::Environment, params::EPHParams)

Execute one simulation timestep with Active Inference-based EPH control.

# Workflow
1. Perception: Compute SPM for each agent
2. Inference: Compute self-haze and belief entropy
3. Action Selection: Minimize Expected Free Energy G(a)
4. Physics: Update positions and orientations
5. Tracking: Update coverage map and detect information gain events
"""
function step!(env::Environment, params::EPHParams)
    # Initialize controller with EPH parameters
    controller = EPH.GradientEPHController(params)
    spm_params = SPM.SPMParams(d_max=params.fov_range)

    # --- 1. Perception & Action Selection ---
    for agent in env.agents
        # Compute SPM (Saliency Polar Map)
        spm = SPM.compute_spm(agent, env, spm_params)

        # Store SPM for visualization/debugging
        agent.current_spm = spm

        # Compute self-haze from SPM occupancy
        agent.self_haze = SelfHaze.compute_self_haze(spm, params)

        # Track visible agents (for analysis)
        agent.visible_agents = _get_visible_agent_ids(agent, env, params)

        # Compute precision matrix (will be computed inside EFE, but store for viz)
        Π = SelfHaze.compute_precision_matrix(spm, agent.self_haze, params)
        agent.current_precision = Π

        # Preferred velocity (no goals in sparse foraging)
        pref_vel = nothing
        if agent.goal !== nothing
            dx, dy, dist = toroidal_distance(agent.position, agent.goal, env.width, env.height)
            if dist > 0
                pref_vel = [dx / dist * params.max_speed, dy / dist * params.max_speed]
            end
        end

        # Decide action by minimizing Expected Free Energy
        action = EPH.decide_action(controller, agent, spm, pref_vel)
        agent.velocity = action
    end

    # --- 2. Physics Update ---
    dt = env.dt
    for agent in env.agents
        # Update position
        agent.position += agent.velocity * dt

        # Toroidal wrap-around
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)

        # Update orientation (heading direction)
        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end

    # --- 3. Coverage Map Update ---
    _update_coverage_map!(env, params)

    # --- 4. Frame Counter ---
    env.frame_count += 1
end

"""
    _get_visible_agent_ids(agent, env, params) -> Vector{Int}

Get IDs of agents currently within FOV.
Used for tracking visible neighbors and computing occupancy statistics.
"""
function _get_visible_agent_ids(agent::Agent, env::Environment, params::EPHParams)::Vector{Int}
    visible_ids = Int[]

    for other in env.agents
        if other.id == agent.id
            continue
        end

        # Compute toroidal distance
        dx, dy, dist = toroidal_distance(agent.position, other.position, env.width, env.height)

        # Check if within range
        if dist > params.fov_range
            continue
        end

        # Check if within FOV angle
        angle_to_other = atan(dy, dx)
        relative_angle = mod(angle_to_other - agent.orientation + π, 2π) - π

        if abs(relative_angle) <= params.fov_angle / 2.0
            push!(visible_ids, other.id)
        end
    end

    return visible_ids
end

"""
    _update_coverage_map!(env, params)

Update coverage map based on current agent positions.
Marks grid cells as covered if an agent is within detection range.
"""
function _update_coverage_map!(env::Environment, params::EPHParams)
    grid_w = size(env.coverage_map, 1)
    grid_h = size(env.coverage_map, 2)

    for agent in env.agents
        # Compute grid coordinates
        gx = clamp(floor(Int, agent.position[1] / env.grid_size) + 1, 1, grid_w)
        gy = clamp(floor(Int, agent.position[2] / env.grid_size) + 1, 1, grid_h)

        # Mark as covered
        env.coverage_map[gx, gy] = true

        # Also mark adjacent cells (agent's footprint)
        for dx in -1:1, dy in -1:1
            nx = clamp(gx + dx, 1, grid_w)
            ny = clamp(gy + dy, 1, grid_h)
            env.coverage_map[nx, ny] = true
        end
    end
end

end
