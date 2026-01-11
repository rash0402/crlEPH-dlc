#!/usr/bin/env julia

"""
Phase 5: Results Analysis Script
Analyzes Haze comparison experiment results and generates comprehensive metrics.

Computes:
- Freezing Rate
- Success Rate
- Collision Rate
- Surprise statistics
- Path efficiency

Outputs:
- CSV summary tables
- Visualization plots
- Markdown report
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Statistics
using LinearAlgebra
using HDF5
using DataFrames
using CSV

# Load modules
include("../src/config.jl")
include("../src/metrics.jl")

using .Config
using .Metrics

"""
Load simulation data from HDF5 file
"""
function load_simulation_data(filepath::String)
    h5open(filepath, "r") do file
        positions = read(file, "positions")  # (n_steps, n_agents, 2)
        velocities = read(file, "velocities")  # (n_steps, n_agents, 2)
        spms = read(file, "spms")  # (n_steps, n_agents, 16, 16, 3)
        actions = read(file, "actions")  # (n_steps, n_agents, 2)
        surprises = read(file, "surprises")  # (n_steps, n_agents)
        agent_goals = read(file, "agent_goals")  # (n_agents, 2)

        # Metadata
        attr_dict = attrs(file)
        metadata = Dict(
            "scenario" => attr_dict["scenario"],
            "density" => attr_dict["density"],
            "steps" => attr_dict["steps"],
            "lambda_goal" => attr_dict["lambda_goal"],
            "lambda_safety" => attr_dict["lambda_safety"],
            "lambda_surprise" => attr_dict["lambda_surprise"],
            "haze_fixed" => attr_dict["haze_fixed"],
            "seed" => attr_dict["seed"]
        )

        return (
            positions=positions,
            velocities=velocities,
            spms=spms,
            actions=actions,
            surprises=surprises,
            agent_goals=agent_goals,
            metadata=metadata
        )
    end
end

"""
Compute episode-level metrics
"""
function compute_episode_metrics(data)
    positions = data.positions  # (n_steps, n_agents, 2)
    velocities = data.velocities  # (n_steps, n_agents, 2)
    spms = data.spms  # (n_steps, n_agents, 16, 16, 3)
    actions = data.actions  # (n_steps, n_agents, 2)
    surprises = data.surprises  # (n_steps, n_agents)
    metadata = data.metadata

    n_steps, n_agents, _ = size(positions)
    world_params = WorldParams()

    # Convert velocities to per-agent trajectories
    agent_velocities = [
        [velocities[t, i, :] for t in 1:n_steps]
        for i in 1:n_agents
    ]

    # Freezing detection
    detector = FreezeDetector()
    freeze_results = [detect_freezing(vel_traj, detector) for vel_traj in agent_velocities]
    freezing_count = sum(result.is_frozen for result in freeze_results)
    freezing_rate = freezing_count / n_agents

    mean_freeze_duration = freezing_count > 0 ?
        mean(result.freeze_duration for result in freeze_results if result.is_frozen) :
        0.0

    # Success rate (reached goal with low final distance)
    goal_threshold = 3.0  # meters (relaxed threshold)
    success_count = 0

    for i in 1:n_agents
        final_pos = positions[end, i, :]
        goal_pos = data.agent_goals[i, :]  # Use actual goal position
        final_distance = norm(final_pos - goal_pos)

        if final_distance < goal_threshold
            success_count += 1
        end
    end
    success_rate = success_count / n_agents

    # Collision detection (simple proximity-based)
    collision_count = 0
    collision_threshold = 0.8  # meters

    for t in 1:n_steps
        for i in 1:n_agents
            for j in (i+1):n_agents
                dist = norm(positions[t, i, :] - positions[t, j, :])
                if dist < collision_threshold
                    collision_count += 1
                    break  # Count once per agent per timestep
                end
            end
        end
    end
    collision_rate = collision_count / (n_steps * n_agents)

    # Surprise statistics
    surprise_mean = mean(surprises)
    surprise_std = std(surprises)
    surprise_max = maximum(surprises)

    # Jerk (motion smoothness)
    jerks = Float64[]
    for i in 1:n_agents
        agent_vels = agent_velocities[i]
        jerk = compute_jerk(agent_vels, world_params.dt)
        push!(jerks, jerk)
    end
    mean_jerk = mean(jerks)

    # Sample counterfactual pairs for future test design
    # (save first 10 timesteps × first 3 agents for analysis)
    cf_samples = []
    if n_steps >= 10 && n_agents >= 3
        for t in 1:10
            for i in 1:min(3, n_agents)
                push!(cf_samples, (
                    timestep=t,
                    agent_id=i,
                    spm=spms[t, i, :, :, :],
                    action_taken=actions[t, i, :],
                    surprise=surprises[t, i],
                    velocity=velocities[t, i, :]
                ))
            end
        end
    end

    return Dict(
        "haze" => metadata["haze_fixed"],
        "scenario" => metadata["scenario"],
        "density" => metadata["density"],
        "seed" => metadata["seed"],
        "freezing_rate" => freezing_rate,
        "mean_freeze_duration" => mean_freeze_duration,
        "success_rate" => success_rate,
        "collision_rate" => collision_rate,
        "surprise_mean" => surprise_mean,
        "surprise_std" => surprise_std,
        "surprise_max" => surprise_max,
        "mean_jerk" => mean_jerk,
        "n_agents" => n_agents,
        "n_steps" => n_steps,
        "cf_samples" => cf_samples  # For Counterfactual redesign
    )
end

"""
Parse filename to extract parameters
"""
function parse_filename(filename::String)
    # Expected format: sim_h0.5_scramble_d10_s1.h5
    m = match(r"sim_h([0-9.]+)_([a-z]+)_d([0-9]+)_s([0-9]+)\.h5", filename)

    if isnothing(m)
        return nothing
    end

    return (
        haze = parse(Float64, m.captures[1]),
        scenario = m.captures[2],
        density = parse(Int, m.captures[3]),
        seed = parse(Int, m.captures[4])
    )
end

"""
Main analysis function
"""
function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. scripts/analyze_phase5_results.jl <results_directory>")
        println()
        println("Example:")
        println("  julia --project=. scripts/analyze_phase5_results.jl results/phase5/haze_comparison_20260110_120000")
        return
    end

    results_dir = ARGS[1]

    if !isdir(results_dir)
        println("❌ Error: Directory not found: $results_dir")
        return
    end

    println("=" ^ 70)
    println("Phase 5: Results Analysis")
    println("=" ^ 70)
    println()
    println("Input directory: $results_dir")
    println()

    # Find all HDF5 files
    h5_files = filter(f -> endswith(f, ".h5"), readdir(results_dir, join=true))

    if isempty(h5_files)
        println("❌ Error: No .h5 files found in $results_dir")
        return
    end

    println("Found $(length(h5_files)) simulation files")
    println()

    # Process each file
    all_metrics = []

    for (i, filepath) in enumerate(h5_files)
        filename = basename(filepath)
        print("  [$i/$(length(h5_files))] Processing: $filename ... ")

        try
            data = load_simulation_data(filepath)
            metrics = compute_episode_metrics(data)
            push!(all_metrics, metrics)
            println("✅")
        catch e
            println("❌")
            @warn "Failed to process $filename: $e"
        end
    end

    println()
    println("Successfully processed $(length(all_metrics)) files")
    println()

    # Convert to DataFrame
    df = DataFrame(all_metrics)

    # Sort by haze, scenario, density, seed
    sort!(df, [:haze, :scenario, :density, :seed])

    # Save full results to CSV
    csv_path = joinpath(results_dir, "metrics_full.csv")
    CSV.write(csv_path, df)
    println("📊 Full metrics saved to: $csv_path")

    # Compute summary statistics grouped by Haze
    summary_df = combine(groupby(df, [:haze, :scenario, :density]),
        :freezing_rate => mean => :freezing_rate_mean,
        :freezing_rate => std => :freezing_rate_std,
        :success_rate => mean => :success_rate_mean,
        :success_rate => std => :success_rate_std,
        :collision_rate => mean => :collision_rate_mean,
        :collision_rate => std => :collision_rate_std,
        :surprise_mean => mean => :surprise_mean_mean,
        :surprise_mean => std => :surprise_mean_std,
        :mean_jerk => mean => :mean_jerk_mean,
        :mean_jerk => std => :mean_jerk_std,
        nrow => :n_episodes
    )

    summary_csv_path = joinpath(results_dir, "metrics_summary.csv")
    CSV.write(summary_csv_path, summary_df)
    println("📊 Summary metrics saved to: $summary_csv_path")

    # Generate Markdown report
    report_path = joinpath(results_dir, "analysis_report.md")
    generate_markdown_report(df, summary_df, report_path, results_dir)
    println("📄 Analysis report saved to: $report_path")

    # Print summary to console
    println()
    println("=" ^ 70)
    println("Summary by Haze Value (averaged across all conditions)")
    println("=" ^ 70)

    haze_summary = combine(groupby(df, :haze),
        :freezing_rate => mean => :freezing_rate,
        :success_rate => mean => :success_rate,
        :collision_rate => mean => :collision_rate,
        :surprise_mean => mean => :surprise_mean
    )

    println()
    for row in eachrow(haze_summary)
        @printf("Haze = %.1f:\n", row.haze)
        @printf("  Freezing Rate:   %.2f%%\n", row.freezing_rate * 100)
        @printf("  Success Rate:    %.2f%%\n", row.success_rate * 100)
        @printf("  Collision Rate:  %.4f\n", row.collision_rate)
        @printf("  Surprise (mean): %.4f\n", row.surprise_mean)
        println()
    end

    println("=" ^ 70)
    println("Analysis Complete!")
    println("=" ^ 70)
end

"""
Generate Markdown analysis report
"""
function generate_markdown_report(df::DataFrame, summary_df::DataFrame,
                                   output_path::String, results_dir::String)
    open(output_path, "w") do io
        println(io, "# Phase 5: Haze Comparison Analysis Report")
        println(io)
        println(io, "**Generated**: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io, "**Results Directory**: `$results_dir`")
        println(io)

        println(io, "## Experimental Design")
        println(io)
        println(io, "- **Haze values**: $(sort(unique(df.haze)))")
        println(io, "- **Scenarios**: $(unique(df.scenario))")
        println(io, "- **Densities**: $(sort(unique(df.density)))")
        println(io, "- **Seeds per condition**: $(length(unique(df.seed)))")
        println(io, "- **Total episodes**: $(nrow(df))")
        println(io)

        println(io, "## Key Metrics")
        println(io)
        println(io, "### Overall Summary by Haze")
        println(io)

        haze_summary = combine(groupby(df, :haze),
            :freezing_rate => mean => :freezing_rate,
            :success_rate => mean => :success_rate,
            :collision_rate => mean => :collision_rate,
            :surprise_mean => mean => :surprise_mean
        )

        println(io, "| Haze | Freezing Rate | Success Rate | Collision Rate | Surprise (mean) |")
        println(io, "|------|--------------|--------------|----------------|-----------------|")

        for row in eachrow(sort(haze_summary, :haze))
            @printf(io, "| %.1f | %.2f%% | %.2f%% | %.4f | %.4f |\n",
                row.haze,
                row.freezing_rate * 100,
                row.success_rate * 100,
                row.collision_rate,
                row.surprise_mean
            )
        end

        println(io)
        println(io, "## Detailed Results")
        println(io)
        println(io, "See `metrics_full.csv` for complete per-episode results.")
        println(io, "See `metrics_summary.csv` for grouped statistics.")
        println(io)

        println(io, "## Interpretation")
        println(io)
        println(io, "**Lower Freezing Rate** indicates better performance in handling uncertainty.")
        println(io, "**Higher Success Rate** indicates effective goal-reaching behavior.")
        println(io, "**Lower Collision Rate** indicates safer navigation.")
        println(io, "**Surprise values** reflect how well actions match VAE-learned patterns.")
        println(io)
    end
end

# Run analysis
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
