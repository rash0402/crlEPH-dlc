"""
EPH最適パラメータ フルスケール検証実験

最適パラメータ (γ_info=2.0) での性能を30試行×300ステップで厳密に評価

目的:
- パラメータ最適化の結果を統計的に信頼できる規模で検証
- ベースライン実験と同じ条件で比較可能なデータを取得
- 安全性(0衝突)を維持しつつカバレッジ率向上を確認
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "../src_julia"))
Pkg.instantiate()

# Load project modules
include("../src_julia/utils/MathUtils.jl")
include("../src_julia/utils/DataCollector.jl")
include("../src_julia/utils/ExperimentLogger.jl")
include("../src_julia/core/Types.jl")
include("../src_julia/perception/SPM.jl")
include("../src_julia/prediction/SPMPredictor.jl")
include("../src_julia/control/SelfHaze.jl")
include("../src_julia/control/EPH.jl")
include("../src_julia/Simulation.jl")

using .Types
using .Simulation
using .SPM
using .EPH
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

const N_TRIALS = 30  # フルスケール検証: 30試行
const N_STEPS = 300  # ベースライン実験と同じステップ数
const N_AGENTS = 10

const LOG_DIR = joinpath(@__DIR__, "../src_julia/data/logs")
mkpath(LOG_DIR)

# ========================================
# Simulation Functions
# ========================================

function step_with_controller!(env::Environment, params::EPHParams, predictor::SPMPredictor.Predictor)
    spm_params = SPM.SPMParams(d_max=params.fov_range)

    for agent in env.agents
        agent.previous_spm = agent.current_spm
        spm = SPM.compute_spm(agent, env, spm_params)
        agent.current_spm = spm
        agent.self_haze = SelfHaze.compute_self_haze(spm, params)
        agent.visible_agents = _get_visible_agent_ids(agent, env, params)
        Π = SelfHaze.compute_precision_matrix(spm, agent.self_haze, params)
        agent.current_precision = Π

        pref_vel = nothing
        controller = EPH.GradientEPHController(params, predictor)
        action = EPH.decide_action(controller, agent, spm, env, pref_vel)

        agent.last_action = copy(action)
        agent.velocity = action
    end

    dt = env.dt
    for agent in env.agents
        agent.position += agent.velocity * dt
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)

        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end

    _update_coverage_map!(env)
    env.frame_count += 1
end

function _get_visible_agent_ids(agent::Agent, env::Environment, params::EPHParams)
    visible = Int[]
    for other in env.agents
        if other.id == agent.id continue end
        dx, dy, dist = MathUtils.toroidal_distance(agent.position, other.position, env.width, env.height)
        if dist > params.fov_range continue end
        angle_to_other = atan(dy, dx)
        rel_angle = angle_to_other - agent.orientation
        while rel_angle > π rel_angle -= 2π end
        while rel_angle < -π rel_angle += 2π end
        if abs(rel_angle) <= params.fov_angle / 2
            push!(visible, other.id)
        end
    end
    return visible
end

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

function run_single_trial(trial_id::Int, params::EPHParams)
    env = Simulation.initialize_simulation(n_agents=N_AGENTS)
    predictor = SPMPredictor.LinearPredictor(0.1)
    logger = ExperimentLogger.Logger("eph_optimized_trial$(trial_id)")

    for step in 1:N_STEPS
        step_with_controller!(env, params, predictor)
        ExperimentLogger.log_step(logger, step, step * 0.1, env.agents, env)
    end

    # メトリクス計算
    metrics = Dict{String, Any}()
    metrics["total_collisions"] = sum(logger.collision_count)
    total_cells = length(env.coverage_map)
    covered_cells = sum(env.coverage_map)
    metrics["coverage_rate"] = 100.0 * covered_cells / total_cells

    if !isempty(logger.velocity_magnitudes)
        all_speeds = vcat(logger.velocity_magnitudes...)
        metrics["avg_speed"] = isempty(all_speeds) ? 0.0 : mean(all_speeds)
    else
        metrics["avg_speed"] = 0.0
    end

    if !isempty(logger.agent_efe_values)
        all_efe = vcat(logger.agent_efe_values...)
        metrics["avg_efe"] = isempty(all_efe) ? 0.0 : mean(all_efe)
    else
        metrics["avg_efe"] = 0.0
    end

    return metrics
end

# ========================================
# Main Execution
# ========================================

println("╔══════════════════════════════════════════════════════════════╗")
println("║  EPH最適パラメータ フルスケール検証実験                      ║")
println("║  γ_info = 2.0 (最適化結果)                                   ║")
println("╚══════════════════════════════════════════════════════════════╝")
println()
println("Configuration:")
println("  Trials: $N_TRIALS")
println("  Steps per trial: $N_STEPS")
println("  Agents: $N_AGENTS")
println()
println("Optimized Parameters:")
println("  β = 1.0 (Entropy weight)")
println("  λ = 0.1 (Pragmatic weight)")
println("  γ_info = 2.0 (Information gain weight) ← OPTIMIZED")
println("  h_max = 0.8 (Max self-haze)")
println("  Ω_threshold = 0.05 (Occupancy threshold)")
println()

# 最適パラメータ設定
params = EPHParams(
    β=1.0,
    λ=0.1,
    γ_info=2.0,  # 最適化された値
    h_max=0.8,
    α=10.0,
    Ω_threshold=0.05,
    max_iter=5,
    η=0.1,
    predictor_type=:linear,
    collect_data=false,
    enable_online_learning=false
)

println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("Running $N_TRIALS trials...")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

all_metrics = []

for trial in 1:N_TRIALS
    print("  Trial $trial/$N_TRIALS... ")
    metrics = run_single_trial(trial, params)
    push!(all_metrics, metrics)
    println("✓ (collisions=$(metrics["total_collisions"]), coverage=$(round(metrics["coverage_rate"], digits=2))%)")
end

# 集計
aggregated = Dict{String, Any}()
aggregated["config"] = params

for key in ["total_collisions", "coverage_rate", "avg_speed", "avg_efe"]
    values = [m[key] for m in all_metrics]
    aggregated["$(key)_mean"] = mean(values)
    aggregated["$(key)_std"] = std(values)
    aggregated["$(key)_all"] = values
end

println()
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("## 検証結果")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

@printf("### 性能指標 (平均 ± 標準偏差)\n\n")
@printf("- カバレッジ率: %.2f%% ± %.2f%%\n",
        aggregated["coverage_rate_mean"], aggregated["coverage_rate_std"])
@printf("- 衝突回数: %.2f ± %.2f\n",
        aggregated["total_collisions_mean"], aggregated["total_collisions_std"])
@printf("- 平均速度: %.2f ± %.2f\n",
        aggregated["avg_speed_mean"], aggregated["avg_speed_std"])
@printf("- 平均EFE: %.2f ± %.2f\n",
        aggregated["avg_efe_mean"], aggregated["avg_efe_std"])
println()

# 安全性チェック
if aggregated["total_collisions_mean"] == 0.0
    println("✅ 安全性: 完璧 (0衝突を達成)")
else
    println("⚠️  安全性: $(round(aggregated["total_collisions_mean"], digits=2))回の衝突")
end

println()

# ベースラインとの比較（参考値）
baseline_coverage = 28.10  # パラメータ最適化実験でのベースライン (200ステップ)
println("### パラメータ最適化実験との比較")
println()
@printf("- ベースライン (200ステップ): %.2f%%\n", baseline_coverage)
@printf("- 最適化後 (200ステップ): 30.40%%\n")
@printf("- 今回 (300ステップ): %.2f%%\n", aggregated["coverage_rate_mean"])
println()
println("注: ステップ数の違いにより直接比較はできませんが、")
println("    長期的な性能評価として参考になります。")

println()

# 結果保存
timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
log_path = joinpath(LOG_DIR, "eph_optimized_validation_$(timestamp).jld2")
save(log_path, aggregated)
println("✓ Saved: $log_path")
println()

println("✅ EPH最適パラメータ フルスケール検証実験 完了")
println()
