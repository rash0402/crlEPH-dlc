"""
Basic Shepherding Simulation Test.

Tests integration of:
1. Sheep BOIDS agents
2. SPM-based Social Value
3. EPH dog controller
4. Full simulation loop

Minimal test: 1 dog + 5 sheep, 100 steps
"""

using Printf
using LinearAlgebra

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
Run basic shepherding simulation.
"""
function run_shepherding_test()
    println("=" ^ 60)
    println("Basic Shepherding Simulation Test")
    println("=" ^ 60)

    # === Parameters (from environment or defaults) ===
    world_size = parse(Float64, get(ENV, "EPH_WORLD_SIZE", "400.0"))
    n_sheep = parse(Int, get(ENV, "EPH_N_SHEEP", "5"))
    n_steps = parse(Int, get(ENV, "EPH_STEPS", "100"))

    # Goal position (top-right quadrant)
    goal_position = [0.75 * world_size, 0.75 * world_size]

    # === Initialize Agents ===
    println("\n[1/4] Initializing agents...")

    # Sheep: spawn in center
    flock = create_sheep_flock(
        n_sheep, world_size,
        spawn_region=(0.4, 0.6),
        initial_weights=[1.5, 1.0, 1.0]
    )

    # Dog: spawn opposite side (bottom-left quadrant)
    dog = ShepherdingDog(1, 0.25 * world_size, 0.25 * world_size)

    # Shepherding parameters
    shep_params = ShepherdingParams(
        λ_compact=1.0,
        λ_goal=0.5,
        goal_position=goal_position,
        max_iter=3,  # Fast iteration for testing
        η=0.05,
        max_speed=40.0
    )

    # Sheep parameters
    sheep_params = SheepParams(
        world_size=world_size,
        flee_range=120.0,
        k_flee=150.0,
        r_fear=40.0,
        max_speed=40.0,
        dt=0.1
    )

    @printf("  ✓ Dog initialized at [%.0f, %.0f]\n", dog.position...)
    println("  ✓ $n_sheep sheep spawned in center")
    @printf("  ✓ Goal set to [%.0f, %.0f]\n", goal_position...)

    # === Initial State ===
    initial_com = compute_center_of_mass(flock)
    initial_compactness = compute_compactness(flock)
    initial_goal_dist = norm(initial_com - goal_position)

    println("\n[2/4] Initial state:")
    @printf("  Sheep COM:       [%.1f, %.1f]\n", initial_com...)
    @printf("  Compactness:     %.2f\n", initial_compactness)
    @printf("  Goal distance:   %.2f\n", initial_goal_dist)

    # === Simulation Loop ===
    println("\n[3/4] Running simulation ($n_steps steps)...")

    for step in 1:n_steps
        # Update dog (EPH controller)
        update_shepherding_dog!(dog, flock, shep_params, world_size)

        # Update sheep (BOIDS + flee)
        dog_positions = [dog.position]
        for sheep in flock
            update_sheep!(sheep, flock, dog_positions, sheep_params)
        end

        # Progress indicator
        if step % 20 == 0
            com = compute_center_of_mass(flock)
            dist = norm(com - goal_position)
            @printf("  Step %3d: COM=[%.1f, %.1f], Goal dist=%.1f\n",
                    step, com..., dist)
        end
    end

    # === Final State ===
    final_com = compute_center_of_mass(flock)
    final_compactness = compute_compactness(flock)
    final_goal_dist = norm(final_com - goal_position)

    println("\n[4/4] Final state:")
    @printf("  Sheep COM:       [%.1f, %.1f]\n", final_com...)
    @printf("  Compactness:     %.2f\n", final_compactness)
    @printf("  Goal distance:   %.2f\n", final_goal_dist)

    # === Evaluation ===
    println("\n" * "=" ^ 60)
    println("Evaluation")
    println("=" ^ 60)

    # Success criteria
    goal_reached = final_goal_dist < 100.0  # Within 100 units
    moved_towards_goal = final_goal_dist < initial_goal_dist
    maintained_cohesion = final_compactness < 2.0 * initial_compactness

    if goal_reached
        println("\nGoal reached (dist < 100):           ✓")
    else
        @printf("\nGoal reached (dist < 100):           ✗ (%.1f)\n", final_goal_dist)
    end

    @printf("Moved towards goal:                  %s\n",
            moved_towards_goal ? "✓" : "✗")
    @printf("Maintained cohesion (C < 2×init):    %s\n",
            maintained_cohesion ? "✓" : "✗")

    # Overall success
    success = goal_reached && moved_towards_goal && maintained_cohesion

    println("\n" * "=" ^ 60)
    if success
        println("TEST PASSED ✓")
    else
        println("TEST PARTIAL (some criteria not met)")
    end
    println("=" ^ 60)

    return success
end

"""
Main entry point
"""
function main()
    try
        success = run_shepherding_test()
        exit(success ? 0 : 1)
    catch e
        println("\n" * "=" ^ 60)
        println("TEST FAILED ✗")
        println("=" ^ 60)
        rethrow(e)
    end
end

# Run test
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
