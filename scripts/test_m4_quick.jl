#!/usr/bin/env julia
"""
Quick test of M4 predictive control in simulation.
Runs a short simulation with predictive mode enabled.
"""

println("=" ^ 60)
println("🚀 M4 PREDICTIVE CONTROL - QUICK TEST")
println("=" ^ 60)

# Temporarily modify control params to enable predictive control
ENV["USE_PREDICTIVE"] = "true"

# Set short duration for quick test
ENV["MAX_STEPS"] = "100"

println("\n⚙️  Configuration:")
println("  Mode: PREDICTIVE (M4)")
println("  Steps: 100")
println("  VAE: Enabled")
println("\n🔄 Starting simulation...")
println("-" ^ 60)

# Run simulation
include("run_simulation.jl")

println("\n" * "=" ^ 60)
println("✅ M4 PREDICTIVE CONTROL TEST COMPLETE")
println("=" ^ 60)
println("\n💡 Check viewer output for behavior differences")
println("   Predictive mode should show:")
println("   - Smoother trajectories (lower jerk)")
println("   - Earlier collision avoidance")
println("   - Reduced freezing events")
