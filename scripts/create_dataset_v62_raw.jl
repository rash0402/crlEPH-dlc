#!/usr/bin/env julia
"""
VAE Training Data Collection for v6.2: Raw Trajectory Data Architecture

Purpose:
  Generate diverse training dataset with RAW TRAJECTORY DATA only:
  - Store: (pos, vel, u, heading) + obstacles + metadata
  - SPMs computed during data collection for control, but NOT stored
  - SPMs will be reconstructed during VAE training from raw data
  - Enables flexibility: SPM structure changes don't require data recollection
  - Storage savings: ~100x smaller (16.8 MB vs 2.1 GB per simulation)

Configuration:
  - D_max = 8.0m (2³, mathematical elegance + biological validity)
  - Bin 1-6 Haze=0 Fixed (step function, no sigmoid blending)
  - Precision-Weighted Safety: Φ_safety also weighted by Π(ρ)
  - Multiple scenarios: Scramble crossing + Corridor (narrow passage)
  - Multiple density conditions: 5, 10, 20 agents/group
  - Corridor width variation: 3.0m (narrow), 5.0m (wide)
  - Exploration noise for action diversity: 0.3 std
  - 3 random seeds per condition

Output:
  - Raw trajectories: data/vae_training/raw_v62/v62_{scenario}_d{density}_s{seed}_YYYYMMDD_HHMMSS.h5
  - No unified dataset (created during VAE training with SPM reconstruction)

Estimated time: ~3 hours (27 simulations × ~7 min/run)
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
println("VAE Training Data Collection v6.2: Raw Trajectory Data")
println("="^80)
println()

# Parse arguments
args = parse_commandline()

# Configuration - Override defaults for v6.2
const OUTPUT_DIR = haskey(args, "output-dir") && args["output-dir"] != "data/vae_training/raw" ?
                   args["output-dir"] : "data/vae_training/raw_v62"
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

# v6.2 SPM and Foveation parameters (same as v6.1)
const V62_SPM_PARAMS = SPMParams(sensing_ratio=8.0)  # D_max = 8.0m (2³)
const V62_FOV_PARAMS = FoveationParams(
    rho_index_critical=6,  # Not used during data collection (only for inference)
    h_critical=0.0,         # Haze=0.0 everywhere (pure observation for VAE training)
    h_peripheral=0.0        # Haze=0.0 everywhere (Haze is applied only at inference time)
)

println("Configuration:")
println("  Scenarios: $(SCENARIOS)")
println("  Densities: $(DENSITIES)")
println("  Seeds: $(SEEDS_RANGE)")
println("  Steps per run: $(MAX_STEPS)")
println("  Corridor widths: $(CORRIDOR_WIDTHS) m")
println("  Exploration noise: $(EXPLORATION_NOISE) std")
println("  D_max: 8.0m")
println("  Data format: Raw trajectories (pos, vel, u, heading)")
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
    log_filename = "v62_$(scenario)$(scenario_suffix)_d$(density)_s$(seed)_$(timestamp).h5"
    log_path = joinpath(OUTPUT_DIR, log_filename)

    println("  Scenario=$scenario, Density=$density, Seed=$seed$(scenario == "corridor" ? ", Width=$(corridor_width)m" : "")")
    println("    Output: $log_filename")

    # Initialize world and agents
    world_params = WorldParams(max_steps=MAX_STEPS)
    agent_params = AgentParams(n_agents_per_group=density)
    control_params = ControlParams(use_vae=false)  # No VAE during data collection

    # Initialize SPM config with D_max=8.0m
    spm_config = init_spm(V62_SPM_PARAMS)

    # Create scenario
    if scenario == "scramble"
        agents, scenario_params = initialize_scenario(
            SCRAMBLE_CROSSING,
            density;
            seed=seed
        )
        obstacles = get_obstacles(scenario_params)
    elseif scenario == "corridor"
        agents, scenario_params = initialize_scenario(
            CORRIDOR,
            density;
            seed=seed,
            corridor_width=corridor_width
        )
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

    # Data storage - v6.2: Raw trajectory data only (NO SPMs)
    action_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    pos_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    vel_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    heading_log = zeros(Float32, MAX_STEPS, length(agents))

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
                    if norm(obs_rel_pos) < V62_SPM_PARAMS.sensing_ratio * (V62_SPM_PARAMS.r_robot + agent_params.r_agent)
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
                rho_index_critical=V62_FOV_PARAMS.rho_index_critical,
                h_critical=V62_FOV_PARAMS.h_critical,
                h_peripheral=V62_FOV_PARAMS.h_peripheral
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

            # Compute heading from velocity
            heading = norm(agent.vel) > 1e-6 ? atan(agent.vel[2], agent.vel[1]) : 0.0

            # Log data BEFORE updating dynamics - v6.2: No SPM, add heading
            action_log[step, agent_idx, :] = u
            pos_log[step, agent_idx, :] = agent.pos
            vel_log[step, agent_idx, :] = agent.vel
            heading_log[step, agent_idx] = heading

            # Check for freezing
            if norm(agent.vel) < 0.1
                freezing_count += 1
            end

            # Update agent dynamics with step!
            # Note: obstacles are static positions (x, y), need to convert to Obstacle type if required
            # For simplicity, we'll pass empty obstacles array and rely on SPM-based collision avoidance
            Dynamics.step!(agent, u, agent_params, world_params, Obstacle[], agents)
        end
    end

    # Compute metrics BEFORE saving to HDF5
    total_agent_steps = length(agents) * MAX_STEPS
    collision_rate = 100.0 * collision_count / total_agent_steps
    freezing_rate = 100.0 * freezing_count / total_agent_steps

    # Save to HDF5 with v6.2 structure: Raw trajectory data only
    h5open(log_path, "w") do file
        # Trajectory data group
        traj_group = create_group(file, "trajectory")
        traj_group["pos", compress=4] = pos_log
        traj_group["vel", compress=4] = vel_log
        traj_group["u", compress=4] = action_log
        traj_group["heading", compress=4] = heading_log

        # Obstacles group (store as [M, 2] matrix: x, y positions)
        obs_group = create_group(file, "obstacles")
        if !isempty(obstacles)
            # Convert obstacles to matrix [M, 2] - use collect() to avoid Adjoint type
            obs_matrix = collect(hcat([[o[1], o[2]] for o in obstacles]...)')
            obs_group["data"] = obs_matrix
        else
            obs_group["data"] = zeros(Float32, 0, 2)
        end

        # Metadata group (with computed metrics)
        meta_group = create_group(file, "metadata")
        meta_group["scenario"] = scenario
        meta_group["density"] = density
        meta_group["seed"] = seed
        if scenario == "corridor"
            meta_group["corridor_width"] = corridor_width
        end
        meta_group["n_agents"] = length(agents)
        meta_group["n_steps"] = MAX_STEPS
        meta_group["dt"] = world_params.dt
        meta_group["collision_rate"] = collision_rate
        meta_group["freezing_rate"] = freezing_rate
        meta_group["exploration_noise"] = EXPLORATION_NOISE
        meta_group["timestamp"] = string(now())

        # SPM parameters group (for reconstruction during VAE training)
        spm_group = create_group(file, "spm_params")
        spm_group["n_rho"] = V62_SPM_PARAMS.n_rho
        spm_group["n_theta"] = V62_SPM_PARAMS.n_theta
        spm_group["sensing_ratio"] = V62_SPM_PARAMS.sensing_ratio
        spm_group["rho_index_critical"] = V62_FOV_PARAMS.rho_index_critical
        spm_group["h_critical"] = V62_FOV_PARAMS.h_critical
        spm_group["h_peripheral"] = V62_FOV_PARAMS.h_peripheral
    end

    println("    Collision rate: $(round(collision_rate, digits=2))%")
    println("    Freezing rate: $(round(freezing_rate, digits=2))%")
    println("    ✅ Saved: $log_path")

    # Force garbage collection to free memory
    GC.gc()

    return log_path
end

# Main execution
println("Starting data collection...")
println()

# Run simulations for all conditions
simulation_count = 0

for scenario in SCENARIOS
    if scenario == "corridor"
        # Multiple corridor widths for variety
        for width in CORRIDOR_WIDTHS
            for density in DENSITIES
                for seed in SEEDS_RANGE
                    global simulation_count += 1
                    run_single_simulation(scenario, density, seed, width)
                end
            end
        end
    else
        # Scramble: no width variation
        for density in DENSITIES
            for seed in SEEDS_RANGE
                global simulation_count += 1
                run_single_simulation(scenario, density, seed)
            end
        end
    end
    println()
end

println("="^80)
println("Data Collection Complete")
println("="^80)
println("  Total simulations: $simulation_count")
println("  Output directory: $OUTPUT_DIR")
println()
println("Next steps:")
println("  1. VAE Training: Use trajectory_loader.jl to reconstruct SPMs on-the-fly")
println("  2. Train VAE: julia --project=. scripts/train_action_vae_v62.jl")
println("  3. Validate: Check reconstruction quality (MSE < 0.05)")
println("="^80)
