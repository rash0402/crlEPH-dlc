#!/usr/bin/env julia

"""
EPH Main Simulation Script
4-group scramble crossing with FEP controller
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using LinearAlgebra  # For norm, cos, sin functions

# Load modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")
include("../src/communication.jl")
include("../src/logger.jl")
include("../src/vae.jl")

using Statistics
using Dates
using Flux
using BSON
using DelimitedFiles  # For CSV export
using Random
using HDF5
using .Config
using .SPM
using .Dynamics
using .Controller
using .Communication
using .Logger
using .VAEModel

"""
Main simulation loop
"""
function main()
    println("=" ^ 60)
    println("=" ^ 60)
    println("!!! EPH Simulation - VERSION 3 STARTING !!!")
    println("!!! IF YOU DO NOT SEE THIS, OLD CODE IS RUNNING !!!")
    println("=" ^ 60)
    
    # Load configuration
    # Initialize parameters
    control_params = ControlParams(experiment_condition=Config.A4_EPH, use_predictive_control=false)
    world_params = WorldParams(max_steps=1000) # Extended steps for viewing
    comm_params = CommParams()
    spm_params = SPMParams()
    agent_params = AgentParams()
    
    println("\n📋 Configuration:")
    println("  SPM: $(spm_params.n_rho)x$(spm_params.n_theta), FOV=$(spm_params.fov_deg)°")
    println("  Agents: $(agent_params.n_agents_per_group) per group (4 groups)")
    println("  Obstacles: 4 corners ($(world_params.obstacle_size)x$(world_params.obstacle_size))")
    println("  Goal area: center ±$(world_params.center_margin)")
    println("  World: $(world_params.width)x$(world_params.height), dt=$(world_params.dt)s")
    println("  Steps: $(world_params.max_steps)")
    println("  ZMQ: $(comm_params.zmq_endpoint)")
    
    # Initialize agents
    println("\n🤖 Initializing agents...")
    agents = init_agents(agent_params, world_params)
    println("  Total agents: $(length(agents))")
    
    # Initialize obstacles
    println("\n🚧 Initializing obstacles...")
    obstacles = init_obstacles(world_params)
    println("  Corner obstacles: $(length(obstacles))")
    
    # Initialize SPM
    println("\n🗺️  Initializing SPM...")
    spm_config = init_spm(spm_params)
    
    # Initialize communication
    println("\n📡 Initializing ZMQ publisher...")
    publisher = init_publisher(comm_params)
    println("  Listening on: $(comm_params.zmq_endpoint)")
    
    # Initialize HDF5 logger
    println("\n💾 Initializing HDF5 logger...")
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    if !isdir("data")
        mkdir("data")
    end
    log_filename = joinpath("data", "eph_sim_$(timestamp).h5")
    data_logger = init_logger(log_filename, world_params.max_steps, length(agents))
    println("  Output: $(log_filename)")
    
    # Load VAE model for Haze estimation (EPH theoretical requirement)
    # VAE's latent variance σ²_z provides epistemic uncertainty: H[k] = Agg(σ²_z[k])
    println("\n🧠 Loading VAE model...")
    vae_model = nothing
    model_path = "models/vae_latest.bson"
    if isfile(model_path)
        try
            BSON.@load model_path model
            vae_model = model
            println("  ✅ VAE model loaded from: $model_path")
        catch e
            @warn "Failed to load VAE model: $e"
            println("  ⚠️  VAE model load failed. Haze will be set to 0.0")
        end
    else
        println("  ℹ️  No trained VAE model found. Haze will be set to 0.0")
        println("     Run simulation first to collect data, then train with:")
        println("     julia --project=. scripts/train_vae.jl")
    end
    
    # Select agent for detailed logging (first agent from NORTH group)
    detail_agent_id = 1
    
    println("\n▶️  Starting simulation...")
    println("  Press Ctrl+C to stop\n")
    
    # Simulation loop
    try
        for step in 1:world_params.max_steps
            # Update all agents
            for agent in agents
                # Calculate ego-centric transformation parameters
                heading = 0.0
                rot_angle = π/2  # Default: East → Up
                vel_norm = norm(agent.vel)
                
                if vel_norm > 0.001
                    heading = atan(agent.vel[2], agent.vel[1])
                    rot_angle = -heading + π/2  # Rotate so velocity points to +Y
                end
                
                cos_θ = cos(rot_angle)
                sin_θ = sin(rot_angle)
                
                # Calculate FOV and sensing parameters
                r_total = spm_params.r_robot + agent_params.r_agent
                max_sensing_distance = spm_params.sensing_ratio * r_total
                
                # Get relative positions and velocities in EGO-CENTRIC frame
                # Apply FOV and distance filtering BEFORE transformation
                rel_pos_ego = Vector{Float64}[]
                rel_vel = Vector{Float64}[]
                local_agents = Vector{Float64}[]  # For visualization [x, y, group]
                
                for other in agents
                    if other.id != agent.id
                        # World-frame relative position
                        r_rel_world = relative_position(agent.pos, other.pos, world_params)
                        
                        # Pre-filter: Check distance BEFORE rotation (cheaper)
                        dist = norm(r_rel_world)
                        if dist > max_sensing_distance
                            continue  # Skip agents beyond sensing range
                        end
                        
                        # Transform to ego-centric frame (velocity = +Y)
                        r_rel_ego = [
                            cos_θ * r_rel_world[1] - sin_θ * r_rel_world[2],
                            sin_θ * r_rel_world[1] + cos_θ * r_rel_world[2]
                        ]
                        
                        # FOV check in ego-centric frame (angle from +Y axis)
                        # atan(x, y) gives angle from +Y axis (forward), positive=left, negative=right
                        # Standard atan2 is atan(y, x), Julia atan(x, y) is equivalent to atan2(x, y) in meaning?
                        # Wait, Julia atan(y, x) computes angle of (x, y) from X-axis.
                        # I want angle from Y-axis.
                        # theta = atan(x, y) gives angle of (y, x) from X-axis (which is Y-axis).
                        # Correct.
                        theta_val = atan(r_rel_ego[1], r_rel_ego[2])
                        if abs(theta_val) > spm_params.fov_rad / 2
                            continue  # Skip agents outside FOV
                        end
                        
                        # Add to filtered lists
                        # Transform relative velocity to ego-centric frame (same rotation as position)
                        v_rel_world = other.vel - agent.vel
                        v_rel_ego = [
                            cos_θ * v_rel_world[1] - sin_θ * v_rel_world[2],
                            sin_θ * v_rel_world[1] + cos_θ * v_rel_world[2]
                        ]
                        
                        push!(rel_pos_ego, r_rel_ego)
                        push!(rel_vel, v_rel_ego)
                        
                        # Add to local_agents for visualization
                        push!(local_agents, [r_rel_ego[1], r_rel_ego[2], Float64(Int(other.group))])
                    end
                end
                
                # DEBUG: Log filtering result for Agent 1
                if agent.id == 1 && step % 100 == 0
                    open(joinpath("log", "debug_filter.log"), "a") do io
                        println(io, "Step $step: Agent 1 sees $(length(rel_pos_ego)) agents after filtering (max_dist=$max_sensing_distance, fov_rad=$(spm_params.fov_rad))")
                        for (i, pos) in enumerate(rel_pos_ego)
                            dist = norm(pos)
                            theta = atan(pos[1], pos[2])
                            println(io, "  Agent $i: pos=$pos, dist=$dist, theta=$(rad2deg(theta))°")
                        end
                    end
                end
                
                # DEBUG: Log right before SPM generation for Agent 1
                # (Removed debug logging)
                
                # Generate SPM using ego-centric coordinates with adaptive β modulation
                # Use agent.precision from previous step (solves circular dependency)
                spm = generate_spm_3ch(spm_config, rel_pos_ego, rel_vel, agent_params.r_agent, agent.precision)
                
                # Compute action: predictive (M4) or reactive (M3)
                if control_params.use_predictive_control
                    # M4: Predictive collision avoidance with EFE
                    # Get other agents (exclude self)
                    other_agents = [a for a in agents if a.id != agent.id]
                    action = compute_action_predictive(
                        agent, spm, other_agents,
                        control_params, agent_params, world_params, spm_config
                    )
                else
                    # M3: Reactive control (baseline)
                    action = compute_action(agent, spm, control_params, agent_params)
                end
                
                # Apply exploration (for diverse VAE training data)
                if control_params.exploration_rate > 0 || control_params.exploration_noise > 0
                    if rand() < control_params.exploration_rate
                        # Epsilon-greedy: Random action
                        action = (rand(2) .* 2 .- 1) .* agent_params.u_max
                    else
                        # Gaussian noise on FEP action
                        if control_params.exploration_noise > 0
                            noise = randn(2) .* control_params.exploration_noise .* agent_params.u_max
                            action = action .+ noise
                        end
                    end
                    # Clamp to valid range
                    action = clamp.(action, -agent_params.u_max, agent_params.u_max)
                end
                
                # Step dynamics (with agent-agent collision detection)
                step!(agent, action, agent_params, world_params, obstacles, agents)
                
                # Log detail for selected agent
                if agent.id == detail_agent_id
                    fe = free_energy(agent.vel, agent.goal_vel, spm, control_params)
                    
                    # Compute Haze (uncertainty estimate from VAE latent variance)
                    # VAE provides theoretically grounded epistemic uncertainty via σ²_z
                    haze = 0.0
                    spm_recon = zeros(16, 16, 3)
                    
                    if vae_model !== nothing
                        try
                            # Reshape SPM to (16, 16, 3, 1) and convert to Float32 for Flux
                            spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
                            
                            # VAE forward pass: returns (x_hat, μ, logσ)
                            x_hat, μ, logσ = vae_model(spm_input)
                            
                            # Compute Haze from latent variance σ²_z (EPH Eq. 3.2)
                            # H[k] = Agg(σ²_z[k])
                            haze_val = VAEModel.compute_haze(vae_model, spm_input)
                            haze = Float64(haze_val[1])
                            
                            # Get reconstructed SPM (remove batch dim) and convert back to Float64
                            spm_recon = Float64.(x_hat[:, :, :, 1])
                        catch e
                            # Log error to file for debugging
                            if step % 50 == 0
                                open("log/vae_error.log", "a") do io
                                    println(io, "[Step $step] VAE Error: $e")
                                    showerror(io, e)
                                    println(io, "")
                                end
                                @warn "VAE inference failed: $e"
                            end
                            haze = 0.0
                            spm_recon = zeros(16, 16, 3)
                        end
                    end
                    
                    # Compute Precision from Haze: Π = 1/(H + ε)
                    precision = 1.0 / (haze + control_params.epsilon)
                    
                    # Publish detail packet with reconstruction
                    publish_detail(publisher, agent, spm, action, fe, haze, precision, spm_recon, step, agents, world_params, comm_params, spm_params, agent_params, local_agents)
                end
                
                # Update agent's precision for next iteration (all agents)
                # Precision Π = 1/(H + ε) where H is VAE latent variance
                if vae_model !== nothing
                    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
                    haze_val = VAEModel.compute_haze(vae_model, spm_input)
                    agent_haze = Float64(haze_val[1])
                    agent.precision = 1.0 / (agent_haze + control_params.epsilon)
                end
            end
            
            # Log all agents data for this step
            log_step!(data_logger, agents, step)
            
            # Publish global state
            publish_global(publisher, agents, step, comm_params)
            
            # Progress indicator
            if step % 100 == 0
                @printf("  Step %4d / %d\n", step, world_params.max_steps)
                flush(stdout)
            end
            
            # Real-time pacing (optional)
            sleep(world_params.dt * 0.5)  # Run at 2x speed
        end
        
    catch e
        if isa(e, InterruptException)
            println("\n\n⏸️  Simulation interrupted by user")
        else
            println("\n\n❌ Error: $e")
            rethrow(e)
        end
    finally
        # Cleanup
        println("\n🧹 Cleaning up...")
        close_publisher(publisher)
        close_logger(data_logger)
        println("✅ Simulation complete!")
    end
end

# Run simulation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
