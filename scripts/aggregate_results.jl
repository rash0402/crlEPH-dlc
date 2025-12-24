#!/usr/bin/env julia
"""
Result Aggregation Script
Aggregates metrics across multiple seeds for each experiment condition.

Usage:
    julia --project=. scripts/aggregate_results.jl [results_dir]
"""

using JSON
using Statistics
using Printf
using Dates

# ===== Configuration =====
struct AggregationConfig
    results_dir::String
    output_file::String
end

function AggregationConfig(;
    results_dir="results/ablation",
    output_file="results/ablation/summary.json"
)
    AggregationConfig(results_dir, output_file)
end

# ===== Data Loading =====

"""
Load all metric files from a condition directory.
"""
function load_condition_metrics(condition_dir::String)
    if !isdir(condition_dir)
        @warn "Directory not found: $condition_dir"
        return []
    end
    
    metrics_files = filter(f -> endswith(f, "_metrics.json"), readdir(condition_dir, join=true))
    
    metrics_list = []
    for file in metrics_files
        try
            data = JSON.parsefile(file)
            push!(metrics_list, data)
        catch e
            @warn "Failed to load $file: $e"
        end
    end
    
    return metrics_list
end

# ===== Statistics Computation =====

"""
Extract metric values from list of metric dictionaries.
"""
function extract_metric(metrics_list::Vector, metric_path::Vector{String})
    values = Float64[]
    
    for metrics in metrics_list
        try
            value = metrics
            for key in metric_path
                value = value[key]
            end
            push!(values, Float64(value))
        catch e
            @warn "Failed to extract metric $(join(metric_path, ".")): $e"
        end
    end
    
    return values
end

"""
Compute statistics for a metric.
"""
function compute_statistics(values::Vector{Float64})
    if isempty(values)
        return Dict(
            "mean" => NaN,
            "std" => NaN,
            "min" => NaN,
            "max" => NaN,
            "median" => NaN,
            "n" => 0
        )
    end
    
    return Dict(
        "mean" => mean(values),
        "std" => std(values),
        "min" => minimum(values),
        "max" => maximum(values),
        "median" => median(values),
        "n" => length(values)
    )
end

"""
Aggregate metrics for a single condition.
"""
function aggregate_condition(condition_dir::String, condition_name::String)
    println("\n📊 Aggregating: $condition_name")
    
    # Load all metrics
    metrics_list = load_condition_metrics(condition_dir)
    
    if isempty(metrics_list)
        @warn "No metrics found for $condition_name"
        return Dict("condition" => condition_name, "n_experiments" => 0)
    end
    
    println("   Found $(length(metrics_list)) experiments")
    
    # Define metrics to aggregate
    metric_paths = [
        (["performance", "success_rate"], "success_rate"),
        (["performance", "collision_rate"], "collision_rate"),
        (["motion_quality", "freezing_rate"], "freezing_rate"),
        (["motion_quality", "avg_jerk"], "avg_jerk"),
        (["motion_quality", "min_ttc"], "min_ttc")
    ]
    
    # Aggregate each metric
    aggregated = Dict(
        "condition" => condition_name,
        "n_experiments" => length(metrics_list),
        "metrics" => Dict()
    )
    
    for (path, name) in metric_paths
        values = extract_metric(metrics_list, path)
        stats = compute_statistics(values)
        aggregated["metrics"][name] = stats
        
        @printf("   %s: %.2f ± %.2f (n=%d)\n", 
                name, stats["mean"], stats["std"], stats["n"])
    end
    
    return aggregated
end

# ===== Main Aggregation =====

"""
Aggregate results for all conditions.
"""
function aggregate_all_results(config::AggregationConfig)
    println("=" ^ 60)
    println("📊 RESULT AGGREGATION")
    println("=" ^ 60)
    
    println("\n📂 Results directory: $(config.results_dir)")
    
    if !isdir(config.results_dir)
        @error "Results directory not found: $(config.results_dir)"
        return nothing
    end
    
    # Find all condition directories
    condition_dirs = filter(isdir, readdir(config.results_dir, join=true))
    
    if isempty(condition_dirs)
        @warn "No condition directories found"
        return nothing
    end
    
    println("   Found $(length(condition_dirs)) conditions")
    
    # Aggregate each condition
    summary = Dict(
        "timestamp" => string(now()),
        "results_dir" => config.results_dir,
        "conditions" => Dict()
    )
    
    for dir in condition_dirs
        condition_name = basename(dir)
        aggregated = aggregate_condition(dir, condition_name)
        summary["conditions"][condition_name] = aggregated
    end
    
    # Save summary
    println("\n💾 Saving summary to: $(config.output_file)")
    mkpath(dirname(config.output_file))
    
    open(config.output_file, "w") do io
        JSON.print(io, summary, 2)
    end
    
    println("\n" * "=" ^ 60)
    println("✅ AGGREGATION COMPLETE")
    println("=" ^ 60)
    
    # Print comparison
    print_comparison(summary)
    
    return summary
end

"""
Print comparison between conditions.
"""
function print_comparison(summary::Dict)
    conditions = summary["conditions"]
    
    if length(conditions) < 2
        return
    end
    
    println("\n📈 Condition Comparison:")
    println("=" ^ 60)
    
    # Get condition names
    cond_names = sort(collect(keys(conditions)))
    
    # Print header
    @printf("%-20s", "Metric")
    for name in cond_names
        @printf(" | %12s", uppercase(name))
    end
    println()
    println("-" ^ 60)
    
    # Print each metric
    metrics = ["freezing_rate", "avg_jerk", "success_rate", "collision_rate", "min_ttc"]
    
    for metric in metrics
        @printf("%-20s", metric)
        for name in cond_names
            cond = conditions[name]
            if haskey(cond["metrics"], metric)
                val = cond["metrics"][metric]["mean"]
                @printf(" | %12.2f", val)
            else
                @printf(" | %12s", "N/A")
            end
        end
        println()
    end
    
    println("=" ^ 60)
end

# ===== Main Entry Point =====
function main(args::Vector{String})
    results_dir = length(args) >= 1 ? args[1] : "results/ablation"
    
    config = AggregationConfig(results_dir=results_dir)
    
    summary = aggregate_all_results(config)
    
    return summary
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
