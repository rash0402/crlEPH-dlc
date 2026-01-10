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
    # Generate current SPM
    precision = 1.0 / (control_params.haze_fixed + 1e-6)
    spm = generate_spm(
        agent.pos,
        agent.vel,
        others,
        obstacles,
        spm_config,
        spm_params,
        agent_params,
        world_params,
        precision
    )

    # Generate action candidates
    u_candidates = generate_action_candidates(
        agent,
        control_params.n_candidates,
        agent_params
    )

    best_u = nothing
    best_free_energy = Inf

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
        end
    end

    return best_u
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

    v_desired = normalize(to_goal) * agent_params.v_desired

    # Prediction: where will I be if I apply u?
    dt = 0.1
    v_next = agent.vel + (u - agent_params.damping * agent.vel) / agent_params.mass * dt

    # Free Energy = distance from desired velocity
    F_goal = norm(v_next - v_desired)^2

    return F_goal
end

"""
Compute safety Free Energy (collision avoidance)
"""
function compute_safety_free_energy(
    spm::Array{Float64, 3},
    u::Vector{Float64},
    spm_params::SPMParams
)
    # Use proximity channel (channel 1) to estimate collision risk
    proximity_channel = spm[:, :, 1]

    # High proximity → high collision risk → high Free Energy
    # We want to avoid actions that lead to high proximity states
    F_safety = mean(proximity_channel)

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

    # Initialize control parameters
    control_params = ControlParamsV56(
        args["lambda-goal"],
        args["lambda-safety"],
        args["lambda-surprise"],
        args["haze-fixed"],
        args["n-candidates"],
        0.0  # sigma_noise (no exploration noise in EPH mode)
    )

    # Load configs
    world_params = WorldParams()
    agent_params = AgentParams()
    spm_config = SPMConfig()
    spm_params = SPMParams()

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

    # Simulation loop
    println("🚀 Starting simulation...")
    println()

    all_positions = []
    all_velocities = []
    all_spms = []
    all_actions = []
    all_surprises = []

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

        for agent in agents
            others = [a for a in agents if a.id != agent.id]

            # Compute action with EPH controller
            u = compute_action_eph(
                agent,
                others,
                scenario_params.obstacles,
                vae,
                control_params,
                spm_config,
                spm_params,
                agent_params,
                world_params
            )

            push!(actions, u)

            # Store SPM (for logging)
            precision = 1.0 / (control_params.haze_fixed + 1e-6)
            spm = generate_spm(
                agent.pos,
                agent.vel,
                others,
                scenario_params.obstacles,
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

        # Update dynamics
        for (i, agent) in enumerate(agents)
            u = actions[i]
            # Simple Euler integration
            dt = world_params.dt
            acc = (u - agent_params.damping * agent.vel) / agent_params.mass
            agent.vel = agent.vel + acc * dt
            agent.pos = agent.pos + agent.vel * dt

            # Toroidal boundary
            agent.pos[1] = mod(agent.pos[1], world_params.world_width)
            agent.pos[2] = mod(agent.pos[2], world_params.world_height)
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

        # Write datasets
        write(file, "positions", pos_array)
        write(file, "velocities", vel_array)
        write(file, "spms", spm_array)
        write(file, "actions", action_array)
        write(file, "surprises", surprise_array)

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
