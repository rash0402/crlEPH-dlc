#!/usr/bin/env julia

"""
EPH v5.6 Simulation Script with Surprise Integration
Implements F_total = F_goal + λ_safety·F_safety + λ_surprise·S(u)
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using LinearAlgebra
using Statistics
using Flux
using BSON
using ArgParse
using Random
using HDF5

# Load modules
include("../src/config.jl")
include("../src/config_v56.jl")
include("../src/spm.jl")
include("../src/prediction.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")
include("../src/communication.jl")
include("../src/logger.jl")
include("../src/scenarios.jl")
include("../src/action_vae.jl")
include("../src/surprise.jl")

using .Config
using .ConfigV56
using .SPM
using .Dynamics
using .Controller
using .Communication
using .Logger
using .Scenarios
using .ActionVAEModel
using .SurpriseModule

"""
Generate SPM for agent with fixed precision (Haze-based control)
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
        r_rel_world = Dynamics.relative_position(agent.pos, other.pos, world_params)
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

    # Transform obstacles to ego frame
    for obs in obstacles
        r_rel_world = Dynamics.relative_position(agent.pos, [obs[1], obs[2]], world_params)
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
    spm = SPM.generate_spm_3ch(spm_config, rel_pos_ego, rel_vel, agent_params.r_agent, precision)

    return spm
end

"""
Parse command line arguments
"""
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--seed"
            help = "Random seed"
            arg_type = Int
            default = 42
        "--density"
            help = "Number of agents per group"
            arg_type = Int
            default = 10
        "--steps"
            help = "Simulation steps"
            arg_type = Int
            default = 1500
        "--scenario"
            help = "Simulation scenario: 'scramble' or 'corridor'"
            arg_type = String
            default = "scramble"
        "--corridor-width"
            help = "Corridor width in meters (only for corridor scenario)"
            arg_type = Float64
            default = 4.0
        "--vae-model"
            help = "Path to trained VAE model (.bson file)"
            arg_type = String
            default = "models/action_vae_v56_best.bson"
        "--lambda-goal"
            help = "Weight for goal-reaching term"
            arg_type = Float64
            default = 1.0
        "--lambda-safety"
            help = "Weight for safety/collision-avoidance term"
            arg_type = Float64
            default = 5.0
        "--lambda-surprise"
            help = "Weight for Surprise term (0 = baseline)"
            arg_type = Float64
            default = 1.0
        "--haze-fixed"
            help = "Fixed Haze value (0.0 - 1.0)"
            arg_type = Float64
            default = 0.5
        "--n-candidates"
            help = "Number of action candidates for optimization"
            arg_type = Int
            default = 20
        "--output"
            help = "Output HDF5 file path"
            arg_type = String
            default = ""
        "--visualize"
            help = "Enable real-time visualization via ZMQ"
            action = :store_true
    end

    return parse_args(s)
end

"""
Compute action using EPH controller with Surprise integration
"""
function compute_action_eph(
    agent::Agent,
    others::Vector{Agent},
    obstacles::Vector{Tuple{Float64, Float64}},
    vae::Union{ActionConditionedVAE, Nothing},
    control_params::ControlParamsV56,
    spm_config::SPMConfig,
    spm_params::SPMParams,
    agent_params::AgentParams,
    world_params::WorldParams
)
    # Generate current SPM with clamped precision
    precision_raw = 1.0 / (control_params.haze_fixed + 1e-6)
    precision = clamp(precision_raw, 0.01, 100.0)

    spm = generate_spm_fixed_haze(
        agent,
        others,
        obstacles,
        spm_config,
        spm_params,
        agent_params,
        world_params,
        precision
    )

    # Compute β values (for diagnostics) using clamped precision
    beta_r = spm_params.beta_r_min + (spm_params.beta_r_max - spm_params.beta_r_min) * precision
    beta_nu = spm_params.beta_nu_min + (spm_params.beta_nu_max - spm_params.beta_nu_min) * precision

    # Compute SPM statistics (for diagnostics)
    spm_stats = Dict(
        "ch1_mean" => mean(spm[:, :, 1]),
        "ch1_std" => std(spm[:, :, 1]),
        "ch1_max" => maximum(spm[:, :, 1]),
        "ch2_mean" => mean(spm[:, :, 2]),
        "ch2_std" => std(spm[:, :, 2]),
        "ch2_max" => maximum(spm[:, :, 2]),
        "ch2_var" => var(spm[:, :, 2]),
        "ch3_mean" => mean(spm[:, :, 3]),
        "ch3_std" => std(spm[:, :, 3]),
        "ch3_max" => maximum(spm[:, :, 3]),
        "ch3_var" => var(spm[:, :, 3])
    )

    # Generate action candidates
    u_candidates = generate_action_candidates(
        agent,
        control_params.n_candidates,
        agent_params
    )

    best_u = nothing
    best_free_energy = Inf
    best_F_goal = 0.0
    best_F_safety = 0.0
    best_S_u = 0.0

    for u in u_candidates
        # 1. Goal-reaching Free Energy
        F_goal = compute_goal_free_energy(agent, u, agent_params)

        # 2. Safety Free Energy (collision avoidance)
        F_safety = compute_safety_free_energy(spm, u, spm_params)

        # 3. Surprise term
        S_u = 0.0
        if !isnothing(vae) && control_params.lambda_surprise > 0.0
            try
                S_u = compute_surprise(vae, spm, u)
            catch e
                @warn "Surprise computation failed: $e"
                S_u = 0.0
            end
        end

        # Total Free Energy with Surprise
        F_total = control_params.lambda_goal * F_goal +
                  control_params.lambda_safety * F_safety +
                  control_params.lambda_surprise * S_u

        if F_total < best_free_energy
            best_free_energy = F_total
            best_u = u
            best_F_goal = F_goal
            best_F_safety = F_safety
            best_S_u = S_u
        end
    end

    # Return action and diagnostics
    diagnostics = Dict(
        "F_goal" => best_F_goal,
        "F_safety" => best_F_safety,
        "S_u" => best_S_u,
        "F_total" => best_free_energy,
        "beta_r" => beta_r,
        "beta_nu" => beta_nu,
        "precision" => precision,
        "spm_stats" => spm_stats
    )

    return (best_u, diagnostics)
end

"""
Generate action candidates (random sampling + systematic)
"""
function generate_action_candidates(
    agent::Agent,
    n_candidates::Int,
    agent_params::AgentParams
)
    candidates = Vector{Float64}[]

    # 1. Current velocity (inertia)
    push!(candidates, agent.vel)

    # 2. Towards goal
    to_goal = agent.goal - agent.pos
    if norm(to_goal) > 1e-6
        u_goal = normalize(to_goal) * agent_params.u_max
        push!(candidates, u_goal)
    end

    # 3. Random candidates
    for _ in 1:(n_candidates - 2)
        θ = rand() * 2π
        magnitude = rand() * agent_params.u_max
        u_random = [magnitude * cos(θ), magnitude * sin(θ)]
        push!(candidates, u_random)
    end

    return candidates
end

"""
Compute goal-reaching Free Energy
"""
function compute_goal_free_energy(
    agent::Agent,
    u::Vector{Float64},
    agent_params::AgentParams
)
    # Desired velocity towards goal
    to_goal = agent.goal - agent.pos
    if norm(to_goal) < 1e-6
        return 0.0
    end

    # Use reasonable walking speed (2.0 m/s)
    desired_speed = 2.0
    v_desired = normalize(to_goal) * desired_speed

    # Prediction: where will I be if I apply u?
    dt = 0.1
    v_next = agent.vel + (u - agent_params.damping * agent.vel) / agent_params.mass * dt

    # Free Energy = distance from desired velocity
    F_goal = norm(v_next - v_desired)^2

    return F_goal
end

"""
Compute safety Free Energy (collision avoidance)

Following proposal_v5.6.md Line 250:
F_safety(u) = λ_safe Σ_{m,n} φ(ŷ_{m,n}[k+1](u))

Where:
- ŷ[k+1]: Predicted SPM (or current SPM as proxy)
- φ(·): Potential function for collision risk
- Ch2: Proximity Saliency (distance-based)
- Ch3: Collision Risk (velocity-based)

Theory Reference: proposal_v5.6.md Lines 247-255
"""
function compute_safety_free_energy(
    spm::Array{Float64, 3},
    u::Vector{Float64},
    spm_params::SPMParams
)
    # Extract relevant channels
    ch2_proximity = spm[:, :, 2]  # Proximity Saliency (exp(-ρ*β_r))
    ch3_collision = spm[:, :, 3]  # Collision Risk (TTC-based)

    # Potential function φ: exponential risk mapping
    # Higher values = closer/more dangerous = higher penalty
    # k controls sensitivity (higher k = more emphasis on high values)
    k_proximity = 5.0
    k_collision = 5.0

    φ_proximity(val) = exp(k_proximity * val)
    φ_collision(val) = exp(k_collision * val)

    # Apply potential function to each cell and sum
    risk_proximity = sum(φ_proximity.(ch2_proximity))
    risk_collision = sum(φ_collision.(ch3_collision))

    # Weighted combination (proposal suggests both channels)
    # Equal weight for now; can be tuned
    w_proximity = 0.5
    w_collision = 0.5

    F_safety = w_proximity * risk_proximity + w_collision * risk_collision

    # Note: λ_safe is applied externally in control_params.lambda_safety
    return F_safety
end

"""
Main simulation loop
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("EPH v5.6 Simulation with Surprise Integration")
    println("=" ^ 70)
    println()
    println("Configuration:")
    println("  Scenario: $(args["scenario"])")
    println("  Density: $(args["density"]) agents/group")
    println("  Steps: $(args["steps"])")
    println("  λ_goal: $(args["lambda-goal"])")
    println("  λ_safety: $(args["lambda-safety"])")
    println("  λ_surprise: $(args["lambda-surprise"])")
    println("  Haze (fixed): $(args["haze-fixed"])")
    println("  VAE model: $(args["vae-model"])")
    println()

    # Set random seed
    Random.seed!(args["seed"])

    # Load VAE model
    vae = nothing
    if args["lambda-surprise"] > 0.0
        if isfile(args["vae-model"])
            println("📂 Loading VAE model...")
            BSON.@load args["vae-model"] model
            vae = model
            println("  ✅ VAE loaded from $(args["vae-model"])")
        else
            @warn "VAE model not found: $(args["vae-model"]). Running without Surprise."
            args["lambda-surprise"] = 0.0
        end
    else
        println("ℹ️  Running in BASELINE mode (λ_surprise = 0)")
    end
    println()

    # Initialize control parameters (using keyword arguments)
    control_params = ControlParamsV56(
        lambda_goal=args["lambda-goal"],
        lambda_safety=args["lambda-safety"],
        lambda_surprise=args["lambda-surprise"],
        haze_fixed=args["haze-fixed"],
        n_candidates=args["n-candidates"],
        sigma_noise=0.3,  # Default noise for candidate generation
        use_vae=(args["lambda-surprise"] > 0.0)
    )

    # Load configs
    world_params = WorldParams()
    agent_params = AgentParams()
    spm_params = SPMParams()
    spm_config = init_spm(spm_params)  # Correct initialization

    # Initialize scenario
    scenario_type = args["scenario"] == "scramble" ? SCRAMBLE_CROSSING : CORRIDOR
    agents, scenario_params = initialize_scenario(
        scenario_type,
        args["density"],
        seed=args["seed"],
        corridor_width=args["corridor-width"]
    )

    println("🎬 Initialized $(length(agents)) agents in $(args["scenario"]) scenario")
    println()

    # Initialize communication (optional)
    publisher = nothing
    if args["visualize"]
        comm_params = CommParams()
        publisher = init_publisher(comm_params)
        println("📡 ZMQ publisher initialized")
    end

    # Prepare output file
    output_path = args["output"]
    if isempty(output_path)
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        condition_str = args["lambda-surprise"] > 0.0 ? "eph" : "baseline"
        output_path = "data/logs/sim_$(condition_str)_$(args["scenario"])_d$(args["density"])_$(timestamp).h5"
    end
    mkpath(dirname(output_path))

    # Store agent goals (for success rate evaluation)
    agent_goals = [agent.goal for agent in agents]

    # Get obstacles from scenario
    obstacles = get_obstacles(scenario_params)

    # Simulation loop
    println("🚀 Starting simulation...")
    println()

    all_positions = []
    all_velocities = []
    all_spms = []
    all_actions = []
    all_surprises = []

    # Diagnostic data
    all_betas = []          # (beta_r, beta_nu)
    all_precisions = []     # precision values
    all_spm_stats = []      # SPM statistics
    all_free_energies = []  # (F_goal, F_safety, S_u, F_total)

    for step in 1:args["steps"]
        if step % 100 == 0
            @printf("  Step %4d / %d\n", step, args["steps"])
        end

        # Store state
        positions = [agent.pos for agent in agents]
        velocities = [agent.vel for agent in agents]
        push!(all_positions, positions)
        push!(all_velocities, velocities)

        # Compute actions for all agents
        actions = Vector{Float64}[]
        spms_step = []
        surprises_step = Float64[]

        # Diagnostic data for this step
        betas_step = []
        precisions_step = Float64[]
        spm_stats_step = []
        free_energies_step = []

        for agent in agents
            others = [a for a in agents if a.id != agent.id]

            # Compute action with EPH controller (now returns diagnostics)
            u, diagnostics = compute_action_eph(
                agent,
                others,
                obstacles,
                vae,
                control_params,
                spm_config,
                spm_params,
                agent_params,
                world_params
            )

            push!(actions, u)

            # Store diagnostic data
            push!(betas_step, (diagnostics["beta_r"], diagnostics["beta_nu"]))
            push!(precisions_step, diagnostics["precision"])
            push!(spm_stats_step, diagnostics["spm_stats"])
            push!(free_energies_step, (diagnostics["F_goal"], diagnostics["F_safety"],
                                       diagnostics["S_u"], diagnostics["F_total"]))

            # Store SPM (for logging) with clamped precision
            precision_raw = 1.0 / (control_params.haze_fixed + 1e-6)
            precision = clamp(precision_raw, 0.01, 100.0)
            spm = generate_spm_fixed_haze(
                agent,
                others,
                obstacles,
                spm_config,
                spm_params,
                agent_params,
                world_params,
                precision
            )
            push!(spms_step, spm)

            # Compute Surprise (for logging)
            if !isnothing(vae)
                S = compute_surprise(vae, spm, u)
                push!(surprises_step, S)
            else
                push!(surprises_step, 0.0)
            end
        end

        push!(all_spms, spms_step)
        push!(all_actions, actions)
        push!(all_surprises, surprises_step)

        # Store diagnostic data
        push!(all_betas, betas_step)
        push!(all_precisions, precisions_step)
        push!(all_spm_stats, spm_stats_step)
        push!(all_free_energies, free_energies_step)

        # Update dynamics
        for (i, agent) in enumerate(agents)
            u = actions[i]
            # Simple Euler integration
            dt = world_params.dt
            acc = (u - agent_params.damping * agent.vel) / agent_params.mass
            agent.vel = agent.vel + acc * dt
            agent.pos = agent.pos + agent.vel * dt

            # Toroidal boundary
            agent.pos[1] = mod(agent.pos[1], world_params.width)
            agent.pos[2] = mod(agent.pos[2], world_params.height)
        end

        # Publish state (if visualizing)
        if !isnothing(publisher)
            publish_state(publisher, agents, step)
        end
    end

    println()
    println("✅ Simulation complete!")
    println()

    # Save results
    println("💾 Saving results to: $output_path")
    save_simulation_data(
        output_path,
        all_positions,
        all_velocities,
        all_spms,
        all_actions,
        all_surprises,
        agent_goals,
        all_betas,
        all_precisions,
        all_spm_stats,
        all_free_energies,
        args,
        control_params
    )

    println()
    println("=" ^ 70)
    println("Done!")
    println("=" ^ 70)
end

"""
Save simulation data to HDF5
"""
function save_simulation_data(
    filepath::String,
    positions,
    velocities,
    spms,
    actions,
    surprises,
    agent_goals,
    betas,
    precisions,
    spm_stats,
    free_energies,
    args,
    control_params::ControlParamsV56
)
    h5open(filepath, "w") do file
        # Convert to arrays
        n_steps = length(positions)
        n_agents = length(positions[1])

        # Positions: (n_steps, n_agents, 2)
        pos_array = zeros(Float64, n_steps, n_agents, 2)
        for t in 1:n_steps
            for i in 1:n_agents
                pos_array[t, i, :] = positions[t][i]
            end
        end

        # Velocities: (n_steps, n_agents, 2)
        vel_array = zeros(Float64, n_steps, n_agents, 2)
        for t in 1:n_steps
            for i in 1:n_agents
                vel_array[t, i, :] = velocities[t][i]
            end
        end

        # SPMs: (n_steps, n_agents, 16, 16, 3)
        spm_array = zeros(Float32, n_steps, n_agents, 16, 16, 3)
        for t in 1:n_steps
            for i in 1:n_agents
                spm_array[t, i, :, :, :] = spms[t][i]
            end
        end

        # Actions: (n_steps, n_agents, 2)
        action_array = zeros(Float64, n_steps, n_agents, 2)
        for t in 1:n_steps
            for i in 1:n_agents
                action_array[t, i, :] = actions[t][i]
            end
        end

        # Surprises: (n_steps, n_agents)
        surprise_array = zeros(Float64, n_steps, n_agents)
        for t in 1:n_steps
            for i in 1:n_agents
                surprise_array[t, i] = surprises[t][i]
            end
        end

        # Agent goals: (n_agents, 2)
        goal_array = zeros(Float64, n_agents, 2)
        for i in 1:n_agents
            goal_array[i, :] = agent_goals[i]
        end

        # === Diagnostic Data ===

        # Betas: (n_steps, n_agents, 2) - [beta_r, beta_nu]
        beta_array = zeros(Float64, n_steps, n_agents, 2)
        for t in 1:n_steps
            for i in 1:n_agents
                beta_array[t, i, 1] = betas[t][i][1]  # beta_r
                beta_array[t, i, 2] = betas[t][i][2]  # beta_nu
            end
        end

        # Precisions: (n_steps, n_agents)
        precision_array = zeros(Float64, n_steps, n_agents)
        for t in 1:n_steps
            for i in 1:n_agents
                precision_array[t, i] = precisions[t][i]
            end
        end

        # SPM Statistics: (n_steps, n_agents, 11)
        # [ch1_mean, ch1_std, ch1_max, ch2_mean, ch2_std, ch2_max, ch2_var,
        #  ch3_mean, ch3_std, ch3_max, ch3_var]
        spm_stat_array = zeros(Float64, n_steps, n_agents, 11)
        for t in 1:n_steps
            for i in 1:n_agents
                stats = spm_stats[t][i]
                spm_stat_array[t, i, 1] = stats["ch1_mean"]
                spm_stat_array[t, i, 2] = stats["ch1_std"]
                spm_stat_array[t, i, 3] = stats["ch1_max"]
                spm_stat_array[t, i, 4] = stats["ch2_mean"]
                spm_stat_array[t, i, 5] = stats["ch2_std"]
                spm_stat_array[t, i, 6] = stats["ch2_max"]
                spm_stat_array[t, i, 7] = stats["ch2_var"]
                spm_stat_array[t, i, 8] = stats["ch3_mean"]
                spm_stat_array[t, i, 9] = stats["ch3_std"]
                spm_stat_array[t, i, 10] = stats["ch3_max"]
                spm_stat_array[t, i, 11] = stats["ch3_var"]
            end
        end

        # Free Energies: (n_steps, n_agents, 4)
        # [F_goal, F_safety, S_u, F_total]
        fe_array = zeros(Float64, n_steps, n_agents, 4)
        for t in 1:n_steps
            for i in 1:n_agents
                fe_array[t, i, 1] = free_energies[t][i][1]  # F_goal
                fe_array[t, i, 2] = free_energies[t][i][2]  # F_safety
                fe_array[t, i, 3] = free_energies[t][i][3]  # S_u
                fe_array[t, i, 4] = free_energies[t][i][4]  # F_total
            end
        end

        # Write datasets
        write(file, "positions", pos_array)
        write(file, "velocities", vel_array)
        write(file, "spms", spm_array)
        write(file, "actions", action_array)
        write(file, "surprises", surprise_array)
        write(file, "agent_goals", goal_array)

        # Write diagnostic datasets
        write(file, "betas", beta_array)
        write(file, "precisions", precision_array)
        write(file, "spm_statistics", spm_stat_array)
        write(file, "free_energies", fe_array)

        # Metadata
        attrs(file)["scenario"] = args["scenario"]
        attrs(file)["density"] = args["density"]
        attrs(file)["steps"] = args["steps"]
        attrs(file)["lambda_goal"] = control_params.lambda_goal
        attrs(file)["lambda_safety"] = control_params.lambda_safety
        attrs(file)["lambda_surprise"] = control_params.lambda_surprise
        attrs(file)["haze_fixed"] = control_params.haze_fixed
        attrs(file)["n_candidates"] = control_params.n_candidates
        attrs(file)["vae_model"] = args["vae-model"]
        attrs(file)["seed"] = args["seed"]
        attrs(file)["creation_date"] = string(now())
    end

    println("  ✅ Data saved successfully")
end

# Run simulation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
