#!/usr/bin/env julia

"""
EPH v7.2 Simulation Script
Implements Model A (5D State, Omnidirectional Force, Heading Alignment)
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
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/prediction.jl")  # Required by Controller
include("../src/action_vae.jl")  # Required by Controller
include("../src/controller.jl")
# include("../src/communication.jl") # Optional if needed
include("../src/scenarios.jl")

using .Config
using .SPM
using .Dynamics
using .Prediction
using .ActionVAEModel
using .Controller
using .Scenarios

"""
Generate SPM for agent using explicit Heading (v7.2)
"""
function generate_spm_v72(
    agent::Agent,
    others::Vector{Agent},
    obstacles::Vector{Tuple{Float64, Float64}},
    spm_config::SPMConfig,
    spm_params::SPMParams,
    agent_params::AgentParams,
    world_params::WorldParams,
    precision::Float64=1.0  # Base precision, typically modulated later or passed as is
)
    # Ego Heading from State
    θ = agent.heading
    cos_θ = cos(θ)
    sin_θ = sin(θ)

    # Maximum sensing distance
    r_total = spm_params.r_robot + agent_params.r_agent
    max_sensing_distance = spm_params.sensing_ratio * r_total

    # Prepare ego-centric coordinates
    rel_pos_ego = Vector{Vector{Float64}}()
    rel_vel_ego = Vector{Vector{Float64}}()

    # Transform other agents to ego frame
    for other in others
        r_rel_world = Dynamics.relative_position(agent.pos, other.pos, world_params)
        dist = norm(r_rel_world)

        if dist > max_sensing_distance
            continue
        end

        # Ego-centric transformation: Rotate by -θ
        # x' = x cos(-θ) - y sin(-θ) = x cosθ + y sinθ
        # y' = x sin(-θ) + y cos(-θ) = -x sinθ + y cosθ
        # Wait, rotation matrix R(-θ) = [c s; -s c]
        # x_ego = x_world * c + y_world * s
        # y_ego = -x_world * s + y_world * c
        
        # Let's verify standard rotation:
        # Vector v at angle alpha. Rotate frame by theta. New angle alpha-theta.
        # x = r cos(alpha), y = r sin(alpha)
        # x' = r cos(alpha-theta) = r(c a c th + s a s th) = x c + y s
        # y' = r sin(alpha-theta) = r(s a c th - c a s th) = y c - x s
        
        r_rel_ego = [
            r_rel_world[1] * cos_θ + r_rel_world[2] * sin_θ,
            -r_rel_world[1] * sin_θ + r_rel_world[2] * cos_θ
        ]

        # FOV check
        theta_val = atan(r_rel_ego[1], r_rel_ego[2]) # Needs consistent axis def.
        # Usually atan(x, y) if 0 is Up/Y-axis?
        # Standard: atan(y, x).
        # In SPM module: theta_val = atan(p_rel[1], p_rel[2]) -> atan(x, y)? 
        # Check src/spm.jl:123 "theta_val = atan(p_rel[1], p_rel[2])" 
        # Wait, atan(y, x) is standard. atan(x, y) means x is Y-axis?
        # In Julia: atan(y, x) computes angle of vector (x, y).
        # atan(x, y) computes angle of (y, x)? No, arguments are (y, x).
        # atan(y, x).
        # spm.jl line 123: `theta_val = atan(p_rel[1], p_rel[2])`.
        # This implies `atan(x, y)` where `x=p_rel[1]`, `y=p_rel[2]`.
        # This corresponds to angle from Y-axis (North)? 
        # If x is 1, y is 0, atan(1, 0) = pi/2. (Right)
        # If x is 0, y is 1, atan(0, 1) = 0. (Forward/Up)
        # Yes, atan(x, y) effectively treats Y as forward (0 deg).
        
        if abs(theta_val) > spm_params.fov_rad / 2
            continue
        end

        # Relative velocity in ego frame
        # v_rel_world = other.vel - agent.vel # Or just absolute? 
        # trajectory_loader kept absolute velocity but rotated. 
        # spm.jl uses `radial_vel = -dot(p_rel, v_rel)`.
        # If v_rel is relative (closing), then positive dot means separating.
        # If v_rel is absolute velocity of other, and p_rel is position of other.
        # Then `dot` depends on both.
        # Let's stick to absolute velocity of other, rotated.
        v_world = other.vel 
        v_ego = [
            v_world[1] * cos_θ + v_world[2] * sin_θ,
            -v_world[1] * sin_θ + v_world[2] * cos_θ
        ]

        push!(rel_pos_ego, r_rel_ego)
        push!(rel_vel_ego, v_ego)
    end

    # Transform obstacles to ego frame
    for obs in obstacles
        r_rel_world = Dynamics.relative_position(agent.pos, [obs[1], obs[2]], world_params)
        dist = norm(r_rel_world)

        if dist > max_sensing_distance
            continue
        end

        r_rel_ego = [
            r_rel_world[1] * cos_θ + r_rel_world[2] * sin_θ,
            -r_rel_world[1] * sin_θ + r_rel_world[2] * cos_θ
        ]

        theta_val = atan(r_rel_ego[1], r_rel_ego[2])
        if abs(theta_val) > spm_params.fov_rad / 2
            continue
        end

        push!(rel_pos_ego, r_rel_ego)
        push!(rel_vel_ego, [0.0, 0.0])  # Obstacles are static
    end

    # Generate SPM
    spm = SPM.generate_spm_3ch(spm_config, rel_pos_ego, rel_vel_ego, agent_params.r_agent, precision)

    return spm
end

function parse_commandline()
    s = ArgParseSettings(description="EPH v7.2 Simulation")

    @add_arg_table! s begin
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
        "--vae-model"
            help = "Path to trained VAE model (.bson file)"
            arg_type = String
            default = "models/action_vae_v72_best.bson"
        "--output"
            help = "Output HDF5 file path"
            arg_type = String
            default = ""
    end

    return parse_args(s)
end

function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("EPH v7.2 Simulation (Model A)")
    println("=" ^ 70)
    
    # Load VAE
    vae = nothing
    if isfile(args["vae-model"])
        println("📂 Loading VAE model...")
        BSON.@load args["vae-model"] model
        # Move to CPU for simulation
        vae = model |> cpu
        println("  ✅ VAE loaded from $(args["vae-model"])")
    else
        @warn "VAE model not found: $(args["vae-model"]). Running in fallback mode (Reactive)."
    end

    # Initialize scenarios
    Random.seed!(args["seed"])
    world_params = WorldParams(dt=0.01) # 10ms
    agent_params = AgentParams()
    world_params = WorldParams(dt=0.01) # 10ms
    agent_params = AgentParams()
    spm_params = SPMParams(n_rho=12, n_theta=12) # Match VAE model
    spm_config = init_spm(spm_params)
    
    scenario_type = args["scenario"] == "scramble" ? SCRAMBLE_CROSSING : CORRIDOR
    agents, scenario_params = initialize_scenario(
        scenario_type,
        args["density"],
        seed=args["seed"]
    )
    # Re-initialize agents to ensure v7.2 params (mass, align, etc) if scenario doesn't set them fully?
    # initialize_scenario uses Default AgentParams which is now v7.2.
    # But init_agents inside might need update?
    # initialize_scenario calls Dynamics.init_agents.
    
    obstacles = get_obstacles(scenario_params)
    
    # Initialize physical obstacles for Dynamics (Vector{Obstacle})
    physics_obstacles = Vector{Obstacle}()
    if args["scenario"] == "scramble"
        physics_obstacles = Dynamics.init_obstacles(world_params)
    elseif args["scenario"] == "corridor"
        # Use default corridor obstacles matching init_corridor_agents if possible
        # Or just convert points if specific width not available in args to match exactly
        # Ideally we should match init_corridor(agents) logic.
        # Check Scenarios.jl init_corridor defaults: width=10.0 (Step 251 Line 93)
        # Check Dynamics.jl init_corridor_obstacles defaults: width=4.0?
        # This mismatch is risky.
        # Fallback to point conversion is safer to ensure visual/physical match if parameters differ.
        physics_obstacles = [Obstacle(p[1]-0.15, p[1]+0.15, p[2]-0.15, p[2]+0.15) for p in obstacles]
    else
        # Random or others: Convert points to small obstacles
        # 0.15m half-width = 0.3m size (approx 1ft)
        physics_obstacles = [Obstacle(p[1]-0.15, p[1]+0.15, p[2]-0.15, p[2]+0.15) for p in obstacles]
    end

    println("🚀 Starting simulation...")
    
    # Storage
    n_agents = length(agents)
    n_steps = args["steps"]
    
    trajectory_pos = zeros(n_steps, n_agents, 2)
    trajectory_vel = zeros(n_steps, n_agents, 2)
    trajectory_heading = zeros(n_steps, n_agents)
    trajectory_u = zeros(n_steps, n_agents, 2)
    
    for t in 1:n_steps
        if t % 500 == 0
            println("  Step $t/$n_steps")
        end
        
        # 1. Update Plans / Compute Actions
        actions = Vector{Vector{Float64}}(undef, n_agents)
        
        for (i, agent) in enumerate(agents)
            others = [a for a in agents if a.id != agent.id]
            
            # Generate SPM (Uses point obstacles)
            spm = generate_spm_v72(
                agent, others, obstacles, spm_config, spm_params,
                agent_params, world_params
            )
            
            # Compute Action
            u = Controller.compute_action_v72(
                agent, spm, others, agent_params, world_params, spm_config,
                vae_model=vae
            )
            
            actions[i] = u
        end
        
        # 2. Dynamics Update (Uses physics obstacles)
        for (i, agent) in enumerate(agents)
            u = actions[i]
            Dynamics.step_v72!(agent, u, agent_params, world_params, physics_obstacles, agents)
            
            # Log
            trajectory_pos[t, i, :] = agent.pos
            trajectory_vel[t, i, :] = agent.vel
            trajectory_heading[t, i] = agent.heading
            trajectory_u[t, i, :] = u
        end
    end
    
    # Save results
    output_path = args["output"]
    if isempty(output_path)
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        output_path = "data/logs/sim_v72_$(args["scenario"])_d$(args["density"])_$(timestamp).h5"
    end
    mkpath(dirname(output_path))
    
    h5open(output_path, "w") do file
        file["trajectory/pos"] = trajectory_pos
        file["trajectory/vel"] = trajectory_vel
        file["trajectory/heading"] = trajectory_heading
        file["trajectory/u"] = trajectory_u
        attrs(file)["version"] = "v7.2"
        attrs(file)["scenario"] = args["scenario"]
    end
    
    println("✅ Saved to $output_path")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
