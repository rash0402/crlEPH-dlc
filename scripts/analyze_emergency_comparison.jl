#!/usr/bin/env julia

"""
Comparison Analysis Script for EPH vs Baseline
Generates comparison plots and reports.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using HDF5
using Statistics
using DataFrames
using Plots

include("../src/metrics.jl")
using .Metrics

"""
Extract condition, k_emergency, density, and seed from filename like "sim_baseline_k5_d15_s1.h5"
"""
function parse_comparison_filename(filename::String)
    m = match(r"sim_(baseline|eph)_k(\d+)_d(\d+)_s(\d+)\.h5", filename)
    if m !== nothing
        return m[1], parse(Int, m[2]), parse(Int, m[3]), parse(Int, m[4])
    end
    return nothing, nothing, nothing, nothing
end

"""
Analyze freezing for a single HDF5 file.
"""
function analyze_file(filepath::String; velocity_threshold::Float64=0.1, duration_threshold::Float64=2.0)
    h5open(filepath, "r") do f
        n_agents = read_attribute(f, "num_agents")
        n_steps = read_attribute(f, "actual_steps")
        vel_all = Float64.(read(f, "data/velocity"))
        
        # Build velocity trajectories per agent
        velocities = Vector{Vector{Vector{Float64}}}()
        for a in 1:n_agents
            agent_vel = [Vector{Float64}(vel_all[:, a, t]) for t in 1:n_steps]
            push!(velocities, agent_vel)
        end
        
        # Compute freezing rate
        detector = FreezeDetector(velocity_threshold=velocity_threshold, duration_threshold=duration_threshold)
        freeze_result = compute_freezing_rate(velocities, detector)
        
        # Read collision data if available
        collision_rate = 0.0
        if haskey(f, "data/collision_counts")
            collision_counts = Int.(read(f, "data/collision_counts"))
            collision_rate = sum(collision_counts .> 0) / n_agents
        end
        
        return (
            n_agents=n_agents,
            n_steps=n_steps,
            freezing_rate=freeze_result.freezing_rate,
            n_frozen=freeze_result.n_frozen,
            collision_rate=collision_rate
        )
    end
end

"""
Main analysis function
"""
function main()
    input_dir = "data/logs/comparison_emergency"
    output_dir = "results/comparison_emergency"
    
    println("📊 EPH vs Baseline Comparison Analysis (Variable Emergency Avoidance)")
    println("=" ^ 60)
    
    # Find all HDF5 files
    files = filter(f -> endswith(f, ".h5"), readdir(input_dir))
    
    if isempty(files)
        println("❌ No HDF5 files found in $input_dir")
        return
    end
    
    println("   Found $(length(files)) simulation files")
    
    # Collect results
    results = DataFrame(
        Condition=String[],
        KEmergency=Int[],
        Density=Int[],
        Seed=Int[],
        NAgents=Int[],
        FreezingRate=Float64[],
        NFrozen=Int[],
        CollisionRate=Float64[]
    )
    
    for file in files
        filepath = joinpath(input_dir, file)
        condition, k_emerg, density, seed = parse_comparison_filename(file)
        
        if condition === nothing
            println("   ⚠️ Skipping $file (cannot parse filename)")
            continue
        end
        
        result = analyze_file(filepath)
        push!(results, (condition, k_emerg, density, seed, result.n_agents, result.freezing_rate, result.n_frozen, result.collision_rate))
    end
    
    # Sort
    sort!(results, [:KEmergency, :Condition, :Density, :Seed])
    
    # Print raw results
    println("\n📋 Raw Results (Top 20):")
    println(first(results, 20))
    
    # Aggregate by condition, k_emergency, and density
    aggregated = combine(groupby(results, [:Condition, :KEmergency, :Density]),
        :FreezingRate => mean => :MeanFreezingRate,
        :FreezingRate => std => :StdFreezingRate,
        :CollisionRate => mean => :MeanCollisionRate,
        :NAgents => first => :NAgents
    )
    
    println("\n📊 Aggregated Results:")
    println(aggregated)
    
    mkpath(output_dir)
    
    # Generate plots for each KEmergency
    for k in unique(aggregated.KEmergency)
        data_k = filter(row -> row.KEmergency == k, aggregated)
        baseline_data = filter(row -> row.Condition == "baseline", data_k)
        eph_data = filter(row -> row.Condition == "eph", data_k)
        
        densities = baseline_data.Density
        
        p = plot(
            xlabel="Agent Density",
            ylabel="Freezing Rate (%)",
            title="EPH vs Baseline (k_emerg=$k)",
            legend=:topleft,
            size=(800, 500)
        )
        
        plot!(p, densities, baseline_data.MeanFreezingRate .* 100,
            yerr=coalesce.(baseline_data.StdFreezingRate, 0.0) .* 100,
            label="BASELINE", marker=:circle, linewidth=2, color=:red)
            
        plot!(p, densities, eph_data.MeanFreezingRate .* 100,
            yerr=coalesce.(eph_data.StdFreezingRate, 0.0) .* 100,
            label="EPH", marker=:diamond, linewidth=2, color=:blue)
            
        plot_path = joinpath(output_dir, "freezing_k$(k).png")
        savefig(p, plot_path)
        println("📈 Plot saved: $plot_path")
    end

    # Report generation
    report_path = joinpath(output_dir, "emergency_comparison_report.md")
    open(report_path, "w") do io
        println(io, "# EPH vs Baseline: Emergency Avoidance Analysis")
        println(io, "Generated: $(Dates.now())")
        
        for k in unique(aggregated.KEmergency)
            println(io, "\n## k_emergency = $k")
            println(io, "| Density | BASELINE | EPH | Improvement |")
            println(io, "|---------|----------|-----|-------------|")
            
            data_k = filter(row -> row.KEmergency == k, aggregated)
            baseline = filter(row -> row.Condition == "baseline", data_k)
            eph = filter(row -> row.Condition == "eph", data_k)
            
            for i in 1:nrow(baseline)
                b_rate = baseline.MeanFreezingRate[i] * 100
                e_rate = eph.MeanFreezingRate[i] * 100
                diff = b_rate - e_rate
                println(io, "| $(baseline.Density[i]) | $(round(b_rate, digits=1))% | $(round(e_rate, digits=1))% | **$(round(diff, digits=1))%** |")
            end
            println(io, "\n![Plot](freezing_k$(k).png)")
        end
    end
    println("📝 Report saved: $report_path")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
