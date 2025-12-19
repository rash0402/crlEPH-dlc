"""
HDF5 Data Logger
Real-time buffered writing of simulation data
"""

module Logger

using HDF5
using ..Config

export DataLogger, init_logger, log_step!, close_logger

"""
HDF5 data logger
"""
mutable struct DataLogger
    file::HDF5.File
    spm_dataset::HDF5.Dataset
    action_dataset::HDF5.Dataset
    position_dataset::HDF5.Dataset
    velocity_dataset::HDF5.Dataset
    step_count::Int
    max_steps::Int
end

"""
Initialize HDF5 logger with preallocated datasets
"""
function init_logger(
    filename::String,
    spm_params::SPMParams=DEFAULT_SPM,
    world_params::WorldParams=DEFAULT_WORLD
)
    # Create HDF5 file
    file = h5open(filename, "w")
    
    # Create datasets with chunking for efficient writing
    spm_ds = create_dataset(
        file,
        "/data/spm",
        datatype(Float32),
        dataspace(spm_params.n_rho, spm_params.n_theta, 3, world_params.max_steps),
        chunk=(spm_params.n_rho, spm_params.n_theta, 3, 1)
    )
    
    action_ds = create_dataset(
        file,
        "/data/action",
        datatype(Float32),
        dataspace(2, world_params.max_steps),
        chunk=(2, 100)
    )
    
    position_ds = create_dataset(
        file,
        "/data/position",
        datatype(Float32),
        dataspace(2, world_params.max_steps),
        chunk=(2, 100)
    )
    
    velocity_ds = create_dataset(
        file,
        "/data/velocity",
        datatype(Float32),
        dataspace(2, world_params.max_steps),
        chunk=(2, 100)
    )
    
    # Store metadata
    attributes(file)["n_rho"] = spm_params.n_rho
    attributes(file)["n_theta"] = spm_params.n_theta
    attributes(file)["fov_deg"] = spm_params.fov_deg
    attributes(file)["dt"] = world_params.dt
    
    return DataLogger(
        file,
        spm_ds,
        action_ds,
        position_ds,
        velocity_ds,
        0,
        world_params.max_steps
    )
end

"""
Log data for current step
"""
function log_step!(
    logger::DataLogger,
    spm::Array{Float64, 3},
    action::Vector{Float64},
    position::Vector{Float64},
    velocity::Vector{Float64}
)
    logger.step_count += 1
    step = logger.step_count
    
    if step > logger.max_steps
        @warn "Exceeded max_steps, skipping logging"
        return
    end
    
    # Write data (HDF5 uses 1-based indexing)
    logger.spm_dataset[:, :, :, step] = Float32.(spm)
    logger.action_dataset[:, step] = Float32.(action)
    logger.position_dataset[:, step] = Float32.(position)
    logger.velocity_dataset[:, step] = Float32.(velocity)
end

"""
Close logger and finalize file
"""
function close_logger(logger::DataLogger)
    # Trim datasets to actual step count
    if logger.step_count < logger.max_steps
        # Note: HDF5.jl doesn't support easy resizing, so we leave as is
        attributes(logger.file)["actual_steps"] = logger.step_count
    end
    
    close(logger.file)
end

end # module
