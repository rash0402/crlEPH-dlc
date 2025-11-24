"""
Single Comprehensive Diagnostic Experiment
Runs one 1000-step experiment with default parameters
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EPH
using .Simulation
using .SPMPredictor
using .ExperimentLogger

# Parse command-line arguments
num_steps = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1000
predictor_arg = length(ARGS) >= 2 ? Symbol(ARGS[2]) : :linear

println("╔════════════════════════════════════════════════════════════╗")
println("║  EPH Comprehensive Diagnostic Experiment                  ║")
println("╚════════════════════════════════════════════════════════════╝")
println()
println("Configuration: Default parameters")
println("Steps: $num_steps")
println("Predictor: $predictor_arg")
println("Agents: 10")
println()

# Setup with optimized parameters
params = Types.EPHParams(
    predictor_type = predictor_arg,
    collect_data = false,
    Ω_threshold = 0.12  # Optimized for state transitions
)

env = Types.Environment(400.0, 400.0, grid_size=20)

# Add 10 agents
println("Initializing 10 agents...")
for i in 1:10
    x = rand() * env.width
    y = rand() * env.height
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env.agents, agent)
end

# Initialize predictor based on type
if predictor_arg == :gru
    model_path = joinpath(@__DIR__, "../data/models/predictor_model.jld2")
    predictor = SPMPredictor.load_predictor(model_path)
else
    predictor = SPMPredictor.LinearPredictor(env.dt)
end

# Initialize logger
logger = ExperimentLogger.Logger("comprehensive_diagnostic")

# State tracking
prev_positions = nothing
prev_velocities = nothing
prev_actions = nothing
prev_self_haze = nothing
prev_efe = nothing

println("Starting simulation...")
print("Progress: ")
flush(stdout)

# Run simulation
for step in 1:num_steps
    # Capture state before simulation
    if step > 1 && step % 10 == 0
        prev_positions = [(a.position[1], a.position[2]) for a in env.agents]
        prev_velocities = [sqrt(a.velocity[1]^2 + a.velocity[2]^2) for a in env.agents]
        prev_actions = [copy(a.velocity) for a in env.agents]
        prev_self_haze = [a.self_haze for a in env.agents]
        # Capture EFE before optimization
        prev_efe = [a.current_efe for a in env.agents]
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

        # Phase 3: Gradient (with EFE before/after)
        efe_after = [a.current_efe for a in env.agents]
        ExperimentLogger.log_gradient_metrics(logger, env.agents, prev_actions, prev_efe, efe_after)

        # Phase 4: Self-Haze
        ExperimentLogger.log_selfhaze_metrics(logger, env.agents, prev_self_haze)
    end

    # Progress indicator
    if step % 100 == 0
        print(".")
        flush(stdout)
    end
end

println()
println()
println("Simulation complete!")
println()

# Save log
log_path = ExperimentLogger.save_log(logger)

println()
println("═══════════════════════════════════════════════════════════")
println("  Running Diagnostic Analysis")
println("═══════════════════════════════════════════════════════════")
println()

# Run analysis
include("../scripts/analyze_experiment.jl")
analyze_experiment(log_path)
