"""
EXP-1: ベースライン比較実験

EPH vs Potential Field vs DWA の定量的性能比較

実験設定:
- 3手法 × 30試行 × 300ステップ
- 評価指標: 衝突回数、カバレッジ率、速度維持率、EFE改善率
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "../src_julia"))
Pkg.instantiate()

# Load project modules using include
include("../src_julia/utils/MathUtils.jl")
include("../src_julia/utils/DataCollector.jl")
include("../src_julia/utils/ExperimentLogger.jl")
include("../src_julia/core/Types.jl")
include("../src_julia/perception/SPM.jl")
include("../src_julia/prediction/SPMPredictor.jl")
include("../src_julia/control/SelfHaze.jl")
include("../src_julia/control/EPH.jl")
include("../src_julia/control/PotentialField.jl")
include("../src_julia/control/DWA.jl")
include("../src_julia/Simulation.jl")

using .Types
using .Simulation
using .SPM
using .EPH
using .PotentialField
using .DWA
using .SelfHaze
using .SPMPredictor
using .ExperimentLogger
using .MathUtils

using JLD2
using Statistics
using Printf
using Dates
using LinearAlgebra

# ========================================
# Configuration
# ========================================

const N_TRIALS = 30
const N_STEPS = 300
const N_AGENTS = 10

# Controller types
const CONTROLLER_TYPES = [:eph, :potential_field, :dwa]

const LOG_DIR = joinpath(@__DIR__, "../src_julia/data/logs")
mkpath(LOG_DIR)

# ========================================
# Step function with controller selection
# ========================================

"""
Modified step! function that accepts controller type parameter.
"""
function step_with_controller!(env::Environment, params::EPHParams,
                               predictor::SPMPredictor.Predictor,
                               controller_type::Symbol)
    spm_params = SPM.SPMParams(d_max=params.fov_range)

    # --- 1. Perception & Action Selection ---
    for agent in env.agents
        # Store previous SPM
        agent.previous_spm = agent.current_spm

        # Compute SPM
        spm = SPM.compute_spm(agent, env, spm_params)
        agent.current_spm = spm

        # Compute self-haze
        agent.self_haze = SelfHaze.compute_self_haze(spm, params)

        # Track visible agents
        agent.visible_agents = _get_visible_agent_ids(agent, env, params)

        # Compute precision matrix
        Π = SelfHaze.compute_precision_matrix(spm, agent.self_haze, params)
        agent.current_precision = Π

        # Preferred velocity (no goals)
        pref_vel = nothing

        # Select controller and decide action
        if controller_type == :eph
            controller = EPH.GradientEPHController(params, predictor)
            action = EPH.decide_action(controller, agent, spm, env, pref_vel)
        elseif controller_type == :potential_field
            controller = PotentialField.PotentialFieldController(params)
            action = PotentialField.decide_action(controller, agent, spm, env, pref_vel)
        elseif controller_type == :dwa
            controller = DWA.DWAController(params)
            action = DWA.decide_action(controller, agent, spm, env, pref_vel)
        else
            error("Unknown controller type: $controller_type")
        end

        agent.last_action = copy(action)
        agent.velocity = action
    end

    # --- 2. Physics Update ---
    dt = env.dt
    for agent in env.agents
        # Update position
        agent.position += agent.velocity * dt

        # Toroidal wrap-around
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)

        # Update orientation
        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end

    # --- 3. Coverage Map Update ---
    _update_coverage_map!(env)

    env.frame_count += 1
end

"""
Get visible agent IDs within FOV.
"""
function _get_visible_agent_ids(agent::Agent, env::Environment, params::EPHParams)
    visible = Int[]

    for other in env.agents
        if other.id == agent.id
            continue
        end

        dx, dy, dist = MathUtils.toroidal_distance(agent.position, other.position,
                                                   env.width, env.height)

        if dist > params.fov_range
            continue
        end

        # Check FOV angle
        angle_to_other = atan(dy, dx)
        rel_angle = angle_to_other - agent.orientation

        # Normalize to [-π, π]
        while rel_angle > π
            rel_angle -= 2π
        end
        while rel_angle < -π
            rel_angle += 2π
        end

        if abs(rel_angle) <= params.fov_angle / 2
            push!(visible, other.id)
        end
    end

    return visible
end

"""
Update coverage map based on agent positions.
"""
function _update_coverage_map!(env::Environment)
    for agent in env.agents
        grid_x = floor(Int, agent.position[1] / env.grid_size) + 1
        grid_y = floor(Int, agent.position[2] / env.grid_size) + 1

        grid_w = size(env.coverage_map, 1)
        grid_h = size(env.coverage_map, 2)

        grid_x = clamp(grid_x, 1, grid_w)
        grid_y = clamp(grid_y, 1, grid_h)

        env.coverage_map[grid_x, grid_y] = true
    end
end

# ========================================
# Experiment Runner
# ========================================

"""
Run single trial with specified controller.
"""
function run_single_trial(controller_type::Symbol, trial_id::Int, params::EPHParams)
    # Initialize environment
    env = Simulation.initialize_simulation(n_agents=N_AGENTS)

    # Initialize predictor (for EPH only, but required by interface)
    predictor = SPMPredictor.LinearPredictor(0.1)  # dt = 0.1

    # Initialize logger
    logger = ExperimentLogger.Logger("baseline_$(controller_type)_trial$(trial_id)")

    # Run simulation
    for step in 1:N_STEPS
        step_with_controller!(env, params, predictor, controller_type)
        ExperimentLogger.log_step(logger, step, step * 0.1, env.agents, env)
    end

    # Compute metrics manually
    metrics = Dict{String, Any}()

    # Total collisions
    metrics["total_collisions"] = sum(logger.collision_count)

    # Coverage rate (%)
    total_cells = length(env.coverage_map)
    covered_cells = sum(env.coverage_map)
    metrics["coverage_rate"] = 100.0 * covered_cells / total_cells

    # Average speed
    if !isempty(logger.velocity_magnitudes)
        all_speeds = vcat(logger.velocity_magnitudes...)
        metrics["avg_speed"] = isempty(all_speeds) ? 0.0 : mean(all_speeds)
    else
        metrics["avg_speed"] = 0.0
    end

    # Average EFE (for EPH only)
    if !isempty(logger.agent_efe_values)
        all_efe = vcat(logger.agent_efe_values...)
        metrics["avg_efe"] = isempty(all_efe) ? 0.0 : mean(all_efe)
    else
        metrics["avg_efe"] = 0.0
    end

    return metrics
end

"""
Run full experiment for one controller type.
"""
function run_controller_experiment(controller_type::Symbol, params::EPHParams)
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("Running $(controller_type) - $N_TRIALS trials × $N_STEPS steps")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()

    all_metrics = []

    for trial in 1:N_TRIALS
        print("  Trial $trial/$N_TRIALS... ")

        metrics = run_single_trial(controller_type, trial, params)
        push!(all_metrics, metrics)

        println("✓ (collisions=$(metrics["total_collisions"]), coverage=$(metrics["coverage_rate"])%)")
    end

    # Aggregate results
    aggregated = Dict{String, Any}()

    # Average each metric
    metric_keys = keys(first(all_metrics))
    for key in metric_keys
        values = [m[key] for m in all_metrics]
        aggregated["$(key)_mean"] = mean(values)
        aggregated["$(key)_std"] = std(values)
        aggregated["$(key)_all"] = values  # Store all trials for statistical tests
    end

    println()
    println("Summary:")
    @printf("  Collisions: %.2f ± %.2f\n", aggregated["total_collisions_mean"], aggregated["total_collisions_std"])
    @printf("  Coverage: %.2f%% ± %.2f%%\n", aggregated["coverage_rate_mean"], aggregated["coverage_rate_std"])
    @printf("  Avg Speed: %.2f ± %.2f\n", aggregated["avg_speed_mean"], aggregated["avg_speed_std"])
    println()

    # Save results
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    log_path = joinpath(LOG_DIR, "baseline_$(controller_type)_$(timestamp).jld2")

    save(log_path, aggregated)
    println("  ✓ Saved: $log_path")
    println()

    return aggregated
end

# ========================================
# Main Execution
# ========================================

println("╔══════════════════════════════════════════════════════════════╗")
println("║  EXP-1: ベースライン比較実験                                 ║")
println("║  EPH vs Potential Field vs DWA                               ║")
println("╚══════════════════════════════════════════════════════════════╝")
println()
println("Configuration:")
println("  Trials: $N_TRIALS")
println("  Steps per trial: $N_STEPS")
println("  Agents: $N_AGENTS")
println()

# EPH Params (Default configuration)
params = EPHParams(
    β=1.0,
    λ=0.1,
    γ_info=0.5,
    h_max=0.8,
    α=10.0,
    Ω_threshold=0.05,
    max_iter=5,
    η=0.1,
    predictor_type=:linear,
    collect_data=false,
    enable_online_learning=false
)

# Run experiments for each controller
results = Dict{Symbol, Any}()

for controller_type in CONTROLLER_TYPES
    results[controller_type] = run_controller_experiment(controller_type, params)
end

# ========================================
# Comparative Analysis
# ========================================

println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("## Comparative Summary")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

println("| Method | Collisions | Coverage (%) | Avg Speed |")
println("|:---|:---|:---|:---|")

for controller_type in CONTROLLER_TYPES
    r = results[controller_type]
    @printf("| %-15s | %.2f ± %.2f | %.2f ± %.2f | %.2f ± %.2f |\n",
            uppercase(string(controller_type)),
            r["total_collisions_mean"], r["total_collisions_std"],
            r["coverage_rate_mean"], r["coverage_rate_std"],
            r["avg_speed_mean"], r["avg_speed_std"])
end

println()
println("✅ EXP-1 ベースライン比較実験 完了")
println()
