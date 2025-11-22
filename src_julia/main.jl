using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

include("utils/MathUtils.jl")
include("core/Types.jl")
include("perception/SPM.jl")
include("control/SelfHaze.jl")
include("control/EPH.jl")
include("Simulation.jl")

using .Simulation
using .Types
using ZMQ
using JSON

function main()
    println("Starting Julia EPH Server (Sparse Foraging Task)...")
    println("Active Inference: Expected Free Energy with Self-Hazing")

    # Initialize EPH Parameters
    params = Types.EPHParams(
        # Self-hazing parameters
        h_max=0.8,
        α=2.0,
        Ω_threshold=1.0,
        γ=2.0,
        # EFE weights
        β=0.5,   # Entropy term (epistemic value)
        λ=0.1,   # Pragmatic term (low for exploration-focused behavior)
        # Precision
        Π_max=1.0,
        decay_rate=0.1,
        # Optimization
        max_iter=5,
        η=0.1,
        # Physical
        max_speed=50.0,
        max_accel=100.0,
        # FOV
        fov_angle=210.0 * π / 180.0,  # 210 degrees
        fov_range=100.0
    )

    # Initialize Sparse Foraging Environment (smaller world for better observation)
    env = Simulation.initialize_simulation(width=500.0, height=500.0, n_agents=10)
    println("Simulation initialized with $(length(env.agents)) agents.")
    println("World size: $(env.width) × $(env.height)")
    println("FOV: $(params.fov_angle * 180 / π)° × $(params.fov_range)px")

    # Initialize ZeroMQ
    context = Context()
    socket = Socket(context, PUB)
    bind(socket, "tcp://*:5555")
    println("ZMQ Server bound to tcp://*:5555")

    # Main Loop
    try
        while true
            # Step Simulation with EPH Parameters
            Simulation.step!(env, params)

            # Prepare Data for Visualization
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
                    "orientation" => agent.orientation,
                    "has_goal" => agent.goal !== nothing,
                    # Active Inference state
                    "self_haze" => agent.self_haze,
                    "num_visible" => length(agent.visible_agents)
                ))
            end

            message = Dict(
                "frame" => env.frame_count,
                "agents" => agents_data,
                "haze_grid" => env.haze_grid,  # Keep for backward compatibility
                "coverage" => sum(env.coverage_map) / length(env.coverage_map)
            )

            # Send Data
            ZMQ.send(socket, JSON.json(message))

            if env.frame_count % 100 == 0
                coverage_pct = 100.0 * sum(env.coverage_map) / length(env.coverage_map)
                println("Frame: $(env.frame_count) | Coverage: $(round(coverage_pct, digits=1))%")
            end

            # Sleep to limit FPS (approx 60 FPS)
            sleep(0.016)
        end
    catch e
        if e isa InterruptException
            println("\nServer stopped by user.")
            coverage_pct = 100.0 * sum(env.coverage_map) / length(env.coverage_map)
            println("Final coverage: $(round(coverage_pct, digits=1))%")
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
