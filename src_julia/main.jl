using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

include("utils/MathUtils.jl")
include("core/Types.jl")
include("perception/SPM.jl")
include("control/EPH.jl")
include("Simulation.jl")

using .Simulation
using ZMQ
using JSON

function main()
    println("Starting Julia EPH Server...")
    
    # Initialize Simulation
    env = Simulation.initialize_simulation(width=800.0, height=800.0, n_agents=20)
    println("Simulation initialized with $(length(env.agents)) agents.")
    
    # Initialize ZeroMQ
    context = Context()
    socket = Socket(context, PUB)
    bind(socket, "tcp://*:5555")
    println("ZMQ Server bound to tcp://*:5555")
    
    # Main Loop
    frame_count = 0
    try
        while true
            # Step Simulation
            Simulation.step!(env)
            
            # Prepare Data
            agents_data = []
            for agent in env.agents
                push!(agents_data, Dict(
                    "id" => agent.id,
                    "x" => agent.position[1],
                    "y" => agent.position[2],
                    "vx" => agent.velocity[1],
                    "vy" => agent.velocity[2],
                    "radius" => agent.radius,
                    "color" => agent.color,
                    "orientation" => agent.orientation
                ))
            end
            
            message = Dict(
                "frame" => frame_count,
                "agents" => agents_data,
                "haze_grid" => env.haze_grid
            )
            
            # Send Data
            ZMQ.send(socket, JSON.json(message))
            
            frame_count += 1
            if frame_count % 100 == 0
                println("Frame: $frame_count")
            end
            
            # Sleep to limit FPS (approx 60 FPS)
            sleep(0.016)
        end
    catch e
        if e isa InterruptException
            println("Server stopped by user.")
        else
            rethrow(e)
        end
    finally
        close(socket)
        close(context)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
