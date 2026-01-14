#!/usr/bin/env julia
"""
VAE Training Data Collection for v6.3: Random Obstacles Scenario

Purpose:
  Generate unbiased training data for VAE with Random Obstacles scenario.
  - Unstructured environment with randomly placed circular obstacles
  - Random walk + geometric collision avoidance (NO controller bias)
  - Diverse navigation patterns (agents navigate around obstacles)
  - Complements structured scenarios (Scramble, Corridor)

Scenario Design:
  - 4 groups at corners, diagonal crossing paths
  - 50-100 randomly placed circular obstacles (2-4m radius)
  - 10m safe zones around agent start/goal areas
  - 50×50m world (same as Scramble)

Configuration:
  - D_max = 6.0m (12x12 SPM, same as v6.3)
  - Safety threshold = 4.0m (hard collision avoidance)
  - Exploration noise = 0.3 std (diverse behaviors)
  - Repulsion strength = 2.0
  - Multiple density conditions: 5, 10, 15, 20 agents/group
  - Multiple obstacle counts: 30, 50, 70 obstacles
  - 5 random seeds per condition

Target: < 0.1% collision rate

Output:
  - Raw trajectories: data/vae_training/raw_v63/v63_random_d{density}_n{num_obs}_s{seed}_YYYYMMDD_HHMMSS.h5

Estimated time: ~2 hours (60 simulations × ~120s/run)
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
include("../src/prediction.jl")
include("../src/action_vae.jl")
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
    s = ArgParseSettings(description="VAE Training Data Collection v6.3 (Random Obstacles)")

    @add_arg_table! s begin
        "--densities"
            help = "Agent densities (comma-separated, e.g., '5,10,15,20')"
            arg_type = String
            default = "5,10,15,20"
        "--obstacle-counts"
            help = "Number of obstacles (comma-separated, e.g., '30,50,70')"
            arg_type = String
            default = "30,50,70"
        "--seeds"
            help = "Random seeds (range format, e.g., '1:5')"
            arg_type = String
            default = "1:5"
        "--steps"
            help = "Simulation steps per run"
            arg_type = Int
            default = 3000
        "--exploration-noise"
            help = "Exploration noise std for action diversity"
            arg_type = Float64
            default = 0.3
        "--safety-threshold"
            help = "Minimum distance to maintain (meters)"
            arg_type = Float64
            default = 4.0
        "--repulsion-strength"
            help = "Strength of repulsive force"
            arg_type = Float64
            default = 2.0
        "--output-dir"
            help = "Output directory for raw logs"
            arg_type = String
            default = "data/vae_training/raw_v63"
        "--dry-run"
            help = "Test mode: only 100 steps"
            action = :store_true
    end

    return parse_args(s)
end

println("="^80)
println("VAE Training Data Collection v6.3: Random Obstacles Scenario")
println("="^80)
println()

# Parse arguments
args = parse_commandline()

# Configuration
const OUTPUT_DIR = args["output-dir"]
mkpath(OUTPUT_DIR)

const DENSITIES = parse.(Int, split(args["densities"], ","))
const OBSTACLE_COUNTS = parse.(Int, split(args["obstacle-counts"], ","))
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
const EXPLORATION_NOISE = args["exploration-noise"]
const SAFETY_THRESHOLD = args["safety-threshold"]
const REPULSION_STRENGTH = args["repulsion-strength"]

# v6.3 SPM parameters
const V63_SPM_PARAMS = SPMParams(n_rho=12, n_theta=12, sensing_ratio=3.0)  # D_max = 6.0m

println("Configuration:")
println("  Controller: Random Walk + Geometric Collision Avoidance (v6.3)")
println("  Scenario: Random Obstacles")
println("  Densities: $(DENSITIES) agents/group")
println("  Obstacle counts: $(OBSTACLE_COUNTS)")
println("  Seeds: $(SEEDS_RANGE)")
println("  Steps per run: $(MAX_STEPS)")
println("  Exploration noise: $(EXPLORATION_NOISE) std")
println("  Safety threshold: $(SAFETY_THRESHOLD) m")
println("  Repulsion strength: $(REPULSION_STRENGTH)")
println("  D_max: 6.0m (12x12 grid)")
println("  Output: $OUTPUT_DIR")
println()

"""
Run single simulation and save raw log
"""
function run_random_obstacles_simulation(
    density::Int,
    num_obstacles::Int,
    seed::Int,
    obstacle_seed::Int
)
    println("\n" * "="^70)
    println("Random Obstacles: Density=$(density), Obstacles=$(num_obstacles), Seed=$(seed), ObsSeed=$(obstacle_seed)")
    println("="^70)

    # Initialize scenario
    agents, scenario_params = initialize_scenario(
        RANDOM_OBSTACLES,
        density,
        seed=seed,
        num_obstacles=num_obstacles,
        obstacle_seed=obstacle_seed
    )

    # Get obstacles
    obstacles = get_obstacles(scenario_params)
    println("  Generated $(length(obstacles)) obstacle points")

    # Create world parameters
    world_x, world_y = scenario_params.world_size
    world_params = WorldParams(
        width=world_x,
        height=world_y,
        max_steps=MAX_STEPS
    )

    # Create agent parameters (v6.3: human-like velocity)
    agent_params = AgentParams(n_agents_per_group=density, u_max=2.0)

    # Tracking metrics
    collision_count = 0
    freezing_count = 0
    near_collision_count = 0

    # v6.3: Extended data storage
    action_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    pos_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    vel_log = zeros(Float32, MAX_STEPS, length(agents), 2)
    heading_log = zeros(Float32, MAX_STEPS, length(agents))

    # NEW in v6.3: Extended logs
    goal_log = zeros(Float32, length(agents), 2)  # Goal direction vector per agent
    d_pref_log = zeros(Float32, MAX_STEPS, length(agents), 2)  # Preferred direction
    group_log = zeros(Int32, length(agents))  # Agent group ID
    collision_flag_log = zeros(Bool, MAX_STEPS, length(agents))  # Collision event flag
    near_collision_flag_log = zeros(Bool, MAX_STEPS, length(agents))  # Near-collision flag

    # Store static data (goal is now a direction vector)
    for (idx, agent) in enumerate(agents)
        goal_log[idx, :] = agent.goal  # Direction vector
        group_log[idx] = Int32(agent.group)
    end

    # Simulation loop
    for step in 1:MAX_STEPS
        if step % 500 == 0
            collision_rate = 100.0 * collision_count / (step * length(agents))
            println(@sprintf("  Step %d/%d | Collisions: %.2f%%",
                    step, MAX_STEPS, collision_rate))
        end

        # Update each agent
        for (agent_idx, agent) in enumerate(agents)
            # Get other agents (excluding self)
            other_agents = filter(a -> a.id != agent.id, agents)

            # Compute preferred direction (agent.goal is now a direction vector)
            d_pref = agent.goal  # Direction vector (already normalized)

            # Log preferred direction
            d_pref_log[step, agent_idx, :] = d_pref

            # v6.3: Controller-Bias-Free Action Generation
            u = Controller.compute_action_random_collision_free(
                agent,
                other_agents,
                obstacles,
                agent_params,
                world_params;
                exploration_noise=EXPLORATION_NOISE,
                safety_threshold=SAFETY_THRESHOLD,
                repulsion_strength=REPULSION_STRENGTH
            )

            # Collision detection (for metrics only, no emergency stop)
            in_collision = false
            in_near_collision = false
            min_dist_agents = Inf
            min_dist_obstacles = Inf

            for other in other_agents
                dist = norm(agent.pos - other.pos)
                min_dist_agents = min(min_dist_agents, dist)

                if dist < agent_params.emergency_threshold_agent
                    in_collision = true
                    collision_count += 1
                elseif dist < SAFETY_THRESHOLD
                    in_near_collision = true
                    near_collision_count += 1
                end
            end

            # Check obstacle collisions
            if !isempty(obstacles)
                for obs in obstacles
                    obs_pos = [obs[1], obs[2]]
                    dist = norm(agent.pos - obs_pos)
                    min_dist_obstacles = min(min_dist_obstacles, dist)

                    if dist < agent_params.r_agent
                        in_collision = true
                        collision_count += 1
                    elseif dist < SAFETY_THRESHOLD
                        in_near_collision = true
                        near_collision_count += 1
                    end
                end
            end

            # Log collision flags
            collision_flag_log[step, agent_idx] = in_collision
            near_collision_flag_log[step, agent_idx] = in_near_collision

            # Compute heading from velocity
            heading = norm(agent.vel) > 1e-6 ? atan(agent.vel[2], agent.vel[1]) : 0.0

            # Log data BEFORE updating dynamics
            action_log[step, agent_idx, :] = u
            pos_log[step, agent_idx, :] = agent.pos
            vel_log[step, agent_idx, :] = agent.vel
            heading_log[step, agent_idx] = heading

            # Check for freezing
            if norm(agent.vel) < 0.1
                freezing_count += 1
            end

            # Update agent dynamics using unicycle model (v6.3: kinematic model)
            Dynamics.step_unicycle!(agent, u, agent_params, world_params, Obstacle[], agents)

            # Note: No goal cycling needed - agents move continuously in their assigned direction
            # Torus boundary allows infinite motion in the same direction
        end
    end

    # Compute metrics
    total_agent_steps = length(agents) * MAX_STEPS
    collision_rate = 100.0 * collision_count / total_agent_steps
    near_collision_rate = 100.0 * near_collision_count / total_agent_steps
    freezing_rate = 100.0 * freezing_count / total_agent_steps

    # Save to HDF5 with v6.3 extended structure
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    log_path = joinpath(
        OUTPUT_DIR,
        @sprintf("v63_random_d%d_n%d_s%d_%s.h5",
                density, num_obstacles, seed, timestamp)
    )

    h5open(log_path, "w") do file
        # Trajectory data group
        traj_group = create_group(file, "trajectory")
        # pos_log is [T, N, 2], need [2, N, T] for HDF5
        traj_group["pos", compress=4] = collect(permutedims(pos_log, (3, 2, 1)))  # [2, N, T]
        traj_group["vel", compress=4] = collect(permutedims(vel_log, (3, 2, 1)))  # [2, N, T]
        traj_group["u", compress=4] = collect(permutedims(action_log, (3, 2, 1)))  # [2, N, T]
        traj_group["heading", compress=4] = collect(permutedims(heading_log, (2, 1)))  # [N, T]

        # NEW in v6.3: Extended trajectory data
        traj_group["goal", compress=4] = collect(permutedims(goal_log, (2, 1)))  # [2, N]
        traj_group["d_pref", compress=4] = collect(permutedims(d_pref_log, (3, 2, 1)))  # [2, N, T]
        traj_group["group"] = group_log  # [N]

        # Obstacles group
        obs_group = create_group(file, "obstacles")
        if !isempty(obstacles)
            obs_matrix = collect(hcat([[o[1], o[2]] for o in obstacles]...)')
            obs_group["data", compress=4] = permutedims(obs_matrix, (2, 1))  # [2, M]
        else
            obs_group["data"] = zeros(Float32, 2, 0)
        end

        # NEW in v6.3: Events group (collision flags)
        events_group = create_group(file, "events")
        events_group["collision", compress=4] = collect(permutedims(collision_flag_log, (2, 1)))  # [N, T]
        events_group["near_collision", compress=4] = collect(permutedims(near_collision_flag_log, (2, 1)))  # [N, T]

        # Metadata group
        meta_group = create_group(file, "metadata")
        meta_group["scenario"] = "random_obstacles"
        meta_group["density"] = density
        meta_group["num_obstacles"] = num_obstacles
        meta_group["seed"] = seed
        meta_group["obstacle_seed"] = obstacle_seed
        meta_group["n_agents"] = length(agents)
        meta_group["n_steps"] = MAX_STEPS
        meta_group["dt"] = world_params.dt
        meta_group["world_size"] = collect(scenario_params.world_size)
        meta_group["collision_rate"] = collision_rate
        meta_group["near_collision_rate"] = near_collision_rate
        meta_group["freezing_rate"] = freezing_rate
        meta_group["exploration_noise"] = EXPLORATION_NOISE
        meta_group["safety_threshold"] = SAFETY_THRESHOLD
        meta_group["repulsion_strength"] = REPULSION_STRENGTH
        meta_group["controller_type"] = "RandomWalk_CollisionFree_v63"
        meta_group["timestamp"] = string(now())

        # SPM parameters group
        spm_group = create_group(file, "spm_params")
        spm_group["n_rho"] = V63_SPM_PARAMS.n_rho
        spm_group["n_theta"] = V63_SPM_PARAMS.n_theta
        spm_group["sensing_ratio"] = V63_SPM_PARAMS.sensing_ratio
        spm_group["r_robot"] = V63_SPM_PARAMS.r_robot
        spm_group["r_agent"] = agent_params.r_agent
    end

    println("\n  Summary:")
    println(@sprintf("    Collision rate: %.3f%% (Target: <0.1%%)", collision_rate))
    println(@sprintf("    Near-collision rate: %.2f%%", near_collision_rate))
    println(@sprintf("    Freezing rate: %.2f%%", freezing_rate))

    if collision_rate > 0.1
        println("    ⚠️  WARNING: Collision rate exceeds target (0.1%)")
    else
        println("    ✅ Collision rate within target")
    end

    println(@sprintf("    ✅ Saved: %s", log_path))

    # Force garbage collection
    GC.gc()

    return collision_rate
end

# Main execution
total_runs = length(DENSITIES) * length(OBSTACLE_COUNTS) * length(SEEDS_RANGE)
println("Total simulations: $(total_runs)")
println("Estimated time: ~$(div(total_runs * 120, 60)) minutes")
println()

start_time = time()
run_count = 0
collision_rates = Float64[]

for density in DENSITIES
    for num_obstacles in OBSTACLE_COUNTS
        for seed in SEEDS_RANGE
            global run_count += 1
            # Use seed+1000 as obstacle seed to ensure different obstacle placement
            obstacle_seed = seed + 1000

            println("\n[$run_count/$total_runs]")
            collision_rate = run_random_obstacles_simulation(
                density,
                num_obstacles,
                seed,
                obstacle_seed
            )
            push!(collision_rates, collision_rate)
        end
    end
end

elapsed = time() - start_time

println("\n" * "="^80)
println("All simulations completed!")
println("="^80)
println(@sprintf("  Total runs: %d", total_runs))
println(@sprintf("  Total time: %.1f minutes", elapsed / 60))
println(@sprintf("  Average collision rate: %.3f%%", mean(collision_rates)))
println(@sprintf("  Max collision rate: %.3f%%", maximum(collision_rates)))
println(@sprintf("  Output directory: %s", OUTPUT_DIR))
println("="^80)
