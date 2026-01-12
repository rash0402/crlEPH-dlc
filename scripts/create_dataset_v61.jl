#!/usr/bin/env julia
"""
VAE Training Data Collection for v6.1: Bin 1-6 Haze=0 Fixed Strategy

Purpose:
  Generate training dataset for Action-Conditioned VAE (Pattern D) with:
  - D_max = 8.0m (2³, mathematical elegance + biological validity)
  - Bin 1-6 Haze=0 Fixed (step function, no sigmoid blending)
  - Multiple density conditions (5, 10, 15, 20 agents/group)
  - Multiple random seeds for diversity

Output:
  - Raw logs: data/vae_training/raw/v61_density{D}_seed{S}_YYYYMMDD_HHMMSS.h5
  - Unified dataset: data/vae_training/dataset_v61.h5
    - Train: 70% (densities 5/10/15, seeds 1-3)
    - Val: 15% (densities 5/10/15, seed 4)
    - Test: 10% (densities 5/10/15, seed 5)
    - OOD: 5% (density 20, seed 1)

Estimated time: ~6 hours (GPU recommended for training phase)
Target samples: 50,000 triplets (y[k], u[k], y[k+1])
"""

using Pkg
Pkg.activate(".")

using Printf
using Statistics
using HDF5
using Dates
using Random

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
println("VAE Training Data Collection for v6.1: Bin 1-6 Haze=0 Fixed")
println("="^80)
println()

# Configuration
const OUTPUT_DIR = joinpath(@__DIR__, "../data/vae_training/raw")
mkpath(OUTPUT_DIR)

# Simulation parameters
const MAX_STEPS = 3000  # 100 seconds @ 30Hz
const DENSITIES = [5, 10, 15, 20]  # agents per group (4 groups total)
const N_SEEDS_PER_DENSITY = 5  # For diversity

# v6.1 SPM and Foveation parameters
const V61_SPM_PARAMS = SPMParams(sensing_ratio=8.0)  # D_max = 8.0m (2³)
const V61_FOV_PARAMS = FoveationParams(
    rho_index_critical=6,  # Bin 1-6 (0-2.18m)
    h_critical=0.0,         # Haze=0.0 in critical zone
    h_peripheral=0.5        # Haze=0.5 in peripheral zone
)

"""
Run single simulation and save log
"""
function run_single_simulation(
    density::Int,
    seed::Int
)
    Random.seed!(seed)

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    log_filename = "v61_density$(density)_seed$(seed)_$(timestamp).h5"
    log_path = joinpath(OUTPUT_DIR, log_filename)

    println("  Density=$density, Seed=$seed")
    println("    Output: $log_filename")

    # Initialize world and agents
    world_params = WorldParams(max_steps=MAX_STEPS)
    agent_params = AgentParams(n_agents_per_group=density)
    control_params = ControlParams(use_vae=false)  # No VAE during data collection

    # Initialize SPM config with D_max=8.0m
    spm_config = init_spm(V61_SPM_PARAMS)

    # Create scenario: scramble crossing (4-group)
    agents = create_scramble_crossing(agent_params, world_params)

    # Initialize logger
    logger = Logger.init_logger(log_path, agent_params, world_params, spm_config)

    # Tracking metrics
    collision_count = 0
    freezing_count = 0

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

            # Compute action (v6.1 with Bin 1-6 Haze=0)
            u = compute_action_v61(
                agent,
                spm_current,
                other_agents,
                nothing,  # No VAE during data collection
                control_params,
                agent_params,
                world_params,
                spm_config,
                d_pref,
                1.0,  # precision (not used without VAE)
                control_params.k_2,
                control_params.k_3;
                rho_index_critical=V61_FOV_PARAMS.rho_index_critical,
                h_critical=V61_FOV_PARAMS.h_critical,
                h_peripheral=V61_FOV_PARAMS.h_peripheral
            )

            # Apply action
            agent.u = u

            # Check for collision
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
        end

        # Log current state
        Logger.log_step!(logger, agents, step)

        # Update dynamics
        agents = step_dynamics(agents, world_params, agent_params)
    end

    # Finalize log
    Logger.finalize_logger!(logger)

    # Compute metrics
    total_agent_steps = length(agents) * MAX_STEPS
    collision_rate = 100.0 * collision_count / total_agent_steps
    freezing_rate = 100.0 * freezing_count / total_agent_steps

    println("    Collision rate: $(round(collision_rate, digits=2))%")
    println("    Freezing rate: $(round(freezing_rate, digits=2))%")
    println("    ✅ Saved: $log_path")

    return log_path, Dict(
        "collision_rate" => collision_rate,
        "freezing_rate" => freezing_rate
    )
end

"""
Extract (SPM[k], action[k], SPM[k+1]) samples from HDF5 log
"""
function extract_samples_from_log(
    filepath::String;
    step_interval::Int=5,
    max_agents_per_step::Int=3,
    max_samples_per_file::Int=5000
)
    samples = []

    h5open(filepath, "r") do file
        # Read data: (n_steps, n_agents, ...)
        spm_data = read(file, "/data/spm")       # (n_steps, n_agents, 16, 16, 3)
        action_data = read(file, "/data/actions") # (n_steps, n_agents, 2)

        n_steps, n_agents, _, _, _ = size(spm_data)

        sample_count = 0

        # Sample every `step_interval` steps to avoid temporal redundancy
        for step in 1:step_interval:(n_steps-1)
            if sample_count >= max_samples_per_file
                break
            end

            # Randomly select subset of agents for diversity
            n_sample_agents = min(max_agents_per_step, n_agents)
            sampled_agents = sort(rand(1:n_agents, n_sample_agents))

            for agent_id in sampled_agents
                spm_current = Float32.(spm_data[step, agent_id, :, :, :])
                action = Float32.(action_data[step, agent_id, :])
                spm_next = Float32.(spm_data[step+1, agent_id, :, :, :])

                push!(samples, (spm_current, action, spm_next))
                sample_count += 1

                if sample_count >= max_samples_per_file
                    break
                end
            end
        end
    end

    return samples
end

# Main execution
println("Starting data collection...")
println("  Densities: $DENSITIES")
println("  Seeds per density: $N_SEEDS_PER_DENSITY")
println("  Steps per simulation: $MAX_STEPS")
println("  Output directory: $OUTPUT_DIR")
println()

all_logs = []
all_metrics = []

for density in DENSITIES
    for seed in 1:N_SEEDS_PER_DENSITY
        log_path, metrics = run_single_simulation(density, seed)
        push!(all_logs, (density, seed, log_path))
        push!(all_metrics, metrics)
    end
    println()
end

println("="^80)
println("Data Collection Summary")
println("="^80)
println("  Total simulations: $(length(all_logs))")
println("  Total log files: $(length(all_logs))")
println()

# Aggregate metrics
avg_collision = mean([m["collision_rate"] for m in all_metrics])
avg_freezing = mean([m["freezing_rate"] for m in all_metrics])
@printf("  Average collision rate: %.2f%%\n", avg_collision)
@printf("  Average freezing rate: %.2f%%\n", avg_freezing)
println()

# Extract samples and create unified dataset
println("="^80)
println("Creating Unified Dataset")
println("="^80)
println()

train_samples = []
val_samples = []
test_samples = []
ood_samples = []

for (density, seed, log_path) in all_logs
    println("  Extracting samples from: $(basename(log_path))")
    samples = extract_samples_from_log(log_path)
    println("    Extracted $(length(samples)) samples")

    # Data split logic
    if density in [5, 10, 15]
        if seed in [1, 2, 3]
            append!(train_samples, samples)  # Train: 70%
        elseif seed == 4
            append!(val_samples, samples)    # Val: 15%
        elseif seed == 5
            append!(test_samples, samples)   # Test: 10%
        end
    elseif density == 20 && seed == 1
        append!(ood_samples, samples)        # OOD: 5%
    end
end

println()
println("Dataset splits:")
@printf("  Train: %d samples (%.1f%%)\n", length(train_samples),
        100.0 * length(train_samples) / (length(train_samples) + length(val_samples) + length(test_samples) + length(ood_samples)))
@printf("  Val: %d samples (%.1f%%)\n", length(val_samples),
        100.0 * length(val_samples) / (length(train_samples) + length(val_samples) + length(test_samples) + length(ood_samples)))
@printf("  Test: %d samples (%.1f%%)\n", length(test_samples),
        100.0 * length(test_samples) / (length(train_samples) + length(val_samples) + length(test_samples) + length(ood_samples)))
@printf("  OOD: %d samples (%.1f%%)\n", length(ood_samples),
        100.0 * length(ood_samples) / (length(train_samples) + length(val_samples) + length(test_samples) + length(ood_samples)))
println()

# Save unified dataset
dataset_path = joinpath(@__DIR__, "../data/vae_training/dataset_v61.h5")
mkpath(dirname(dataset_path))

println("Saving unified dataset: $dataset_path")

h5open(dataset_path, "w") do file
    # Helper function to save samples
    function save_split(split_name, samples)
        if isempty(samples)
            return
        end

        n_samples = length(samples)

        # Stack samples into arrays
        spm_current_arr = zeros(Float32, n_samples, 16, 16, 3)
        action_arr = zeros(Float32, n_samples, 2)
        spm_next_arr = zeros(Float32, n_samples, 16, 16, 3)

        for (i, (spm_curr, act, spm_nxt)) in enumerate(samples)
            spm_current_arr[i, :, :, :] = spm_curr
            action_arr[i, :] = act
            spm_next_arr[i, :, :, :] = spm_nxt
        end

        # Create group and write
        g = create_group(file, split_name)
        g["spm_current"] = spm_current_arr
        g["actions"] = action_arr
        g["spm_next"] = spm_next_arr
    end

    save_split("train", train_samples)
    save_split("val", val_samples)
    save_split("test", test_samples)
    save_split("ood", ood_samples)

    # Metadata
    attributes(file)["creation_date"] = string(now())
    attributes(file)["version"] = "v6.1"
    attributes(file)["d_max"] = 8.0
    attributes(file)["rho_index_critical"] = 6
    attributes(file)["h_critical"] = 0.0
    attributes(file)["h_peripheral"] = 0.5
    attributes(file)["n_train"] = length(train_samples)
    attributes(file)["n_val"] = length(val_samples)
    attributes(file)["n_test"] = length(test_samples)
    attributes(file)["n_ood"] = length(ood_samples)
end

println("✅ Saved: $dataset_path")
println()

println("="^80)
println("Data Collection Complete")
println("="^80)
println()
println("Next steps:")
println("  1. Train VAE: julia --project=. scripts/train_action_vae_v61.jl")
println("  2. Validate: Check reconstruction quality (MSE < 0.05)")
println("  3. Integrate: Update models/action_vae_best.bson with new model")
println("="^80)
