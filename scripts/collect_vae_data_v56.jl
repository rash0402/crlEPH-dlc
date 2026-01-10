#!/usr/bin/env julia

"""
Phase 1: VAE Training Data Collection Script
Collects (SPM[k], action[k], SPM[k+1]) samples for both scenarios
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Random
using HDF5
using LinearAlgebra
using Statistics
using ArgParse

# Load modules
include("../src/config.jl")
include("../src/dynamics.jl")
include("../src/spm.jl")
include("../src/prediction.jl")  # Required by controller.jl
include("../src/controller.jl")
include("../src/scenarios.jl")

using .Config
using .Dynamics
using .SPM
using .Controller
using .Scenarios

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--scenario"
            help = "Scenario type: 'scramble' or 'corridor' or 'both'"
            arg_type = String
            default = "both"
        "--densities"
            help = "Agent densities (comma-separated)"
            arg_type = String
            default = "5,10,15,20"
        "--seeds"
            help = "Random seeds (range: start:end)"
            arg_type = String
            default = "1:5"
        "--steps"
            help = "Simulation steps per run"
            arg_type = Int
            default = 1500
        "--haze"
            help = "Fixed Haze value for SPM generation (use 0.0 for VAE training)"
            arg_type = Float64
            default = 0.0
        "--exploration-noise"
            help = "Exploration noise std (for action diversity)"
            arg_type = Float64
            default = 0.3
        "--output-dir"
            help = "Output directory for logs"
            arg_type = String
            default = "data/vae_training/raw"
        "--dry-run"
            help = "Test mode: only 100 steps"
            action = :store_true
    end

    return parse_args(s)
end

"""
Generate SPM for agent with fixed precision
"""
function generate_spm_fixed_haze(
    agent::Agent,
    others::Vector{Agent},
    obstacles::Vector{Tuple{Float64, Float64}},
    spm_config::SPMConfig,
    spm_params::SPMParams,
    agent_params::AgentParams,
    world_params::WorldParams,
    precision::Float64
)
    # Prepare ego-centric coordinates
    rel_pos_ego = Vector{Vector{Float64}}()
    rel_vel = Vector{Vector{Float64}}()

    # Agent velocity direction for ego frame
    vel_norm = norm(agent.vel)
    if vel_norm > 1e-6
        θ = atan(agent.vel[2], agent.vel[1])
    else
        # Use goal direction if stationary
        goal_dir = agent.goal - agent.pos
        θ = atan(goal_dir[2], goal_dir[1])
    end
    cos_θ = cos(θ)
    sin_θ = sin(θ)

    # Maximum sensing distance
    r_total = spm_params.r_robot + agent_params.r_agent
    max_sensing_distance = spm_params.sensing_ratio * r_total

    # Transform other agents to ego frame
    for other in others
        r_rel_world = relative_position(agent.pos, other.pos, world_params)
        dist = norm(r_rel_world)

        if dist > max_sensing_distance
            continue
        end

        # Ego-centric transformation
        r_rel_ego = [
            cos_θ * r_rel_world[1] - sin_θ * r_rel_world[2],
            sin_θ * r_rel_world[1] + cos_θ * r_rel_world[2]
        ]

        # FOV check
        theta_val = atan(r_rel_ego[1], r_rel_ego[2])
        if abs(theta_val) > spm_params.fov_rad / 2
            continue
        end

        # Relative velocity in ego frame
        v_rel_world = other.vel - agent.vel
        v_rel_ego = [
            cos_θ * v_rel_world[1] - sin_θ * v_rel_world[2],
            sin_θ * v_rel_world[1] + cos_θ * v_rel_world[2]
        ]

        push!(rel_pos_ego, r_rel_ego)
        push!(rel_vel, v_rel_ego)
    end

    # Transform obstacles to ego frame (for Corridor)
    for obs in obstacles
        r_rel_world = relative_position(agent.pos, [obs[1], obs[2]], world_params)
        dist = norm(r_rel_world)

        if dist > max_sensing_distance
            continue
        end

        r_rel_ego = [
            cos_θ * r_rel_world[1] - sin_θ * r_rel_world[2],
            sin_θ * r_rel_world[1] + cos_θ * r_rel_world[2]
        ]

        theta_val = atan(r_rel_ego[1], r_rel_ego[2])
        if abs(theta_val) > spm_params.fov_rad / 2
            continue
        end

        push!(rel_pos_ego, r_rel_ego)
        push!(rel_vel, [0.0, 0.0])  # Obstacles are static
    end

    # Generate SPM
    spm = generate_spm_3ch(spm_config, rel_pos_ego, rel_vel, agent_params.r_agent, precision)

    return spm
end

"""
Exploration policy: Simple goal-directed + noise
"""
function exploration_policy(
    agent::Agent,
    spm::Array{Float64, 3},
    control_params::ControlParams,
    agent_params::AgentParams,
    exploration_noise::Float64
)
    # Compute FEP action using existing controller
    u_fep = compute_action(agent, spm, control_params, agent_params)

    # Add exploration noise
    noise = randn(2) * exploration_noise
    u_noisy = u_fep + noise

    # Clamp to max control input
    u_clamped = clamp.(u_noisy, -agent_params.u_max, agent_params.u_max)

    return u_clamped
end

"""
Run single data collection simulation
"""
function run_collection_simulation(
    scenario_type::ScenarioType,
    density::Int,
    seed::Int,
    args::Dict,
    spm_params::SPMParams,
    world_params::WorldParams,
    agent_params::AgentParams,
    control_params::ControlParams
)
    scenario_name = scenario_type == SCRAMBLE_CROSSING ? "scramble" : "corridor"
    println("\n📊 Collecting: scenario=$scenario_name, density=$density, seed=$seed")

    Random.seed!(seed)

    # Initialize scenario
    agents, scenario_params = initialize_scenario(
        scenario_type,
        density,
        seed=seed,
        corridor_width=4.0
    )
    obstacles = get_obstacles(scenario_params)

    # Initialize SPM with fixed Haze
    haze_fixed = args["haze"]
    # Precision from Haze: Π = 1 / (H + ε)
    precision_fixed = 1.0 / (haze_fixed + 1e-6)

    spm_config = init_spm(spm_params)

    # Prepare data storage
    n_agents = length(agents)
    n_steps = args["steps"]

    # Pre-allocate arrays
    spm_data = zeros(Float32, n_steps, n_agents, 16, 16, 3)
    action_data = zeros(Float32, n_steps, n_agents, 2)
    position_data = zeros(Float32, n_steps, n_agents, 2)
    velocity_data = zeros(Float32, n_steps, n_agents, 2)

    # Simulation loop
    for step in 1:n_steps
        for (i, agent) in enumerate(agents)
            # Get other agents (excluding self)
            others = [a for a in agents if a.id != agent.id]

            # Generate SPM[k] with fixed precision
            spm_current = generate_spm_fixed_haze(
                agent, others, obstacles,
                spm_config, spm_params, agent_params, world_params,
                precision_fixed
            )

            # Compute action with exploration noise
            action = exploration_policy(
                agent, spm_current,
                control_params, agent_params,
                args["exploration-noise"]
            )

            # Store SPM[k] and action[k]
            spm_data[step, i, :, :, :] = Float32.(spm_current)
            action_data[step, i, :] = Float32.(action)
            position_data[step, i, :] = Float32.(agent.pos)
            velocity_data[step, i, :] = Float32.(agent.vel)

            # Update agent dynamics (simplified: no collision detection)
            # Using simple Euler integration
            # a = (u - D*v) / M
            dt = world_params.dt
            mass = agent_params.mass
            damping = agent_params.damping

            acc = (action - damping * agent.vel) / mass
            agent.vel = agent.vel + acc * dt
            agent.pos = agent.pos + agent.vel * dt

            # Apply toroidal boundary conditions
            world_width = 50.0  # From scenario initialization
            world_height = 50.0
            agent.pos[1] = mod(agent.pos[1], world_width)
            agent.pos[2] = mod(agent.pos[2], world_height)
        end

        # Progress indicator
        if step % 500 == 0 || step == n_steps
            @printf("  Step %4d / %d\n", step, n_steps)
        end
    end

    # Save to HDF5
    output_dir = joinpath(args["output-dir"], scenario_name)
    mkpath(output_dir)
    filename = joinpath(output_dir, "sim_d$(density)_s$(seed).h5")

    h5open(filename, "w") do file
        # Create groups
        create_group(file, "/metadata")
        create_group(file, "/data")

        # Metadata
        attrs(file["/metadata"])["version"] = "5.6.0"
        attrs(file["/metadata"])["scenario"] = scenario_name
        attrs(file["/metadata"])["density"] = density
        attrs(file["/metadata"])["seed"] = seed
        attrs(file["/metadata"])["n_steps"] = n_steps
        attrs(file["/metadata"])["n_agents"] = n_agents
        attrs(file["/metadata"])["haze_fixed"] = haze_fixed
        attrs(file["/metadata"])["exploration_noise"] = args["exploration-noise"]
        attrs(file["/metadata"])["creation_date"] = string(now())

        # Data arrays: (n_steps, n_agents, ...)
        file["/data/spm"] = spm_data
        file["/data/actions"] = action_data
        file["/data/positions"] = position_data
        file["/data/velocities"] = velocity_data
    end

    total_samples = (n_steps - 1) * n_agents  # -1 because we need (k, k+1) pairs
    println("  ✅ Saved: $filename ($total_samples samples)")

    return total_samples
end

"""
Main data collection loop
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("EPH v5.6 - Phase 1: VAE Training Data Collection")
    println("=" ^ 70)

    # Parse configuration
    scenarios_list = if args["scenario"] == "both"
        [SCRAMBLE_CROSSING, CORRIDOR]
    elseif args["scenario"] == "scramble"
        [SCRAMBLE_CROSSING]
    elseif args["scenario"] == "corridor"
        [CORRIDOR]
    else
        error("Invalid scenario: $(args["scenario"])")
    end

    densities = parse.(Int, split(args["densities"], ","))
    seed_range = eval(Meta.parse(args["seeds"]))
    seeds = collect(seed_range)

    if args["dry-run"]
        println("\n⚠️  DRY RUN MODE: Only 100 steps per simulation")
        args["steps"] = 100
    end

    # Configuration
    spm_params = SPMParams()
    world_params = WorldParams(max_steps=args["steps"])
    agent_params = AgentParams()
    control_params = ControlParams(
        exploration_rate=0.0,  # Use deterministic policy with noise
        exploration_noise=0.0  # Add noise explicitly in exploration_policy
    )

    println("\nConfiguration:")
    println("  Scenarios: $(length(scenarios_list))")
    println("  Densities: $densities")
    println("  Seeds: $seeds")
    println("  Steps per run: $(args["steps"])")
    println("  Fixed Haze: $(args["haze"])")
    println("  Exploration noise: $(args["exploration-noise"])")
    println("  Output dir: $(args["output-dir"])")

    # Collect data
    total_samples = 0
    total_runs = 0

    for scenario_type in scenarios_list
        for density in densities
            for seed in seeds
                samples = run_collection_simulation(
                    scenario_type, density, seed, args,
                    spm_params, world_params, agent_params, control_params
                )
                total_samples += samples
                total_runs += 1
            end
        end
    end

    # Summary
    println("\n" * "=" ^ 70)
    println("✅ Data Collection Complete!")
    println("=" ^ 70)
    println("  Total runs: $total_runs")
    println("  Total samples: $total_samples")
    println("  Average samples/run: $(round(Int, total_samples / total_runs))")
    println("\nNext step: Create unified dataset_v56.h5 with Train/Val/Test splits")
    println("  Run: julia --project=. scripts/create_dataset_v56.jl")
end

# Run data collection
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
