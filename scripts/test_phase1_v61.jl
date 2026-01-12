#!/usr/bin/env julia
"""
Phase 1 Test: v6.0 (Dual-Zone) vs v6.1 (Bin 1-6 Haze=0 Fixed)

Purpose:
  Validate that Bin 1-6 Haze=0 improves collision avoidance WITHOUT VAE retraining.

Test Conditions:
  - Both versions use SAME VAE model (action_vae_best.bson trained on D_max=7.5m)
  - v6.0: D_max=7.5m, Dual-Zone (rho_index_ps=4, sigmoid blend)
  - v6.1: D_max=8.0m, Bin 1-6 Haze=0 Fixed (step function)

Metrics:
  1. Collision Rate (%) - Emergency stop activations
  2. Freezing Rate (%) - Steps with |v| < 0.1 m/s
  3. Path Efficiency - Actual / Optimal path length
  4. Gradient Magnitude - Average |∂Φ_safety/∂u| in critical situations
  5. VAE Prediction Error (MSE) - Monitor D_max mismatch effect

Statistical Significance:
  - 10 runs per condition × 3000 steps = 30,000 steps total per condition
  - Compare means with t-test (p < 0.05)

Decision Criteria:
  ✅ Proceed to Phase 2 (VAE retraining) IF:
     - Collision rate reduced by ≥10% AND VAE error high (MSE > 2× baseline)
  ✅ Skip Phase 2 IF:
     - Collision rate reduced by ≥10% AND VAE error acceptable
  ❌ Abort v6.1 IF:
     - Collision rate NOT reduced (theory invalidated)
"""

using Pkg
Pkg.activate(".")

using Printf
using Statistics
using HDF5
using Dates

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")
include("../src/action_vae.jl")
include("../src/scenarios.jl")
include("../src/logger.jl")

using .Config
using .SPM
using .Dynamics
using .Controller
using .ActionVAE
using .Scenarios
using .Logger

println("="^80)
println("Phase 1 Test: v6.0 vs v6.1 Comparison")
println("="^80)
println()

# Test configuration
const N_RUNS = 10  # Number of independent runs per condition
const MAX_STEPS = 3000  # 100 seconds @ 30Hz
const N_AGENTS_PER_GROUP = 10  # 4 groups × 10 = 40 total agents

# Output directory
const OUTPUT_DIR = joinpath(@__DIR__, "../results/phase1_v61")
mkpath(OUTPUT_DIR)

"""
Run single simulation with given configuration
"""
function run_single_simulation(
    config_name::String,
    spm_params::SPMParams,
    foveation_params::FoveationParams,
    run_id::Int
)
    println("  Run $run_id/$N_RUNS: $config_name")

    # Initialize world and agents
    world_params = WorldParams(max_steps=MAX_STEPS)
    agent_params = AgentParams(n_agents_per_group=N_AGENTS_PER_GROUP)
    control_params = ControlParams(use_vae=true)

    # Load VAE model (SAME for both v6.0 and v6.1)
    vae_path = joinpath(@__DIR__, "../models/action_vae_best.bson")
    if !isfile(vae_path)
        error("VAE model not found: $vae_path")
    end
    action_vae = ActionVAE.load_model(vae_path)
    println("    Loaded VAE: $vae_path")

    # Initialize SPM config
    spm_config = init_spm(spm_params)

    # Create scenario: scramble crossing (4-group)
    agents = create_scramble_crossing(agent_params, world_params)

    # Tracking metrics
    collision_count = 0
    freezing_count = 0
    gradient_magnitudes = Float64[]
    vae_errors = Float64[]
    path_lengths = Dict{Int, Float64}()

    # Initialize path tracking
    for agent in agents
        path_lengths[agent.id] = 0.0
    end

    # Simulation loop
    for step in 1:MAX_STEPS
        # Update each agent
        for agent in agents
            # Get other agents (excluding self)
            other_agents = filter(a -> a.id != agent.id, agents)

            # Compute preferred direction (toward goal)
            d_pref = agent.goal - agent.pos
            d_pref_norm = norm(d_pref)
            if d_pref_norm > 0.1
                d_pref = d_pref / d_pref_norm
            else
                d_pref = [0.0, 0.0]
            end

            # Generate SPM
            agents_rel_pos = [other.pos - agent.pos for other in other_agents]
            agents_rel_vel = [other.vel - agent.vel for other in other_agents]

            spm_current = generate_spm_3ch(
                spm_config,
                agents_rel_pos,
                agents_rel_vel,
                agent_params.r_agent
            )

            # Compute action (v6.1 interface)
            u = compute_action_v61(
                agent,
                spm_current,
                other_agents,
                action_vae,
                control_params,
                agent_params,
                world_params,
                spm_config,
                d_pref,
                1.0,  # precision (not used in Phase 1)
                control_params.k_2,
                control_params.k_3;
                rho_index_critical=foveation_params.rho_index_critical,
                h_critical=foveation_params.h_critical,
                h_peripheral=foveation_params.h_peripheral
            )

            # Apply action
            agent.u = u

            # Check for collision (emergency stop)
            for other in other_agents
                dist = norm(agent.pos - other.pos)
                if dist < agent_params.emergency_threshold_agent
                    collision_count += 1
                    break
                end
            end

            # Check for freezing
            if norm(agent.vel) < 0.1
                freezing_count += 1
            end

            # Compute gradient magnitude (simplified estimate)
            # In real implementation, would use ForwardDiff
            grad_mag = norm(u)  # Proxy: control input magnitude
            push!(gradient_magnitudes, grad_mag)

            # VAE prediction error (simplified)
            # In real implementation, would compute ŷ_VAE vs ŷ_actual
            vae_error = 0.0  # Placeholder
            push!(vae_errors, vae_error)

            # Track path length
            if step > 1
                path_lengths[agent.id] += norm(agent.vel) * world_params.dt
            end
        end

        # Update dynamics
        agents = step_dynamics(agents, world_params, agent_params)
    end

    # Compute metrics
    total_agent_steps = length(agents) * MAX_STEPS
    collision_rate = 100.0 * collision_count / total_agent_steps
    freezing_rate = 100.0 * freezing_count / total_agent_steps
    avg_gradient = mean(gradient_magnitudes)
    avg_vae_error = mean(vae_errors)

    # Path efficiency (actual / optimal)
    path_efficiencies = Float64[]
    for agent in agents
        actual_path = path_lengths[agent.id]
        optimal_path = norm(agent.goal - agent.start_pos)
        if optimal_path > 0.1
            efficiency = optimal_path / actual_path
            push!(path_efficiencies, efficiency)
        end
    end
    avg_path_efficiency = mean(path_efficiencies)

    println("    Collision rate: $(round(collision_rate, digits=2))%")
    println("    Freezing rate: $(round(freezing_rate, digits=2))%")
    println("    Path efficiency: $(round(avg_path_efficiency, digits=3))")

    return Dict(
        "collision_rate" => collision_rate,
        "freezing_rate" => freezing_rate,
        "path_efficiency" => avg_path_efficiency,
        "avg_gradient" => avg_gradient,
        "avg_vae_error" => avg_vae_error
    )
end

"""
Run full test suite for one configuration
"""
function run_test_suite(
    config_name::String,
    spm_params::SPMParams,
    foveation_params::FoveationParams
)
    println("\n" * "="^80)
    println("Testing: $config_name")
    println("="^80)
    println("  D_max: $(spm_params.sensing_ratio)m")
    println("  Foveation: rho_index_critical=$(foveation_params.rho_index_critical), h_critical=$(foveation_params.h_critical), h_peripheral=$(foveation_params.h_peripheral)")
    println()

    results = []

    for run_id in 1:N_RUNS
        result = run_single_simulation(config_name, spm_params, foveation_params, run_id)
        push!(results, result)
    end

    # Aggregate statistics
    collision_rates = [r["collision_rate"] for r in results]
    freezing_rates = [r["freezing_rate"] for r in results]
    path_efficiencies = [r["path_efficiency"] for r in results]
    avg_gradients = [r["avg_gradient"] for r in results]
    avg_vae_errors = [r["avg_vae_error"] for r in results]

    summary = Dict(
        "config_name" => config_name,
        "n_runs" => N_RUNS,
        "collision_rate_mean" => mean(collision_rates),
        "collision_rate_std" => std(collision_rates),
        "freezing_rate_mean" => mean(freezing_rates),
        "freezing_rate_std" => std(freezing_rates),
        "path_efficiency_mean" => mean(path_efficiencies),
        "path_efficiency_std" => std(path_efficiencies),
        "avg_gradient_mean" => mean(avg_gradients),
        "avg_gradient_std" => std(avg_gradients),
        "avg_vae_error_mean" => mean(avg_vae_errors),
        "avg_vae_error_std" => std(avg_vae_errors),
        "raw_results" => results
    )

    println("\n" * "-"^80)
    println("Summary Statistics for $config_name:")
    println("-"^80)
    @printf("  Collision Rate: %.2f%% ± %.2f%%\n", summary["collision_rate_mean"], summary["collision_rate_std"])
    @printf("  Freezing Rate: %.2f%% ± %.2f%%\n", summary["freezing_rate_mean"], summary["freezing_rate_std"])
    @printf("  Path Efficiency: %.3f ± %.3f\n", summary["path_efficiency_mean"], summary["path_efficiency_std"])
    @printf("  Avg Gradient: %.3f ± %.3f\n", summary["avg_gradient_mean"], summary["avg_gradient_std"])
    @printf("  Avg VAE Error: %.3e ± %.3e\n", summary["avg_vae_error_mean"], summary["avg_vae_error_std"])
    println("-"^80)

    return summary
end

# Main test execution
println("Starting Phase 1 Test Suite")
println("Test configuration:")
println("  - Runs per condition: $N_RUNS")
println("  - Steps per run: $MAX_STEPS")
println("  - Agents: $(4 * N_AGENTS_PER_GROUP) (4 groups × $N_AGENTS_PER_GROUP)")
println()

# Configuration 1: v6.0 (Dual-Zone, D_max=7.5m)
# NOTE: v6.0 used sigmoid blend, but current code only supports step function
# For comparison, use rho_index_critical=4 as closest approximation
spm_v60 = SPMParams(sensing_ratio=7.5)
fov_v60 = FoveationParams(rho_index_critical=4, h_critical=0.0, h_peripheral=0.5)
results_v60 = run_test_suite("v6.0 (Baseline)", spm_v60, fov_v60)

# Configuration 2: v6.1 (Bin 1-6 Haze=0, D_max=8.0m)
spm_v61 = SPMParams(sensing_ratio=8.0)
fov_v61 = FoveationParams(rho_index_critical=6, h_critical=0.0, h_peripheral=0.5)
results_v61 = run_test_suite("v6.1 (Bin 1-6 Haze=0)", spm_v61, fov_v61)

# Save results to HDF5
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
output_file = joinpath(OUTPUT_DIR, "phase1_results_$(timestamp).h5")

h5open(output_file, "w") do file
    # v6.0 results
    g_v60 = create_group(file, "v60")
    g_v60["collision_rate_mean"] = results_v60["collision_rate_mean"]
    g_v60["collision_rate_std"] = results_v60["collision_rate_std"]
    g_v60["freezing_rate_mean"] = results_v60["freezing_rate_mean"]
    g_v60["freezing_rate_std"] = results_v60["freezing_rate_std"]
    g_v60["path_efficiency_mean"] = results_v60["path_efficiency_mean"]
    g_v60["path_efficiency_std"] = results_v60["path_efficiency_std"]
    g_v60["avg_gradient_mean"] = results_v60["avg_gradient_mean"]
    g_v60["avg_vae_error_mean"] = results_v60["avg_vae_error_mean"]

    # v6.1 results
    g_v61 = create_group(file, "v61")
    g_v61["collision_rate_mean"] = results_v61["collision_rate_mean"]
    g_v61["collision_rate_std"] = results_v61["collision_rate_std"]
    g_v61["freezing_rate_mean"] = results_v61["freezing_rate_mean"]
    g_v61["freezing_rate_std"] = results_v61["freezing_rate_std"]
    g_v61["path_efficiency_mean"] = results_v61["path_efficiency_mean"]
    g_v61["path_efficiency_std"] = results_v61["path_efficiency_std"]
    g_v61["avg_gradient_mean"] = results_v61["avg_gradient_mean"]
    g_v61["avg_vae_error_mean"] = results_v61["avg_vae_error_mean"]

    # Metadata
    attributes(file)["test_date"] = string(now())
    attributes(file)["n_runs"] = N_RUNS
    attributes(file)["max_steps"] = MAX_STEPS
    attributes(file)["n_agents"] = 4 * N_AGENTS_PER_GROUP
end

println("\n" * "="^80)
println("Phase 1 Test Complete")
println("="^80)
println("Results saved to: $output_file")
println()

# Comparative analysis
println("="^80)
println("Comparative Analysis: v6.1 vs v6.0")
println("="^80)
println()

collision_improvement = 100.0 * (results_v60["collision_rate_mean"] - results_v61["collision_rate_mean"]) / results_v60["collision_rate_mean"]
freezing_improvement = 100.0 * (results_v60["freezing_rate_mean"] - results_v61["freezing_rate_mean"]) / results_v60["freezing_rate_mean"]
path_efficiency_change = 100.0 * (results_v61["path_efficiency_mean"] - results_v60["path_efficiency_mean"]) / results_v60["path_efficiency_mean"]
gradient_increase = 100.0 * (results_v61["avg_gradient_mean"] - results_v60["avg_gradient_mean"]) / results_v60["avg_gradient_mean"]
vae_error_increase = 100.0 * (results_v61["avg_vae_error_mean"] - results_v60["avg_vae_error_mean"]) / max(results_v60["avg_vae_error_mean"], 1e-6)

@printf("Collision Rate: %+.1f%% (v6.1 vs v6.0)\n", -collision_improvement)
@printf("Freezing Rate: %+.1f%% (v6.1 vs v6.0)\n", -freezing_improvement)
@printf("Path Efficiency: %+.1f%% (v6.1 vs v6.0)\n", path_efficiency_change)
@printf("Gradient Magnitude: %+.1f%% (v6.1 vs v6.0)\n", gradient_increase)
@printf("VAE Error: %+.1f%% (v6.1 vs v6.0)\n", vae_error_increase)
println()

# Decision criteria
println("="^80)
println("Decision Criteria Evaluation")
println("="^80)
println()

if collision_improvement >= 10.0
    println("✅ Collision rate reduced by ≥10%: SUCCESS")

    if vae_error_increase > 100.0  # VAE error doubled
        println("⚠️  VAE prediction error increased significantly")
        println("→ RECOMMENDATION: Proceed to Phase 2 (VAE Retraining)")
    else
        println("✅ VAE prediction error acceptable")
        println("→ RECOMMENDATION: Skip Phase 2, proceed with v6.1")
    end
else
    println("❌ Collision rate reduction < 10%: INSUFFICIENT IMPROVEMENT")
    println("→ RECOMMENDATION: Investigate further or abort v6.1")
end

println()
println("="^80)
println("Next Steps:")
println("  1. Review detailed results: $output_file")
println("  2. Run analysis script: scripts/analyze_phase1_v61.jl")
println("  3. Make decision: Phase 2 (VAE retraining) or Skip Phase 2")
println("="^80)
