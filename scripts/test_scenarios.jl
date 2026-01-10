#!/usr/bin/env julia

"""
Test script for scenarios.jl
Verify both Scramble Crossing and Corridor scenarios
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf

# Load modules
include("../src/config.jl")
include("../src/dynamics.jl")
include("../src/scenarios.jl")

using .Dynamics
using .Scenarios

println("=" ^ 60)
println("Testing EPH v5.6 Scenarios Module")
println("=" ^ 60)

# Test 1: Scramble Crossing
println("\n🔹 Test 1: Scramble Crossing Scenario")
println("-" ^ 60)

agents_scramble, params_scramble = initialize_scenario(
    SCRAMBLE_CROSSING,
    10,  # 10 agents per group
    seed=42
)

println("  Scenario: $(params_scramble.scenario_type)")
println("  World size: $(params_scramble.world_size)")
println("  Number of groups: $(params_scramble.num_groups)")
println("  Total agents: $(length(agents_scramble))")
println("  Expected: $(params_scramble.num_groups * 10)")

# Verify agent distribution
group_counts = Dict()
for agent in agents_scramble
    group = agent.group
    group_counts[group] = get(group_counts, group, 0) + 1
end

println("\n  Agent distribution by group:")
for (group, count) in sort(collect(group_counts), by=x->Int(x[1]))
    println("    $group: $count agents")
end

# Get obstacles (should be empty for Scramble)
obstacles_scramble = get_obstacles(params_scramble)
println("\n  Obstacles: $(length(obstacles_scramble))")
@assert length(obstacles_scramble) == 0 "Scramble should have no obstacles!"

println("  ✅ Scramble Crossing test passed!")

# Test 2: Corridor
println("\n🔹 Test 2: Corridor Scenario")
println("-" ^ 60)

agents_corridor, params_corridor = initialize_scenario(
    CORRIDOR,
    15,  # 15 agents per group
    seed=123,
    corridor_width=4.0
)

println("  Scenario: $(params_corridor.scenario_type)")
println("  World size: $(params_corridor.world_size)")
println("  Corridor width: $(params_corridor.corridor_width)")
println("  Number of groups: $(params_corridor.num_groups)")
println("  Total agents: $(length(agents_corridor))")
println("  Expected: $(params_corridor.num_groups * 15)")

# Verify agent distribution
group_counts_corridor = Dict()
for agent in agents_corridor
    group = agent.group
    group_counts_corridor[group] = get(group_counts_corridor, group, 0) + 1
end

println("\n  Agent distribution by group:")
for (group, count) in sort(collect(group_counts_corridor), by=x->Int(x[1]))
    println("    $group: $count agents")
end

# Get obstacles (should have walls for Corridor)
obstacles_corridor = get_obstacles(params_corridor)
println("\n  Obstacles: $(length(obstacles_corridor))")
@assert length(obstacles_corridor) > 0 "Corridor should have wall obstacles!"
println("  Wall segments: $(length(obstacles_corridor))")

println("  ✅ Corridor test passed!")

# Test 3: Agent properties verification
println("\n🔹 Test 3: Agent Properties Verification")
println("-" ^ 60)

sample_agent = agents_scramble[1]
println("  Sample agent (ID=$(sample_agent.id)):")
println("    Group: $(sample_agent.group)")
println("    Position: $(sample_agent.pos)")
println("    Velocity: $(sample_agent.vel)")
println("    Goal: $(sample_agent.goal)")
println("    Goal velocity: $(sample_agent.goal_vel)")
println("    Color: $(sample_agent.color)")
println("    Precision: $(sample_agent.precision)")

@assert length(sample_agent.pos) == 2 "Position should be 2D!"
@assert length(sample_agent.vel) == 2 "Velocity should be 2D!"
@assert length(sample_agent.goal) == 2 "Goal should be 2D!"
@assert length(sample_agent.goal_vel) == 2 "Goal velocity should be 2D!"

println("  ✅ Agent properties verified!")

# Summary
println("\n" * "=" ^ 60)
println("✅ All scenarios tests passed!")
println("=" ^ 60)
println("\nSummary:")
println("  - Scramble Crossing: $(length(agents_scramble)) agents, 4 groups")
println("  - Corridor: $(length(agents_corridor)) agents, 2 groups")
println("  - Both scenarios initialized successfully")
println("\n🎉 Phase 0.4: Scenarios module complete!")
