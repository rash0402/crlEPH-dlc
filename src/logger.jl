"""
HDF5 Data Logger - Multi-Agent Version
Real-time buffered writing of simulation data for all agents
"""

module Logger

using HDF5
using ..Config
using ..Dynamics

export DataLogger, init_logger, log_step!, close_logger

"""
HDF5 data logger for multi-agent simulation
"""
mutable struct DataLogger
    file::HDF5.File
    position_dataset::HDF5.Dataset
    velocity_dataset::HDF5.Dataset
    action_dataset::HDF5.Dataset
    haze_dataset::HDF5.Dataset
    precision_dataset::HDF5.Dataset
    step_count::Int
    max_steps::Int
    num_agents::Int
end

"""
Initialize HDF5 logger with preallocated datasets for all agents
"""
function init_logger(
    filename::String,
    max_steps::Int,
    num_agents::Int
)
    # Create HDF5 file
    file = h5open(filename, "w")
    
    # Create datasets with chunking for efficient writing
    # Shape: (dimension, agent_id, timestep)
    position_ds = create_dataset(
        file,
        "/data/position",
        datatype(Float32),
        dataspace(2, num_agents, max_steps),
        chunk=(2, min(num_agents, 10), min(max_steps, 100))
    )
    
    velocity_ds = create_dataset(
        file,
        "/data/velocity",
        datatype(Float32),
        dataspace(2, num_agents, max_steps),
        chunk=(2, min(num_agents, 10), min(max_steps, 100))
    )
    
    action_ds = create_dataset(
        file,
        "/data/action",
        datatype(Float32),
        dataspace(2, num_agents, max_steps),
        chunk=(2, min(num_agents, 10), min(max_steps, 100))
    )
    
    haze_ds = create_dataset(
        file,
        "/data/haze",
        datatype(Float32),
        dataspace(num_agents, max_steps),
        chunk=(min(num_agents, 10), min(max_steps, 100))
    )
    
    precision_ds = create_dataset(
        file,
        "/data/precision",
        datatype(Float32),
        dataspace(num_agents, max_steps),
        chunk=(min(num_agents, 10), min(max_steps, 100))
    )
    
    # Store metadata
    attributes(file)["num_agents"] = num_agents
    attributes(file)["max_steps"] = max_steps
    attributes(file)["description"] = "EPH Multi-Agent Simulation Data"
    
    return DataLogger(
        file,
        position_ds,
        velocity_ds,
        action_ds,
        haze_ds,
        precision_ds,
        0,
        max_steps,
        num_agents
    )
end

"""
Log data for all agents at current step
"""
function log_step!(
    logger::DataLogger,
    agents::Vector{Agent},
    step::Int
)
    if step > logger.max_steps
        @warn "Exceeded max_steps, skipping logging"
        return
    end
    
    # Extract data from all agents
    for (i, agent) in enumerate(agents)
        # Position and velocity
        logger.position_dataset[:, i, step] = Float32.(agent.pos)
        logger.velocity_dataset[:, i, step] = Float32.(agent.vel)
        
        # Action (stored in agent.acc for now, or zero if not available)
        # Note: In actual simulation, action should be passed separately
        logger.action_dataset[:, i, step] = Float32.(agent.acc)
        
        # Haze and Precision
        # Note: Haze needs to be computed from agent state
        # For now, using precision inverse
        logger.precision_dataset[i, step] = Float32(agent.precision)
        logger.haze_dataset[i, step] = Float32(1.0 / (agent.precision + 1e-6))
    end
    
    logger.step_count = step
end

"""
Close logger and finalize file
"""
function close_logger(logger::DataLogger)
    # Store actual step count
    attributes(logger.file)["actual_steps"] = logger.step_count
    
    close(logger.file)
end

end # module
