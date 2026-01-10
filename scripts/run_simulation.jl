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
include("../src/prediction.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")
include("../src/communication.jl")
include("../src/logger.jl")
include("../src/action_vae.jl")

using Statistics
using Dates
using Flux
using BSON
using ArgParse
using DelimitedFiles  # For CSV export
using Random
using HDF5
using .Config
using .SPM
using .Dynamics
using .Controller
using .Communication
using .Logger
using .ActionVAEModel

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
            help = "Number of agents per group (Total = 4x)"
            arg_type = Int
            default = 10
        "--steps"
            help = "Simulation steps"
            arg_type = Int
            default = 1000
        "--condition"
            help = "Experiment condition (1=BASELINE, 2=SPM, 3=BETA, 4=EPH)"
            arg_type = Int
            default = 4
        "--output"
            help = "Output HDF5 file path"
            arg_type = String
            default = ""
        "--scenario"
            help = "Simulation scenario: 'scramble' (4-way crossing) or 'corridor' (bidirectional)"
            arg_type = String
            default = "scramble"
        "--corridor-width"
            help = "Corridor width in meters (only for corridor scenario)"
            arg_type = Float64
            default = 4.0
        "--k-emergency"
            help = "Emergency repulsion strength (lower = more freezing possible)"
            arg_type = Float64
            default = 20.0
        "--no-emergency"
            help = "Disable emergency avoidance entirely"
            action = :store_true
    end

    return parse_args(s)
end

"""
Main simulation loop
"""
function main()
    args = parse_commandline()
    
    # Set seed
    Random.seed!(args["seed"])
    
    println("=" ^ 60)
    println("=" ^ 60)
    println("!!! EPH Simulation - VERSION 3 STARTING !!!")
    println("!!! IF YOU DO NOT SEE THIS, OLD CODE IS RUNNING !!!")
    println("=" ^ 60)
    
    # Load configuration
    # Initialize parameters with overrides from args
    condition_enum = Config.ExperimentCondition(args["condition"])
    
    control_params = ControlParams(
        experiment_condition=condition_enum, 
        use_predictive_control=true
    )
    
    world_params = WorldParams(max_steps=args["steps"])
    comm_params = CommParams()
    spm_params = SPMParams()
    
    # Override agent density and emergency parameters
    agent_params = AgentParams(
        n_agents_per_group=args["density"],
        k_emergency=args["k-emergency"],
        enable_emergency=!args["no-emergency"]
    )
    
    println("\n📋 Configuration (Seed: $(args["seed"])):")
    println("  Condition: $(condition_enum)")
    println("  SPM: $(spm_params.n_rho)x$(spm_params.n_theta), FOV=$(spm_params.fov_deg)°")
    
    # Scenario-based initialization
    scenario = args["scenario"]
    println("  Scenario: $scenario")
    
    if scenario == "corridor"
        println("  Agents: $(agent_params.n_agents_per_group) per group (2 groups: East/West)")
        println("  Obstacles: Corridor walls (width=4.0m)")
    else
        println("  Agents: $(agent_params.n_agents_per_group) per group (4 groups)")
        println("  Obstacles: 4 corners ($(world_params.obstacle_size)x$(world_params.obstacle_size))")
    end
    println("  Goal area: center ±$(world_params.center_margin)")
    println("  World: $(world_params.width)x$(world_params.height), dt=$(world_params.dt)s")
    println("  Steps: $(world_params.max_steps)")
    println("  ZMQ: $(comm_params.zmq_endpoint)")
    
    # Initialize agents based on scenario
    println("\n🤖 Initializing agents...")
    if scenario == "corridor"
        agents = init_corridor_agents(agent_params, world_params, corridor_width=args["corridor-width"], seed=args["seed"])
    else
        agents = init_agents(agent_params, world_params, seed=args["seed"])
    end
    println("  Total agents: $(length(agents))")
    
    # Initialize obstacles based on scenario
    println("\n🚧 Initializing obstacles...")
    if scenario == "corridor"
        obstacles = init_corridor_obstacles(world_params, corridor_width=args["corridor-width"])
        println("  Corridor walls: $(length(obstacles)), width=$(args["corridor-width"])m")
    else
        obstacles = init_obstacles(world_params)
        println("  Corner obstacles: $(length(obstacles))")
    end
    
    # Initialize SPM
    println("\n🗺️  Initializing SPM...")
    spm_config = init_spm(spm_params)
    
    # Initialize communication
    println("\n📡 Initializing ZMQ publisher...")
    publisher = init_publisher(comm_params)
    println("  Listening on: $(comm_params.zmq_endpoint)")
    
    # Initialize HDF5 logger
    println("\n💾 Initializing HDF5 logger...")
    
    log_filename = args["output"]
    if isempty(log_filename)
        timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
        if !isdir(joinpath("data", "logs"))
            mkpath(joinpath("data", "logs"))
        end
        log_filename = joinpath("data", "logs", "eph_sim_$(timestamp).h5")
    else
        # Ensure directory exists
        dir = dirname(log_filename)
        if !isdir(dir)
             mkpath(dir)
        end
    end
    
    data_logger = init_logger(log_filename, world_params.max_steps, length(agents))
    println("  Output: $(log_filename)")
    
    # Load VAE model for Haze estimation (EPH theoretical requirement)
    # VAE's latent variance σ²_z provides epistemic uncertainty: H[k] = Agg(σ²_z[k])
    println("\n🧠 Loading VAE model...")
    vae_model = nothing
    model_path = "models/action_vae_best.bson"
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
    
    # Initialize collision counter per agent
    collision_count = zeros(Int, length(agents))
    
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
                # DEBUG: Log filtering result for Agent 1
                # if agent.id == 1 && step % 100 == 0
                #     open(joinpath("log", "debug_filter.log"), "a") do io
                #         println(io, "Step $step: Agent 1 sees $(length(rel_pos_ego)) agents after filtering (max_dist=$max_sensing_distance, fov_rad=$(spm_params.fov_rad))")
                #         for (i, pos) in enumerate(rel_pos_ego)
                #             dist = norm(pos)
                #             theta = atan(pos[1], pos[2])
                #             println(io, "  Agent $i: pos=$pos, dist=$dist, theta=$(rad2deg(theta))°")
                #         end
                #     end
                # end
                
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
                    # M3: Reactive control
                    # A1_BASELINE / A2_SPM_ONLY: Standard FEP
                    # A3_ADAPTIVE_BETA / A4_EPH: FEP with Surprise (if VAE available)
                    
                    if vae_model !== nothing && (control_params.experiment_condition == Config.A4_EPH || control_params.experiment_condition == Config.A3_ADAPTIVE_BETA)
                        # Compute current surprise (reconstruction error)
                        # Using previous action (or zero if first step) for surprise estimation context is tricky
                        # Instead, we assume the agent wants to minimize NEW surprise
                        # For simplicity in this loop, we calculate surprise of CURRENT state given ZERO action (baseline)
                        # Or ideally, we pass the surprise function to the controller to optimize u
                        
                        # Current implementation of compute_action_with_surprise optimizes u to minimize:
                        # F = F_vel + F_obs + λ * ||SPM - VAE(SPM, u)||²
                        # We need a baseline surprise value for logging, but the optimization handles the minimization
                        
                        # We use a default surprise value of 0.0 for the function call signature if not optimizing iteratively
                        # But wait, compute_action_with_surprise takes `surprise` as a FLOAT scalar argument.
                        # Looking at controller.jl: it uses `surprise` as a weight or pre-computed value?
                        # Re-reading controller.jl: 
                        # function free_energy_with_surprise(..., surprise::Float64; ...)
                        # F_surprise = λ_surprise * surprise
                        # This means 'surprise' is treated as a CONSTANT scalar in the gradient! 
                        # This is WRONG if we want to Minimize surprise through action u.
                        # The derivative ∇_u (Surprise) would be 0 if 'surprise' is passed as a constant float.
                        
                        # Correction: We want u that minimizes reconstruction error.
                        # The current controller implementation passed 'surprise' scalar, which is constant w.r.t velocity.
                        # That implementation effectively adds a constant penalty term, which does NOT affect the gradient ∇_v F.
                        # So u = -η * ∇F will be identically same as before.
                        
                        # To actually minimize surprise, the free energy function must Evaluating Surprise(v) where v -> u.
                        # Since VAE is a neural network, taking gradient of VAE output w.r.t input u inside the controller loop (using ForwardDiff)
                        # requires the VAE model to be differentiable and included in the free_energy function closure.
                        
                        # Given the complexity of differentiating through the Flux model within the ForwardDiff call for every agent step,
                        # we should fallback to a sample-based or discrete choice, OR simply accept that we cannot easily gradient-descent through the VAE in Julia's ForwardDiff without significant overhead.
                        
                        # Alternative: Use "Haze" (Uncertainty) as the modulator for control gain (Beta), which IS implemented.
                        # The user asked to "reduce surprise".
                        # If we assume "Surprise" = "Haze" (Uncertainty), then reducing Haze is what Pattern D does via action selection?
                        # Pattern D trained VAE allows estimating H(y, u).
                        # If we want to pick u to minimize H(y, u), we need to search u.
                        
                        # Let's stick to the request: "Use compute_action_with_surprise".
                        # If I implemented it taking a Float, I made a mistake in controller.jl logic if the goal was active minimization.
                        # However, if the goal is just "Precision Control" (Beta modulation), then we don't need a new action function, we just need to update how `agent.precision` is used.
                        # The user said "precisionではなく，サプライズを低減させたい" (Not precision, want to reduce surprise).
                        
                        # If I look at the previous turn, the user approved "F = F_vel + F_obstacle + λ * Surprise".
                        # If Surprise is fixed scalar, it does nothing for minimization.
                        # I must have implemented it wrong or misunderstood.
                        # Let's check `controller.jl` again.
                        
                        # If I cannot change controller.jl right now easily (I can, but...), 
                        # simplest "Effective" way to minimize surprise without full gradient:
                        # Sample candidate actions, evaluate Free Energy + Surprise for each, pick best.
                        
                        # But let's look at what I CAN do.
                        # I will use standard compute_action for now to avoid breaking run, 
                        # BUT I will update the logic to actually USE the VAE for action selection if possible.
                        # Or, I will revert to Beta modulation but call it "Surprise based modulation".
                        
                        # Actually, looking at the user request: "re-run with surprise enabled". 
                        # I need to make sure `compute_action_with_surprise` actually does something useful.
                        # If it just takes a float, it does nothing.
                        
                        # Let's assume for this step, we just use standard compute_action but we ensure Haze/Surprise is calculated and logged correctly,
                        # and maybe we update precision based on Surprise.
                        
                        # Wait, the prompt said "Current I implemented... F_surprise = λ * surprise".
                        # Yes, that is a constant offset. It does not change the optimal 'u'.
                        # The user might have been misled by my explanation or I misled myself.
                        
                        # CORRECT APPROACH for "Active Surprise Minimization":
                        # We need to evaluate F(u) = F_task(u) + λ * Surprise(u) for multiple u, and pick best.
                        # Since we can't easily grad-descend, let's use a simple Sampling optimizer.
                        
                        # Implementing Sample-based Action Selection here:
                        if vae_model !== nothing
                             # Sample candidates
                             n_samples = 10
                             best_u = [0.0, 0.0]
                             min_F = Inf
                             
                             # Candidates: 
                             # 1. Gradient-based action (task only)
                             u_grad = compute_action(agent, spm, control_params, agent_params)
                             candidates = [u_grad]
                             
                             # 2. Random perturbations
                             for _ in 1:n_samples
                                 push!(candidates, u_grad .+ 2.0 .* randn(2))
                             end
                             # 3. Stop
                             push!(candidates, [0.0, 0.0])
                             
                             # Evaluate
                             for u_cand in candidates
                                 u_cand = clamp.(u_cand, -agent_params.u_max, agent_params.u_max)
                                 
                                 # Task Free Energy
                                 v_cand = agent.vel + (u_cand .- agent_params.damping .* agent.vel) ./ agent_params.mass .* world_params.dt
                                 F_task = free_energy(v_cand, agent.goal_vel, spm, control_params)
                                 
                                 # Surprise Term
                                 surp = compute_surprise(vae_model, spm, u_cand)
                                 
                                 # Total
                                 lambda = 100.0 # Weight for surprise
                                 F_total = F_task + lambda * surp
                                 
                                 if F_total < min_F
                                     min_F = F_total
                                     best_u = u_cand
                                 end
                             end
                             action = best_u
                        else
                             action = compute_action(agent, spm, control_params, agent_params)
                        end
                        
                    else
                        action = compute_action(agent, spm, control_params, agent_params)
                    end
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
                
                # Step dynamics (with collision detection - returns collision count)
                collisions_this_step = step!(agent, action, agent_params, world_params, obstacles, agents)
                collision_count[agent.id] += collisions_this_step
                
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
                            # Needs action u for Pattern B prediction
                            action_input = Float32.(reshape(action, 2, 1))
                            x_hat, μ, logσ = vae_model(spm_input, action_input)
                            
                            # Compute Haze from latent variance σ²_z (EPH Eq. 3.2)
                            # H[k] = Agg(σ²_z(y[k], u[k])) -> Action-Dependent
                            haze_val = ActionVAEModel.compute_haze(vae_model, spm_input, action_input)
                            haze = Float64(haze_val[1])
                            
                            # Get reconstructed SPM (remove batch dim) and convert back to Float64
                            spm_recon = Float64.(x_hat[:, :, :, 1])
                        catch e
                            # Log error to file for debugging
                            if step % 50 == 0
                                open(joinpath("data", "logs", "vae_error.log"), "a") do io
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
                # A1_BASELINE: Fixed precision (no Haze modulation)
                # A3_ADAPTIVE_BETA / A4_EPH: VAE-based Haze modulation
                if control_params.experiment_condition == Config.A1_BASELINE || control_params.experiment_condition == Config.A2_SPM_ONLY
                    # Fixed precision for baseline conditions
                    agent.precision = 1.0
                elseif vae_model !== nothing
                    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
                    action_input = Float32.(reshape(action, 2, 1))
                    haze_val = ActionVAEModel.compute_haze(vae_model, spm_input, action_input)
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
        close_logger(data_logger, collision_counts=collision_count)
        println("✅ Simulation complete!")
    end
end

# Run simulation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
