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
    comm_params::CommParams=DEFAULT_COMM,
    spm_params::SPMParams=DEFAULT_SPM,
    agent_params::AgentParams=DEFAULT_AGENT,
    local_agents::Vector{Vector{Float64}}=Vector{Vector{Float64}}[]
)
    # local_agents is already prepared in run_simulation.jl with [x, y, group] format
    # and properly filtered and aligned with SPM input.
    
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
