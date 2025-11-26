"""
Shepherding Experiment Main Entry Point (with ZeroMQ Visualization)

This script runs a real-time shepherding simulation with:
- ShepherdingEPHv2 controller (SPM-based Social Value)
- Sheep BOIDS agents with flee behavior
- ZeroMQ messaging for live visualization via viewer.py
"""

using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Printf
using LinearAlgebra
using Random
using ZMQ
using JSON

# Setup module path
push!(LOAD_PATH, @__DIR__)

# Load modules in dependency order
include("core/Types.jl")
include("utils/MathUtils.jl")
include("perception/SPM.jl")
include("control/SelfHaze.jl")
include("agents/SheepAgent.jl")
include("control/SocialValue.jl")
include("control/ShepherdingEPHv2.jl")

using .Types
using .SheepAgent
using .ShepherdingEPHv2

"""
Create ZeroMQ visualization message
"""
function create_viz_message(frame::Int, dogs, flock, world_size::Float64, goal_position::Vector{Float64})
    agents = []

    # Add all dogs
    for dog in dogs
        # Dog 1 is marked with special color for tracking
        is_tracked = (dog.id == 1)
        color = is_tracked ? [255, 0, 255] : [255, 0, 0]  # Magenta for tracked, red for others

        push!(agents, Dict(
            "id" => dog.id,
            "x" => dog.position[1],
            "y" => dog.position[2],
            "vx" => dog.velocity[1],
            "vy" => dog.velocity[2],
            "radius" => dog.radius,  # Use actual physical radius (2.4)
            "color" => color,
            "orientation" => atan(dog.velocity[2], dog.velocity[1]),
            "has_goal" => true,
            "type" => "dog"
        ))
    end

    # Add sheep
    for (i, sheep) in enumerate(flock)
        push!(agents, Dict(
            "id" => 100 + i,  # Offset IDs to avoid collision with dog
            "x" => sheep.position[1],
            "y" => sheep.position[2],
            "vx" => sheep.velocity[1],
            "vy" => sheep.velocity[2],
            "radius" => sheep.radius,  # Use actual physical radius (2.0)
            "color" => [0, 200, 0],  # Green for sheep
            "orientation" => atan(sheep.velocity[2], sheep.velocity[1]),
            "has_goal" => false,
            "type" => "sheep"
        ))
    end

    # No haze grid for shepherding (could add if needed)
    haze_grid = fill(0.0, 10, 10)

    # Add tracked dog data (dog 1) for dashboard plots
    tracked_dog = dogs[1]

    # Convert SPM to lists for JSON (transpose for Python row-major order)
    spm_occ = tracked_dog.current_spm !== nothing ?
              collect(transpose(tracked_dog.current_spm[1, :, :])) :
              zeros(6, 6)
    spm_rad = tracked_dog.current_spm !== nothing ?
              collect(transpose(tracked_dog.current_spm[2, :, :])) :
              zeros(6, 6)
    spm_tan = tracked_dog.current_spm !== nothing ?
              collect(transpose(tracked_dog.current_spm[3, :, :])) :
              zeros(6, 6)

    tracked_data = Dict(
        "id" => tracked_dog.id,
        "self_haze" => tracked_dog.self_haze,
        "efe" => tracked_dog.last_efe,
        "entropy" => tracked_dog.last_entropy,
        "surprise" => tracked_dog.last_surprise,
        "gradient" => tracked_dog.last_gradient,
        "spm_occupancy" => [collect(row) for row in eachrow(spm_occ)],
        "spm_radial" => [collect(row) for row in eachrow(spm_rad)],
        "spm_tangential" => [collect(row) for row in eachrow(spm_tan)]
    )

    return Dict(
        "frame" => frame,
        "agents" => agents,
        "haze_grid" => haze_grid,
        "world_size" => [world_size, world_size],
        "goal_position" => goal_position,  # Add goal position to message
        "tracked_agent" => tracked_data
    )
end

"""
Run shepherding simulation with visualization
"""
function run_shepherding_with_viz()
    println("=" ^ 60)
    println("Phase 4 Shepherding Simulation (Real-time Visualization)")
    println("=" ^ 60)

    # === Parameters (from environment or defaults) ===
    world_size = parse(Float64, get(ENV, "EPH_WORLD_SIZE", "400.0"))
    n_sheep = parse(Int, get(ENV, "EPH_N_SHEEP", "30"))  # Default: 30 sheep
    n_dogs = parse(Int, get(ENV, "EPH_N_DOGS", "5"))     # Default: 5 dogs
    n_steps = parse(Int, get(ENV, "EPH_STEPS", "1000"))
    seed = parse(Int, get(ENV, "EPH_SEED", "42"))

    # Set random seed for reproducibility
    Random.seed!(seed)

    println("\nConfiguration:")
    println("  World size:    $(world_size) × $(world_size)")
    println("  Sheep:         $n_sheep")
    println("  Dogs:          $n_dogs")
    println("  Steps:         $n_steps")
    println("  Random seed:   $seed")

    # Goal position (top-right quadrant)
    goal_position = [0.75 * world_size, 0.75 * world_size]

    # === Initialize Agents ===
    println("\nInitializing agents...")

    # Sheep: spawn in center
    flock = create_sheep_flock(
        n_sheep, world_size,
        spawn_region=(0.4, 0.6),
        initial_weights=[1.5, 1.0, 1.0]
    )

    # Dogs: spawn around the perimeter
    dogs = ShepherdingDog[]
    for i in 1:n_dogs
        # Distribute dogs evenly around the perimeter
        angle = 2π * (i - 1) / n_dogs
        radius_spawn = 0.4 * world_size
        x = world_size / 2 + radius_spawn * cos(angle)
        y = world_size / 2 + radius_spawn * sin(angle)
        push!(dogs, ShepherdingDog(i, x, y))
    end

    # Shepherding parameters
    shep_params = ShepherdingParams(
        λ_compact=1.0,
        λ_goal=0.5,
        goal_position=goal_position,
        max_iter=3,
        η=0.05,
        max_speed=40.0
    )

    # Sheep parameters (with strong flee response, slower than dogs)
    sheep_params = SheepParams(
        world_size=world_size,
        flee_range=100.0,         # Matched to dog FOV range
        k_flee=800.0,             # Very strong flee force
        r_fear=40.0,              # Adjusted for narrower range
        max_speed=10.0,           # Much slower than dogs (dog: 40.0)
        max_acceleration=20.0,    # Slower acceleration
        dt=0.1
    )

    println("  ✓ $n_dogs dogs initialized around perimeter")
    println("  ✓ $n_sheep sheep spawned in center")
    @printf("  ✓ Goal set to [%.0f, %.0f]\n", goal_position...)

    # === Initialize ZMQ ===
    println("\nInitializing ZeroMQ...")
    ctx = Context()

    # PUB socket for simulation data
    socket = Socket(ctx, PUB)
    ZMQ.bind(socket, "tcp://*:5555")
    println("  ✓ ZMQ PUB Server bound to tcp://*:5555")

    # REP socket for control commands (non-blocking)
    control_socket = Socket(ctx, REP)
    ZMQ.bind(control_socket, "tcp://*:5556")
    println("  ✓ ZMQ REP Control bound to tcp://*:5556")
    println("  ✓ Ready for viewer connection")

    # No sleep needed - viewer will connect when ready
    # PUB-SUB and REQ-REP sockets work asynchronously

    # === Simulation Loop ===
    println("\nStarting simulation ($n_steps steps)...")
    println("Press Ctrl+C to stop")
    println("")

    # Disable default SIGINT handling
    Base.exit_on_sigint(false)

    # Simulation control variables
    should_reset = false
    is_running = true

    try
        for step in 1:n_steps
            # Check for control commands (non-blocking)
            # Use try-catch with DONTWAIT flag for non-blocking receive
            try
                # Try to receive with DONTWAIT flag (will throw if no message)
                cmd_json = ZMQ.recv(control_socket, String; mode=ZMQ.DONTWAIT)
                cmd = JSON.parse(cmd_json)

                if cmd["command"] == "reset"
                    # Reset simulation within the loop (don't break)
                    println("\n[CONTROL] Received RESET command - resetting agents...")

                    # Reinitialize all agents
                    dogs = ShepherdingEPHv2.create_shepherding_dogs(
                        n_dogs,
                        world_size,
                        shep_params
                    )

                    flock = create_sheep_flock(
                        n_sheep,
                        world_size,
                        spawn_region=(0.3, 0.7)
                    )

                    # Reset step counter
                    step = 1

                    println("[CONTROL] Reset complete - $(n_dogs) dogs, $(n_sheep) sheep")
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "ok", "message" => "reset_complete")))
                elseif cmd["command"] == "set_dog_speed"
                    new_speed = cmd["value"]
                    shep_params.max_speed = new_speed
                    println("[CONTROL] Dog max speed set to $new_speed")
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "ok", "dog_speed" => new_speed)))
                elseif cmd["command"] == "set_sheep_speed"
                    new_speed = cmd["value"]
                    sheep_params.max_speed = new_speed
                    sheep_params.max_acceleration = new_speed * 2.0  # Maintain ratio
                    println("[CONTROL] Sheep max speed set to $new_speed")
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "ok", "sheep_speed" => new_speed)))
                elseif cmd["command"] == "set_boids_params"
                    params_dict = cmd["value"]
                    if haskey(params_dict, "w_separation")
                        sheep_params.w_separation = params_dict["w_separation"]
                    end
                    if haskey(params_dict, "w_alignment")
                        sheep_params.w_alignment = params_dict["w_alignment"]
                    end
                    if haskey(params_dict, "w_cohesion")
                        sheep_params.w_cohesion = params_dict["w_cohesion"]
                    end
                    # Update flee weight in all sheep's boids_weights (3rd multiplier in update_sheep!)
                    if haskey(params_dict, "flee_weight")
                        # Store flee_weight separately for reference
                        flee_weight = params_dict["flee_weight"]
                        println("[CONTROL] BOIDS params updated: sep=$(sheep_params.w_separation), ali=$(sheep_params.w_alignment), coh=$(sheep_params.w_cohesion), flee=$flee_weight")
                    else
                        println("[CONTROL] BOIDS params updated: sep=$(sheep_params.w_separation), ali=$(sheep_params.w_alignment), coh=$(sheep_params.w_cohesion)")
                    end
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "ok")))
                elseif cmd["command"] == "set_goal_position"
                    new_goal = cmd["value"]  # [x, y] array
                    goal_position[1] = new_goal[1]
                    goal_position[2] = new_goal[2]
                    println("[CONTROL] Goal position updated to [$(goal_position[1]), $(goal_position[2])]")
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "ok", "goal_position" => goal_position)))
                else
                    ZMQ.send(control_socket, JSON.json(Dict("status" => "unknown_command")))
                end
            catch
                # No message available (EAGAIN error), continue normally
            end

            # Update all dogs (EPH controller with dog-dog collision avoidance)
            for dog in dogs
                update_shepherding_dog!(dog, flock, shep_params, world_size, other_dogs=dogs)
            end

            # Update sheep (BOIDS + flee from all dogs)
            dog_positions = [dog.position for dog in dogs]
            for sheep in flock
                update_sheep!(sheep, flock, dog_positions, sheep_params)
            end

            # Send visualization message (includes all dogs and sheep)
            msg = create_viz_message(step, dogs, flock, world_size, goal_position)
            ZMQ.send(socket, JSON.json(msg))

            # Progress indicator (every 100 steps)
            if step % 100 == 0
                com = compute_center_of_mass(flock)
                dist = norm(com - goal_position)
                compactness = compute_compactness(flock)
                @printf("  Step %4d: COM=[%.1f, %.1f], Goal dist=%.1f, Compact=%.1f\n",
                        step, com..., dist, compactness)
            end

            # Small delay for real-time visualization (60 FPS target)
            sleep(0.016)
        end

    catch e
        if isa(e, InterruptException)
            println("\n\nSimulation interrupted by user (Ctrl+C)")
        else
            println("\nError occurred:")
            rethrow(e)
        end
    finally
        # Cleanup
        println("\nCleaning up...")
        close(socket)
        close(control_socket)
        close(ctx)
        println("  ✓ ZMQ connections closed")

        # Final statistics (only if not resetting)
        if !should_reset
            final_com = compute_center_of_mass(flock)
            final_dist = norm(final_com - goal_position)
            final_compact = compute_compactness(flock)

            println("\n" * "=" ^ 60)
            println("Final State:")
            println("=" ^ 60)
            @printf("  Sheep COM:       [%.1f, %.1f]\n", final_com...)
            @printf("  Goal distance:   %.2f\n", final_dist)
            @printf("  Compactness:     %.2f\n", final_compact)

            if final_dist < 100.0
                println("\n  ✓ Goal reached!")
            else
                println("\n  Goal not reached (dist > 100)")
            end

            println("=" ^ 60)
        end
    end

    # Handle reset: restart simulation
    if should_reset
        println("\n" * "=" ^ 60)
        println("RESETTING SIMULATION...")
        println("=" ^ 60)
        run_shepherding_with_viz()  # Recursive call to restart
    end
end

"""
Main entry point
"""
function main()
    run_shepherding_with_viz()
end

# Run simulation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
