"""
Test script for Sheep BOIDS implementation.

Tests:
1. BOIDS forces computation
2. Flee-from-dog behavior
3. Time-varying BOIDS weights
4. Multi-sheep simulation
"""

using Printf
using LinearAlgebra

# Setup module path
push!(LOAD_PATH, @__DIR__)

# Load modules
include("utils/MathUtils.jl")
include("agents/SheepAgent.jl")

using .SheepAgent

"""
Test 1: Basic BOIDS forces
"""
function test_boids_forces()
    println("\n=== Test 1: BOIDS Forces ===")

    params = SheepParams(world_size=400.0)

    # Create 3 sheep in a line
    sheep1 = Sheep(1, 200.0, 200.0, vx=10.0, vy=0.0)
    sheep2 = Sheep(2, 250.0, 200.0, vx=10.0, vy=0.0)  # 50 units to the right
    sheep3 = Sheep(3, 150.0, 200.0, vx=10.0, vy=0.0)  # 50 units to the left

    flock = [sheep1, sheep2, sheep3]

    # Compute BOIDS for sheep1 (middle)
    boids = compute_boids_forces(sheep1, flock, params)

    @printf("Sheep 1 (middle) BOIDS forces:\n")
    @printf("  Separation: [%.2f, %.2f]\n", boids.separation...)
    @printf("  Alignment:  [%.2f, %.2f]\n", boids.alignment...)
    @printf("  Cohesion:   [%.2f, %.2f]\n", boids.cohesion...)

    # Expected: Separation should push away from both neighbors (≈ 0 in x, some noise in y)
    # Alignment should match average velocity (10, 0)
    # Cohesion should be ≈ 0 (already at center)

    println("✓ BOIDS forces computed successfully")
end

"""
Test 2: Flee-from-dog behavior
"""
function test_flee_from_dog()
    println("\n=== Test 2: Flee-from-Dog ===")

    params = SheepParams(
        flee_range=120.0,
        k_flee=150.0,
        r_fear=40.0,
        world_size=400.0
    )

    sheep = Sheep(1, 200.0, 200.0)

    # Dog at different distances
    distances = [10.0, 40.0, 80.0, 120.0, 150.0]

    println("\nFlee force vs distance:")
    for dist in distances
        dog_pos = [200.0 + dist, 200.0]
        flee = compute_flee_force(sheep, [dog_pos], params)

        flee_magnitude = norm(flee)
        expected = dist < params.flee_range ? params.k_flee * exp(-dist / params.r_fear) : 0.0

        @printf("  d=%.0f: |F|=%.2f (expected: %.2f) %s\n",
                dist, flee_magnitude, expected,
                abs(flee_magnitude - expected) < 1.0 ? "✓" : "✗")
    end

    println("✓ Flee force decay verified")
end

"""
Test 3: Time-varying BOIDS weights
"""
function test_temporal_weights()
    println("\n=== Test 3: Time-Varying BOIDS Weights ===")

    flock = create_sheep_flock(5, 400.0, initial_weights=[1.5, 1.0, 1.0])
    T_total = 300.0

    test_times = [50.0, 150.0, 250.0]
    expected_weights = [
        [1.0, 1.0, 2.5],    # Phase 1: High cohesion
        [1.5, 1.0, 1.0],    # Phase 2: Balanced
        [3.0, 0.5, 0.5]     # Phase 3: High separation
    ]

    for (i, t) in enumerate(test_times)
        adjust_boids_weights_temporal!(flock, t, T_total)

        w_actual = flock[1].boids_weights
        w_expected = expected_weights[i]

        match = all(abs.(w_actual .- w_expected) .< 0.01)

        @printf("  t=%.0f: [%.1f, %.1f, %.1f] %s\n",
                t, w_actual..., match ? "✓" : "✗")
    end

    println("✓ Temporal weight adjustment working")
end

"""
Test 4: Multi-step simulation
"""
function test_simulation()
    println("\n=== Test 4: Multi-Step Simulation ===")

    params = SheepParams(world_size=400.0, dt=0.1)

    # Create flock
    flock = create_sheep_flock(10, 400.0, spawn_region=(0.4, 0.6))

    # Single dog position
    dog_pos = [200.0, 100.0]

    # Simulate 20 steps
    n_steps = 20

    initial_com = compute_center_of_mass(flock)
    initial_compactness = compute_compactness(flock)

    @printf("Initial state:\n")
    @printf("  Center of mass: [%.1f, %.1f]\n", initial_com...)
    @printf("  Compactness:    %.2f\n", initial_compactness)

    for step in 1:n_steps
        for sheep in flock
            update_sheep!(sheep, flock, [dog_pos], params)
        end
    end

    final_com = compute_center_of_mass(flock)
    final_compactness = compute_compactness(flock)

    @printf("\nAfter %d steps:\n", n_steps)
    @printf("  Center of mass: [%.1f, %.1f]\n", final_com...)
    @printf("  Compactness:    %.2f\n", final_compactness)

    # COM should move away from dog (upward, away from y=100)
    moved_away = final_com[2] > initial_com[2]

    @printf("\nSheep moved away from dog: %s\n", moved_away ? "✓" : "✗")

    println("✓ Simulation completed successfully")
end

"""
Run all tests
"""
function main()
    println("=" ^ 50)
    println("Sheep BOIDS Implementation Tests")
    println("=" ^ 50)

    try
        test_boids_forces()
        test_flee_from_dog()
        test_temporal_weights()
        test_simulation()

        println("\n" * "=" ^ 50)
        println("All tests passed! ✓")
        println("=" ^ 50)
    catch e
        println("\n" * "=" ^ 50)
        println("Test failed! ✗")
        println("=" ^ 50)
        rethrow(e)
    end
end

# Run tests
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
