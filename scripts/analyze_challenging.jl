#!/usr/bin/env julia

"""
Challenging Corridor Analysis Script
Analyzes results from narrow corridor experiments.
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
Parse filename like "sim_baseline_w2_d25_s1.h5"
"""
function parse_challenging_filename(filename::String)
    m = match(r"sim_(baseline|eph)_w(\d+)_d(\d+)_s(\d+)\.h5", filename)
    if m !== nothing
        return m[1], parse(Int, m[2]), parse(Int, m[3]), parse(Int, m[4])
    end
    return nothing, nothing, nothing, nothing
end

"""
Analyze freezing for a single HDF5 file.
"""
function analyze_file(filepath::String)
    h5open(filepath, "r") do f
        n_agents = read_attribute(f, "num_agents")
        n_steps = read_attribute(f, "actual_steps")
        vel_all = Float64.(read(f, "data/velocity"))
        
        velocities = Vector{Vector{Vector{Float64}}}()
        for a in 1:n_agents
            agent_vel = [Vector{Float64}(vel_all[:, a, t]) for t in 1:n_steps]
            push!(velocities, agent_vel)
        end
        
        detector = FreezeDetector(velocity_threshold=0.1, duration_threshold=2.0)
        freeze_result = compute_freezing_rate(velocities, detector)
        
        return (
            n_agents=n_agents,
            freezing_rate=freeze_result.freezing_rate,
            n_frozen=freeze_result.n_frozen
        )
    end
end

function main()
    input_dir = "data/logs/comparison_challenging"
    output_dir = "results/comparison_challenging"
    
    println("📊 Challenging Corridor Analysis")
    println("=" ^ 60)
    
    files = filter(f -> endswith(f, ".h5"), readdir(input_dir))
    
    if isempty(files)
        println("❌ No HDF5 files found in $input_dir")
        return
    end
    
    println("   Found $(length(files)) files")
    
    results = DataFrame(
        Condition=String[],
        Width=Int[],
        Density=Int[],
        Seed=Int[],
        NAgents=Int[],
        FreezingRate=Float64[],
        NFrozen=Int[]
    )
    
    for file in files
        filepath = joinpath(input_dir, file)
        condition, width, density, seed = parse_challenging_filename(file)
        
        if condition === nothing
            continue
        end
        
        result = analyze_file(filepath)
        push!(results, (condition, width, density, seed, result.n_agents, result.freezing_rate, result.n_frozen))
    end
    
    sort!(results, [:Width, :Condition, :Density, :Seed])
    
    println("\n📋 Raw Results:")
    println(results)
    
    # Aggregate
    aggregated = combine(groupby(results, [:Condition, :Width, :Density]),
        :FreezingRate => mean => :MeanFreezingRate,
        :FreezingRate => std => :StdFreezingRate,
        :NAgents => first => :NAgents
    )
    
    println("\n📊 Aggregated:")
    println(aggregated)
    
    mkpath(output_dir)
    
    # Create comparison plot for each width
    for width in unique(aggregated.Width)
        width_data = filter(row -> row.Width == width, aggregated)
        baseline_data = filter(row -> row.Condition == "baseline", width_data)
        eph_data = filter(row -> row.Condition == "eph", width_data)
        
        densities = baseline_data.Density
        
        p = plot(
            xlabel="Agent Density (per group)",
            ylabel="Freezing Rate (%)",
            title="Width=$(width)m: EPH vs Baseline",
            legend=:topleft,
            size=(700, 450),
            ylim=(0, maximum(vcat(baseline_data.MeanFreezingRate, eph_data.MeanFreezingRate)) * 100 + 10)
        )
        
        plot!(p, densities, baseline_data.MeanFreezingRate .* 100,
            yerr=coalesce.(baseline_data.StdFreezingRate, 0.0) .* 100,
            label="BASELINE (Fixed β)",
            marker=:circle, linewidth=2, color=:red
        )
        
        plot!(p, densities, eph_data.MeanFreezingRate .* 100,
            yerr=coalesce.(eph_data.StdFreezingRate, 0.0) .* 100,
            label="EPH (Haze Modulation)",
            marker=:diamond, linewidth=2, color=:blue
        )
        
        savefig(p, joinpath(output_dir, "freezing_w$(width)m.png"))
        println("📈 Saved: freezing_w$(width)m.png")
    end
    
    # Generate report
    report_path = joinpath(output_dir, "challenging_report.md")
    open(report_path, "w") do io
        println(io, "# Challenging Corridor Comparison Report")
        println(io, "\nGenerated: $(Dates.now())\n")
        
        for width in sort(unique(aggregated.Width))
            println(io, "## Corridor Width = $(width)m\n")
            println(io, "| Density | BASELINE | EPH | Improvement |")
            println(io, "|---------|----------|-----|-------------|")
            
            width_data = filter(row -> row.Width == width, aggregated)
            baseline_data = filter(row -> row.Condition == "baseline", width_data)
            eph_data = filter(row -> row.Condition == "eph", width_data)
            
            for i in 1:nrow(baseline_data)
                b = baseline_data.MeanFreezingRate[i] * 100
                e = eph_data.MeanFreezingRate[i] * 100
                imp = b - e
                println(io, "| $(baseline_data.Density[i]) | $(round(b, digits=1))% | $(round(e, digits=1))% | **$(round(imp, digits=1))%** |")
            end
            println(io, "\n![](freezing_w$(width)m.png)\n")
        end
    end
    println("📝 Report saved: $report_path")
    
    # CSV
    csv_path = joinpath(output_dir, "challenging_results.csv")
    open(csv_path, "w") do io
        println(io, "Condition,Width,Density,Seed,NAgents,FreezingRate,NFrozen")
        for row in eachrow(results)
            println(io, "$(row.Condition),$(row.Width),$(row.Density),$(row.Seed),$(row.NAgents),$(round(row.FreezingRate, digits=4)),$(row.NFrozen)")
        end
    end
    println("📄 CSV saved: $csv_path")
    
    println("\n✅ Analysis complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
