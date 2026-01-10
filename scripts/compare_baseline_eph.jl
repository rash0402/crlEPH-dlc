#!/usr/bin/env julia

"""
Phase 5: Baseline vs EPH Comparison Experiment
Automatically runs multiple simulations comparing Baseline (λ_surprise=0) vs EPH (λ_surprise>0)
"""

using Printf
using Dates
using Statistics
using HDF5
using ArgParse

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--scenarios"
            help = "Scenarios to test (comma-separated): scramble,corridor"
            arg_type = String
            default = "scramble,corridor"
        "--densities"
            help = "Agent densities to test (comma-separated integers)"
            arg_type = String
            default = "5,10,15,20"
        "--seeds"
            help = "Random seeds for multiple runs (comma-separated integers)"
            arg_type = String
            default = "1,2,3"
        "--steps"
            help = "Simulation steps"
            arg_type = Int
            default = 1500
        "--lambda-surprise-values"
            help = "λ_surprise values to test (comma-separated, 0 = baseline)"
            arg_type = String
            default = "0.0,0.5,1.0,2.0"
        "--vae-model"
            help = "Path to trained VAE model (.bson file)"
            arg_type = String
            default = "models/action_vae_v56_best.bson"
        "--output-dir"
            help = "Output directory for simulation logs"
            arg_type = String
            default = "data/logs/comparison"
        "--report-dir"
            help = "Output directory for comparison reports"
            arg_type = String
            default = "results/comparison"
    end

    return parse_args(s)
end

"""
Run a single simulation configuration
"""
function run_single_simulation(
    scenario::String,
    density::Int,
    seed::Int,
    lambda_surprise::Float64,
    vae_model::String,
    steps::Int,
    output_dir::String
)
    # Generate output filename
    condition = lambda_surprise > 0.0 ? "eph" : "baseline"
    output_file = joinpath(
        output_dir,
        "sim_$(condition)_$(scenario)_d$(density)_s$(seed)_ls$(lambda_surprise).h5"
    )

    # Build command
    cmd = `julia --project=. scripts/run_simulation_eph.jl
        --scenario $scenario
        --density $density
        --seed $seed
        --steps $steps
        --lambda-surprise $lambda_surprise
        --vae-model $vae_model
        --output $output_file`

    println("  Running: $(condition) | $(scenario) | density=$(density) | seed=$(seed)")

    try
        run(cmd)
        return (success=true, output_file=output_file)
    catch e
        @warn "Simulation failed: $e"
        return (success=false, output_file="")
    end
end

"""
Generate comparison report
"""
function generate_comparison_report(
    results::Vector{Dict{String, Any}},
    output_path::String
)
    # Group results by scenario and condition
    grouped = Dict{String, Dict{String, Vector{Dict{String, Any}}}}()

    for result in results
        scenario = result["scenario"]
        condition = result["condition"]

        if !haskey(grouped, scenario)
            grouped[scenario] = Dict{String, Vector{Dict{String, Any}}}()
        end
        if !haskey(grouped[scenario], condition)
            grouped[scenario][condition] = []
        end

        push!(grouped[scenario][condition], result)
    end

    # Write report
    open(output_path, "w") do io
        println(io, "# Baseline vs EPH Comparison Report")
        println(io, "")
        println(io, "Generated: $(now())")
        println(io, "")

        for scenario in sort(collect(keys(grouped)))
            println(io, "## Scenario: $(uppercase(scenario))")
            println(io, "")

            scenario_results = grouped[scenario]

            # Create comparison table
            println(io, "### Summary Table")
            println(io, "")
            println(io, "| Condition | λ_surprise | Density | N Runs | Freezing Rate | Mean Surprise | Throughput |")
            println(io, "|-----------|------------|---------|--------|---------------|---------------|------------|")

            for condition in ["baseline", "eph"]
                if !haskey(scenario_results, condition)
                    continue
                end

                for result in scenario_results[condition]
                    @printf(io, "| %s | %.1f | %d | %d | %.2f%% | %.4f | %.2f |\n",
                            condition,
                            result["lambda_surprise"],
                            result["density"],
                            result["n_runs"],
                            result["freezing_rate"] * 100,
                            result["mean_surprise"],
                            result["throughput"])
                end
            end

            println(io, "")

            # Statistical comparison
            if haskey(scenario_results, "baseline") && haskey(scenario_results, "eph")
                println(io, "### Analysis")
                println(io, "")

                baseline_freeze = mean([r["freezing_rate"] for r in scenario_results["baseline"]])
                eph_freeze = mean([r["freezing_rate"] for r in scenario_results["eph"]])
                freeze_reduction = (baseline_freeze - eph_freeze) / baseline_freeze * 100

                println(io, "- **Freezing Rate Reduction**: $(round(freeze_reduction, digits=1))%")
                println(io, "  - Baseline: $(round(baseline_freeze * 100, digits=1))%")
                println(io, "  - EPH: $(round(eph_freeze * 100, digits=1))%")
                println(io, "")

                if scenario == "corridor"
                    baseline_throughput = mean([r["throughput"] for r in scenario_results["baseline"]])
                    eph_throughput = mean([r["throughput"] for r in scenario_results["eph"]])
                    throughput_improvement = (eph_throughput - baseline_throughput) / baseline_throughput * 100

                    println(io, "- **Throughput Improvement**: $(round(throughput_improvement, digits=1))%")
                    println(io, "  - Baseline: $(round(baseline_throughput, digits=2)) agents/sec")
                    println(io, "  - EPH: $(round(eph_throughput, digits=2)) agents/sec")
                    println(io, "")
                end
            end
        end

        println(io, "## Conclusion")
        println(io, "")
        println(io, "See visualization plots in `results/comparison/` for detailed analysis.")
    end

    println("📊 Comparison report saved to: $output_path")
end

"""
Main comparison experiment
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("Phase 5: Baseline vs EPH Comparison Experiment")
    println("=" ^ 70)
    println()

    # Parse arguments
    scenarios = split(args["scenarios"], ",")
    densities = [parse(Int, d) for d in split(args["densities"], ",")]
    seeds = [parse(Int, s) for s in split(args["seeds"], ",")]
    lambda_surprise_values = [parse(Float64, ls) for ls in split(args["lambda-surprise-values"], ",")]

    # Create output directories
    mkpath(args["output-dir"])
    mkpath(args["report-dir"])

    println("Configuration:")
    println("  Scenarios: $(scenarios)")
    println("  Densities: $(densities)")
    println("  Seeds: $(seeds)")
    println("  λ_surprise values: $(lambda_surprise_values)")
    println("  Steps: $(args["steps"])")
    println()

    # Calculate total number of simulations
    total_sims = length(scenarios) * length(densities) * length(seeds) * length(lambda_surprise_values)
    println("Total simulations: $total_sims")
    println()

    # Run all simulations
    results = []
    sim_count = 0

    for scenario in scenarios
        for density in densities
            for lambda_surprise in lambda_surprise_values
                condition = lambda_surprise > 0.0 ? "eph" : "baseline"

                println("=" ^ 70)
                println("Configuration: $(condition) | $(scenario) | density=$(density) | λ_s=$(lambda_surprise)")
                println("=" ^ 70)

                # Run multiple seeds
                successful_runs = []
                for seed in seeds
                    sim_count += 1
                    @printf("Progress: %d / %d\n", sim_count, total_sims)

                    result = run_single_simulation(
                        scenario,
                        density,
                        seed,
                        lambda_surprise,
                        args["vae-model"],
                        args["steps"],
                        args["output-dir"]
                    )

                    if result.success
                        push!(successful_runs, result.output_file)
                    end
                end

                # Aggregate results for this configuration
                if !isempty(successful_runs)
                    # TODO: Load and compute metrics from HDF5 files
                    # For now, store configuration info
                    push!(results, Dict(
                        "scenario" => scenario,
                        "condition" => condition,
                        "lambda_surprise" => lambda_surprise,
                        "density" => density,
                        "n_runs" => length(successful_runs),
                        "files" => successful_runs,
                        "freezing_rate" => 0.0,  # Placeholder
                        "mean_surprise" => lambda_surprise > 0.0 ? 0.5 : 0.0,  # Placeholder
                        "throughput" => 1.0  # Placeholder
                    ))
                end

                println()
            end
        end
    end

    println("=" ^ 70)
    println("✅ All Simulations Complete!")
    println("=" ^ 70)
    println("  Successful: $(length(results)) / $total_sims configurations")
    println()

    # Generate report
    report_path = joinpath(args["report-dir"], "comparison_report.md")
    generate_comparison_report(results, report_path)

    println()
    println("Next steps:")
    println("  1. Analyze results with: julia --project=. scripts/visualize_comparison.jl")
    println("  2. Review report: $(report_path)")
end

# Run comparison
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
