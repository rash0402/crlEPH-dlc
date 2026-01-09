#!/usr/bin/env julia

"""
Throughput Analysis Script for Corridor Scenario
Computes throughput metrics for corridor batch experiments.
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
Analyze throughput for a single HDF5 file.
"""
function analyze_throughput(filepath::String; crossing_x::Float64=50.0, dt::Float64=0.033)
    h5open(filepath, "r") do f
        n_agents = read_attribute(f, "num_agents")
        n_steps = read_attribute(f, "actual_steps")
        pos_all = Float64.(read(f, "data/position"))
        
        # Build position trajectories per agent
        positions = Vector{Vector{Vector{Float64}}}()
        for a in 1:n_agents
            agent_traj = [Vector{Float64}(pos_all[:, a, t]) for t in 1:n_steps]
            push!(positions, agent_traj)
        end
        
        # Compute throughput
        result = compute_throughput(positions, crossing_x=crossing_x, direction=:both, dt=dt)
        
        return (
            n_agents=n_agents,
            n_steps=n_steps,
            n_crossings=result.n_crossings,
            throughput=result.throughput_per_second,
            simulation_time=n_steps * dt
        )
    end
end

"""
Extract density and seed from filename like "sim_d5_s1.h5"
"""
function parse_filename(filename::String)
    m = match(r"sim_d(\d+)_s(\d+)\.h5", filename)
    if m !== nothing
        return parse(Int, m[1]), parse(Int, m[2])
    end
    return nothing, nothing
end

"""
Main analysis function
"""
function main()
    input_dir = "data/logs/batch_corridor"
    output_dir = "results/evaluation"
    
    println("📊 Throughput Analysis for Corridor Scenario")
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
        Density=Int[],
        Seed=Int[],
        NAgents=Int[],
        NCrossings=Int[],
        Throughput=Float64[],
        SimTime=Float64[]
    )
    
    for file in files
        filepath = joinpath(input_dir, file)
        density, seed = parse_filename(file)
        
        if density === nothing
            println("   ⚠️ Skipping $file (cannot parse filename)")
            continue
        end
        
        result = analyze_throughput(filepath)
        push!(results, (density, seed, result.n_agents, result.n_crossings, result.throughput, result.simulation_time))
    end
    
    # Sort by density and seed
    sort!(results, [:Density, :Seed])
    
    # Print results table
    println("\n📋 Results:")
    println(results)
    
    # Aggregate by density
    aggregated = combine(groupby(results, :Density), 
        :NCrossings => mean => :MeanCrossings,
        :NCrossings => std => :StdCrossings,
        :Throughput => mean => :MeanThroughput,
        :Throughput => std => :StdThroughput,
        :NAgents => first => :NAgents
    )
    
    println("\n📊 Aggregated by Density:")
    println(aggregated)
    
    # Create plot using Plots.jl
    densities = aggregated.Density
    throughputs = aggregated.MeanThroughput
    stds = coalesce.(aggregated.StdThroughput, 0.0)
    
    p = bar(densities, throughputs, yerr=stds,
        xlabel="Agent Density (per group)",
        ylabel="Throughput (agents/s)",
        title="Corridor Scenario: Throughput vs Density",
        legend=false,
        color=:steelblue,
        size=(800, 500)
    )
    
    # Save plot
    mkpath(output_dir)
    plot_path = joinpath(output_dir, "throughput_vs_density.png")
    savefig(p, plot_path)
    println("\n📈 Plot saved to: $plot_path")
    
    # Save CSV
    csv_path = joinpath(output_dir, "throughput_analysis.csv")
    open(csv_path, "w") do io
        println(io, "Density,Seed,NAgents,NCrossings,Throughput,SimTime")
        for row in eachrow(results)
            println(io, "$(row.Density),$(row.Seed),$(row.NAgents),$(row.NCrossings),$(round(row.Throughput, digits=4)),$(round(row.SimTime, digits=2))")
        end
    end
    println("📄 CSV saved to: $csv_path")
    
    # Generate markdown report
    report_path = joinpath(output_dir, "throughput_report.md")
    open(report_path, "w") do io
        println(io, "# Corridor Throughput Analysis Report")
        println(io, "")
        println(io, "Generated: $(Dates.now())")
        println(io, "")
        println(io, "## Summary")
        println(io, "")
        println(io, "| Density | N Agents | Mean Crossings | Mean Throughput (agents/s) |")
        println(io, "|---------|----------|----------------|---------------------------|")
        for row in eachrow(aggregated)
            println(io, "| $(row.Density) | $(row.NAgents) | $(round(row.MeanCrossings, digits=1)) | $(round(row.MeanThroughput, digits=3)) |")
        end
        println(io, "")
        println(io, "## Observations")
        println(io, "")
        println(io, "- **Crossing Line**: x = 50.0 (corridor center)")
        println(io, "- **Simulation Time**: $(round(results.SimTime[1], digits=1))s per run")
        println(io, "")
        println(io, "## Plot")
        println(io, "")
        println(io, "![Throughput vs Density](throughput_vs_density.png)")
    end
    println("📝 Report saved to: $report_path")
    
    println("\n✅ Throughput analysis complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
