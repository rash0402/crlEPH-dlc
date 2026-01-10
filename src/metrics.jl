"""
Metrics Module for EPH v5.6
Implements evaluation metrics including Freezing Rate, Throughput, and Surprise statistics.
"""

module Metrics

using LinearAlgebra
using Statistics
using HDF5

export FreezeDetector, detect_freezing, compute_freezing_rate
export compute_success_rate, compute_collision_rate, compute_collision_count
export compute_jerk, compute_min_ttc, compute_throughput
export compute_path_efficiency, compute_surprise_statistics
export EpisodeMetrics, compute_episode_metrics
export load_simulation_results, SimulationResults

"""
Freezing detector configuration
"""
struct FreezeDetector
    velocity_threshold::Float64  # Minimum velocity to consider as moving (m/s)
    duration_threshold::Float64  # Minimum duration to consider as freezing (s)
    dt::Float64                  # Time step (s)
    
    function FreezeDetector(;
        velocity_threshold::Float64=0.1,
        duration_threshold::Float64=2.0,
        dt::Float64=0.033
    )
        new(velocity_threshold, duration_threshold, dt)
    end
end

"""
Detect freezing events in a velocity trajectory.
Returns: (is_frozen::Bool, freeze_duration::Float64, freeze_events::Vector{Tuple{Int, Int}})
"""
function detect_freezing(
    velocities::Vector{Vector{Float64}},
    detector::FreezeDetector
)
    n_steps = length(velocities)
    min_freeze_steps = Int(ceil(detector.duration_threshold / detector.dt))
    
    # Track low-velocity periods
    low_velocity_count = 0
    freeze_events = Tuple{Int, Int}[]
    freeze_start = 0
    
    for (i, vel) in enumerate(velocities)
        speed = norm(vel)
        
        if speed < detector.velocity_threshold
            if low_velocity_count == 0
                freeze_start = i
            end
            low_velocity_count += 1
        else
            # Check if previous low-velocity period was long enough
            if low_velocity_count >= min_freeze_steps
                push!(freeze_events, (freeze_start, i-1))
            end
            low_velocity_count = 0
        end
    end
    
    # Check final period
    if low_velocity_count >= min_freeze_steps
        push!(freeze_events, (freeze_start, n_steps))
    end
    
    # Calculate total freeze duration
    total_freeze_duration = isempty(freeze_events) ? 0.0 : sum(
        (stop - start + 1) * detector.dt 
        for (start, stop) in freeze_events
    )
    
    is_frozen = !isempty(freeze_events)
    
    return (
        is_frozen=is_frozen,
        freeze_duration=total_freeze_duration,
        freeze_events=freeze_events
    )
end

"""
Compute freezing rate across multiple episodes.
Returns: (freezing_rate::Float64, mean_freeze_duration::Float64)
"""
function compute_freezing_rate(
    episode_velocities::Vector{Vector{Vector{Float64}}},
    detector::FreezeDetector=FreezeDetector()
)
    n_episodes = length(episode_velocities)
    frozen_count = 0
    total_freeze_duration = 0.0
    freeze_durations = Float64[]
    
    for velocities in episode_velocities
        result = detect_freezing(velocities, detector)
        if result.is_frozen
            frozen_count += 1
            total_freeze_duration += result.freeze_duration
            push!(freeze_durations, result.freeze_duration)
        end
    end
    
    freezing_rate = frozen_count / n_episodes
    mean_freeze_duration = frozen_count > 0 ? mean(freeze_durations) : 0.0
    
    return (
        freezing_rate=freezing_rate,
        mean_freeze_duration=mean_freeze_duration,
        n_frozen=frozen_count,
        n_total=n_episodes
    )
end

"""
Compute success rate (goal reached within threshold).
"""
function compute_success_rate(
    final_positions::Vector{Vector{Float64}},
    goal_positions::Vector{Vector{Float64}};
    threshold::Float64=1.0
)
    n_episodes = length(final_positions)
    success_count = sum(
        norm(final_positions[i] - goal_positions[i]) < threshold
        for i in 1:n_episodes
    )
    return success_count / n_episodes
end

"""
Compute collision rate.
"""
function compute_collision_rate(
    collision_flags::Vector{Bool}
)
    return sum(collision_flags) / length(collision_flags)
end

"""
Compute jerk (rate of change of acceleration) over trajectory.
"""
function compute_jerk(
    accelerations::Vector{Vector{Float64}},
    dt::Float64=0.033
)
    if length(accelerations) < 2
        return 0.0
    end
    
    jerks = Float64[]
    for i in 2:length(accelerations)
        jerk = norm(accelerations[i] - accelerations[i-1]) / dt
        push!(jerks, jerk)
    end
    
    return mean(jerks)
end

"""
Compute throughput for corridor scenario.
Throughput = number of agents that cross a vertical line (e.g., corridor center) per unit time.

Args:
    positions: Vector of position trajectories for each agent [Vector{Vector{Float64}}]
    crossing_x: X-coordinate of the crossing line (default: center at 50.0)
    direction: Expected crossing direction - :east (left→right) or :west (right→left) or :both
    dt: Time step in seconds

Returns:
    (n_crossings, throughput_per_second, crossing_times)
"""
function compute_throughput(
    positions::Vector{Vector{Vector{Float64}}};
    crossing_x::Float64=50.0,
    direction::Symbol=:both,
    dt::Float64=0.033
)
    total_crossings = 0
    crossing_times = Float64[]
    
    for agent_positions in positions
        for t in 2:length(agent_positions)
            prev_x = agent_positions[t-1][1]
            curr_x = agent_positions[t][1]
            
            crossed = false
            
            if direction == :east
                # Left to right crossing
                if prev_x < crossing_x && curr_x >= crossing_x
                    crossed = true
                end
            elseif direction == :west
                # Right to left crossing
                if prev_x > crossing_x && curr_x <= crossing_x
                    crossed = true
                end
            else  # :both
                if (prev_x < crossing_x && curr_x >= crossing_x) ||
                   (prev_x > crossing_x && curr_x <= crossing_x)
                    crossed = true
                end
            end
            
            if crossed
                total_crossings += 1
                push!(crossing_times, t * dt)
            end
        end
    end
    
    # Compute total simulation time
    if isempty(positions) || isempty(positions[1])
        return (n_crossings=0, throughput_per_second=0.0, crossing_times=Float64[])
    end
    
    total_time = length(positions[1]) * dt
    throughput_per_second = total_crossings / total_time
    
    return (
        n_crossings=total_crossings,
        throughput_per_second=throughput_per_second,
        crossing_times=crossing_times
    )
end

"""
Compute minimum Time-to-Collision (TTC) during episode.
"""
function compute_min_ttc(
    agent_positions::Vector{Vector{Float64}},
    agent_velocities::Vector{Vector{Float64}},
    other_agents_positions::Vector{Vector{Vector{Float64}}},
    other_agents_velocities::Vector{Vector{Vector{Float64}}};
    safety_radius::Float64=0.5
)
    min_ttc = Inf
    
    for t in 1:length(agent_positions)
        pos = agent_positions[t]
        vel = agent_velocities[t]
        
        for other_pos in other_agents_positions[t]
            for other_vel in other_agents_velocities[t]
                # Relative position and velocity
                rel_pos = other_pos - pos
                rel_vel = other_vel - vel
                
                # Check if approaching
                if dot(rel_pos, rel_vel) < 0
                    # Time to closest approach
                    dist = norm(rel_pos)
                    rel_speed = norm(rel_vel)
                    
                    if rel_speed > 1e-6
                        ttc = (dist - 2 * safety_radius) / rel_speed
                        if ttc > 0
                            min_ttc = min(min_ttc, ttc)
                        end
                    end
                end
            end
        end
    end
    
    return min_ttc
end

"""
Container for episode metrics
"""
struct EpisodeMetrics
    freezing_rate::Float64
    mean_freeze_duration::Float64
    success_rate::Float64
    collision_rate::Float64
    mean_jerk::Float64
    min_ttc::Float64
    
    # Additional statistics
    n_episodes::Int
    n_frozen::Int
end

"""
Compute all metrics for a set of episodes.
"""
function compute_episode_metrics(
    episode_data::Vector{Dict{String, Any}};
    freeze_detector::FreezeDetector=FreezeDetector(),
    goal_threshold::Float64=1.0,
    safety_radius::Float64=0.5
)
    n_episodes = length(episode_data)
    
    # Extract data
    velocities = [ep["velocities"] for ep in episode_data]
    accelerations = [ep["accelerations"] for ep in episode_data]
    final_positions = [ep["positions"][end] for ep in episode_data]
    goal_positions = [ep["goal"] for ep in episode_data]
    collision_flags = [ep["collision"] for ep in episode_data]
    
    # Compute metrics
    freeze_result = compute_freezing_rate(velocities, freeze_detector)
    success_rate = compute_success_rate(final_positions, goal_positions, threshold=goal_threshold)
    collision_rate = compute_collision_rate(collision_flags)
    
    # Compute jerk for each episode
    jerks = [compute_jerk(acc) for acc in accelerations]
    mean_jerk = mean(jerks)
    
    # Compute min TTC (if data available)
    min_ttc = Inf
    if haskey(episode_data[1], "other_positions")
        ttcs = [
            compute_min_ttc(
                ep["positions"],
                ep["velocities"],
                ep["other_positions"],
                ep["other_velocities"],
                safety_radius=safety_radius
            )
            for ep in episode_data
        ]
        min_ttc = minimum(ttcs)
    end
    
    return EpisodeMetrics(
        freeze_result.freezing_rate,
        freeze_result.mean_freeze_duration,
        success_rate,
        collision_rate,
        mean_jerk,
        min_ttc,
        n_episodes,
        freeze_result.n_frozen
    )
end

"""
Compute collision count (total number of collision events).
"""
function compute_collision_count(
    positions::Vector{Vector{Vector{Float64}}};
    collision_radius::Float64=0.5
)
    n_agents = length(positions)
    n_steps = length(positions[1])
    collision_count = 0

    for t in 1:n_steps
        for i in 1:n_agents
            for j in (i+1):n_agents
                dist = norm(positions[i][t] - positions[j][t])
                if dist < 2 * collision_radius
                    collision_count += 1
                end
            end
        end
    end

    return collision_count
end

"""
Compute path efficiency (actual path length / straight-line distance to goal).
Lower values indicate more efficient paths.
"""
function compute_path_efficiency(
    positions::Vector{Vector{Float64}},
    goal::Vector{Float64}
)
    if length(positions) < 2
        return 1.0
    end

    # Compute actual path length
    actual_length = 0.0
    for i in 2:length(positions)
        actual_length += norm(positions[i] - positions[i-1])
    end

    # Compute straight-line distance
    straight_line_distance = norm(positions[1] - goal)

    if straight_line_distance < 1e-6
        return 1.0
    end

    efficiency = actual_length / straight_line_distance

    return efficiency
end

"""
Compute Surprise statistics for EPH evaluation.

Returns:
    - mean_surprise: Average Surprise across all agents and timesteps
    - max_surprise: Maximum Surprise observed
    - std_surprise: Standard deviation of Surprise
    - surprise_timeline: Mean Surprise at each timestep
"""
function compute_surprise_statistics(
    surprises::Array{Float64, 2}  # (n_steps, n_agents)
)
    # Flatten for overall statistics
    all_surprises = vec(surprises)

    mean_surprise = mean(all_surprises)
    max_surprise = maximum(all_surprises)
    std_surprise = std(all_surprises)

    # Compute mean Surprise at each timestep
    surprise_timeline = vec(mean(surprises, dims=2))

    return (
        mean_surprise=mean_surprise,
        max_surprise=max_surprise,
        std_surprise=std_surprise,
        surprise_timeline=surprise_timeline
    )
end

"""
Container for simulation results loaded from HDF5.
"""
struct SimulationResults
    positions::Array{Float64, 3}      # (n_steps, n_agents, 2)
    velocities::Array{Float64, 3}     # (n_steps, n_agents, 2)
    spms::Array{Float32, 5}           # (n_steps, n_agents, 16, 16, 3)
    actions::Array{Float64, 3}        # (n_steps, n_agents, 2)
    surprises::Array{Float64, 2}      # (n_steps, n_agents)
    metadata::Dict{String, Any}
end

"""
Load simulation results from HDF5 file.

Handles dimension order mismatch between logger storage and expected format:
- Logger stores: (features, agents, time)
- Expected format: (time, agents, features)
"""
function load_simulation_results(filepath::String)
    h5open(filepath, "r") do file
        # Read data (stored as: features × agents × time)
        pos_raw = read(file, "data/position")      # (2, n_agents, n_steps)
        vel_raw = read(file, "data/velocity")      # (2, n_agents, n_steps)
        act_raw = read(file, "data/action")        # (2, n_agents, n_steps)
        haze_raw = read(file, "data/haze")         # (n_agents, n_steps)
        prec_raw = read(file, "data/precision")    # (n_agents, n_steps)

        # Permute dimensions to: (time, agents, features)
        positions = permutedims(pos_raw, (3, 2, 1))    # → (n_steps, n_agents, 2)
        velocities = permutedims(vel_raw, (3, 2, 1))   # → (n_steps, n_agents, 2)
        actions = permutedims(act_raw, (3, 2, 1))      # → (n_steps, n_agents, 2)

        # Haze/Precision: (agents, time) → (time, agents)
        hazes = permutedims(haze_raw, (2, 1))          # → (n_steps, n_agents)
        precisions = permutedims(prec_raw, (2, 1))     # → (n_steps, n_agents)

        # SPMs: Check if exists (may not be logged in all simulations)
        if exists(file, "data/spms")
            spms_raw = read(file, "data/spms")
            # Assuming spms stored as: (16, 16, 3, agents, time)
            spms = permutedims(spms_raw, (5, 4, 1, 2, 3))  # → (time, agents, 16, 16, 3)
        else
            # Create empty array if not available
            n_steps, n_agents = size(hazes)
            spms = zeros(Float32, n_steps, n_agents, 16, 16, 3)
        end

        # Surprises: use hazes as placeholder if not available
        # (In v5.6.1, Surprise should be computed from VAE at runtime)
        surprises = hazes  # Temporary: use haze values

        # Load metadata
        metadata = Dict{String, Any}()
        if exists(file, "metadata") || haskey(attrs(file), "actual_steps")
            for attr_name in keys(attrs(file))
                metadata[attr_name] = read(attrs(file)[attr_name])
            end
        end

        return SimulationResults(
            positions,
            velocities,
            spms,
            actions,
            surprises,
            metadata
        )
    end
end

end # module
