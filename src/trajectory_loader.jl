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
        heading::Vector{Float64}, # [N] headings at time t
        obstacles::Matrix{Float64},  # [M, 2] obstacle data
        agent_idx::Int,
        spm_config::SPMConfig,
        r_agent::Float64=0.3
    )

Reconstruct SPM for a specific agent at a specific timestep (Ego-centric).

Args:
- pos: [N, 2] All agent positions at time t
- vel: [N, 2] All agent velocities at time t
- heading: [N] All agent headings at time t
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
    heading,
    obstacles,
    agent_idx,
    spm_config,
    r_agent=0.3
)
    n_agents = size(pos, 1)

    # Focal agent state
    agent_pos = pos[agent_idx, :]
    agent_heading = heading[agent_idx]

    # Rotation matrix for Global -> Ego transform
    # Rotate by -(heading - pi/2) => pi/2 - heading
    # This aligns Heading with +Y axis (SPM Forward)
    c = cos(pi/2 - agent_heading)
    s = sin(pi/2 - agent_heading)
    
    function rotate_vec(v)
        return [v[1]*c - v[2]*s, v[1]*s + v[2]*c]
    end

    # Compute relative positions and velocities for all other agents
    agents_rel_pos = Vector{Vector{Float64}}()
    agents_rel_vel = Vector{Vector{Float64}}()

    for i in 1:n_agents
        if i != agent_idx
            # Global relative vector
            rel_pos_global = pos[i, :] - agent_pos
            rel_vel_global = vel[i, :]  # Relative velocity in SPM is usually relative to ego velocity? 
            # Wait, `spm.jl` uses `radial_vel = -dot(p_rel, v_rel)`.
            # If v_rel is relative velocity (v_other - v_ego), then it makes sense.
            # But previous code used `vel[i, :]` (absolute velocity of other).
            # Let's check spm.jl logic.
            # `generate_spm_3ch` takes `agents_rel_vel`.
            # If `radial_vel` implies closing speed, we usually want (v_other - v_ego).
            # But line 116 in old code: `push!(agents_rel_vel, vel[i, :])`. It passed ABSOLUTE velocity of neighbor.
            # Does `spm.jl` subtract ego velocity? No.
            # So it used absolute velocity of neighbor.
            # If `v_rel` is neighbor's velocity, `dot(p_rel, v_rel)` is closing speed ONLY IF ego is static.
            # This might be a bug or intended simplification in previous versions.
            # However, for TTC, we need relative velocity (v_other - v_ego) or projection.
            # For now, I will stick to what was there (passing neighbor's velocity) BUT rotated.
            # Or should I pass `vel[i, :] - vel[agent_idx, :]`?
            # Given "v7.2" is a major update, maybe I should fix this to be proper relative velocity?
            # But if I change it, I might break consistency with how `spm.jl` was tuned.
            # Let's check `spm.jl` again. 
            # `radial_vel = -dot(p_rel, v_rel)`. This assumes v_rel is the velocity vector.
            # If ego moves towards neighbor, collision risk should increase.
            # If I only pass neighbor velocity, ego motion is ignored in TTC.
            # This seems like a limitation. 
            # I will preserve the previous behavior (passing neighbor velocity) to avoid changing SPM logic implicitly,
            # BUT I must rotate it to ego frame.
            
            # Update: Actually, let's rotate absolute velocity of neighbor into ego frame.
            v_global = vel[i, :]
            
            # Apply rotation
            rel_pos_ego = rotate_vec(rel_pos_global)
            rel_vel_ego = rotate_vec(v_global) # Still absolute velocity, just rotated.

            push!(agents_rel_pos, rel_pos_ego)
            push!(agents_rel_vel, rel_vel_ego)
        end
    end

    # Add obstacles
    # obstacles is [M, 4] matrix: x_min, x_max, y_min, y_max
    # We treat them as rectangular obstacles.
    # To represent them in SPM (which expects points), we calculate the 
    # CLOSEST point on the obstacle to the agent (simulating LiDAR return).
    
    n_obs = size(obstacles, 1)
    # Check if obstacles is [M, 2] or [M, 4]
    # Previous data might be [M, 2] (points). New data is [M, 4].
    is_rect = size(obstacles, 2) == 4
    
    for i in 1:n_obs
        if is_rect
            x_min, x_max, y_min, y_max = obstacles[i, :]
            
            # Find closest point on rectangle to agent (AABB distance)
            # Clamp agent pos to rectangle bounds
            c_x = clamp(agent_pos[1], x_min, x_max)
            c_y = clamp(agent_pos[2], y_min, y_max)
            
            # If agent is inside, closest point is agent pos (dist 0), or push to boundary?
            # Usually keep as is (dist 0).
            # But we want relative vector.
            # Convert to relative
            
            # Note: This single point approximation basically says "the obstacle is at this distance".
            # For a large wall, this is decent for "distance to wall".
            # But it doesn't cover the field of view (it occupies only 1 angle).
            # Walls should occupy multiple angles.
            # Ideally we should sample points. 
            # But calculating closest point is a good start for "nearest obstacle".
            
            # BETTER APPROACH for Walls: Sample multiple points along the perimeter?
            # Or just corners?
            # For data collection/training, maybe just the closest point is sufficient for safety?
            # Let's stick to Closest Point for now to avoid exploding point count.
            
            obs_pos = [c_x, c_y]
        else
            # Point obstacle
            obs_pos = [obstacles[i, 1], obstacles[i, 2]]
        end
        
        rel_pos_global = obs_pos - agent_pos
        rel_pos_ego = rotate_vec(rel_pos_global)
        
        push!(agents_rel_pos, rel_pos_ego)
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
    heading = data.heading # [T, N] (v7.2: Required)
    obstacles = data.obstacles  # [M, 4]

    # Create SPM config from stored parameters
    spm_params = Main.Config.SPMParams(
        data.spm_params["n_rho"],          # n_rho
        data.spm_params["n_theta"],        # n_theta
        360.0,                              # fov_deg
        2π,                                 # fov_rad
        0.4,                                # r_robot
        data.spm_params["sensing_ratio"],  # sensing_ratio
        0.5,                                # sigma_spm
        5.0,                                # beta_r_fixed
        5.0,                                # beta_nu_fixed
        1.0,                                # beta_r_min
        10.0,                               # beta_r_max
        1.0,                                # beta_nu_min
        10.0                                # beta_nu_max
    )

    spm_config = Main.SPM.init_spm(spm_params)

    r_agent = 0.3

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
                heading[t, :], # Pass all headings
                obstacles,
                agent_idx,
                spm_config,
                r_agent
            )

            # Reconstruct SPM at time t+1
            spm_t1 = reconstruct_spm_at_timestep(
                pos[t+1, :, :],
                vel[t+1, :, :],
                heading[t+1, :], # Pass all headings
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
    # Create regex from glob pattern
    regex_str = replace(pattern, "." => "\\.", "*" => ".*")
    regex = Regex(regex_str * "\$")
    files = filter(f -> occursin(regex, f), readdir(directory, join=true))

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
    # Create regex from glob pattern
    regex_str = replace(pattern, "." => "\\.", "*" => ".*")
    regex = Regex(regex_str * "\$")
    files = filter(f -> occursin(regex, f), readdir(directory, join=true))

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
