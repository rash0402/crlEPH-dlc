"""
Quick test script for comprehensive logging system
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EPH
using .Simulation
using .SPMPredictor
using ..ExperimentLogger

println("=== Quick Logging Test ===")
println("Running 100 steps with comprehensive diagnostics...")
println()

# Setup
params = Types.EPHParams(
    predictor_type = :linear,  # Use linear predictor for simplicity
    collect_data = false
)

env = Types.Environment(400.0, 400.0, grid_size=20)

# Add 5 agents
for i in 1:5
    x = rand() * env.width
    y = rand() * env.height
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env.agents, agent)
end

# Initialize predictor
predictor = SPMPredictor.LinearPredictor(env.dt)

# Initialize logger
logger = ExperimentLogger.Logger("test_comprehensive")

# State tracking
prev_positions = nothing
prev_velocities = nothing
prev_actions = nothing
prev_self_haze = nothing

# Run 100 steps
for step in 1:100
    # Capture state before simulation
    if step > 1 && step % 10 == 0
        prev_positions = [(a.position[1], a.position[2]) for a in env.agents]
        prev_velocities = [sqrt(a.velocity[1]^2 + a.velocity[2]^2) for a in env.agents]
        prev_actions = [copy(a.velocity) for a in env.agents]
        prev_self_haze = [a.self_haze for a in env.agents]
    end

    # Run simulation
    Simulation.step!(env, params, predictor)

    # Log every 10 steps
    if step % 10 == 0
        # Basic logging
        ExperimentLogger.log_step(logger, step, step * 0.1, env.agents, env)

        # System metrics
        coverage = Simulation.compute_coverage(env)
        total_haze = sum(env.haze_grid)
        avg_sep = mean([sqrt((a.position[1] - b.position[1])^2 + (a.position[2] - b.position[2])^2)
                       for a in env.agents for b in env.agents if a.id != b.id])
        ExperimentLogger.log_system_metrics(logger, coverage, total_haze, avg_sep, 0)

        # Phase 1: Health
        ExperimentLogger.log_health_metrics(logger, env.agents, env, prev_positions, prev_velocities)

        # Phase 2: Prediction
        spm_params = SPM.SPMParams()
        ExperimentLogger.log_prediction_metrics(logger, env.agents, predictor, env, spm_params)

        # Phase 3: Gradient
        ExperimentLogger.log_gradient_metrics(logger, env.agents, prev_actions, nothing, nothing)

        # Phase 4: Self-Haze
        ExperimentLogger.log_selfhaze_metrics(logger, env.agents, prev_self_haze)
    end

    if step % 25 == 0
        print(".")
    end
end

println()
println()
println("Test complete! Saving log...")

# Save log
log_path = ExperimentLogger.save_log(logger)

println()
println("Now running diagnostic analysis...")
println()

# Run analysis
include("../scripts/analyze_experiment.jl")
analyze_experiment(log_path)
