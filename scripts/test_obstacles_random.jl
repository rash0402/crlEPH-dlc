#!/usr/bin/env julia

"""
Test script for Random Obstacles scenario
Validates obstacle generation and basic scenario properties
"""

using Pkg
Pkg.activate(".")

# Load project modules
include("../src/config.jl")
include("../src/dynamics.jl")
include("../src/scenarios.jl")

using .Config
using .Dynamics
using .Scenarios

function test_random_obstacles()
    println("=" ^ 70)
    println("Testing Random Obstacles Scenario")
    println("=" ^ 70)

    # Test 1: Basic initialization
    println("\n[Test 1] Basic initialization (50 obstacles, 10 agents per group)")
    agents, params = initialize_scenario(
        RANDOM_OBSTACLES,
        10,
        seed=42,
        num_obstacles=50,
        obstacle_seed=123
    )

    println("  ✓ World size: $(params.world_size)")
    println("  ✓ Number of groups: $(params.num_groups)")
    println("  ✓ Total agents: $(length(agents))")
    println("  ✓ Num obstacles config: $(params.num_obstacles)")
    println("  ✓ Obstacle seed: $(params.obstacle_seed)")

    # Test 2: Obstacle generation
    println("\n[Test 2] Obstacle generation")
    obstacles = get_obstacles(params)
    println("  ✓ Total obstacle points: $(length(obstacles))")

    # Count unique obstacle circles (approximate)
    # Since we fill circles with 1.0m spacing, a 3m-radius circle has ~28 points
    estimated_circles = length(obstacles) ÷ 20  # Rough estimate
    println("  ✓ Estimated number of obstacle circles: ~$estimated_circles")

    # Test 3: Verify safe zones
    println("\n[Test 3] Verify safe zones (10m radius around corners)")
    safe_zones = [
        (5.0, 5.0),      # Bottom-left
        (5.0, 45.0),     # Top-left
        (45.0, 45.0),    # Top-right
        (45.0, 5.0)      # Bottom-right
    ]
    safe_radius = 10.0

    violations = 0
    for obs in obstacles
        for safe_pos in safe_zones
            dist = sqrt((obs[1] - safe_pos[1])^2 + (obs[2] - safe_pos[2])^2)
            if dist < safe_radius
                violations += 1
                break
            end
        end
    end

    if violations > 0
        println("  ⚠️  WARNING: $violations obstacle points in safe zones!")
    else
        println("  ✓ No obstacles in safe zones")
    end

    # Test 4: Agent starting positions
    println("\n[Test 4] Agent starting positions")
    for (i, pos) in enumerate(params.group_positions)
        println("  Group $i: $(pos)")
    end

    for (i, goal) in enumerate(params.group_goals)
        println("  Group $i goal: $(goal)")
    end

    # Test 5: Reproducibility
    println("\n[Test 5] Reproducibility test")
    agents2, params2 = initialize_scenario(
        RANDOM_OBSTACLES,
        10,
        seed=42,
        num_obstacles=50,
        obstacle_seed=123
    )
    obstacles2 = get_obstacles(params2)

    if length(obstacles) == length(obstacles2) && obstacles == obstacles2
        println("  ✓ Obstacle generation is reproducible")
    else
        println("  ✗ FAIL: Obstacles differ between runs!")
        println("    Run 1: $(length(obstacles)) points")
        println("    Run 2: $(length(obstacles2)) points")
    end

    # Test 6: Different seeds produce different obstacles
    println("\n[Test 6] Different obstacle seeds produce different results")
    _, params3 = initialize_scenario(
        RANDOM_OBSTACLES,
        10,
        seed=42,
        num_obstacles=50,
        obstacle_seed=456  # Different seed
    )
    obstacles3 = get_obstacles(params3)

    if obstacles != obstacles3
        println("  ✓ Different seeds produce different obstacles")
        println("    Seed 123: $(length(obstacles)) points")
        println("    Seed 456: $(length(obstacles3)) points")
    else
        println("  ✗ WARNING: Seeds don't affect obstacles!")
    end

    # Test 7: Varying number of obstacles
    println("\n[Test 7] Varying number of obstacles")
    for n_obs in [20, 50, 100]
        _, params_n = initialize_scenario(
            RANDOM_OBSTACLES,
            10,
            seed=42,
            num_obstacles=n_obs,
            obstacle_seed=42
        )
        obstacles_n = get_obstacles(params_n)
        println("  Config: $n_obs obstacles → Generated $(length(obstacles_n)) points")
    end

    println("\n" * "=" ^ 70)
    println("All tests completed!")
    println("=" ^ 70)
end

# Run tests
test_random_obstacles()
