"""
ZMQ Communication Module
PUB/SUB pattern with MsgPack serialization
"""

module Communication

using ZMQ
using MsgPack
using LinearAlgebra: norm
using ..Config
using ..Dynamics: Agent, relative_position

export Publisher, init_publisher, publish_global, publish_detail, close_publisher

"""
ZMQ Publisher wrapper
"""
mutable struct Publisher
    context::ZMQ.Context
    socket::ZMQ.Socket
    endpoint::String
end

"""
Initialize ZMQ PUB socket
"""
function init_publisher(comm_params::CommParams=DEFAULT_COMM)
    ctx = ZMQ.Context()
    socket = ZMQ.Socket(ctx, ZMQ.PUB)
    ZMQ.bind(socket, comm_params.zmq_endpoint)
    
    # Allow subscribers to connect
    sleep(0.1)
    
    return Publisher(ctx, socket, comm_params.zmq_endpoint)
end

"""
Publish global state (all agents)
"""
function publish_global(
    pub::Publisher,
    agents::Vector{Agent},
    step::Int,
    comm_params::CommParams=DEFAULT_COMM
)
    # Prepare data
    data = Dict(
        "step" => step,
        "n_agents" => length(agents),
        "positions" => [a.pos for a in agents],
        "velocities" => [a.vel for a in agents],
        "groups" => [Int(a.group) for a in agents],
        "colors" => [a.color for a in agents]
    )
    
    # Serialize with MsgPack
    msg_data = MsgPack.pack(data)
    
    # Send with topic prefix
    topic = comm_params.global_topic
    ZMQ.send(pub.socket, topic * " ", more=true)
    ZMQ.send(pub.socket, msg_data)
end

"""
Publish detail state (selected agent)
"""
function publish_detail(
    pub::Publisher,
    agent::Agent,
    spm::Array{Float64, 3},
    action::Vector{Float64},
    free_energy::Float64,
    step::Int,
    all_agents::Vector{Agent},
    world_params::WorldParams,
    comm_params::CommParams=DEFAULT_COMM
)
    # Transform other agents to local coordinates (ego-centric frame)
    # Local frame: ego at origin, velocity direction is +Y (forward/up)
    
    local_agents = []
    
    # Calculate ego heading for local transformation
    heading = 0.0
    rot_angle = π/2 # Default rotation (East=0 -> Up=90)
    vel_norm = norm(agent.vel)
    
    # Use velocity for orientation if moving
    # Lowered threshold to 0.001 to capture slow movements
    if vel_norm > 0.001
        heading = atan(agent.vel[2], agent.vel[1])
        # We want velocity direction to be +Y (Up) in local frame
        # Standard rotation: x' = x cosθ - y sinθ
        # To map v_theta to +90deg (π/2), we rotate by π/2 - v_theta
        rot_angle = -heading + π/2
    end
    
    
    cos_θ = cos(rot_angle)
    sin_θ = sin(rot_angle)
    
    for other in all_agents
        if other.id != agent.id
            # Get relative position in world frame
            rel_pos = relative_position(agent.pos, other.pos, world_params)
            
            # Rotate to local frame (velocity direction = +Y)
            local_x = cos_θ * rel_pos[1] - sin_θ * rel_pos[2]
            local_y = sin_θ * rel_pos[1] + cos_θ * rel_pos[2]
            
            # Include group ID for visualization coloring
            # Note: Enum must be converted to Int first
            push!(local_agents, [local_x, local_y, Float64(Int(other.group))])
        end
    end
    
    # Prepare data
    data = Dict(
        "step" => step,
        "agent_id" => agent.id,
        "group" => Int(agent.group),
        "position" => agent.pos,
        "velocity" => agent.vel,
        "spm" => spm,  # 16x16x3 array
        "action" => action,
        "free_energy" => free_energy,
        "local_agents" => local_agents  # Other agents in local coordinates
    )
    
    # Serialize with MsgPack
    msg_data = MsgPack.pack(data)
    
    # Send with topic prefix
    topic = comm_params.detail_topic
    ZMQ.send(pub.socket, topic * " ", more=true)
    ZMQ.send(pub.socket, msg_data)
end

"""
Close publisher
"""
function close_publisher(pub::Publisher)
    ZMQ.close(pub.socket)
    ZMQ.close(pub.context)
end

end # module
