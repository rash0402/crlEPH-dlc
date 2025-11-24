"""
Phase 2 Parameter Sensitivity Analysis

Tests different combinations of Phase 2 parameters to find optimal settings:
- haze_deposit_amount: [0.05, 0.1, 0.2, 0.3]
- haze_decay_rate: [0.95, 0.97, 0.99]
- haze_deposit_type: [:lubricant, :repellent]

Usage:
    julia --project=. parameter_sensitivity_phase2.jl
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EnvironmentalHaze
using .EPH
using .Simulation
using .SPMPredictor
using Statistics
using Random
using JSON
using Dates

println("╔════════════════════════════════════════════════════════════╗")
println("║  Phase 2 Parameter Sensitivity Analysis                   ║")
println("╚════════════════════════════════════════════════════════════╝")
println()

# Experiment settings
num_steps = 500
num_agents = 5

# Parameter ranges
deposit_amounts = [0.05, 0.1, 0.2, 0.3]
decay_rates = [0.95, 0.97, 0.99]
haze_types = [:lubricant, :repellent]

# Results storage
all_results = []

# Fixed initial positions for reproducibility
Random.seed!(42)
initial_positions = [(rand() * 400.0, rand() * 400.0) for _ in 1:num_agents]

total_experiments = length(deposit_amounts) * length(decay_rates) * length(haze_types)
current_exp = 0

println("Total experiments: $total_experiments")
println("Parameters:")
println("  deposit_amounts: $deposit_amounts")
println("  decay_rates: $decay_rates")
println("  haze_types: $haze_types")
println()

for haze_type in haze_types
    for decay_rate in decay_rates
        for deposit_amount in deposit_amounts
            global current_exp += 1

            println("═══════════════════════════════════════════════════════════")
            println("Experiment $current_exp/$total_experiments")
            println("  Type: $haze_type")
            println("  Deposit: $deposit_amount")
            println("  Decay: $decay_rate")
            println("═══════════════════════════════════════════════════════════")

            # Setup parameters
            params = Types.EPHParams(
                predictor_type = :linear,
                collect_data = false,
                Ω_threshold = 0.12,
                enable_env_haze = true,
                haze_deposit_amount = deposit_amount,
                haze_decay_rate = decay_rate,
                haze_deposit_type = haze_type
            )

            # Setup environment
            env = Types.Environment(400.0, 400.0, grid_size=20)

            # Add agents with fixed positions
            for (i, (x, y)) in enumerate(initial_positions)
                agent = Types.Agent(i, x, y, color=(100, 150, 255))
                push!(env.agents, agent)
            end

            predictor = SPMPredictor.LinearPredictor(env.dt)

            # Tracking
            coverage_history = Float64[]
            separation_history = Float64[]
            self_haze_history = Float64[]
            env_haze_history = Float64[]

            # Run simulation
            for step in 1:num_steps
                Simulation.step!(env, params, predictor)

                if step % 10 == 0
                    # Coverage
                    coverage = Simulation.compute_coverage(env)
                    push!(coverage_history, coverage)

                    # Separation
                    sep_distances = [sqrt((a.position[1] - b.position[1])^2 + (a.position[2] - b.position[2])^2)
                                     for a in env.agents for b in env.agents if a.id < b.id]
                    avg_sep = mean(sep_distances)
                    push!(separation_history, avg_sep)

                    # Self-haze
                    avg_haze = mean([a.self_haze for a in env.agents])
                    push!(self_haze_history, avg_haze)

                    # Env haze
                    total_env_haze = sum(env.haze_grid)
                    push!(env_haze_history, total_env_haze)
                end
            end

            # Final metrics
            final_coverage = Simulation.compute_coverage(env)
            final_sep = mean(separation_history)
            final_self_haze = mean(self_haze_history)
            final_env_haze = mean(env_haze_history)

            result = Dict(
                "haze_type" => string(haze_type),
                "deposit_amount" => deposit_amount,
                "decay_rate" => decay_rate,
                "final_coverage" => final_coverage,
                "avg_separation" => final_sep,
                "avg_self_haze" => final_self_haze,
                "avg_env_haze" => final_env_haze,
                "coverage_history" => coverage_history,
                "separation_history" => separation_history,
                "self_haze_history" => self_haze_history,
                "env_haze_history" => env_haze_history
            )

            push!(all_results, result)

            println("Results:")
            println("  Coverage: $(round(final_coverage * 100, digits=1))%")
            println("  Separation: $(round(final_sep, digits=1))px")
            println("  Self-Haze: $(round(final_self_haze, digits=3))")
            println("  Env Haze: $(round(final_env_haze, digits=1))")
            println()
        end
    end
end

# Save results
output_dir = joinpath(@__DIR__, "../data/analysis")
mkpath(output_dir)

timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
output_file = joinpath(output_dir, "phase2_sensitivity_$(timestamp).json")

results_json = Dict(
    "metadata" => Dict(
        "timestamp" => timestamp,
        "num_steps" => num_steps,
        "num_agents" => num_agents,
        "experiment_type" => "phase2_parameter_sensitivity"
    ),
    "results" => all_results
)

open(output_file, "w") do io
    JSON.print(io, results_json, 2)
end

println("═══════════════════════════════════════════════════════════")
println("  Analysis Complete!")
println("═══════════════════════════════════════════════════════════")
println()
println("Results saved to: $output_file")
println()

# Find best configuration
best_coverage = maximum([r["final_coverage"] for r in all_results])
best_result = filter(r -> r["final_coverage"] == best_coverage, all_results)[1]

println("Best Configuration (by Coverage):")
println("  Type: $(best_result["haze_type"])")
println("  Deposit: $(best_result["deposit_amount"])")
println("  Decay: $(best_result["decay_rate"])")
println("  Coverage: $(round(best_result["final_coverage"] * 100, digits=1))%")
println("  Env Haze: $(round(best_result["avg_env_haze"], digits=1))")
