"""
Phase 1 vs Phase 2 Comparison Experiment

Compares behavior and performance between:
- Phase 1: Scalar self-haze only
- Phase 2: Spatial self-haze + Environmental haze (stigmergy)

Metrics:
- Coverage efficiency
- Agent coordination (separation distance)
- Haze trail formation
- Collision avoidance

Usage:
    julia --project=. compare_phase1_phase2.jl [num_steps] [num_agents]

Default: 500 steps, 5 agents
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EnvironmentalHaze
using .EPH
using .Simulation
using .SPMPredictor
using Statistics
using Random

# Parse arguments
num_steps = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 500
num_agents = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 5

println("╔════════════════════════════════════════════════════════════╗")
println("║  Phase 1 vs Phase 2 Comparison Experiment                 ║")
println("╚════════════════════════════════════════════════════════════╝")
println()
println("Configuration:")
println("  Steps:  $num_steps")
println("  Agents: $num_agents")
println()

# ========== Phase 1 Experiment ==========
println("═══════════════════════════════════════════════════════════")
println("  Phase 1: Scalar Self-Haze Only")
println("═══════════════════════════════════════════════════════════")
println()

params_phase1 = Types.EPHParams(
    predictor_type = :linear,
    collect_data = false,
    Ω_threshold = 0.12,
    enable_env_haze = false  # Phase 1
)

env1 = Types.Environment(400.0, 400.0, grid_size=20)

# Add agents (same initial positions for fair comparison)
Random.seed!(42)  # Fix seed for reproducibility
initial_positions = []
for i in 1:num_agents
    x = rand() * env1.width
    y = rand() * env1.height
    push!(initial_positions, (x, y))
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env1.agents, agent)
end

predictor1 = SPMPredictor.LinearPredictor(env1.dt)

# Tracking metrics
coverage_history_phase1 = Float64[]
separation_history_phase1 = Float64[]
self_haze_history_phase1 = Float64[]

print("Running Phase 1 simulation: ")
flush(stdout)

for step in 1:num_steps
    Simulation.step!(env1, params_phase1, predictor1)

    if step % 10 == 0
        # Coverage
        coverage = Simulation.compute_coverage(env1)
        push!(coverage_history_phase1, coverage)

        # Average separation
        sep_distances = [sqrt((a.position[1] - b.position[1])^2 + (a.position[2] - b.position[2])^2)
                         for a in env1.agents for b in env1.agents if a.id < b.id]
        avg_sep = mean(sep_distances)
        push!(separation_history_phase1, avg_sep)

        # Average self-haze
        avg_haze = mean([a.self_haze for a in env1.agents])
        push!(self_haze_history_phase1, avg_haze)
    end

    if step % 50 == 0
        print(".")
        flush(stdout)
    end
end

println()
println()

final_coverage_phase1 = Simulation.compute_coverage(env1)
final_sep_phase1 = mean(separation_history_phase1)
final_haze_phase1 = mean(self_haze_history_phase1)

println("Phase 1 Results:")
println("  Final coverage: $(round(final_coverage_phase1 * 100, digits=1))%")
println("  Avg separation: $(round(final_sep_phase1, digits=1))px")
println("  Avg self-haze: $(round(final_haze_phase1, digits=3))")
println()

# ========== Phase 2 Experiment ==========
println("═══════════════════════════════════════════════════════════")
println("  Phase 2: Spatial Self-Haze + Environmental Haze")
println("═══════════════════════════════════════════════════════════")
println()

params_phase2 = Types.EPHParams(
    predictor_type = :linear,
    collect_data = false,
    Ω_threshold = 0.12,
    enable_env_haze = true,      # Phase 2
    haze_deposit_amount = 0.2,
    haze_decay_rate = 0.99,
    haze_deposit_type = :repellent
)

env2 = Types.Environment(400.0, 400.0, grid_size=20)

# Use same initial positions as Phase 1
for (i, (x, y)) in enumerate(initial_positions)
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env2.agents, agent)
end

predictor2 = SPMPredictor.LinearPredictor(env2.dt)

# Tracking metrics
coverage_history_phase2 = Float64[]
separation_history_phase2 = Float64[]
self_haze_history_phase2 = Float64[]
env_haze_history_phase2 = Float64[]

print("Running Phase 2 simulation: ")
flush(stdout)

for step in 1:num_steps
    Simulation.step!(env2, params_phase2, predictor2)

    if step % 10 == 0
        # Coverage
        coverage = Simulation.compute_coverage(env2)
        push!(coverage_history_phase2, coverage)

        # Average separation
        sep_distances = [sqrt((a.position[1] - b.position[1])^2 + (a.position[2] - b.position[2])^2)
                         for a in env2.agents for b in env2.agents if a.id < b.id]
        avg_sep = mean(sep_distances)
        push!(separation_history_phase2, avg_sep)

        # Average self-haze
        avg_haze = mean([a.self_haze for a in env2.agents])
        push!(self_haze_history_phase2, avg_haze)

        # Environmental haze
        total_env_haze = sum(env2.haze_grid)
        push!(env_haze_history_phase2, total_env_haze)
    end

    if step % 50 == 0
        print(".")
        flush(stdout)
    end
end

println()
println()

final_coverage_phase2 = Simulation.compute_coverage(env2)
final_sep_phase2 = mean(separation_history_phase2)
final_haze_phase2 = mean(self_haze_history_phase2)
final_env_haze_phase2 = mean(env_haze_history_phase2)

println("Phase 2 Results:")
println("  Final coverage: $(round(final_coverage_phase2 * 100, digits=1))%")
println("  Avg separation: $(round(final_sep_phase2, digits=1))px")
println("  Avg self-haze: $(round(final_haze_phase2, digits=3))")
println("  Avg env haze: $(round(final_env_haze_phase2, digits=1))")
println()

# ========== Comparison Analysis ==========
println("═══════════════════════════════════════════════════════════")
println("  Comparative Analysis")
println("═══════════════════════════════════════════════════════════")
println()

coverage_diff = (final_coverage_phase2 - final_coverage_phase1) * 100
sep_diff = final_sep_phase2 - final_sep_phase1
haze_diff = final_haze_phase2 - final_haze_phase1

println("Δ Coverage: $(round(coverage_diff, digits=1))% $(coverage_diff > 0 ? "↑" : "↓")")
println("Δ Separation: $(round(sep_diff, digits=1))px $(sep_diff > 0 ? "↑" : "↓")")
println("Δ Self-Haze: $(round(haze_diff, digits=3)) $(haze_diff > 0 ? "↑" : "↓")")
println()

# Interpretation
println("Interpretation:")
if final_env_haze_phase2 > 10.0
    println("  ✓ Environmental haze trails formed (stigmergy active)")
else
    println("  ⚠️  Limited environmental haze (stigmergy weak)")
end

if abs(coverage_diff) < 5.0
    println("  ≈ Coverage similar between Phase 1 and Phase 2")
elseif coverage_diff > 0
    println("  ↑ Phase 2 improved coverage (environmental haze guided exploration)")
else
    println("  ↓ Phase 2 reduced coverage (agents following haze trails)")
end

if abs(sep_diff) < 10.0
    println("  ≈ Separation similar between phases")
elseif sep_diff > 0
    println("  ↑ Phase 2 increased separation (haze promotes dispersion)")
else
    println("  ↓ Phase 2 decreased separation (haze promotes clustering)")
end

println()
println("═══════════════════════════════════════════════════════════")
println("  Experiment Complete!")
println("═══════════════════════════════════════════════════════════")
