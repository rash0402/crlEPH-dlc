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
using .SelfHaze
using .EPH
using ZMQ
using JSON

function main()
    println("Starting Julia EPH Server (Sparse Foraging Task)...")
    println("Active Inference: Expected Free Energy with Self-Hazing")

    # Initialize EPH Parameters
    params = Types.EPHParams(
        # Self-hazing parameters
        h_max=0.8,
        α=10.0,              # Increased sensitivity (was 2.0)
        Ω_threshold=0.05,    # Lowered threshold (was 1.0) - typical occupancy is 0.0-0.15
        γ=2.0,
        # EFE weights
        β=1.0,   # Increased entropy term weight (was 0.5) for stronger exploration drive
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

    # Initialize Sparse Foraging Environment (smaller for more interactions)
    env = Simulation.initialize_simulation(width=600.0, height=600.0, n_agents=10)
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

            # Special tracking data for Agent 1 (red agent)
            tracked_agent = env.agents[1]
            tracked_data = if tracked_agent.current_spm !== nothing && tracked_agent.current_precision !== nothing
                # Compute EFE and entropy for tracking
                H_belief = SelfHaze.compute_belief_entropy(tracked_agent.current_precision)

                # Compute current EFE (with zero action for reference)
                zero_action = [0.0, 0.0]
                efe_current = EPH.expected_free_energy(zero_action, tracked_agent,
                                                       tracked_agent.current_spm, nothing, params)

                # SPM occupancy statistics
                spm_occupancy = tracked_agent.current_spm[1, :, :]
                spm_total = sum(spm_occupancy)
                spm_max = maximum(spm_occupancy)

                # Gradient information (for visualization)
                grad_x = tracked_agent.current_gradient !== nothing ? tracked_agent.current_gradient[1] : 0.0
                grad_y = tracked_agent.current_gradient !== nothing ? tracked_agent.current_gradient[2] : 0.0
                grad_norm = tracked_agent.current_gradient !== nothing ? sqrt(grad_x^2 + grad_y^2) : 0.0

                # Send full SPM for visualization
                Dict(
                    "efe" => efe_current,
                    "self_haze" => tracked_agent.self_haze,
                    "belief_entropy" => H_belief,
                    "num_visible" => length(tracked_agent.visible_agents),
                    "spm_total_occupancy" => spm_total,
                    "spm_max_occupancy" => spm_max,
                    "speed" => sqrt(tracked_agent.velocity[1]^2 + tracked_agent.velocity[2]^2),
                    # Gradient visualization
                    "gradient_x" => grad_x,
                    "gradient_y" => grad_y,
                    "gradient_norm" => grad_norm,
                    # Full SPM channels for heatmap visualization
                    "spm_occupancy" => collect(tracked_agent.current_spm[1, :, :]),  # Occupancy channel
                    "spm_radial_vel" => collect(tracked_agent.current_spm[2, :, :]), # Radial velocity
                    "spm_tangential_vel" => collect(tracked_agent.current_spm[3, :, :]) # Tangential velocity
                )
            else
                nothing
            end

            message = Dict(
                "frame" => env.frame_count,
                "agents" => agents_data,
                "haze_grid" => env.haze_grid,  # Keep for backward compatibility
                "coverage" => sum(env.coverage_map) / length(env.coverage_map),
                "tracked_agent" => tracked_data  # Detailed data for Agent 1
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
