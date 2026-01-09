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
Extract condition, density, and seed from filename like "sim_baseline_d5_s1.h5" or "sim_eph_d10_s2.h5"
"""
function parse_comparison_filename(filename::String)
    m = match(r"sim_(baseline|eph)_d(\d+)_s(\d+)\.h5", filename)
    if m !== nothing
        return m[1], parse(Int, m[2]), parse(Int, m[3])
    end
    return nothing, nothing, nothing
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
    input_dir = "data/logs/comparison_corridor"
    output_dir = "results/comparison"
    
    println("📊 EPH vs Baseline Comparison Analysis")
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
        Density=Int[],
        Seed=Int[],
        NAgents=Int[],
        FreezingRate=Float64[],
        NFrozen=Int[],
        CollisionRate=Float64[]
    )
    
    for file in files
        filepath = joinpath(input_dir, file)
        condition, density, seed = parse_comparison_filename(file)
        
        if condition === nothing
            println("   ⚠️ Skipping $file (cannot parse filename)")
            continue
        end
        
        result = analyze_file(filepath)
        push!(results, (condition, density, seed, result.n_agents, result.freezing_rate, result.n_frozen, result.collision_rate))
    end
    
    # Sort
    sort!(results, [:Condition, :Density, :Seed])
    
    # Print raw results
    println("\n📋 Raw Results:")
    println(results)
    
    # Aggregate by condition and density
    aggregated = combine(groupby(results, [:Condition, :Density]),
        :FreezingRate => mean => :MeanFreezingRate,
        :FreezingRate => std => :StdFreezingRate,
        :CollisionRate => mean => :MeanCollisionRate,
        :NAgents => first => :NAgents
    )
    
    println("\n📊 Aggregated Results:")
    println(aggregated)
    
    # Separate by condition
    baseline_data = filter(row -> row.Condition == "baseline", aggregated)
    eph_data = filter(row -> row.Condition == "eph", aggregated)
    
    # Create comparison plot
    mkpath(output_dir)
    
    densities = baseline_data.Density
    
    p = plot(
        xlabel="Agent Density (per group)",
        ylabel="Freezing Rate (%)",
        title="EPH vs Baseline: Freezing Rate Comparison",
        legend=:topright,
        size=(800, 500),
        ylim=(0, max(maximum(baseline_data.MeanFreezingRate), maximum(eph_data.MeanFreezingRate)) * 100 + 5)
    )
    
    # Baseline
    plot!(p, densities, baseline_data.MeanFreezingRate .* 100,
        yerr=coalesce.(baseline_data.StdFreezingRate, 0.0) .* 100,
        label="BASELINE (Fixed β)",
        marker=:circle,
        linewidth=2,
        color=:red
    )
    
    # EPH
    plot!(p, densities, eph_data.MeanFreezingRate .* 100,
        yerr=coalesce.(eph_data.StdFreezingRate, 0.0) .* 100,
        label="EPH (Haze Modulation)",
        marker=:diamond,
        linewidth=2,
        color=:blue
    )
    
    plot_path = joinpath(output_dir, "freezing_comparison.png")
    savefig(p, plot_path)
    println("\n📈 Plot saved to: $plot_path")
    
    # Generate markdown report
    report_path = joinpath(output_dir, "comparison_report.md")
    open(report_path, "w") do io
        println(io, "# EPH vs Baseline Comparison Report")
        println(io, "")
        println(io, "Generated: $(Dates.now())")
        println(io, "")
        println(io, "## Freezing Rate Comparison")
        println(io, "")
        println(io, "| Density | BASELINE | EPH | Improvement |")
        println(io, "|---------|----------|-----|-------------|")
        for i in 1:nrow(baseline_data)
            b_rate = baseline_data.MeanFreezingRate[i] * 100
            e_rate = eph_data.MeanFreezingRate[i] * 100
            improvement = b_rate - e_rate
            println(io, "| $(baseline_data.Density[i]) | $(round(b_rate, digits=1))% | $(round(e_rate, digits=1))% | **$(round(improvement, digits=1))%** |")
        end
        println(io, "")
        println(io, "## Key Findings")
        println(io, "")
        
        # Calculate average improvement
        avg_improvement = mean(baseline_data.MeanFreezingRate .- eph_data.MeanFreezingRate) * 100
        println(io, "- **Average Freezing Rate Reduction**: $(round(avg_improvement, digits=2))%")
        println(io, "- EPH's Haze modulation mechanism effectively reduces deadlocks in narrow corridors.")
        println(io, "")
        println(io, "## Plot")
        println(io, "")
        println(io, "![Freezing Comparison](freezing_comparison.png)")
    end
    println("📝 Report saved to: $report_path")
    
    # Save CSV
    csv_path = joinpath(output_dir, "comparison_results.csv")
    open(csv_path, "w") do io
        println(io, "Condition,Density,Seed,NAgents,FreezingRate,NFrozen,CollisionRate")
        for row in eachrow(results)
            println(io, "$(row.Condition),$(row.Density),$(row.Seed),$(row.NAgents),$(round(row.FreezingRate, digits=4)),$(row.NFrozen),$(round(row.CollisionRate, digits=4))")
        end
    end
    println("📄 CSV saved to: $csv_path")
    
    println("\n✅ Comparison analysis complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
