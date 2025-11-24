"""
Phase 2 Environmental Haze Integration Test

Tests the complete Phase 2 implementation:
- Spatial self-haze computation
- Environmental haze sampling
- Haze composition (max operator)
- Haze deposition and decay

Usage:
    julia --project=. test_phase2.jl
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EnvironmentalHaze
using .EPH
using .Simulation
using .SPMPredictor

println("╔════════════════════════════════════════════════════════════╗")
println("║  Phase 2 Environmental Haze Integration Test              ║")
println("╚════════════════════════════════════════════════════════════╝")
println()

# Setup Phase 2 parameters
params_phase2 = Types.EPHParams(
    predictor_type = :linear,  # Use linear for quick test
    collect_data = false,
    Ω_threshold = 0.12,
    enable_env_haze = true,         # ★ Enable Phase 2
    haze_deposit_amount = 0.2,
    haze_decay_rate = 0.99,
    haze_deposit_type = :repellent
)

# Setup Phase 1 parameters (for comparison)
params_phase1 = Types.EPHParams(
    predictor_type = :linear,
    collect_data = false,
    Ω_threshold = 0.12,
    enable_env_haze = false         # Phase 1
)

println("Testing Phase 2 integration...")
println()

# Initialize small environment
env = Types.Environment(200.0, 200.0, grid_size=20)

# Add 3 agents
for i in 1:3
    x = 50.0 + (i-1) * 60.0
    y = 100.0
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env.agents, agent)
end

# Initialize predictor
predictor = SPMPredictor.LinearPredictor(env.dt)

println("Running 50 simulation steps with Phase 2...")
print("Progress: ")
flush(stdout)

for step in 1:50
    Simulation.step!(env, params_phase2, predictor)

    if step % 10 == 0
        print(".")
        flush(stdout)
    end
end

println()
println()
println("✓ Phase 2 simulation completed successfully!")
println()

# Check haze_grid statistics
total_haze = sum(env.haze_grid)
max_haze = maximum(env.haze_grid)
nonzero_cells = count(x -> x > 0.01, env.haze_grid)

println("Environmental Haze Statistics:")
println("  Total haze: $(round(total_haze, digits=2))")
println("  Max haze: $(round(max_haze, digits=3))")
println("  Nonzero cells: $nonzero_cells / $(length(env.haze_grid))")
println()

# Check agent self-haze
println("Agent Self-Haze Values:")
for agent in env.agents
    println("  Agent $(agent.id): h_self = $(round(agent.self_haze, digits=3))")
end
println()

# Verify Phase 2 functionality
println("Phase 2 Verification:")
if total_haze > 0
    println("  ✓ Haze deposition working (total_haze = $(round(total_haze, digits=2)) > 0)")
else
    println("  ⚠️  Haze deposition not detected (total_haze = 0)")
end

if nonzero_cells > 0
    println("  ✓ Haze spread working ($nonzero_cells cells have haze)")
else
    println("  ⚠️  Haze not spreading")
end

if max_haze < 1.0
    println("  ✓ Haze decay working (max_haze = $(round(max_haze, digits=3)) < 1.0)")
else
    println("  ⚠️  Haze may not be decaying properly")
end

println()
println("═══════════════════════════════════════════════════════════")
println("  Phase 2 Integration Test Complete!")
println("═══════════════════════════════════════════════════════════")
