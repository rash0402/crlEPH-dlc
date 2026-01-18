"""
Agent Dynamics and World Model
2nd-order system with torus topology
"""

module Dynamics

using LinearAlgebra
using Random
using ..Config

export Agent, AgentGroup, Obstacle, CircularObstacle, init_agents, init_obstacles, step!, wrap_torus, relative_position, check_collision, predict_state, predict_other_agents
export init_corridor_agents, init_corridor_obstacles
export distance_to_circular_obstacle

"""
Agent group identifiers (N/S/E/W)
"""
@enum AgentGroup begin
    NORTH = 1
    SOUTH = 2
    EAST = 3
    WEST = 4
end

"""
Static rectangular obstacle
"""
struct Obstacle
    x_min::Float64
    x_max::Float64
    y_min::Float64
    y_max::Float64
end

"""
Circular obstacle for collision detection and visualization (v7.2)

Used for Random Obstacles scenario where obstacles are circular with varying radii.
Provides accurate collision detection compared to point-based approximation.
"""
struct CircularObstacle
    center::Tuple{Float64, Float64}  # (x, y) center position
    radius::Float64                   # Obstacle radius
end

"""
Agent state representation (v7.2: 5D state space)

State: s = [x, y, vx, vy, θ] ∈ ℝ⁵
- (x, y): Position
- (vx, vy): Velocity components
- θ: Heading angle (aligned with velocity direction via k_align)
"""
mutable struct Agent
    id::Int
    group::AgentGroup
    pos::Vector{Float64}      # [x, y]
    vel::Vector{Float64}      # [vx, vy]
    heading::Float64          # θ (v7.2: heading angle, follows velocity direction)
    acc::Vector{Float64}      # [ax, ay]
    d_goal::Vector{Float64}   # Preferred direction unit vector (v7.2: e.g., [1,0] for East)
    color::String             # For visualization
    precision::Float64        # Precision (Π = 1/H) for adaptive β modulation
end

"""
Wrap position to torus topology
"""
function wrap_torus(pos::AbstractVector, world::WorldParams)
    return [
        mod(pos[1], world.width),
        mod(pos[2], world.height)
    ]
end

"""
Initialize agents for 4-group scramble crossing scenario
- North (Blue): Start top, move down (goal: bottom)
- South (Red): Start bottom, move up (goal: top)
- East (Green): Start left, move right (goal: right)
- West (Yellow): Start right, move left (goal: left)
"""
function init_agents(
    agent_params::AgentParams=DEFAULT_AGENT,
    world_params::WorldParams=DEFAULT_WORLD;
    seed::Int=42
)
    Random.seed!(seed)
    
    agents = Agent[]
    n = agent_params.n_agents_per_group
    w = world_params.width
    h = world_params.height
    
    # Group colors
    colors = Dict(
        NORTH => "blue",
        SOUTH => "red",
        EAST => "green",
        WEST => "magenta"
    )
    
    agent_id = 1
    
    # Center region for goals
    margin = world_params.center_margin
    cx_min = w/2 - margin
    cx_max = w/2 + margin
    cy_min = h/2 - margin
    cy_max = h/2 + margin
    
    # North group (top → center, moving South)
    for i in 1:n
        pos = [cx_min + rand() * (cx_max - cx_min), h * 0.85 + rand() * h * 0.1]
        vel = [0.0, -2.0 + randn() * 0.5]  # Moving down
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [0.0, -1.0]  # Direction: South (v7.2: unit vector)
        push!(agents, Agent(agent_id, NORTH, pos, vel, heading, [0.0, 0.0], d_goal, colors[NORTH], 1.0))
        agent_id += 1
    end
    
    # South group (bottom → center, moving North)
    for i in 1:n
        pos = [cx_min + rand() * (cx_max - cx_min), h * 0.05 + rand() * h * 0.1]
        vel = [0.0, 2.0 + randn() * 0.5]  # Moving up
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [0.0, 1.0]  # Direction: North (v7.2: unit vector)
        push!(agents, Agent(agent_id, SOUTH, pos, vel, heading, [0.0, 0.0], d_goal, colors[SOUTH], 1.0))
        agent_id += 1
    end

    # East group (left → center, moving East)
    for i in 1:n
        pos = [w * 0.05 + rand() * w * 0.1, cy_min + rand() * (cy_max - cy_min)]
        vel = [2.0 + randn() * 0.5, 0.0]  # Moving right
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [1.0, 0.0]  # Direction: East (v7.2: unit vector)
        push!(agents, Agent(agent_id, EAST, pos, vel, heading, [0.0, 0.0], d_goal, colors[EAST], 1.0))
        agent_id += 1
    end

    # West group (right → center, moving West)
    for i in 1:n
        pos = [w * 0.85 + rand() * w * 0.1, cy_min + rand() * (cy_max - cy_min)]
        vel = [-2.0 + randn() * 0.5, 0.0]  # Moving left
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [-1.0, 0.0]  # Direction: West (v7.2: unit vector)
        push!(agents, Agent(agent_id, WEST, pos, vel, heading, [0.0, 0.0], d_goal, colors[WEST], 1.0))
        agent_id += 1
    end
    
    return agents
end

"""
Initialize agents for Corridor scenario (Bidirectional Flow).
- East group: Start left side, move right (goal: right exit)
- West group: Start right side, move left (goal: left exit)

Args:
    agent_params: Agent parameters
    world_params: World parameters
    corridor_width: Width of corridor (must match init_corridor_obstacles)
    seed: Random seed
    
Returns:
    Vector of Agent objects
"""
function init_corridor_agents(
    agent_params::AgentParams=DEFAULT_AGENT,
    world_params::WorldParams=DEFAULT_WORLD;
    corridor_width::Float64=4.0,
    corridor_length_ratio::Float64=0.6,
    seed::Int=42
)
    Random.seed!(seed)
    
    agents = Agent[]
    n = agent_params.n_agents_per_group
    w = world_params.width
    h = world_params.height
    
    # Corridor geometry
    corridor_length = w * corridor_length_ratio
    corridor_start_x = (w - corridor_length) / 2
    corridor_end_x = corridor_start_x + corridor_length
    corridor_center_y = h / 2
    
    # Spawn zones (just outside corridor ends)
    spawn_margin = 5.0
    east_spawn_x_min = corridor_start_x - spawn_margin - 5.0
    east_spawn_x_max = corridor_start_x - spawn_margin
    west_spawn_x_min = corridor_end_x + spawn_margin
    west_spawn_x_max = corridor_end_x + spawn_margin + 5.0
    
    # Vertical range within corridor
    spawn_y_min = corridor_center_y - corridor_width / 2 + 0.5
    spawn_y_max = corridor_center_y + corridor_width / 2 - 0.5
    
    # Goal positions (opposite ends)
    east_goal_x = corridor_end_x + 10.0
    west_goal_x = corridor_start_x - 10.0
    
    colors = Dict(
        EAST => "green",
        WEST => "magenta"
    )
    
    agent_id = 1
    
    # East group (left → right, moving East)
    for i in 1:n
        pos = [east_spawn_x_min + rand() * (east_spawn_x_max - east_spawn_x_min),
               spawn_y_min + rand() * (spawn_y_max - spawn_y_min)]
        vel = [2.0 + randn() * 0.3, 0.0]  # Moving right
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [1.0, 0.0]  # Direction: East (v7.2: unit vector)
        push!(agents, Agent(agent_id, EAST, pos, vel, heading, [0.0, 0.0], d_goal, colors[EAST], 1.0))
        agent_id += 1
    end

    # West group (right → left, moving West)
    for i in 1:n
        pos = [west_spawn_x_min + rand() * (west_spawn_x_max - west_spawn_x_min),
               spawn_y_min + rand() * (spawn_y_max - spawn_y_min)]
        vel = [-2.0 + randn() * 0.3, 0.0]  # Moving left
        heading = atan(vel[2], vel[1])  # Initial heading from velocity
        d_goal = [-1.0, 0.0]  # Direction: West (v7.2: unit vector)
        push!(agents, Agent(agent_id, WEST, pos, vel, heading, [0.0, 0.0], d_goal, colors[WEST], 1.0))
        agent_id += 1
    end
    
    return agents
end

"""
Initialize corner obstacles (Scramble Crossing scenario)
"""
function init_obstacles(world_params::WorldParams=DEFAULT_WORLD)
    w = world_params.width
    h = world_params.height
    s = world_params.obstacle_size
    
    obstacles = [
        Obstacle(0.0, s, 0.0, s),           # Bottom-left
        Obstacle(w-s, w, 0.0, s),           # Bottom-right
        Obstacle(0.0, s, h-s, h),           # Top-left
        Obstacle(w-s, w, h-s, h)            # Top-right
    ]
    
    return obstacles
end

"""
Initialize corridor obstacles (Narrow Passage scenario for Bidirectional Flow).
Creates two long walls forming a horizontal corridor in the center of the world.

Args:
    world_params: World parameters
    corridor_width: Width of the corridor (default 4.0m)
    corridor_length: Length of the corridor as fraction of world width (default 0.6)
    
Returns:
    Vector of Obstacle objects forming the corridor walls
"""
function init_corridor_obstacles(
    world_params::WorldParams=DEFAULT_WORLD;
    corridor_width::Float64=4.0,
    corridor_length_ratio::Float64=0.6
)
    w = world_params.width
    h = world_params.height
    
    # Corridor dimensions
    corridor_length = w * corridor_length_ratio
    corridor_start_x = (w - corridor_length) / 2
    corridor_end_x = corridor_start_x + corridor_length
    
    # Corridor centered vertically
    corridor_center_y = h / 2
    wall_thickness = 2.0  # Wall thickness
    
    # Top wall (above corridor)
    top_wall_y_min = corridor_center_y + corridor_width / 2
    top_wall_y_max = top_wall_y_min + wall_thickness
    
    # Bottom wall (below corridor)
    bottom_wall_y_max = corridor_center_y - corridor_width / 2
    bottom_wall_y_min = bottom_wall_y_max - wall_thickness
    
    obstacles = [
        # Top wall
        Obstacle(corridor_start_x, corridor_end_x, top_wall_y_min, top_wall_y_max),
        # Bottom wall
        Obstacle(corridor_start_x, corridor_end_x, bottom_wall_y_min, bottom_wall_y_max)
    ]
    
    return obstacles
end

"""
Check if point is inside obstacle (with agent radius)
"""
function check_collision(
    pos::Vector{Float64},
    obstacles::Vector{Obstacle},
    r_agent::Float64
)
    for obs in obstacles
        # Check collision with margin for agent radius
        if (pos[1] + r_agent > obs.x_min && pos[1] - r_agent < obs.x_max &&
            pos[2] + r_agent > obs.y_min && pos[2] - r_agent < obs.y_max)
            return true
        end
    end
    return false
end

"""
Check collision between two agents
"""
function check_agent_collision(
    pos1::Vector{Float64},
    pos2::Vector{Float64},
    r_agent::Float64,
    world::WorldParams
)
    # Get relative position with torus wrapping
    rel_pos = relative_position(pos1, pos2, world)
    dist = norm(rel_pos)
    
    # Check if distance is less than 2 * radius (collision)
    return dist < 2.0 * r_agent
end

"""
Update agent state using unicycle model (for v6.3 controller-bias-free)

Kinematic unicycle model:
    x_dot = v * cos(θ)
    y_dot = v * sin(θ)
    θ_dot = ω

Args:
    agent: Agent to update
    u: Control input [v, ω] where v is linear velocity, ω is angular velocity
    agent_params: Agent parameters
    world_params: World parameters
    obstacles: List of obstacles (for collision detection)
    all_agents: All agents (for collision detection)

Returns:
    collision_count::Int - Number of collisions detected this step
"""
function step_unicycle!(
    agent::Agent,
    u::Vector{Float64},
    agent_params::AgentParams,
    world_params::WorldParams,
    obstacles::Vector{Obstacle},
    all_agents::Vector{Agent}
)
    collision_count = 0

    # Extract v and ω from control input
    v = u[1]  # Linear velocity
    ω = u[2]  # Angular velocity

    # Compute current heading from velocity
    current_heading = norm(agent.vel) > 1e-6 ? atan(agent.vel[2], agent.vel[1]) : 0.0

    # Update heading with angular velocity
    new_heading = current_heading + ω * world_params.dt

    # Update velocity using unicycle model
    new_vel = [v * cos(new_heading), v * sin(new_heading)]

    # Update position
    new_pos = agent.pos .+ new_vel .* world_params.dt

    # Apply torus wrapping
    new_pos = wrap_torus(new_pos, world_params)

    # Compute acceleration for logging (before updating velocity)
    new_acc = (new_vel .- agent.vel) ./ world_params.dt

    # Update agent state
    agent.pos = new_pos
    agent.vel = new_vel
    agent.acc = new_acc

    # Check collisions (for metrics only)
    # Obstacle collisions
    if check_collision(agent.pos, obstacles, agent_params.r_agent)
        collision_count += 1
    end

    # Agent collisions
    for other in all_agents
        if other.id != agent.id
            rel_pos = relative_position(agent.pos, other.pos, world_params)
            dist = norm(rel_pos)
            if dist < 2.0 * agent_params.r_agent
                collision_count += 1
            end
        end
    end

    return collision_count
end

"""
Update agent state using 2nd-order dynamics with collision detection (v7.2 Model A)
Uses RK4 integration with heading alignment.

Returns:
    collision_count::Int - Number of collisions detected this step
"""
function step!(
    agent::Agent,
    u::Vector{Float64},
    agent_params::AgentParams,
    world_params::WorldParams,
    obstacles::Vector{Obstacle},
    all_agents::Vector{Agent}
)
    # Clamp control input (force magnitude)
    u_norm = norm(u)
    if u_norm > agent_params.u_max
        u = u .* (agent_params.u_max / u_norm)
    end
    
    # Construct current state vector [x, y, vx, vy, θ]
    state_current = [agent.pos[1], agent.pos[2], agent.vel[1], agent.vel[2], agent.heading]

    # RK4 integration (v7.2 dynamics)
    state_next = dynamics_rk4(state_current, u, agent_params, world_params)

    # Extract next state
    agent.pos = [state_next[1], state_next[2]]
    agent.vel = [state_next[3], state_next[4]]
    agent.heading = state_next[5]

    # Apply torus wrapping
    agent.pos = wrap_torus(agent.pos, world_params)

    # Compute acceleration for logging (approximate)
    # Note: This includes drag and heading effects implicitly
    agent.acc = (agent.vel - [state_current[3], state_current[4]]) / world_params.dt

    # Collision detection (for metrics)
    collision_count = 0
    
    # Obstacle collisions
    if check_collision(agent.pos, obstacles, agent_params.r_agent)
        collision_count += 1
    end
    
    # Agent collisions
    for other in all_agents
        if other.id != agent.id
            rel_pos = relative_position(agent.pos, other.pos, world_params)
            dist = norm(rel_pos)
            if dist < 2.0 * agent_params.r_agent
                collision_count += 1
            end
        end
    end

    return collision_count
end

"""
Compute relative position with torus topology
"""
function relative_position(pos_self::Vector{Float64}, pos_other::Vector{Float64}, world::WorldParams)
    dx = pos_other[1] - pos_self[1]
    dy = pos_other[2] - pos_self[2]
    
    # Torus shortest path
    if abs(dx) > world.width / 2
        dx = dx - sign(dx) * world.width
    end
    if abs(dy) > world.height / 2
        dy = dy - sign(dy) * world.height
    end
    
    return [dx, dy]
end

"""
Calculate distance from a point to a circular obstacle (v7.2)

Computes the minimum distance from a point (e.g., agent position) to the edge of a
circular obstacle, accounting for both the obstacle radius and agent radius.

Args:
    pos: Position [x, y]
    obstacle: CircularObstacle
    agent_radius: Radius of the agent (default: 0.5m)

Returns:
    Distance to obstacle edge (negative if penetrating)
"""
function distance_to_circular_obstacle(
    pos::Vector{Float64},
    obstacle::CircularObstacle,
    agent_radius::Float64=0.5
)
    center = [obstacle.center[1], obstacle.center[2]]
    center_distance = norm(pos - center)
    # Distance to obstacle edge = center distance - obstacle radius - agent radius
    return center_distance - obstacle.radius - agent_radius
end

# ===== Predictive Functions for M4 =====

"""
Predict agent state one step ahead given control input.
Used for Expected Free Energy (EFE) computation.

Args:
    agent: Current agent state
    u: Control input [ux, uy]
    agent_params: Agent parameters
    world_params: World parameters

Returns:
    (pos_next, vel_next): Predicted position and velocity
"""
function predict_state(
    agent::Agent,
    u::AbstractVector,
    agent_params::AgentParams,
    world_params::WorldParams
)
    dt = world_params.dt
    M = agent_params.mass
    D = agent_params.damping
    
    # Current state
    pos = agent.pos
    vel = agent.vel
    
    # Predict acceleration
    acc_next = (u - D .* vel) ./ M
    
    # Predict velocity (Euler integration)
    vel_next = vel + acc_next .* dt
    
    # Predict position (Euler integration)
    pos_next = pos + vel_next .* dt
    
    # Apply torus wrapping
    pos_next = wrap_torus(pos_next, world_params)
    
    return pos_next, vel_next
end

"""
Predict other agents' states assuming constant velocity.
Simplified prediction for computational efficiency.

Args:
    agents: Vector of other agents
    world_params: World parameters

Returns:
    Vector of predicted (position, velocity) tuples
"""
function predict_other_agents(
    agents::Vector{Agent},
    world_params::WorldParams
)
    dt = world_params.dt
    predictions = Tuple{Vector{Float64}, Vector{Float64}}[]
    
    for agent in agents
        # Constant velocity assumption
        pos_next = agent.pos + agent.vel .* dt
        pos_next = wrap_torus(pos_next, world_params)
        vel_next = agent.vel  # Constant
        
        push!(predictions, (pos_next, vel_next))
    end
    
    return predictions
end

# ===== v7.2: RK4 Integration with Heading Alignment =====

"""
Compute shortest angular difference with wrap-around (v7.2 helper function).

Args:
    target: Target angle [rad]
    current: Current angle [rad]

Returns:
    diff: Shortest angular difference in [-π, π]
"""
function angle_diff(target::Real, current::Real)
    diff = target - current
    # Wrap to [-π, π]
    while diff > π
        diff -= 2π
    end
    while diff < -π
        diff += 2π
    end
    return diff
end

"""
v7.2: Omnidirectional dynamics with heading alignment (RK4 integration).

State space: s = [x, y, vx, vy, θ] ∈ ℝ⁵
Control input: u = [Fx, Fy] ∈ ℝ²

Dynamics equations:
  dx/dt = vx
  dy/dt = vy
  m·dvx/dt = Fx - cd·|v|·vx  (2nd-order translational dynamics)
  m·dvy/dt = Fy - cd·|v|·vy
  dθ/dt = k_align · angle_diff(atan2(vy, vx), θ)  (Heading alignment)

Args:
    state: Current state [x, y, vx, vy, θ]
    u: Control input [Fx, Fy]
    agent_params: Agent parameters (mass, drag, k_align)
    world_params: World parameters (dt)

Returns:
    state_next: Next state after RK4 integration
"""
function dynamics_rk4(
    state::Vector{Float64},
    u::Vector{Float64},
    agent_params::AgentParams,
    world_params::WorldParams
)
    dt = world_params.dt
    m = agent_params.mass
    cd = agent_params.damping  # v7.2: drag coefficient
    k_align = agent_params.k_align  # v7.2: 4.0 rad/s (heading alignment gain)

    # Define derivative function f(s, u)
    function f(s::Vector{Float64}, u_input::Vector{Float64})
        x, y, vx, vy, theta = s
        Fx, Fy = u_input

        v_norm = sqrt(vx^2 + vy^2)

        # Target heading (velocity direction)
        if v_norm > 0.1  # Threshold to avoid division by zero
            theta_target = atan(vy, vx)
            dtheta = angle_diff(theta_target, theta)
        else
            dtheta = 0.0  # Keep current heading when nearly stopped
        end

        return [
            vx,                           # dx/dt
            vy,                           # dy/dt
            Fx/m - cd/m * vx * v_norm,    # dvx/dt (quadratic drag)
            Fy/m - cd/m * vy * v_norm,    # dvy/dt
            k_align * dtheta              # dθ/dt (heading alignment)
        ]
    end

    # RK4 integration
    k1 = f(state, u)
    k2 = f(state + dt/2 * k1, u)
    k3 = f(state + dt/2 * k2, u)
    k4 = f(state + dt * k3, u)

    state_next = state + dt/6 * (k1 + 2*k2 + 2*k3 + k4)

    return state_next
end

"""
Clamp position to valid corridor bounds (v7.2 funnel-shaped corridor)

For corridor scenarios, ensures agents stay within the funnel-shaped passage.
X=0-40m: width 40→10m (linear transition)
X=40-60m: width 10m (constant)
X=60-100m: width 10→40m (linear transition)
"""
function clamp_to_corridor(pos::Vector{Float64}, world_params::WorldParams)
    # Funnel corridor parameters (matching scenarios.jl)
    narrow_width = 15.0
    wide_width = 50.0
    narrow_x_start = 40.0
    narrow_x_end = 60.0
    world_x = world_params.width
    world_y = world_params.height
    center_y = world_y / 2.0
    margin = 1.0  # Safety margin from walls

    x = pos[1]
    y = pos[2]

    # Calculate valid corridor width at this X position
    if x < narrow_x_start
        t = x / narrow_x_start
        current_width = wide_width - (wide_width - narrow_width) * t
    elseif x <= narrow_x_end
        current_width = narrow_width
    else
        t = (x - narrow_x_end) / (world_x - narrow_x_end)
        current_width = narrow_width + (wide_width - narrow_width) * t
    end

    # Clamp Y to valid range
    y_min = center_y - current_width / 2.0 + margin
    y_max = center_y + current_width / 2.0 - margin
    y_clamped = clamp(y, y_min, y_max)

    return [x, y_clamped]
end

function check_corridor_wall_collision(pos::Vector{Float64}, world_params::WorldParams, r_agent::Float64)
    # Check if agent is colliding with funnel corridor walls
    # Returns true if agent (with radius r_agent) penetrates the corridor walls
    
    # Funnel corridor parameters (matching scenarios.jl and clamp_to_corridor)
    narrow_width = 15.0
    wide_width = 50.0
    narrow_x_start = 40.0
    narrow_x_end = 60.0
    world_x = world_params.width
    center_y = world_params.height / 2.0
    
    x = pos[1]
    y = pos[2]
    
    # Calculate corridor width at this X position
    if x < narrow_x_start
        t = x / narrow_x_start
        current_width = wide_width - (wide_width - narrow_width) * t
    elseif x <= narrow_x_end
        current_width = narrow_width
    else
        t = (x - narrow_x_end) / (world_x - narrow_x_end)
        current_width = narrow_width + (wide_width - narrow_width) * t
    end
    
    # Calculate wall positions
    y_upper = center_y + current_width / 2.0
    y_lower = center_y - current_width / 2.0
    
    # Check if agent penetrates either wall (agent center + radius exceeds wall boundary)
    return (y + r_agent > y_upper) || (y - r_agent < y_lower)
end

"""
Update agent state using v7.2 dynamics (wrapper for dynamics_rk4).

Args:
    agent: Agent to update
    u: Control input [Fx, Fy]
    agent_params: Agent parameters
    world_params: World parameters
    obstacles: List of obstacles (for collision detection)
    all_agents: All agents (for collision detection)

Returns:
    collision_count: Number of collisions detected this step
"""
function step_v72!(
    agent::Agent,
    u::Vector{Float64},
    agent_params::AgentParams,
    world_params::WorldParams,
    obstacles::Vector{Obstacle},
    all_agents::Vector{Agent}
)
    # Store previous position for collision recovery
    prev_pos = copy(agent.pos)

    # Construct current state vector
    state_current = [agent.pos[1], agent.pos[2], agent.vel[1], agent.vel[2], agent.heading]

    # RK4 integration
    state_next = dynamics_rk4(state_current, u, agent_params, world_params)

    # Extract next state
    agent.pos = [state_next[1], state_next[2]]
    agent.vel = [state_next[3], state_next[4]]
    agent.heading = state_next[5]

    # Detect scenario type by world size
    is_funnel_corridor = (world_params.width == 100.0 && world_params.height == 50.0)
    is_scramble = (world_params.width == 50.0 && world_params.height == 50.0)
    is_random_obstacles = (world_params.width == 100.0 && world_params.height == 100.0)

    # Apply boundary conditions based on scenario
    if is_funnel_corridor
        # Corridor: NO torus wrapping, clamp to corridor bounds
        agent.pos = clamp_to_corridor(agent.pos, world_params)
    elseif is_random_obstacles
        # Random obstacles: NO torus wrapping, clamp to world bounds
        agent.pos[1] = clamp(agent.pos[1], 0.0, world_params.width)
        agent.pos[2] = clamp(agent.pos[2], 0.0, world_params.height)
    else
        # Scramble: use torus wrapping (periodic boundaries)
        agent.pos = wrap_torus(agent.pos, world_params)
    end

    # Compute acceleration for logging
    agent.acc = (agent.vel - [state_current[3], state_current[4]]) / world_params.dt

    # Collision detection and processing
    collision_count = 0
    collided = false

    # 1. Discrete Obstacle Collision (Check ALL obstacles regardless of scenario)
    # This prevents agents from entering discrete obstacles (or wall points)
    if check_collision(agent.pos, obstacles, agent_params.r_agent)
        collision_count += 1
        collided = true
    end

    # 2. Funnel Wall Collision (Specific to corridor, ensures mathematical boundary)
    if is_funnel_corridor
        if check_corridor_wall_collision(agent.pos, world_params, agent_params.r_agent)
            collision_count += 1
        end
    end

    # 3. Physical Blocking (Revert position if collided)
    if collided
        # Simple separation logic: Revert to previous position and stop
        # This effectively treats obstacles as solid walls
        agent.pos = prev_pos
        agent.vel = [0.0, 0.0]  # Kill velocity
        # Keep heading
    end

    # Agent collisions (Metrics only, no physical blocking usually for pedestrians)
    for other in all_agents
        if other.id != agent.id
            rel_pos = relative_position(agent.pos, other.pos, world_params)
            dist = norm(rel_pos)
            if dist < 2.0 * agent_params.r_agent
                collision_count += 1
            end
        end
    end

    return collision_count
end            end
        end
    end

    return collision_count
end

export dynamics_rk4, step_v72!, angle_diff

end # module
