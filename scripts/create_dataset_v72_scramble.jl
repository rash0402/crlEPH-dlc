#!/usr/bin/env julia
"""
VAE Training Data Collection for v7.2: 5D State Space with Heading Alignment

MAJOR UPDATE from v6.3 to v7.2:
  ✅ State space: 4D (x, y, vx, vy) → 5D (x, y, vx, vy, θ)
  ✅ Dynamics: Euler + unicycle → RK4 + heading alignment (k_align=4.0 rad/s)
  ✅ Goal: goal_vel → d_goal (direction unit vector)
  ✅ Control: [v, ω] → [Fx, Fy] (omnidirectional force)
  ✅ Physical params: m=70kg, u_max=150N (pedestrian model)

Purpose:
  Generate training dataset for v7.2 VAE learning:
  - Random walk + geometric collision avoidance (controller-bias-free)
  - 5D state trajectories: (x, y, vx, vy, θ)
  - Direction-based goals: d_goal ∈ {N, S, E, W}
  - Storage: ~25 MB per simulation (includes heading)

Configuration:
  - Scenario: Scramble Crossing (4-group)
  - D_max = 6.0m (12×12 SPM grid)
  - Safety threshold = 4.0m (collision avoidance)
  - Exploration noise = 0.3 std
  - Repulsion strength = 2.0
  - Densities: 10 agents/group (default)
  - Seeds: 1,2,3 (default)

Output:
  - Raw trajectories: data/vae_training/raw_v72/v72_scramble_d{density}_s{seed}_YYYYMMDD_HHMMSS.h5
  - HDF5 structure: trajectory/{pos, vel, heading, u, d_goal, group}, events/{collision, near_collision}

Usage:
  julia --project=. scripts/create_dataset_v72_scramble.jl --densities 10 --seeds 1,2,3 --steps 1500
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
include("../src/action_vae.jl")  # Required by controller.jl
include("../src/controller.jl")

using .Config
using .SPM
using .Dynamics
using .Controller

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings(description="VAE Training Data Collection v7.2 (5D State Space)")

    @add_arg_table! s begin
        "--densities"
            help = "Agent densities (comma-separated, e.g., '10,15,20')"
            arg_type = String
            default = "10"
        "--seeds"
            help = "Random seeds (comma-separated, e.g., '1,2,3')"
            arg_type = String
            default = "1,2,3"
        "--steps"
            help = "Simulation steps per run"
            arg_type = Int
            default = 1500
        "--output-dir"
            help = "Output directory"
            arg_type = String
            default = "data/vae_training/raw_v72"
    end

    return parse_args(s)
end

"""
Run single simulation with v7.2 random walk controller
"""
function run_simulation_v72(
    density::Int,
    seed::Int,
    max_steps::Int,
    output_dir::String
)
    # Configuration (v7.2 parameters)
    world_params = WorldParams(dt=0.01)  # v7.2: 10ms timestep
    agent_params = AgentParams(
        mass=70.0,           # v7.2: Pedestrian mass
        damping=0.5,
        r_agent=0.5,
        n_agents_per_group=density,
        u_max=150.0,         # v7.2: Walking force
        k_align=4.0          # v7.2: Heading alignment gain
    )
    spm_params = SPMParams(n_rho=12, n_theta=12, sensing_ratio=3.0)  # D_max=6.0m

    # Initialize agents (v7.2: includes heading and d_goal)
    Random.seed!(seed)
    agents = Dynamics.init_agents(agent_params, world_params; seed=seed)
    obstacles = Dynamics.init_obstacles(world_params)

    # Convert obstacles to tuple format for controller
    obstacle_tuples = [(obs.x_min + (obs.x_max - obs.x_min)/2,
                        obs.y_min + (obs.y_max - obs.y_min)/2)
                       for obs in obstacles]

    # Storage
    n_agents = length(agents)
    trajectory_pos = zeros(max_steps, n_agents, 2)
    trajectory_vel = zeros(max_steps, n_agents, 2)
    trajectory_heading = zeros(max_steps, n_agents)      # v7.2: NEW
    trajectory_u = zeros(max_steps, n_agents, 2)
    trajectory_d_goal = zeros(n_agents, 2)               # v7.2: Direction vectors (constant)
    trajectory_group = zeros(Int, n_agents)
    event_collision = zeros(Bool, max_steps, n_agents)
    event_near_collision = zeros(Bool, max_steps, n_agents)

    # Store d_goal (constant for each agent)
    for i in 1:n_agents
        trajectory_d_goal[i, :] = agents[i].d_goal
        trajectory_group[i] = Int(agents[i].group)
    end

    # Simulation loop
    collision_total = 0
    near_collision_total = 0

    for t in 1:max_steps
        for (i, agent) in enumerate(agents)
            # Generate control input (v7.2: discrete candidate selection)
            other_agents = [a for a in agents if a.id != agent.id]
            u = Controller.compute_action_random_collision_free(
                agent, other_agents, obstacle_tuples,
                agent_params, world_params;
                exploration_noise=1.0,   # Higher noise for exploration
                safety_threshold=0.5,    # Moderate safety buffer (0.5m)
                repulsion_strength=0.0   # Deprecated/Unused
            )

            # Store state before update
            trajectory_pos[t, i, :] = agent.pos
            trajectory_vel[t, i, :] = agent.vel
            trajectory_heading[t, i] = agent.heading  # v7.2: NEW
            trajectory_u[t, i, :] = u

            # Update agent with v7.2 dynamics (step_v72! uses dynamics_rk4)
            collision_count = Dynamics.step_v72!(agent, u, agent_params, world_params, obstacles, agents)

            # Log events
            event_collision[t, i] = collision_count > 0
            event_near_collision[t, i] = false  # TODO: Implement near-collision detection

            collision_total += collision_count
        end

        # Progress reporting
        if t % 500 == 0
            println("  Step $t/$max_steps | Collisions: $(round(collision_total / (t * n_agents) * 100, digits=2))%")
        end
    end

    # Compute statistics
    collision_rate = collision_total / (max_steps * n_agents) * 100
    near_collision_rate = sum(event_near_collision) / (max_steps * n_agents) * 100
    freezing_rate = 0.0  # TODO: Implement freezing detection

    # Generate output filename
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    filename = "v72_scramble_d$(density)_s$(seed)_$(timestamp).h5"
    filepath = joinpath(output_dir, filename)

    # Create output directory if needed
    mkpath(output_dir)

    # Save to HDF5
    h5open(filepath, "w") do file
        # Trajectory data
        traj_group = create_group(file, "trajectory")
        traj_group["pos"] = trajectory_pos
        traj_group["vel"] = trajectory_vel
        traj_group["heading"] = trajectory_heading  # v7.2: NEW
        traj_group["u"] = trajectory_u
        traj_group["d_goal"] = trajectory_d_goal    # v7.2: NEW (constant per agent)
        traj_group["group"] = trajectory_group

        # Events
        events_group = create_group(file, "events")
        events_group["collision"] = event_collision
        events_group["near_collision"] = event_near_collision

        # Metadata
        metadata_group = create_group(file, "metadata")
        metadata_group["scenario"] = "scramble"
        metadata_group["version"] = "v7.2"
        metadata_group["density"] = density
        metadata_group["seed"] = seed
        metadata_group["max_steps"] = max_steps
        metadata_group["dt"] = world_params.dt
        metadata_group["n_agents"] = n_agents
        metadata_group["collision_rate"] = collision_rate
        metadata_group["near_collision_rate"] = near_collision_rate
        metadata_group["freezing_rate"] = freezing_rate

        # SPM parameters
        spm_group = create_group(file, "spm_params")
        spm_group["n_rho"] = spm_params.n_rho
        spm_group["n_theta"] = spm_params.n_theta
        spm_group["sensing_ratio"] = spm_params.sensing_ratio
        spm_group["r_robot"] = spm_params.r_robot
        spm_group["fov_deg"] = spm_params.fov_deg

        # v7.2 specific parameters
        v72_group = create_group(file, "v72_params")
        v72_group["mass"] = agent_params.mass
        v72_group["k_align"] = agent_params.k_align
        v72_group["u_max"] = agent_params.u_max

        # Obstacles (v7.2: Fixed missing obstacles saving)
        # Convert Obstacle structs to [M, 4] array (x_min, x_max, y_min, y_max) or centroids
        # For SPM reconstruction, we usually need obstacle definitions.
        # But trajectory_loader.jl expects "obstacles/data".
        # Let's save as [M, 4] for full info.
        
        # However, debug_spm.jl (and likely trajectory_loader) might expect point clouds or specific format.
        # Let's check init_obstacles results. They are Rectangles.
        # If we save them as (x_min, x_max, y_min, y_max), trajectory_loader need to handle it.
        # But previous error: "obstacles/data not found".
        # Let's save as simple array for now.
        
        obs_data = zeros(length(obstacles), 4)
        for (idx, obs) in enumerate(obstacles)
            obs_data[idx, :] = [obs.x_min, obs.x_max, obs.y_min, obs.y_max]
        end
        
        obs_group = create_group(file, "obstacles")
        obs_group["data"] = obs_data
    end

    println("    Output: $filename")
    println("    Collision rate: $(round(collision_rate, digits=3))% (Target: <0.1%)")
    println("    Near-collision rate: $(round(near_collision_rate, digits=2))%")
    println("    Freezing rate: $(round(freezing_rate, digits=2))%")
    if collision_rate > 0.1
        println("    ⚠️  WARNING: Collision rate exceeds target (0.1%)")
    end
    println("    ✅ Saved: $filepath")

    return collision_rate, near_collision_rate
end

"""
Main execution
"""
function main()
    args = parse_commandline()

    # Parse parameters
    densities = parse.(Int, split(args["densities"], ','))
    seeds = parse.(Int, split(args["seeds"], ','))
    max_steps = args["steps"]
    output_dir = args["output-dir"]

    # Print configuration
    println("================================================================================")
    println("VAE Training Data Collection v7.2: 5D State Space with Heading Alignment")
    println("================================================================================")
    println()
    println("Configuration:")
    println("  Scenario: Scramble Crossing (4-group)")
    println("  Densities: $densities")
    println("  Seeds: $seeds")
    println("  Steps per run: $max_steps")
    println("  Output: $output_dir")
    println("  Physical model: m=70kg, u_max=150N, k_align=4.0 rad/s")
    println("  Data format: Raw trajectories + 5D state (pos, vel, heading)")
    println()
    println("Starting data collection...")
    println()

    collision_rates = Float64[]
    near_collision_rates = Float64[]

    for density in densities
        for seed in seeds
            println("  Scenario=scramble, Density=$density, Seed=$seed")
            collision_rate, near_collision_rate = run_simulation_v72(
                density, seed, max_steps, output_dir
            )
            push!(collision_rates, collision_rate)
            push!(near_collision_rates, near_collision_rate)
        end
    end

    # Summary
    println()
    println("================================================================================")
    println("Data Collection Complete")
    println("================================================================================")
    println("  Total simulations: $(length(collision_rates))")
    println("  Average collision rate: $(round(mean(collision_rates), digits=3))% (Target: <0.1%)")
    println("  Average near-collision rate: $(round(mean(near_collision_rates), digits=2))%")
    println("  Output directory: $output_dir")
    println()

    if mean(collision_rates) > 0.1
        println("⚠️  WARNING: Average collision rate exceeds target!")
        println("   Consider increasing safety_threshold or repulsion_strength")
        println()
    end

    println("Next steps:")
    println("  1. Verify data quality: python viewer/raw_v72_viewer.py data/vae_training/raw_v72/*.h5")
    println("  2. VAE Training: julia --project=. scripts/train_action_vae_v72.jl")
    println("  3. EPH Controller Test: julia --project=. scripts/test_eph_v72.jl")
    println("================================================================================")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
