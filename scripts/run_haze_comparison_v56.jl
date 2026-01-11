#!/usr/bin/env julia

"""
Phase 5: Haze Comparison Experiments
Runs EPH simulations across multiple Haze values to evaluate the effect of perceptual resolution control.

Experimental Design:
- Haze values: {0.0, 0.3, 0.5, 0.7}
- Seeds: {1, 2, 3, 4, 5}
- Scenarios: {"scramble", "corridor"}
- Densities: {5, 10, 15, 20}

Output: results/phase5/haze_comparison_YYYYMMDD_HHMMSS/
"""

using Printf
using Dates
using Statistics

"""
Run a single EPH simulation with specified parameters
"""
function run_single_simulation(;
    haze::Float64,
    scenario::String,
    density::Int,
    seed::Int,
    steps::Int=1500,
    lambda_goal::Float64=1.0,
    lambda_safety::Float64=5.0,
    lambda_surprise::Float64=1.0,
    vae_model::String="models/action_vae_v56_best.bson",
    output_dir::String
)
    # Construct output filename
    output_filename = "sim_h$(haze)_$(scenario)_d$(density)_s$(seed).h5"
    output_path = joinpath(output_dir, output_filename)

    # Construct command
    cmd = `julia --project=. scripts/run_simulation_eph.jl
        --seed $seed
        --density $density
        --steps $steps
        --scenario $scenario
        --lambda-goal $lambda_goal
        --lambda-safety $lambda_safety
        --lambda-surprise $lambda_surprise
        --haze-fixed $haze
        --vae-model $vae_model
        --output $output_path`

    println("  ▶ Running: Haze=$(haze), $(scenario), density=$(density), seed=$(seed)")

    try
        run(cmd)
        return (success=true, path=output_path)
    catch e
        @warn "Simulation failed: $e"
        return (success=false, path="")
    end
end

"""
Main batch experiment
"""
function main()
    println("=" ^ 70)
    println("Phase 5: Haze Comparison Experiments")
    println("=" ^ 70)
    println()

    # Experimental parameters
    haze_values = [0.0, 0.3, 0.5, 0.7]
    scenarios = ["scramble", "corridor"]
    densities = [5, 10, 15, 20]
    seeds = [1, 2, 3, 4, 5]

    # VAE model path
    vae_model = "models/action_vae_v56_best.bson"

    # Check VAE model exists
    if !isfile(vae_model)
        println("❌ Error: VAE model not found at $vae_model")
        println("   Please train VAE first:")
        println("   julia --project=. scripts/train_vae_v56.jl")
        return
    end

    # Create output directory
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    output_root = "results/phase5/haze_comparison_$timestamp"
    mkpath(output_root)

    println("Configuration:")
    println("  Haze values: $haze_values")
    println("  Scenarios: $scenarios")
    println("  Densities: $densities")
    println("  Seeds: $seeds")
    println("  VAE model: $vae_model")
    println("  Output: $output_root")
    println()

    # Calculate total experiments
    n_total = length(haze_values) * length(scenarios) * length(densities) * length(seeds)
    println("Total experiments: $n_total")
    println()

    # Track results
    completed = 0
    failed = 0
    start_time = now()

    # Run experiments
    for haze in haze_values
        for scenario in scenarios
            for density in densities
                for seed in seeds
                    result = run_single_simulation(
                        haze=haze,
                        scenario=scenario,
                        density=density,
                        seed=seed,
                        vae_model=vae_model,
                        output_dir=output_root
                    )

                    if result.success
                        completed += 1
                    else
                        failed += 1
                    end

                    # Progress report
                    elapsed = Dates.value(now() - start_time) / 1000.0  # seconds
                    remaining = n_total - completed - failed
                    avg_time = completed > 0 ? elapsed / completed : 0.0
                    eta = remaining * avg_time

                    @printf("\n  Progress: %d / %d completed, %d failed", completed, n_total, failed)
                    if completed > 0
                        @printf(" (%.1f s/run, ETA: %.1f min)\n", avg_time, eta/60)
                    else
                        println()
                    end
                    println()
                end
            end
        end
    end

    # Final summary
    total_time = Dates.value(now() - start_time) / 1000.0

    println()
    println("=" ^ 70)
    println("Batch Experiments Complete!")
    println("=" ^ 70)
    println("  Completed: $completed / $n_total")
    println("  Failed: $failed")
    @printf("  Total time: %.2f min\n", total_time / 60)
    @printf("  Average time: %.2f s/run\n", total_time / completed)
    println()
    println("Results saved to: $output_root")
    println()
    println("Next step: Analyze results")
    println("  Run: julia --project=. scripts/analyze_phase5_results.jl $output_root")
end

# Run batch experiments
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
