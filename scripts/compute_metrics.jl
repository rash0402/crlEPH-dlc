#!/usr/bin/env julia
"""
Evaluation Metrics Computation Script
Computes comprehensive evaluation metrics from simulation logs for EPH validation.

Metrics (EPH Proposal 4.2):
1. Success Rate: Percentage of agents reaching goal
2. Collision Rate: Percentage of collision events
3. Freezing Rate: Percentage of time spent freezing
4. Jerk: Motion smoothness indicator
5. Minimum TTC: Closest time-to-collision

Usage:
    julia --project=. scripts/compute_metrics.jl <log_file.h5>
"""

using HDF5
using Statistics
using Printf
using Dates
using LinearAlgebra: norm
using JSON

# Load freezing detection module
include("detect_freezing.jl")

# ===== Configuration =====
struct MetricsConfig
    # Goal reaching threshold
    goal_threshold::Float64      # Distance to goal (m)
    
    # Collision detection
    collision_threshold::Float64  # Agent-agent distance (m)
    
    # TTC parameters
    ttc_horizon::Float64         # Maximum TTC to consider (s)
    
    # Freezing parameters (from detect_freezing.jl)
    freezing_threshold::Float64
    freezing_window::Float64
    
    # Simulation parameters
    dt::Float64                  # Timestep (s)
    world_width::Float64
    world_height::Float64
    
    function MetricsConfig(;
        goal_threshold=2.0,
        collision_threshold=3.0,  # 2 * r_agent
        ttc_horizon=5.0,
        freezing_threshold=0.1,
        freezing_window=2.0,
        dt=0.033,
        world_width=100.0,
        world_height=100.0
    )
        new(goal_threshold, collision_threshold, ttc_horizon,
            freezing_threshold, freezing_window, dt, world_width, world_height)
    end
end

# ===== Data Structures =====
struct EvaluationMetrics
    # Performance metrics
    success_rate::Float64        # Percentage
    collision_rate::Float64      # Percentage
    
    # Motion quality metrics
    freezing_rate::Float64       # Percentage
    avg_jerk::Float64           # m/s³
    min_ttc::Float64            # seconds
    
    # Raw counts
    num_agents::Int
    num_successes::Int
    num_collisions::Int
    num_freezing_events::Int
    
    # Simulation info
    total_steps::Int
    total_time::Float64
end

# ===== Metric Calculations =====

"""
Check if agent reached goal within threshold.
"""
function check_goal_reached(
    final_position::Vector{Float64},
    goal_position::Vector{Float64},
    threshold::Float64
)
    distance = norm(final_position - goal_position)
    return distance <= threshold
end

"""
Detect collision events from position history.
Returns number of collision timesteps.
"""
function detect_collisions(
    positions::Array{Float64, 3},  # (2, n_agents, n_steps)
    threshold::Float64,
    world_width::Float64,
    world_height::Float64
)
    n_agents = size(positions, 2)
    n_steps = size(positions, 3)
    collision_count = 0
    
    for step in 1:n_steps
        for i in 1:n_agents
            for j in (i+1):n_agents
                pos_i = positions[:, i, step]
                pos_j = positions[:, j, step]
                
                # Compute distance with torus wrapping
                dx = pos_j[1] - pos_i[1]
                dy = pos_j[2] - pos_i[2]
                
                # Torus shortest path
                if abs(dx) > world_width / 2
                    dx = dx - sign(dx) * world_width
                end
                if abs(dy) > world_height / 2
                    dy = dy - sign(dy) * world_height
                end
                
                dist = sqrt(dx^2 + dy^2)
                
                if dist < threshold
                    collision_count += 1
                    break  # Count once per timestep
                end
            end
        end
    end
    
    return collision_count
end

"""
Compute Jerk (rate of change of acceleration) for motion smoothness.
Lower jerk = smoother motion.
"""
function compute_jerk(
    velocities::Matrix{Float64},  # (2, n_steps)
    dt::Float64
)
    n_steps = size(velocities, 2)
    
    if n_steps < 3
        return 0.0
    end
    
    # Compute accelerations
    accelerations = zeros(2, n_steps - 1)
    for i in 1:(n_steps - 1)
        accelerations[:, i] = (velocities[:, i+1] - velocities[:, i]) / dt
    end
    
    # Compute jerk (derivative of acceleration)
    jerks = Float64[]
    for i in 1:(size(accelerations, 2) - 1)
        jerk = (accelerations[:, i+1] - accelerations[:, i]) / dt
        push!(jerks, norm(jerk))
    end
    
    return mean(jerks)
end

"""
Compute minimum Time-To-Collision (TTC) across all agent pairs.
"""
function compute_min_ttc(
    positions::Array{Float64, 3},   # (2, n_agents, n_steps)
    velocities::Array{Float64, 3},  # (2, n_agents, n_steps)
    world_width::Float64,
    world_height::Float64,
    ttc_horizon::Float64
)
    n_agents = size(positions, 2)
    n_steps = size(positions, 3)
    min_ttc = Inf
    
    for step in 1:n_steps
        for i in 1:n_agents
            for j in (i+1):n_agents
                pos_i = positions[:, i, step]
                pos_j = positions[:, j, step]
                vel_i = velocities[:, i, step]
                vel_j = velocities[:, j, step]
                
                # Relative position and velocity
                dx = pos_j[1] - pos_i[1]
                dy = pos_j[2] - pos_i[2]
                
                # Torus wrapping
                if abs(dx) > world_width / 2
                    dx = dx - sign(dx) * world_width
                end
                if abs(dy) > world_height / 2
                    dy = dy - sign(dy) * world_height
                end
                
                rel_pos = [dx, dy]
                rel_vel = vel_j - vel_i
                
                # TTC calculation
                # TTC = -dot(rel_pos, rel_vel) / ||rel_vel||^2
                dot_product = dot(rel_pos, rel_vel)
                
                if dot_product < 0  # Approaching
                    vel_squared = dot(rel_vel, rel_vel)
                    if vel_squared > 1e-6
                        ttc = -dot_product / vel_squared
                        if ttc > 0 && ttc < ttc_horizon
                            min_ttc = min(min_ttc, ttc)
                        end
                    end
                end
            end
        end
    end
    
    return min_ttc == Inf ? ttc_horizon : min_ttc
end

# ===== Main Analysis =====

"""
Load all necessary data from HDF5 log.
"""
function load_full_simulation_data(filename::String)
    h5open(filename, "r") do file
        positions = Float64.(read(file, "data/position"))    # (2, n_steps)
        velocities = Float64.(read(file, "data/velocity"))   # (2, n_steps)
        
        # For single-agent logs, reshape to (2, 1, n_steps)
        if ndims(positions) == 2
            n_steps = size(positions, 2)
            positions = reshape(positions, 2, 1, n_steps)
            velocities = reshape(velocities, 2, 1, n_steps)
        end
        
        return positions, velocities
    end
end

"""
Compute all evaluation metrics from simulation log.
"""
function compute_all_metrics(
    log_file::String,
    config::MetricsConfig
)
    println("📂 Loading simulation data from: $log_file")
    
    # Load data
    positions, velocities = load_full_simulation_data(log_file)
    n_agents = size(positions, 2)
    n_steps = size(positions, 3)
    total_time = n_steps * config.dt
    
    println("✅ Loaded data: $n_agents agents, $n_steps steps")
    
    # 1. Success Rate (simplified: assume goal is center)
    println("\n📊 Computing Success Rate...")
    goal_center = [config.world_width / 2, config.world_height / 2]
    num_successes = 0
    for i in 1:n_agents
        final_pos = positions[:, i, end]
        if check_goal_reached(final_pos, goal_center, config.goal_threshold)
            num_successes += 1
        end
    end
    success_rate = (num_successes / n_agents) * 100.0
    
    # 2. Collision Rate
    println("📊 Computing Collision Rate...")
    num_collisions = detect_collisions(
        positions, config.collision_threshold,
        config.world_width, config.world_height
    )
    collision_rate = (num_collisions / n_steps) * 100.0
    
    # 3. Freezing Rate (use first agent for now)
    println("📊 Computing Freezing Rate...")
    vel_magnitudes = [norm(velocities[:, 1, i]) for i in 1:n_steps]
    pos_agent1 = positions[:, 1, :]
    
    freezing_params = FreezingParams(
        velocity_threshold=config.freezing_threshold,
        time_window=config.freezing_window,
        dt=config.dt
    )
    
    freezing_events = detect_freezing_events(
        vel_magnitudes, pos_agent1, freezing_params
    )
    
    freezing_analysis = analyze_freezing(freezing_events, n_steps, config.dt)
    freezing_rate = freezing_analysis.freezing_rate
    num_freezing_events = freezing_analysis.num_events
    
    # 4. Average Jerk
    println("📊 Computing Jerk...")
    jerks = Float64[]
    for i in 1:n_agents
        jerk = compute_jerk(velocities[:, i, :], config.dt)
        push!(jerks, jerk)
    end
    avg_jerk = mean(jerks)
    
    # 5. Minimum TTC
    println("📊 Computing Minimum TTC...")
    min_ttc = compute_min_ttc(
        positions, velocities,
        config.world_width, config.world_height,
        config.ttc_horizon
    )
    
    return EvaluationMetrics(
        success_rate,
        collision_rate,
        freezing_rate,
        avg_jerk,
        min_ttc,
        n_agents,
        num_successes,
        num_collisions,
        num_freezing_events,
        n_steps,
        total_time
    )
end

"""
Print metrics report to console.
"""
function print_metrics_report(metrics::EvaluationMetrics)
    println("\n" * "=" ^ 60)
    println("📊 EVALUATION METRICS REPORT")
    println("=" ^ 60)
    
    println("\n🎯 Performance Metrics:")
    @printf("  Success Rate:    %.2f%% (%d/%d agents)\n",
            metrics.success_rate, metrics.num_successes, metrics.num_agents)
    @printf("  Collision Rate:  %.2f%% (%d events)\n",
            metrics.collision_rate, metrics.num_collisions)
    
    println("\n🚦 Motion Quality Metrics:")
    @printf("  Freezing Rate:   %.2f%% (%d events)\n",
            metrics.freezing_rate, metrics.num_freezing_events)
    @printf("  Average Jerk:    %.4f m/s³\n", metrics.avg_jerk)
    @printf("  Minimum TTC:     %.2f s\n", metrics.min_ttc)
    
    println("\n📈 Simulation Summary:")
    @printf("  Total Steps:     %d\n", metrics.total_steps)
    @printf("  Total Time:      %.2f s\n", metrics.total_time)
    @printf("  Num Agents:      %d\n", metrics.num_agents)
    
    println("\n" * "=" ^ 60)
end

"""
Save metrics to JSON file.
"""
function save_metrics_json(metrics::EvaluationMetrics, output_file::String)
    data = Dict(
        "performance" => Dict(
            "success_rate" => metrics.success_rate,
            "collision_rate" => metrics.collision_rate,
            "num_successes" => metrics.num_successes,
            "num_collisions" => metrics.num_collisions
        ),
        "motion_quality" => Dict(
            "freezing_rate" => metrics.freezing_rate,
            "avg_jerk" => metrics.avg_jerk,
            "min_ttc" => metrics.min_ttc,
            "num_freezing_events" => metrics.num_freezing_events
        ),
        "simulation" => Dict(
            "total_steps" => metrics.total_steps,
            "total_time" => metrics.total_time,
            "num_agents" => metrics.num_agents
        )
    )
    
    open(output_file, "w") do io
        JSON.print(io, data, 2)
    end
    
    println("\n💾 Metrics saved to: $output_file")
end

# ===== Main Entry Point =====
function main(args::Vector{String})
    if length(args) < 1
        println("Usage: julia --project=. scripts/compute_metrics.jl <log_file.h5> [output.json]")
        return
    end
    
    log_file = args[1]
    output_file = length(args) >= 2 ? args[2] : nothing
    
    # Initialize configuration
    config = MetricsConfig()
    
    # Compute metrics
    metrics = compute_all_metrics(log_file, config)
    
    # Print report
    print_metrics_report(metrics)
    
    # Save to JSON if requested
    if output_file !== nothing
        save_metrics_json(metrics, output_file)
    end
    
    return metrics
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
