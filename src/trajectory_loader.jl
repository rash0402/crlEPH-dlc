# trajectory_loader.jl
# Utility functions to load raw trajectory data and reconstruct SPMs for VAE training
#
# IMPORTANT: This file requires SPM module to be loaded before inclusion:
#   include("spm.jl")
#   using .SPM

using HDF5
using LinearAlgebra

"""
    load_trajectory_metadata(filepath::String)

Load metadata from raw trajectory HDF5 file.
"""
function load_trajectory_metadata(filepath::String)
    h5open(filepath, "r") do file
        meta = read(file["metadata"])
        spm_params = read(file["spm_params"])

        return (
            metadata=meta,
            spm_params=spm_params
        )
    end
end

"""
    load_trajectory_data(filepath::String)

Load raw trajectory data from HDF5 file.

Returns:
- pos: [T, N, 2] Position trajectories
- vel: [T, N, 2] Velocity trajectories
- u: [T, N, 2] Control input trajectories
- heading: [T, N] Heading angle trajectories
- obstacles: [M, 2] Obstacle positions (x, y)
- metadata: Dict with scenario info
- spm_params: Dict with SPM parameters
"""
function load_trajectory_data(filepath::String)
    h5open(filepath, "r") do file
        pos = read(file["trajectory/pos"])
        vel = read(file["trajectory/vel"])
        u = read(file["trajectory/u"])
        heading = read(file["trajectory/heading"])
        obstacles = read(file["obstacles/data"])

        meta = Dict{String, Any}()
        for key in keys(file["metadata"])
            meta[key] = read(file["metadata"][key])
        end

        spm_params = Dict{String, Any}()
        for key in keys(file["spm_params"])
            spm_params[key] = read(file["spm_params"][key])
        end

        return (
            pos=pos,
            vel=vel,
            u=u,
            heading=heading,
            obstacles=obstacles,
            metadata=meta,
            spm_params=spm_params
        )
    end
end

"""
    reconstruct_spm_at_timestep(
        pos::Matrix{Float64},  # [N, 2] positions at time t
        vel::Matrix{Float64},  # [N, 2] velocities at time t
        obstacles::Matrix{Float64},  # [M, 4] obstacle data
        agent_idx::Int,
        spm_config::SPMConfig,
        r_agent::Float64=0.3
    )

Reconstruct SPM for a specific agent at a specific timestep.

Args:
- pos: [N, 2] All agent positions at time t
- vel: [N, 2] All agent velocities at time t
- obstacles: [M, 2] Obstacle positions (x, y)
- agent_idx: Index of the focal agent (1-indexed)
- spm_config: SPM configuration
- r_agent: Agent radius

Returns:
- spm: [n_bins, n_angles, 3] SPM tensor
"""
function reconstruct_spm_at_timestep(
    pos,
    vel,
    obstacles,
    agent_idx,
    spm_config,
    r_agent=0.3
)
    n_agents = size(pos, 1)

    # Focal agent position
    agent_pos = pos[agent_idx, :]

    # Compute relative positions and velocities for all other agents
    agents_rel_pos = Vector{Vector{Float64}}()
    agents_rel_vel = Vector{Vector{Float64}}()

    for i in 1:n_agents
        if i != agent_idx
            rel_pos = pos[i, :] - agent_pos
            push!(agents_rel_pos, rel_pos)
            push!(agents_rel_vel, vel[i, :])
        end
    end

    # Add obstacles (obstacles is [M, 2] matrix with x, y positions)
    for i in 1:size(obstacles, 1)
        obs_pos = [obstacles[i, 1], obstacles[i, 2]]
        rel_pos = obs_pos - agent_pos
        push!(agents_rel_pos, rel_pos)
        push!(agents_rel_vel, [0.0, 0.0])  # Static obstacles
    end

    # Generate SPM using existing function (from spm.jl)
    spm = Main.SPM.generate_spm_3ch(spm_config, agents_rel_pos, agents_rel_vel, r_agent)

    return spm
end

"""
    extract_vae_training_pairs(
        filepath::String;
        stride::Int=1,
        agent_subsample::Union{Int, Nothing}=nothing
    )

Extract (y[k], u[k], y[k+1]) pairs from raw trajectory data.

Args:
- filepath: Path to HDF5 file with raw trajectory data
- stride: Temporal stride for sampling (default: 1 = all timesteps)
- agent_subsample: If specified, sample only every Nth agent

Returns:
- y_k: Array of SPMs at time k [M, n_bins, n_angles, 3]
- u_k: Array of actions at time k [M, 2]
- y_k1: Array of SPMs at time k+1 [M, n_bins, n_angles, 3]

where M is the total number of samples.
"""
function extract_vae_training_pairs(
    filepath::String;
    stride::Int=1,
    agent_subsample::Union{Int, Nothing}=nothing
)
    # Load raw trajectory data
    data = load_trajectory_data(filepath)

    pos = data.pos  # [T, N, 2]
    vel = data.vel  # [T, N, 2]
    u = data.u      # [T, N, 2]
    obstacles = data.obstacles  # [M, 4]

    # Create SPM config from stored parameters
    # Use default SPM params and override key parameters from stored data
    spm_params = Main.Config.SPMParams(
        data.spm_params["n_rho"],          # n_rho
        data.spm_params["n_theta"],        # n_theta
        360.0,                              # fov_deg (default)
        2π,                                 # fov_rad (default)
        0.4,                                # r_robot (default)
        data.spm_params["sensing_ratio"],  # sensing_ratio
        0.5,                                # sigma_spm (default)
        5.0,                                # beta_r_fixed (default)
        5.0,                                # beta_nu_fixed (default)
        1.0,                                # beta_r_min (default)
        10.0,                               # beta_r_max (default)
        1.0,                                # beta_nu_min (default)
        10.0                                # beta_nu_max (default)
    )

    spm_config = Main.SPM.init_spm(spm_params)

    r_agent = 0.3  # Agent radius (could be stored in metadata)

    T, N, _ = size(pos)

    # Determine which agents to process
    if isnothing(agent_subsample)
        agent_indices = 1:N
    else
        agent_indices = 1:agent_subsample:N
    end

    # Determine which timesteps to process (exclude last step since we need k+1)
    time_indices = 1:stride:(T-1)

    # Estimate number of samples
    n_samples = length(time_indices) * length(agent_indices)

    # Pre-allocate arrays
    n_bins = spm_config.params.n_rho
    n_angles = spm_config.params.n_theta

    y_k = zeros(Float32, n_samples, n_bins, n_angles, 3)
    u_k = zeros(Float32, n_samples, 2)
    y_k1 = zeros(Float32, n_samples, n_bins, n_angles, 3)

    # Extract pairs
    sample_idx = 1
    for t in time_indices
        for agent_idx in agent_indices
            # Reconstruct SPM at time t
            spm_t = reconstruct_spm_at_timestep(
                pos[t, :, :],
                vel[t, :, :],
                obstacles,
                agent_idx,
                spm_config,
                r_agent
            )

            # Reconstruct SPM at time t+1
            spm_t1 = reconstruct_spm_at_timestep(
                pos[t+1, :, :],
                vel[t+1, :, :],
                obstacles,
                agent_idx,
                spm_config,
                r_agent
            )

            # Store data
            y_k[sample_idx, :, :, :] = spm_t
            u_k[sample_idx, :] = u[t, agent_idx, :]
            y_k1[sample_idx, :, :, :] = spm_t1

            sample_idx += 1
        end
    end

    return (y_k=y_k, u_k=u_k, y_k1=y_k1)
end

"""
    load_all_trajectories(
        directory::String;
        pattern::String="v62_*.h5",
        stride::Int=1,
        agent_subsample::Union{Int, Nothing}=nothing
    )

Load and combine VAE training pairs from all trajectory files in a directory.

Args:
- directory: Path to directory containing HDF5 files
- pattern: Glob pattern for file matching
- stride: Temporal stride for sampling
- agent_subsample: If specified, sample only every Nth agent

Returns:
- Combined (y_k, u_k, y_k1) from all files
"""
function load_all_trajectories(
    directory::String;
    pattern::String="v62_*.h5",
    stride::Int=1,
    agent_subsample::Union{Int, Nothing}=nothing
)
    # Find all matching files
    files = filter(f -> occursin(r"v62_.*\.h5$", f), readdir(directory, join=true))

    if isempty(files)
        error("No trajectory files found in $directory matching pattern $pattern")
    end

    println("Found $(length(files)) trajectory files")

    # Accumulate data from all files
    all_y_k = Vector{Array{Float32}}()
    all_u_k = Vector{Array{Float32}}()
    all_y_k1 = Vector{Array{Float32}}()

    for (i, filepath) in enumerate(files)
        println("  Loading file $(i)/$(length(files)): $(basename(filepath))")

        data = extract_vae_training_pairs(filepath; stride=stride, agent_subsample=agent_subsample)

        push!(all_y_k, data.y_k)
        push!(all_u_k, data.u_k)
        push!(all_y_k1, data.y_k1)
    end

    # Concatenate all data
    println("  Concatenating data...")
    y_k_combined = vcat(all_y_k...)
    u_k_combined = vcat(all_u_k...)
    y_k1_combined = vcat(all_y_k1...)

    total_samples = size(y_k_combined, 1)
    println("  Total training pairs: $total_samples")

    return (y_k=y_k_combined, u_k=u_k_combined, y_k1=y_k1_combined)
end

"""
    load_trajectories_batch(
        directory::String;
        pattern::String="v62_*.h5",
        stride::Int=1,
        agent_subsample::Union{Int, Nothing}=nothing,
        max_files::Union{Int, Nothing}=nothing
    )

Load VAE training pairs from trajectory files with memory-efficient batch processing.

Args:
- directory: Path to directory containing HDF5 files
- pattern: Glob pattern for file matching
- stride: Temporal stride for sampling
- agent_subsample: If specified, sample only every Nth agent
- max_files: If specified, limit to first N files (for memory efficiency)

Returns:
- Combined (y_k, u_k, y_k1) from selected files
"""
function load_trajectories_batch(
    directory::String;
    pattern::String="v62_*.h5",
    stride::Int=1,
    agent_subsample::Union{Int, Nothing}=nothing,
    max_files::Union{Int, Nothing}=nothing
)
    # Find all matching files
    files = filter(f -> occursin(r"v62_.*\.h5$", f), readdir(directory, join=true))

    if isempty(files)
        error("No trajectory files found in $directory matching pattern $pattern")
    end

    # Limit number of files if specified
    if !isnothing(max_files)
        files = files[1:min(max_files, length(files))]
        println("Limiting to first $(length(files)) files for memory efficiency")
    end

    println("Found $(length(files)) trajectory files")

    # Accumulate data from all files
    all_y_k = Vector{Array{Float32}}()
    all_u_k = Vector{Array{Float32}}()
    all_y_k1 = Vector{Array{Float32}}()

    for (i, filepath) in enumerate(files)
        println("  Loading file $(i)/$(length(files)): $(basename(filepath))")
        flush(stdout)

        try
            data = extract_vae_training_pairs(filepath; stride=stride, agent_subsample=agent_subsample)

            push!(all_y_k, data.y_k)
            push!(all_u_k, data.u_k)
            push!(all_y_k1, data.y_k1)
        catch e
            println("    ERROR loading $(basename(filepath)): $e")
            println("    Skipping this file...")
            flush(stdout)
            continue
        end

        # Memory management: force garbage collection every 10 files
        if i % 10 == 0
            GC.gc()
            println("    [Memory: $(round(Sys.free_memory()/1e9, digits=2)) GB free]")
            flush(stdout)
        end
    end

    # Concatenate all data
    println("  Concatenating data...")
    flush(stdout)
    y_k_combined = vcat(all_y_k...)
    u_k_combined = vcat(all_u_k...)
    y_k1_combined = vcat(all_y_k1...)

    total_samples = size(y_k_combined, 1)
    println("  Total training pairs: $total_samples")
    flush(stdout)

    return (y_k=y_k_combined, u_k=u_k_combined, y_k1=y_k1_combined)
end
