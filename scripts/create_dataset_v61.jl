#!/usr/bin/env julia
"""
VAE Training Data Collection for v6.1: Bin 1-6 Haze=0 Fixed Strategy

Purpose:
  Generate diverse training dataset for Action-Conditioned VAE (Pattern D) with:
  - D_max = 8.0m (2³, mathematical elegance + biological validity)
  - Bin 1-6 Haze=0 Fixed (step function, no sigmoid blending)
  - Multiple scenarios: Scramble crossing + Corridor (narrow passage)
  - Multiple density conditions: 5, 10, 15, 20 agents/group
  - Corridor width variation: 3.0m (narrow), 4.0m (medium), 5.0m (wide)
  - Exploration noise for action diversity: 0.3 std
  - 5 random seeds per condition

Output:
  - Raw logs: data/vae_training/raw/v61_{scenario}_d{density}_s{seed}_YYYYMMDD_HHMMSS.h5
  - Unified dataset: data/vae_training/dataset_v61.h5
    - Train: 70% (densities 5/10/15, seeds 1-3, all scenarios)
    - Val: 15% (densities 5/10/15, seed 4, all scenarios)
    - Test: 10% (densities 5/10/15, seed 5, all scenarios)
    - OOD: 5% (density 20, seed 1, all scenarios)

Estimated time: ~10 hours (2 scenarios × 4 densities × 5 seeds × ~15 min/run)
Target samples: 50,000-70,000 triplets (y[k], u[k], y[k+1])
"""

using Pkg
Pkg.activate(".")

using Printf
using Statistics
using HDF5
using Dates
using Random
using LinearAlgebra
using ArgParse

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/prediction.jl")  # Required by controller.jl
include("../src/action_vae.jl")  # Required by controller.jl (must be before controller)
include("../src/controller.jl")
include("../src/scenarios.jl")
include("../src/logger.jl")

using .Config
using .SPM
using .Dynamics
using .Prediction
using .Controller
using .ActionVAEModel
using .Scenarios
using .Logger

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings(description="VAE Training Data Collection for v6.1")

    @add_arg_table! s begin
        "--scenario"
            help = "Scenario type: 'scramble', 'corridor', or 'both'"
            arg_type = String
            default = "both"
        "--densities"
            help = "Agent densities (comma-separated, e.g., '5,10,15,20')"
            arg_type = String
            default = "5,10,15,20"
        "--seeds"
            help = "Random seeds (range format, e.g., '1:5')"
            arg_type = String
            default = "1:5"
        "--steps"
            help = "Simulation steps per run"
            arg_type = Int
            default = 3000
        "--corridor-widths"
            help = "Corridor widths in meters (comma-separated, e.g., '3.0,4.0,5.0')"
            arg_type = String
            default = "3.0,4.0,5.0"
        "--exploration-noise"
            help = "Exploration noise std for action diversity"
            arg_type = Float64
            default = 0.3
        "--output-dir"
            help = "Output directory for raw logs"
            arg_type = String
            default = "data/vae_training/raw"
        "--dry-run"
            help = "Test mode: only 100 steps"
            action = :store_true
    end

    return parse_args(s)
end

println("="^80)
println("VAE Training Data Collection for v6.1: Bin 1-6 Haze=0 Fixed")
println("="^80)
println()

# Parse arguments
args = parse_commandline()

# Configuration
const OUTPUT_DIR = args["output-dir"]
mkpath(OUTPUT_DIR)

const SCENARIOS = args["scenario"] == "both" ? ["scramble", "corridor"] : [args["scenario"]]
const DENSITIES = parse.(Int, split(args["densities"], ","))
const SEEDS_RANGE = let
    range_str = args["seeds"]
    if contains(range_str, ":")
        start_end = parse.(Int, split(range_str, ":"))
        collect(start_end[1]:start_end[2])
    else
        parse.(Int, split(range_str, ","))
    end
end
const MAX_STEPS = args["dry-run"] ? 100 : args["steps"]
const CORRIDOR_WIDTHS = parse.(Float64, split(args["corridor-widths"], ","))
const EXPLORATION_NOISE = args["exploration-noise"]

# v6.1 SPM and Foveation parameters
const V61_SPM_PARAMS = SPMParams(sensing_ratio=8.0)  # D_max = 8.0m (2³)
const V61_FOV_PARAMS = FoveationParams(
    rho_index_critical=6,  # Bin 1-6 (0-2.18m)
    h_critical=0.0,         # Haze=0.0 in critical zone
    h_peripheral=0.5        # Haze=0.5 in peripheral zone
)

println("Configuration:")
println("  Scenarios: $(SCENARIOS)")
println("  Densities: $(DENSITIES)")
println("  Seeds: $(SEEDS_RANGE)")
println("  Steps per run: $(MAX_STEPS)")
println("  Corridor widths: $(CORRIDOR_WIDTHS) m")
println("  Exploration noise: $(EXPLORATION_NOISE) std")
println("  D_max: 8.0m")
println("  Foveation: Bin 1-6 Haze=0 Fixed")
println("  Output: $OUTPUT_DIR")
println()

"""
Run single simulation and save log
"""
function run_single_simulation(
    scenario::String,
    density::Int,
    seed::Int,
    corridor_width::Float64=4.0
)
    Random.seed!(seed)

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    scenario_suffix = scenario == "corridor" ? "_w$(Int(round(corridor_width*10)))" : ""
    log_filename = "v61_$(scenario)$(scenario_suffix)_d$(density)_s$(seed)_$(timestamp).h5"
    log_path = joinpath(OUTPUT_DIR, log_filename)

    println("  Scenario=$scenario, Density=$density, Seed=$seed$(scenario == "corridor" ? ", Width=$(corridor_width)m" : "")")
    println("    Output: $log_filename")

    # Initialize world and agents
    world_params = WorldParams(max_steps=MAX_STEPS)
    agent_params = AgentParams(n_agents_per_group=density)
    control_params = ControlParams(use_vae=false)  # No VAE during data collection

    # Initialize SPM config with D_max=8.0m
    spm_config = init_spm(V61_SPM_PARAMS)

    # Create scenario
    if scenario == "scramble"
        scenario_params = ScenarioParams(
            scenario_type=SCRAMBLE_CROSSING,
            num_agents_per_group=density
        )
        agents = initialize_scenario(scenario_params, agent_params, world_params)
        obstacles = []
    elseif scenario == "corridor"
        scenario_params = ScenarioParams(
            scenario_type=CORRIDOR,
            num_agents_per_group=density,
            corridor_width=corridor_width
        )
        agents = initialize_scenario(scenario_params, agent_params, world_params)
        obstacles = get_obstacles(scenario_params)
    else
        error("Unknown scenario: $scenario")
    end

    # Initialize logger (modify to use standard Logger if needed)
    # For now, we'll log manually to HDF5

    # Tracking metrics
    collision_count = 0
    freezing_count = 0

    # Emergency stop tracking (for deadlock avoidance)
    emergency_stop_counters = Dict{Int, Int}(agent.id => 0 for agent in agents)
    EMERGENCY_STOP_TIMEOUT = 20  # Release after 20 steps

    # Data storage
    spm_log = zeros(Float32, MAX_STEPS, length(agents), 16, 16, 3)
    action_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    pos_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    vel_log = zeros(Float32, MAX_STEPS, length(agents), 2)

    # Simulation loop
    for step in 1:MAX_STEPS
        # Update each agent
        for (agent_idx, agent) in enumerate(agents)
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

            # Generate SPM (3 channels)
            agents_rel_pos = [other.pos - agent.pos for other in other_agents]
            agents_rel_vel = [other.vel - agent.vel for other in other_agents]

            # For corridor scenario, add obstacles as static agents
            if scenario == "corridor" && !isempty(obstacles)
                for obs in obstacles
                    obs_pos = [obs[1], obs[2]]
                    obs_rel_pos = obs_pos - agent.pos

                    # Only add if within sensing range
                    if norm(obs_rel_pos) < V61_SPM_PARAMS.sensing_ratio * (V61_SPM_PARAMS.r_robot + agent_params.r_agent)
                        push!(agents_rel_pos, obs_rel_pos)
                        push!(agents_rel_vel, [0.0, 0.0])  # Static obstacle
                    end
                end
            end

            spm_current = generate_spm_3ch(
                spm_config,
                agents_rel_pos,
                agents_rel_vel,
                agent_params.r_agent
            )

            # Compute action (v6.1 with Bin 1-6 Haze=0, no VAE)
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

            # Add exploration noise for action diversity
            if EXPLORATION_NOISE > 0.0
                u = u .+ randn(2) .* EXPLORATION_NOISE
                # Clamp to reasonable range
                u = clamp.(u, -2.0, 2.0)
            end

            # Check for collision and apply emergency stop with deadlock avoidance
            in_collision = false
            for other in other_agents
                dist = norm(agent.pos - other.pos)
                if dist < agent_params.emergency_threshold_agent
                    in_collision = true
                    collision_count += 1
                    break
                end
            end

            # Emergency stop logic with deadlock avoidance
            if in_collision
                emergency_stop_counters[agent.id] += 1

                # If stopped for too long, release with small push toward goal
                if emergency_stop_counters[agent.id] >= EMERGENCY_STOP_TIMEOUT
                    # Small push toward goal to escape deadlock
                    u = 0.1 .* d_pref
                    emergency_stop_counters[agent.id] = 0  # Reset counter
                else
                    # Emergency stop
                    u = [0.0, 0.0]
                end
            else
                # Reset emergency counter when no collision
                emergency_stop_counters[agent.id] = 0
            end

            # Apply action
            agent.u = u

            # Log data
            spm_log[step, agent_idx, :, :, :] = spm_current
            action_log[step, agent_idx, :] = u
            pos_log[step, agent_idx, :] = agent.pos
            vel_log[step, agent_idx, :] = agent.vel

            # Check for freezing
            if norm(agent.vel) < 0.1
                freezing_count += 1
            end
        end

        # Update dynamics
        agents = step_dynamics(agents, world_params, agent_params)
    end

    # Save to HDF5
    h5open(log_path, "w") do file
        g = create_group(file, "data")
        g["spm"] = spm_log
        g["actions"] = action_log
        g["positions"] = pos_log
        g["velocities"] = vel_log

        # Metadata
        attributes(file)["scenario"] = scenario
        attributes(file)["density"] = density
        attributes(file)["seed"] = seed
        attributes(file)["corridor_width"] = scenario == "corridor" ? corridor_width : 0.0
        attributes(file)["d_max"] = 8.0
        attributes(file)["rho_index_critical"] = 6
        attributes(file)["h_critical"] = 0.0
        attributes(file)["h_peripheral"] = 0.5
        attributes(file)["exploration_noise"] = EXPLORATION_NOISE
        attributes(file)["timestamp"] = string(now())
    end

    # Compute metrics
    total_agent_steps = length(agents) * MAX_STEPS
    collision_rate = 100.0 * collision_count / total_agent_steps
    freezing_rate = 100.0 * freezing_count / total_agent_steps

    println("    Collision rate: $(round(collision_rate, digits=2))%")
    println("    Freezing rate: $(round(freezing_rate, digits=2))%")
    println("    ✅ Saved: $log_path")

    return log_path, Dict(
        "collision_rate" => collision_rate,
        "freezing_rate" => freezing_rate,
        "scenario" => scenario,
        "density" => density,
        "seed" => seed
    )
end

"""
Extract (SPM[k], action[k], SPM[k+1]) samples from HDF5 log

Filters out empty/near-empty SPMs (when no agents/obstacles in field of view)
to improve VAE training quality and reduce storage.
"""
function extract_samples_from_log(
    filepath::String;
    step_interval::Int=5,
    max_agents_per_step::Int=3,
    max_samples_per_file::Int=5000,
    min_information_content::Float64=0.05  # At least 5% non-zero elements
)
    samples = []
    skipped_empty = 0

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

                # Filter out empty/near-empty SPMs
                # Check information content: percentage of non-zero elements
                non_zero_current = count(abs.(spm_current) .> 1e-4) / length(spm_current)
                non_zero_next = count(abs.(spm_next) .> 1e-4) / length(spm_next)

                # Skip if both SPMs are nearly empty (nothing in field of view)
                if non_zero_current < min_information_content && non_zero_next < min_information_content
                    skipped_empty += 1
                    continue
                end

                push!(samples, (spm_current, action, spm_next))
                sample_count += 1

                if sample_count >= max_samples_per_file
                    break
                end
            end
        end
    end

    if skipped_empty > 0
        println("      (Filtered $skipped_empty empty SPMs)")
    end

    return samples
end

# Main execution
println("Starting data collection...")
println()

all_logs = []
all_metrics = []

# Run simulations for all conditions
for scenario in SCENARIOS
    if scenario == "corridor"
        # Multiple corridor widths for variety
        for width in CORRIDOR_WIDTHS
            for density in DENSITIES
                for seed in SEEDS_RANGE
                    log_path, metrics = run_single_simulation(scenario, density, seed, width)
                    push!(all_logs, (scenario, density, seed, width, log_path))
                    push!(all_metrics, metrics)
                end
            end
        end
    else
        # Scramble: no width variation
        for density in DENSITIES
            for seed in SEEDS_RANGE
                log_path, metrics = run_single_simulation(scenario, density, seed)
                push!(all_logs, (scenario, density, seed, 0.0, log_path))
                push!(all_metrics, metrics)
            end
        end
    end
    println()
end

println("="^80)
println("Data Collection Summary")
println("="^80)
println("  Total simulations: $(length(all_logs))")
println("  Total log files: $(length(all_logs))")
println()

# Aggregate metrics by scenario
for scenario in SCENARIOS
    scenario_metrics = filter(m -> m["scenario"] == scenario, all_metrics)
    if !isempty(scenario_metrics)
        avg_collision = mean([m["collision_rate"] for m in scenario_metrics])
        avg_freezing = mean([m["freezing_rate"] for m in scenario_metrics])
        @printf("  %s: Collision %.2f%%, Freezing %.2f%%\n",
                uppercase(scenario), avg_collision, avg_freezing)
    end
end
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

for (scenario, density, seed, width, log_path) in all_logs
    println("  Extracting: $(basename(log_path))")
    samples = extract_samples_from_log(log_path)
    println("    $(length(samples)) samples")

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
total_samples = length(train_samples) + length(val_samples) + length(test_samples) + length(ood_samples)
@printf("  Train: %d samples (%.1f%%)\n", length(train_samples), 100.0 * length(train_samples) / total_samples)
@printf("  Val: %d samples (%.1f%%)\n", length(val_samples), 100.0 * length(val_samples) / total_samples)
@printf("  Test: %d samples (%.1f%%)\n", length(test_samples), 100.0 * length(test_samples) / total_samples)
@printf("  OOD: %d samples (%.1f%%)\n", length(ood_samples), 100.0 * length(ood_samples) / total_samples)
@printf("  Total: %d samples\n", total_samples)
println()

# Save unified dataset
dataset_path = joinpath(@__DIR__, "../data/vae_training/dataset_v61.h5")
mkpath(dirname(dataset_path))

println("Saving unified dataset: $dataset_path")

h5open(dataset_path, "w") do file
    # Helper function to save samples
    function save_split(split_name, samples)
        if isempty(samples)
            println("  Warning: $split_name is empty")
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

        println("  $split_name: $n_samples samples saved")
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
    attributes(file)["scenarios"] = join(SCENARIOS, ",")
    attributes(file)["densities"] = join(DENSITIES, ",")
    attributes(file)["corridor_widths"] = join(CORRIDOR_WIDTHS, ",")
    attributes(file)["exploration_noise"] = EXPLORATION_NOISE
    attributes(file)["n_train"] = length(train_samples)
    attributes(file)["n_val"] = length(val_samples)
    attributes(file)["n_test"] = length(test_samples)
    attributes(file)["n_ood"] = length(ood_samples)
end

println("✅ Saved: $dataset_path")

# File size
filesize_mb = round(stat(dataset_path).size / 1024^2, digits=2)
println("  File size: $(filesize_mb) MB")
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
