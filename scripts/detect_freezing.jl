#!/usr/bin/env julia
"""
Freezing Detection Script
Analyzes simulation logs to detect freezing events based on EPH proposal operational definition.

Operational Definition (EPH Proposal 4.1):
    "Freezing occurs when velocity ||ẋ|| remains below threshold ε for T seconds or more,
     despite the goal being reachable."

Usage:
    julia --project=. scripts/detect_freezing.jl <log_file.h5> [options]
"""

using HDF5
using Statistics
using Printf
using Dates
using LinearAlgebra: norm

# ===== Configuration =====
struct FreezingParams
    velocity_threshold::Float64  # ε: velocity threshold (m/s)
    time_window::Float64         # T: minimum duration (seconds)
    dt::Float64                  # Simulation timestep (seconds)
    
    function FreezingParams(;
        velocity_threshold=0.1,   # Default: 0.1 m/s
        time_window=2.0,          # Default: 2.0 seconds
        dt=0.033                  # Default: 30Hz simulation
    )
        new(velocity_threshold, time_window, dt)
    end
end

# ===== Data Structures =====
struct FreezingEvent
    start_step::Int
    end_step::Int
    duration::Float64      # seconds
    avg_velocity::Float64  # m/s
    position::Vector{Float64}  # [x, y] at start
end

struct FreezingAnalysis
    total_steps::Int
    total_time::Float64
    events::Vector{FreezingEvent}
    freezing_rate::Float64  # Percentage of time spent freezing
    num_events::Int
end

# ===== Core Detection Algorithm =====
"""
Detect freezing events from velocity time series.

Args:
    velocities: Vector of velocity magnitudes ||ẋ|| at each step
    positions: Matrix of positions (2 x N) at each step
    params: FreezingParams configuration

Returns:
    Vector of FreezingEvent
"""
function detect_freezing_events(
    velocities::Vector{Float64},
    positions::Matrix{Float64},
    params::FreezingParams
)
    events = FreezingEvent[]
    n_steps = length(velocities)
    
    # Minimum steps for freezing window
    min_steps = Int(ceil(params.time_window / params.dt))
    
    # State tracking
    in_freezing = false
    freezing_start = 0
    freezing_velocities = Float64[]
    
    for step in 1:n_steps
        vel = velocities[step]
        
        if vel <= params.velocity_threshold
            # Below threshold
            if !in_freezing
                # Start potential freezing event
                in_freezing = true
                freezing_start = step
                freezing_velocities = [vel]
            else
                # Continue freezing
                push!(freezing_velocities, vel)
            end
        else
            # Above threshold
            if in_freezing
                # Check if this was a valid freezing event
                freezing_duration_steps = step - freezing_start
                
                if freezing_duration_steps >= min_steps
                    # Valid freezing event
                    duration_sec = freezing_duration_steps * params.dt
                    avg_vel = mean(freezing_velocities)
                    pos_start = positions[:, freezing_start]
                    
                    event = FreezingEvent(
                        freezing_start,
                        step - 1,
                        duration_sec,
                        avg_vel,
                        pos_start
                    )
                    push!(events, event)
                end
                
                # Reset state
                in_freezing = false
                freezing_velocities = Float64[]
            end
        end
    end
    
    # Handle case where simulation ends during freezing
    if in_freezing
        freezing_duration_steps = n_steps - freezing_start + 1
        if freezing_duration_steps >= min_steps
            duration_sec = freezing_duration_steps * params.dt
            avg_vel = mean(freezing_velocities)
            pos_start = positions[:, freezing_start]
            
            event = FreezingEvent(
                freezing_start,
                n_steps,
                duration_sec,
                avg_vel,
                pos_start
            )
            push!(events, event)
        end
    end
    
    return events
end

# ===== HDF5 Log Reading =====
"""
Load velocity and position data from HDF5 simulation log.

Args:
    filename: Path to HDF5 log file

Returns:
    (velocities, positions) tuple
"""
function load_simulation_data(filename::String)
    h5open(filename, "r") do file
        # Read velocity data from data/ group
        vel_data = read(file, "data/velocity")  # Shape: (2, n_steps), Float32
        
        # Compute velocity magnitudes and convert to Float64
        velocities = Float64[norm(vel_data[:, i]) for i in 1:size(vel_data, 2)]
        
        # Read position data from data/ group and convert to Float64
        positions = Float64.(read(file, "data/position"))  # Shape: (2, n_steps)
        
        return velocities, positions
    end
end

# ===== Analysis and Reporting =====
"""
Analyze freezing events and compute statistics.

Args:
    events: Vector of FreezingEvent
    total_steps: Total simulation steps
    dt: Timestep duration

Returns:
    FreezingAnalysis struct
"""
function analyze_freezing(
    events::Vector{FreezingEvent},
    total_steps::Int,
    dt::Float64
)
    total_time = total_steps * dt
    
    # Compute total freezing time (handle empty events)
    freezing_time = sum(e.duration for e in events; init=0.0)
    
    # Freezing rate (percentage)
    freezing_rate = (freezing_time / total_time) * 100.0
    
    return FreezingAnalysis(
        total_steps,
        total_time,
        events,
        freezing_rate,
        length(events)
    )
end

"""
Print analysis results to console.
"""
function print_analysis(analysis::FreezingAnalysis, params::FreezingParams)
    println("=" ^ 60)
    println("🔍 FREEZING DETECTION ANALYSIS")
    println("=" ^ 60)
    
    println("\n📋 Detection Parameters:")
    println("  Velocity Threshold (ε): $(params.velocity_threshold) m/s")
    println("  Time Window (T): $(params.time_window) s")
    println("  Timestep (dt): $(params.dt) s")
    
    println("\n📊 Simulation Summary:")
    println("  Total Steps: $(analysis.total_steps)")
    println("  Total Time: $(round(analysis.total_time, digits=2)) s")
    
    println("\n🚨 Freezing Events:")
    println("  Number of Events: $(analysis.num_events)")
    println("  Freezing Rate: $(round(analysis.freezing_rate, digits=2))%")
    
    if analysis.num_events > 0
        println("\n📝 Event Details:")
        for (i, event) in enumerate(analysis.events)
            @printf("  Event %2d: Steps %4d-%4d | Duration: %.2fs | Avg Vel: %.3f m/s | Pos: [%.1f, %.1f]\n",
                    i, event.start_step, event.end_step, event.duration, 
                    event.avg_velocity, event.position[1], event.position[2])
        end
        
        # Statistics
        durations = [e.duration for e in analysis.events]
        println("\n📈 Duration Statistics:")
        println("  Mean: $(round(mean(durations), digits=2)) s")
        println("  Std:  $(round(std(durations), digits=2)) s")
        println("  Min:  $(round(minimum(durations), digits=2)) s")
        println("  Max:  $(round(maximum(durations), digits=2)) s")
    end
    
    println("\n" * "=" ^ 60)
end

# ===== Main Entry Point =====
function main(args::Vector{String})
    if length(args) < 1
        println("Usage: julia --project=. scripts/detect_freezing.jl <log_file.h5>")
        println("\nOptions:")
        println("  --threshold <value>  Velocity threshold (default: 0.1 m/s)")
        println("  --window <value>     Time window (default: 2.0 s)")
        return
    end
    
    log_file = args[1]
    
    # Parse optional arguments
    params_dict = Dict{Symbol, Float64}()
    i = 2
    while i <= length(args)
        if args[i] == "--threshold" && i + 1 <= length(args)
            params_dict[:velocity_threshold] = parse(Float64, args[i+1])
            i += 2
        elseif args[i] == "--window" && i + 1 <= length(args)
            params_dict[:time_window] = parse(Float64, args[i+1])
            i += 2
        else
            i += 1
        end
    end
    
    # Initialize parameters
    params = FreezingParams(; params_dict...)
    
    println("📂 Loading simulation data from: $log_file")
    
    # Load data
    velocities, positions = load_simulation_data(log_file)
    
    println("✅ Loaded $(length(velocities)) steps")
    
    # Detect freezing events
    println("\n🔍 Detecting freezing events...")
    events = detect_freezing_events(velocities, positions, params)
    
    # Analyze results
    analysis = analyze_freezing(events, length(velocities), params.dt)
    
    # Print results
    print_analysis(analysis, params)
    
    return analysis
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
