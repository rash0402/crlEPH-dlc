"""
Agent Dynamics and World Model
2nd-order system with torus topology
"""

module Dynamics

using LinearAlgebra
using Random
using ..Config

export Agent, AgentGroup, Obstacle, init_agents, init_obstacles, step!, wrap_torus, relative_position, check_collision, predict_state, predict_other_agents

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
Agent state representation
"""
mutable struct Agent
    id::Int
    group::AgentGroup
    pos::Vector{Float64}      # [x, y]
    vel::Vector{Float64}      # [vx, vy]
    acc::Vector{Float64}      # [ax, ay]
    goal::Vector{Float64}     # [gx, gy] - for reference
    goal_vel::Vector{Float64} # [vx_goal, vy_goal] - desired velocity
    color::String             # For visualization
    precision::Float64        # Precision (Π = 1/H) for adaptive β modulation
end

"""
Wrap position to torus topology
"""
function wrap_torus(pos::Vector{Float64}, world::WorldParams)
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
    
    # North group (top → center)
    for i in 1:n
        pos = [cx_min + rand() * (cx_max - cx_min), h * 0.85 + rand() * h * 0.1]
        vel = [0.0, -2.0 + randn() * 0.5]  # Moving down
        goal = [cx_min + rand() * (cx_max - cx_min), cy_min + rand() * (cy_max - cy_min)]
        goal_vel = [0.0, -2.0]  # Constant downward velocity
        push!(agents, Agent(agent_id, NORTH, pos, vel, [0.0, 0.0], goal, goal_vel, colors[NORTH], 1.0))
        agent_id += 1
    end
    
    # South group (bottom → center)
    for i in 1:n
        pos = [cx_min + rand() * (cx_max - cx_min), h * 0.05 + rand() * h * 0.1]
        vel = [0.0, 2.0 + randn() * 0.5]  # Moving up
        goal = [cx_min + rand() * (cx_max - cx_min), cy_min + rand() * (cy_max - cy_min)]
        goal_vel = [0.0, 2.0]  # Constant upward velocity
        push!(agents, Agent(agent_id, SOUTH, pos, vel, [0.0, 0.0], goal, goal_vel, colors[SOUTH], 1.0))
        agent_id += 1
    end
    
    # East group (left → center)
    for i in 1:n
        pos = [w * 0.05 + rand() * w * 0.1, cy_min + rand() * (cy_max - cy_min)]
        vel = [2.0 + randn() * 0.5, 0.0]  # Moving right
        goal = [cx_min + rand() * (cx_max - cx_min), cy_min + rand() * (cy_max - cy_min)]
        goal_vel = [2.0, 0.0]  # Constant rightward velocity
        push!(agents, Agent(agent_id, EAST, pos, vel, [0.0, 0.0], goal, goal_vel, colors[EAST], 1.0))
        agent_id += 1
    end
    
    # West group (right → center)
    for i in 1:n
        pos = [w * 0.85 + rand() * w * 0.1, cy_min + rand() * (cy_max - cy_min)]
        vel = [-2.0 + randn() * 0.5, 0.0]  # Moving left
        goal = [cx_min + rand() * (cx_max - cx_min), cy_min + rand() * (cy_max - cy_min)]
        goal_vel = [-2.0, 0.0]  # Constant leftward velocity
        push!(agents, Agent(agent_id, WEST, pos, vel, [0.0, 0.0], goal, goal_vel, colors[WEST], 1.0))
        agent_id += 1
    end
    
    return agents
end

"""
Initialize corner obstacles
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
Update agent state using 2nd-order dynamics with collision detection
M * a + D * v = u
"""
function step!(
    agent::Agent,
    u::Vector{Float64},
    agent_params::AgentParams,
    world_params::WorldParams,
    obstacles::Vector{Obstacle},
    all_agents::Vector{Agent}
)
    # Clamp control input
    u_clamped = clamp.(u, -agent_params.u_max, agent_params.u_max)
    
    # Emergency repulsion force (only activated when very close to collision)
    emergency_repulsion = [0.0, 0.0]
    k_emergency = 100.0  # Strong emergency repulsion
    emergency_threshold_obs = 0.5  # Activate when within 0.5 units of obstacle
    emergency_threshold_agent = 0.3  # Activate when within 0.3 units of other agent
    
    # Check for emergency collision with obstacles
    for obs in obstacles
        # Check if agent is inside or very close to obstacle
        if (agent.pos[1] + agent_params.r_agent > obs.x_min - emergency_threshold_obs && 
            agent.pos[1] - agent_params.r_agent < obs.x_max + emergency_threshold_obs &&
            agent.pos[2] + agent_params.r_agent > obs.y_min - emergency_threshold_obs && 
            agent.pos[2] - agent_params.r_agent < obs.y_max + emergency_threshold_obs)
            
            # Calculate repulsion away from obstacle center
            obs_center = [(obs.x_min + obs.x_max)/2, (obs.y_min + obs.y_max)/2]
            to_obs = obs_center - agent.pos
            dist_to_obs = norm(to_obs)
            
            if dist_to_obs > 0.1
                # Strong repulsion away from obstacle
                emergency_repulsion -= (to_obs / dist_to_obs) * k_emergency
            end
        end
    end
    
    # Check for emergency collision with other agents
    for other in all_agents
        if other.id != agent.id
            rel_pos = relative_position(agent.pos, other.pos, world_params)
            dist = norm(rel_pos)
            min_dist = 2.0 * agent_params.r_agent
            
            # Emergency repulsion only when very close (within threshold)
            if dist < min_dist + emergency_threshold_agent
                if dist > 0.1
                    # Strong repulsion away from other agent
                    emergency_repulsion -= (rel_pos / dist) * k_emergency * (1.0 - dist / (min_dist + emergency_threshold_agent))
                end
            end
        end
    end
    
    # Combine FEP control with emergency repulsion (only when needed)
    total_force = u_clamped .+ emergency_repulsion
    total_force = clamp.(total_force, -agent_params.u_max * 3.0, agent_params.u_max * 3.0)
    
    # 2nd-order dynamics: a = (F - D*v) / M
    agent.acc = (total_force .- agent_params.damping .* agent.vel) ./ agent_params.mass
    
    # Euler integration
    new_vel = agent.vel .+ agent.acc .* world_params.dt
    new_pos = agent.pos .+ new_vel .* world_params.dt
    
    # Update state
    agent.vel .= new_vel
    agent.pos .= new_pos
    
    # Torus wrapping
    agent.pos = wrap_torus(agent.pos, world_params)
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
    u::Vector{Float64},
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

end # module
