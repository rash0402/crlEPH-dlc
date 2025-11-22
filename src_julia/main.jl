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
using Statistics  # For var() function

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
    env = Simulation.initialize_simulation(width=300.0, height=300.0, n_agents=10)
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
                # Compute Belief Entropy (Combined: Spatial + Temporal Uncertainty)
                
                # 1. Spatial Uncertainty: Entropy of Precision Matrix
                H_spatial = SelfHaze.compute_belief_entropy(tracked_agent.current_precision)
                
                # 2. Temporal Uncertainty: Prediction error variance
                H_temporal = if tracked_agent.previous_spm !== nothing
                    # Compute prediction error
                    prediction_error = tracked_agent.current_spm .- tracked_agent.previous_spm
                    
                    # Variance of prediction error (focus on occupancy channel)
                    error_variance = var(prediction_error[1, :, :])
                    
                    # Convert variance to entropy-like measure
                    # H = -log(1/σ²) = log(σ²)
                    # Add small epsilon to avoid log(0)
                    log(error_variance + 1e-6)
                else
                    # First frame: no temporal uncertainty
                    0.0
                end
                
                # Combined Belief Entropy
                H_belief = H_spatial + H_temporal

                # Compute current EFE (with zero action for reference)
                zero_action = [0.0, 0.0]
                efe_current = EPH.expected_free_energy(zero_action, tracked_agent,
                                                       tracked_agent.current_spm, nothing, params)

                # Compute Surprise (Prediction Error) using previous SPM
                # Surprise = sum of precision-weighted squared prediction errors
                # High surprise = observations differ significantly from predictions
                
                if tracked_agent.previous_spm !== nothing
                    # Prediction error: difference between current and previous SPM
                    prediction_error = tracked_agent.current_spm .- tracked_agent.previous_spm
                    
                    # Compute precision matrix
                    h_self = SelfHaze.compute_self_haze(tracked_agent.current_spm, params)
                    Π = SelfHaze.compute_precision_matrix(tracked_agent.current_spm, h_self, params)
                    
                    # Precision-weighted squared prediction error (Multi-Channel)
                    # Include all three SPM channels with appropriate weighting
                    Nr, Nθ = size(tracked_agent.current_spm, 2), size(tracked_agent.current_spm, 3)
                    
                    # Channel weights (importance of each channel for surprise)
                    w_occ = 1.0   # Occupancy (most important)
                    w_rad = 0.5   # Radial velocity (approaching/receding)
                    w_tan = 0.3   # Tangential velocity (lateral motion)
                    
                    surprise = sum(
                        let
                            # Squared prediction errors for all channels
                            error_occ = prediction_error[1, r, t]^2
                            error_rad = prediction_error[2, r, t]^2
                            error_tan = prediction_error[3, r, t]^2
                            
                            # Combined weighted error
                            weighted_error = w_occ * error_occ + w_rad * error_rad + w_tan * error_tan
                            
                            # Weight by precision (high precision = high surprise for errors)
                            prec = Π[r, t]
                            # Distance weighting (closer bins matter more)
                            dist_weight = 1.0 / (r + 0.1)
                            
                            prec * weighted_error * dist_weight
                        end
                        for r in 1:Nr, t in 1:Nθ
                    )
                else
                    # First frame: no previous SPM, surprise = 0
                    surprise = 0.0
                end

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
                    "surprise" => surprise,  # Prediction error-based surprise
                    "self_haze" => tracked_agent.self_haze,
                    "entropy" => H_belief,  # Combined belief entropy
                    "entropy_spatial" => H_spatial,  # Spatial component
                    "entropy_temporal" => H_temporal,  # Temporal component
                    "num_visible" => length(tracked_agent.visible_agents),
                    "spm_total_occupancy" => spm_total,
                    "spm_max_occupancy" => spm_max,
                    "speed" => sqrt(tracked_agent.velocity[1]^2 + tracked_agent.velocity[2]^2),
                    # Gradient visualization (as array for Python)
                    "gradient" => [grad_x, grad_y],
                    "gradient_norm" => grad_norm,
                    # Full SPM channels for heatmap visualization
                    "spm_occupancy" => collect(tracked_agent.current_spm[1, :, :]),  # Occupancy channel
                    "spm_radial" => collect(tracked_agent.current_spm[2, :, :]), # Radial velocity
                    "spm_tangential" => collect(tracked_agent.current_spm[3, :, :]) # Tangential velocity
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
