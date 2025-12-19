#!/usr/bin/env julia

"""
EPH Main Simulation Script
4-group scramble crossing with FEP controller
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates

# Load modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")
include("../src/communication.jl")
include("../src/logger.jl")

using .Config
using .SPM
using .Dynamics
using .Controller
using .Communication
using .Logger

"""
Main simulation loop
"""
function main()
    println("=" ^ 60)
    println("EPH Simulation - M1 Baseline (Fixed β)")
    println("=" ^ 60)
    
    # Load configuration
    spm_params = DEFAULT_SPM
    world_params = DEFAULT_WORLD
    agent_params = DEFAULT_AGENT
    control_params = DEFAULT_CONTROL
    comm_params = DEFAULT_COMM
    
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
    
    # Initialize logger
    println("\n💾 Initializing HDF5 logger...")
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    log_filename = "data_$(timestamp).h5"
    data_logger = init_logger(log_filename, spm_params, world_params)
    println("  Output: $(log_filename)")
    
    # Select agent for detailed logging (first agent from NORTH group)
    detail_agent_id = 1
    
    println("\n▶️  Starting simulation...")
    println("  Press Ctrl+C to stop\n")
    
    # Simulation loop
    try
        for step in 1:world_params.max_steps
            # Update all agents
            for agent in agents
                # Get relative positions and velocities
                rel_pos = Vector{Float64}[]
                rel_vel = Vector{Float64}[]
                
                for other in agents
                    if other.id != agent.id
                        r_rel = relative_position(agent.pos, other.pos, world_params)
                        v_rel = other.vel - agent.vel
                        push!(rel_pos, r_rel)
                        push!(rel_vel, v_rel)
                    end
                end
                
                # Generate SPM
                spm = generate_spm_3ch(spm_config, rel_pos, rel_vel, agent_params.r_agent, agent.vel)
                
                # Compute action
                action = compute_action(agent, spm, control_params, agent_params)
                
                # Step dynamics (with agent-agent collision detection)
                step!(agent, action, agent_params, world_params, obstacles, agents)
                
                # Log detail for selected agent
                if agent.id == detail_agent_id
                    fe = free_energy(agent.vel, agent.goal_vel, spm, control_params)
                    log_step!(data_logger, spm, action, agent.pos, agent.vel)
                    
                    # Publish detail packet
                    publish_detail(publisher, agent, spm, action, fe, step, agents, world_params, comm_params)
                end
            end
            
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
