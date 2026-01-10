#!/usr/bin/env julia

"""
Visualization Script for Baseline vs EPH Comparison
Generates comparison plots for freezing rate, throughput, and Surprise statistics
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Statistics
using HDF5
using ArgParse
using Plots
using DelimitedFiles

include("../src/metrics.jl")
using .Metrics

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--log-dir"
            help = "Directory containing simulation logs"
            arg_type = String
            default = "data/logs/comparison"
        "--output-dir"
            help = "Output directory for plots"
            arg_type = String
            default = "results/comparison"
        "--scenario"
            help = "Scenario to visualize (scramble or corridor)"
            arg_type = String
            default = "scramble"
    end

    return parse_args(s)
end

"""
Load all simulation results from a directory
"""
function load_all_results(log_dir::String, scenario::String)
    results_dict = Dict{String, Vector{SimulationResults}}()

    # Find all HDF5 files for this scenario
    files = filter(f -> occursin(".h5", f) && occursin(scenario, f), readdir(log_dir, join=true))

    for filepath in files
        filename = basename(filepath)

        # Parse condition from filename
        if occursin("baseline", filename)
            condition = "baseline"
        elseif occursin("eph", filename)
            condition = "eph"
        else
            continue
        end

        try
            result = load_simulation_results(filepath)

            if !haskey(results_dict, condition)
                results_dict[condition] = []
            end

            push!(results_dict[condition], result)
            println("  Loaded: $filename")
        catch e
            @warn "Failed to load $filename: $e"
        end
    end

    return results_dict
end

"""
Compute metrics for a set of results
"""
function compute_metrics_for_results(results::Vector{SimulationResults})
    freezing_rates = Float64[]
    mean_surprises = Float64[]
    throughputs = Float64[]

    for result in results
        # Freezing rate
        n_steps, n_agents, _ = size(result.velocities)
        velocities_per_agent = [
            [result.velocities[t, i, :] for t in 1:n_steps]
            for i in 1:n_agents
        ]

        freeze_result = compute_freezing_rate(velocities_per_agent)
        push!(freezing_rates, freeze_result.freezing_rate)

        # Mean Surprise
        surprise_stats = compute_surprise_statistics(result.surprises)
        push!(mean_surprises, surprise_stats.mean_surprise)

        # Throughput (if corridor scenario)
        positions_per_agent = [
            [result.positions[t, i, :] for t in 1:n_steps]
            for i in 1:n_agents
        ]

        throughput_result = compute_throughput(positions_per_agent)
        push!(throughputs, throughput_result.throughput_per_second)
    end

    return (
        mean_freezing_rate=mean(freezing_rates),
        std_freezing_rate=std(freezing_rates),
        mean_surprise=mean(mean_surprises),
        std_surprise=std(mean_surprises),
        mean_throughput=mean(throughputs),
        std_throughput=std(throughputs)
    )
end

"""
Plot freezing rate comparison
"""
function plot_freezing_comparison(
    baseline_metrics,
    eph_metrics,
    output_path::String
)
    p = bar(
        ["Baseline", "EPH"],
        [baseline_metrics.mean_freezing_rate * 100, eph_metrics.mean_freezing_rate * 100],
        yerr=[baseline_metrics.std_freezing_rate * 100, eph_metrics.std_freezing_rate * 100],
        ylabel="Freezing Rate (%)",
        title="Freezing Rate: Baseline vs EPH",
        legend=false,
        color=[:red :green],
        bar_width=0.5
    )

    savefig(p, output_path)
    println("  Saved: $output_path")
end

"""
Plot Surprise timeline comparison
"""
function plot_surprise_timeline(
    baseline_results::Vector{SimulationResults},
    eph_results::Vector{SimulationResults},
    output_path::String
)
    # Compute mean Surprise timeline for each condition
    baseline_timelines = []
    for result in baseline_results
        stats = compute_surprise_statistics(result.surprises)
        push!(baseline_timelines, stats.surprise_timeline)
    end

    eph_timelines = []
    for result in eph_results
        stats = compute_surprise_statistics(result.surprises)
        push!(eph_timelines, stats.surprise_timeline)
    end

    # Average across runs
    n_steps = length(baseline_timelines[1])
    baseline_mean = [mean([tl[t] for tl in baseline_timelines]) for t in 1:n_steps]
    eph_mean = [mean([tl[t] for tl in eph_timelines]) for t in 1:n_steps]

    # Plot
    p = plot(
        1:n_steps,
        baseline_mean,
        label="Baseline",
        linewidth=2,
        color=:red,
        xlabel="Time Step",
        ylabel="Mean Surprise",
        title="Surprise Timeline: Baseline vs EPH"
    )
    plot!(p, 1:n_steps, eph_mean, label="EPH", linewidth=2, color=:green)

    savefig(p, output_path)
    println("  Saved: $output_path")
end

"""
Plot throughput comparison (for corridor scenario)
"""
function plot_throughput_comparison(
    baseline_metrics,
    eph_metrics,
    output_path::String
)
    p = bar(
        ["Baseline", "EPH"],
        [baseline_metrics.mean_throughput, eph_metrics.mean_throughput],
        yerr=[baseline_metrics.std_throughput, eph_metrics.std_throughput],
        ylabel="Throughput (agents/sec)",
        title="Throughput: Baseline vs EPH",
        legend=false,
        color=[:red :green],
        bar_width=0.5
    )

    savefig(p, output_path)
    println("  Saved: $output_path")
end

"""
Generate summary statistics CSV
"""
function generate_summary_csv(
    baseline_metrics,
    eph_metrics,
    output_path::String
)
    data = [
        ["Metric", "Baseline", "EPH", "Improvement (%)"],
        ["Freezing Rate (%)",
         baseline_metrics.mean_freezing_rate * 100,
         eph_metrics.mean_freezing_rate * 100,
         (baseline_metrics.mean_freezing_rate - eph_metrics.mean_freezing_rate) / baseline_metrics.mean_freezing_rate * 100],
        ["Mean Surprise",
         baseline_metrics.mean_surprise,
         eph_metrics.mean_surprise,
         (eph_metrics.mean_surprise - baseline_metrics.mean_surprise) / max(baseline_metrics.mean_surprise, 1e-6) * 100],
        ["Throughput (agents/sec)",
         baseline_metrics.mean_throughput,
         eph_metrics.mean_throughput,
         (eph_metrics.mean_throughput - baseline_metrics.mean_throughput) / baseline_metrics.mean_throughput * 100]
    ]

    writedlm(output_path, data, ',')
    println("  Saved: $output_path")
end

"""
Main visualization
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("Baseline vs EPH Visualization")
    println("=" ^ 70)
    println()
    println("Configuration:")
    println("  Log directory: $(args["log-dir"])")
    println("  Scenario: $(args["scenario"])")
    println("  Output directory: $(args["output-dir"])")
    println()

    # Create output directory
    mkpath(args["output-dir"])

    # Load results
    println("📂 Loading simulation results...")
    results_dict = load_all_results(args["log-dir"], args["scenario"])

    if !haskey(results_dict, "baseline")
        println("❌ No baseline results found")
        return
    end

    if !haskey(results_dict, "eph")
        println("❌ No EPH results found")
        return
    end

    baseline_results = results_dict["baseline"]
    eph_results = results_dict["eph"]

    println("  Baseline runs: $(length(baseline_results))")
    println("  EPH runs: $(length(eph_results))")
    println()

    # Compute metrics
    println("📊 Computing metrics...")
    baseline_metrics = compute_metrics_for_results(baseline_results)
    eph_metrics = compute_metrics_for_results(eph_results)

    println("  Baseline freezing rate: $(round(baseline_metrics.mean_freezing_rate * 100, digits=1))%")
    println("  EPH freezing rate: $(round(eph_metrics.mean_freezing_rate * 100, digits=1))%")
    println()

    # Generate plots
    println("📈 Generating plots...")

    # 1. Freezing rate comparison
    freezing_plot_path = joinpath(args["output-dir"], "$(args["scenario"])_freezing_comparison.png")
    plot_freezing_comparison(baseline_metrics, eph_metrics, freezing_plot_path)

    # 2. Surprise timeline
    if length(baseline_results) > 0 && length(eph_results) > 0
        surprise_plot_path = joinpath(args["output-dir"], "$(args["scenario"])_surprise_timeline.png")
        plot_surprise_timeline(baseline_results, eph_results, surprise_plot_path)
    end

    # 3. Throughput (if corridor)
    if args["scenario"] == "corridor"
        throughput_plot_path = joinpath(args["output-dir"], "corridor_throughput_comparison.png")
        plot_throughput_comparison(baseline_metrics, eph_metrics, throughput_plot_path)
    end

    # 4. Summary CSV
    summary_csv_path = joinpath(args["output-dir"], "$(args["scenario"])_summary.csv")
    generate_summary_csv(baseline_metrics, eph_metrics, summary_csv_path)

    println()
    println("=" ^ 70)
    println("✅ Visualization Complete!")
    println("=" ^ 70)
    println("  Output directory: $(args["output-dir"])")
    println()
    println("Generated files:")
    println("  - Freezing rate comparison plot")
    println("  - Surprise timeline plot")
    if args["scenario"] == "corridor"
        println("  - Throughput comparison plot")
    end
    println("  - Summary statistics CSV")
end

# Run visualization
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
