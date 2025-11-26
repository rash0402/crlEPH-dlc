"""
EPHパラメータ最適化実験

目的: 安全性（衝突0回）を維持しつつ、カバレッジ率を最大化するパラメータ設定を発見

探索するパラメータ:
1. β (Entropy term weight): Belief Entropyの重み - 探索vs確信のバランス
2. λ (Pragmatic term weight): 目標指向性の重み - 探索の積極性
3. γ_info (Information gain weight): 情報獲得の重み - 新規領域への好奇心
4. h_max (Maximum self-haze): Self-hazeの最大値 - 探索への切り替わりやすさ
5. Ω_threshold (Occupancy threshold): 占有率閾値 - Self-haze発動の感度

実験設計:
- Grid Search: 各パラメータの重要な値を組み合わせて評価
- 各設定で10試行 × 200ステップ（高速評価）
- 評価指標: カバレッジ率、衝突回数、平均速度
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

const N_TRIALS = 10  # 各パラメータ設定で10試行
const N_STEPS = 200   # 200ステップ（高速評価）
const N_AGENTS = 10

const LOG_DIR = joinpath(@__DIR__, "../src_julia/data/logs")
mkpath(LOG_DIR)

# パラメータグリッド定義
# Baseline (Default): β=1.0, λ=0.1, γ_info=0.5, h_max=0.8, Ω_threshold=0.05

param_configs = [
    # ベースライン（比較用）
    (name="Baseline", β=1.0, λ=0.1, γ_info=0.5, h_max=0.8, Ω_threshold=0.05),

    # β調整: 探索性を強化
    (name="HighEntropy", β=2.0, λ=0.1, γ_info=0.5, h_max=0.8, Ω_threshold=0.05),
    (name="VeryHighEntropy", β=3.0, λ=0.1, γ_info=0.5, h_max=0.8, Ω_threshold=0.05),

    # λ調整: 目標指向性を低下（探索優先）
    (name="LowPragmatic", β=1.0, λ=0.05, γ_info=0.5, h_max=0.8, Ω_threshold=0.05),
    (name="NoPragmatic", β=1.0, λ=0.0, γ_info=0.5, h_max=0.8, Ω_threshold=0.05),

    # γ_info調整: 情報獲得を強化
    (name="HighInfoGain", β=1.0, λ=0.1, γ_info=1.0, h_max=0.8, Ω_threshold=0.05),
    (name="VeryHighInfoGain", β=1.0, λ=0.1, γ_info=2.0, h_max=0.8, Ω_threshold=0.05),

    # h_max調整: Self-hazeを高く（探索状態に入りやすく）
    (name="HighHaze", β=1.0, λ=0.1, γ_info=0.5, h_max=0.9, Ω_threshold=0.05),

    # Ω_threshold調整: 感度を高く（少ない占有率でもSelf-hazeが上がる）
    (name="SensitiveThreshold", β=1.0, λ=0.1, γ_info=0.5, h_max=0.8, Ω_threshold=0.03),

    # 組み合わせ: 探索最適化
    (name="ExplorationOptimized", β=2.0, λ=0.05, γ_info=1.0, h_max=0.9, Ω_threshold=0.03),
    (name="AggressiveExploration", β=3.0, λ=0.0, γ_info=2.0, h_max=0.9, Ω_threshold=0.03),
]

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

function run_single_trial(config, trial_id::Int)
    # パラメータ設定
    params = EPHParams(
        β=config.β,
        λ=config.λ,
        γ_info=config.γ_info,
        h_max=config.h_max,
        Ω_threshold=config.Ω_threshold,
        max_iter=5,
        η=0.1,
        predictor_type=:linear,
        collect_data=false,
        enable_online_learning=false
    )

    env = Simulation.initialize_simulation(n_agents=N_AGENTS)
    predictor = SPMPredictor.LinearPredictor(0.1)
    logger = ExperimentLogger.Logger("param_opt_$(config.name)_trial$(trial_id)")

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

    return metrics
end

# ========================================
# Main Execution
# ========================================

println("╔══════════════════════════════════════════════════════════════╗")
println("║  EPHパラメータ最適化実験                                     ║")
println("║  安全性維持 + カバレッジ率最大化                              ║")
println("╚══════════════════════════════════════════════════════════════╝")
println()
println("Configuration:")
println("  Trials per config: $N_TRIALS")
println("  Steps per trial: $N_STEPS")
println("  Agents: $N_AGENTS")
println("  Total configs: $(length(param_configs))")
println()

results = Dict{String, Any}()

for (idx, config) in enumerate(param_configs)
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("[$idx/$(length(param_configs))] Running: $(config.name)")
    println("  β=$(config.β), λ=$(config.λ), γ_info=$(config.γ_info), h_max=$(config.h_max), Ω=$(config.Ω_threshold)")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()

    all_metrics = []
    for trial in 1:N_TRIALS
        print("  Trial $trial/$N_TRIALS... ")
        metrics = run_single_trial(config, trial)
        push!(all_metrics, metrics)
        println("✓ (collisions=$(metrics["total_collisions"]), coverage=$(round(metrics["coverage_rate"], digits=2))%)")
    end

    # 集計
    aggregated = Dict{String, Any}()
    aggregated["config"] = config
    for key in ["total_collisions", "coverage_rate", "avg_speed"]
        values = [m[key] for m in all_metrics]
        aggregated["$(key)_mean"] = mean(values)
        aggregated["$(key)_std"] = std(values)
        aggregated["$(key)_all"] = values
    end

    results[config.name] = aggregated

    println()
    @printf("  Summary: Collisions=%.2f±%.2f, Coverage=%.2f%%±%.2f%%, Speed=%.2f±%.2f\n",
            aggregated["total_collisions_mean"], aggregated["total_collisions_std"],
            aggregated["coverage_rate_mean"], aggregated["coverage_rate_std"],
            aggregated["avg_speed_mean"], aggregated["avg_speed_std"])
    println()
end

# ========================================
# Results Analysis
# ========================================

println()
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("## 最終結果サマリー")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

println("| 設定名 | カバレッジ率 (%) | 衝突回数 | 安全? |")
println("|:---|:---|:---|:---|")

for config in param_configs
    r = results[config.name]
    safe = r["total_collisions_mean"] == 0.0 ? "✅" : "❌"
    @printf("| %-22s | %.2f ± %.2f | %.2f ± %.2f | %s |\n",
            config.name,
            r["coverage_rate_mean"], r["coverage_rate_std"],
            r["total_collisions_mean"], r["total_collisions_std"],
            safe)
end

println()

# ベストな設定を特定
safe_configs = filter(c -> results[c.name]["total_collisions_mean"] == 0.0, param_configs)

if !isempty(safe_configs)
    best_config = safe_configs[argmax([results[c.name]["coverage_rate_mean"] for c in safe_configs])]
    best_result = results[best_config.name]

    println("### 🏆 最適設定（安全性維持 + 最高カバレッジ）")
    println()
    println("**$(best_config.name)**")
    println("- β = $(best_config.β)")
    println("- λ = $(best_config.λ)")
    println("- γ_info = $(best_config.γ_info)")
    println("- h_max = $(best_config.h_max)")
    println("- Ω_threshold = $(best_config.Ω_threshold)")
    println()
    @printf("**性能**: カバレッジ率 = %.2f%% ± %.2f%%, 衝突 = 0回\n",
            best_result["coverage_rate_mean"], best_result["coverage_rate_std"])

    # ベースラインとの比較
    baseline_cov = results["Baseline"]["coverage_rate_mean"]
    improvement = (best_result["coverage_rate_mean"] / baseline_cov - 1) * 100
    println()
    @printf("**改善率**: ベースラインから %.1f%% 向上\n", improvement)
else
    println("⚠️ 安全性を維持した設定が見つかりませんでした")
end

println()

# 結果保存
timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
log_path = joinpath(LOG_DIR, "eph_param_optimization_$(timestamp).jld2")
save(log_path, results)
println("✓ Saved: $log_path")
println()

println("✅ EPHパラメータ最適化実験 完了")
println()
