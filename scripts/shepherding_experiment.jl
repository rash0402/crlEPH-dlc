"""
Shepherding Experiment: EPH-based dog agents vs Boids-based sheep agents

実験設計:
- Phase F1 (0-100s): 収束フェーズ - 犬が羊をターゲットへ誘導
- Phase F2 (100-120s): 逃走誘発フェーズ - 羊の反発力を2倍に増加
- Phase F3 (120-200s): 回復フェーズ - 再収束を評価

評価指標:
1. Recovery Time: F2終了からターゲット半径内に戻るまでの時間
2. Convergence Smoothness: 経路のJerk (加加速度) の総和
3. Final Distance: 最終状態でのターゲットからの距離

比較ベースライン:
- Boids-only: 犬もBoidsルールで制御（EPHなし）
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "../src_julia"))
Pkg.instantiate()

# Load project modules
include("../src_julia/utils/MathUtils.jl")
include("../src_julia/utils/ExperimentParams.jl")
include("../src_julia/core/Types.jl")
include("../src_julia/perception/SPM.jl")
include("../src_julia/prediction/SPMPredictor.jl")
include("../src_julia/control/SelfHaze.jl")
include("../src_julia/control/EPH.jl")
include("../src_julia/agents/BoidsAgent.jl")
include("../src_julia/control/ShepherdingEPH.jl")

using .Types
using .SPM
using .SelfHaze
using .EPH
using .SPMPredictor
using .BoidsAgent
using .ShepherdingEPH
using .MathUtils
using .ExperimentParams

using LinearAlgebra
using Statistics
using Printf
using Dates
using JLD2

# ========================================
# Configuration (環境変数からパラメータ読み取り対応)
# ========================================

# 環境変数からパラメータを取得（未設定の場合はデフォルト値を使用）
const N_SHEEP = get_n_agents(10)  # 15 → 10 (より管理しやすい数)
const N_DOGS = 3  # 2 → 3 (羊:犬比率を3.3:1に改善)
const N_STEPS = get_n_steps(200.0)  # シミュレーション時間から自動計算

# Phase timings (シミュレーション時間に応じて比例配分)
const PHASE_F1_END = round(Int, N_STEPS * 0.5)   # 0-50%: convergence
const PHASE_F2_END = round(Int, N_STEPS * 0.6)   # 50-60%: escape induction
const PHASE_F3_END = N_STEPS                     # 60-100%: recovery

const WORLD_SIZE = get_world_size(500.0)
const TARGET_POSITION = [WORLD_SIZE / 2, WORLD_SIZE / 2]
const TARGET_RADIUS = WORLD_SIZE / 10.0  # ワールドサイズの10%

const LOG_DIR = joinpath(@__DIR__, "../src_julia/data/logs")
mkpath(LOG_DIR)

# ========================================
# Initialization
# ========================================

function initialize_shepherding_scenario()
    env = Environment(WORLD_SIZE, WORLD_SIZE, scenario_type=:shepherding)
    env.target_position = TARGET_POSITION

    # Initialize sheep agents (scattered randomly)
    sheep_agents = Agent[]
    for i in 1:N_SHEEP
        x = rand() * WORLD_SIZE
        y = rand() * WORLD_SIZE
        sheep = Agent(i, x, y, color=(200, 200, 200))  # Gray sheep
        sheep.max_speed = 30.0  # Sheep are slower than dogs
        push!(sheep_agents, sheep)
    end
    env.sheep_agents = sheep_agents

    # Initialize dog agents (near perimeter)
    dog_agents = Agent[]
    for i in 1:N_DOGS
        angle = 2π * i / N_DOGS
        radius = WORLD_SIZE / 3
        x = TARGET_POSITION[1] + radius * cos(angle)
        y = TARGET_POSITION[2] + radius * sin(angle)
        dog = Agent(N_SHEEP + i, x, y, color=(139, 69, 19))  # Brown dogs
        dog.max_speed = 50.0  # Dogs are faster
        push!(dog_agents, dog)
    end
    env.agents = dog_agents  # EPH-controlled agents

    return env
end

# ========================================
# Simulation Step
# ========================================

function step_shepherding!(env::Environment, eph_params::EPHParams,
                          shep_params::ShepherdingEPH.ShepherdingParams,
                          predictor, current_step::Int)

    # Determine if we're in escape induction phase (F2)
    escape_phase = (PHASE_F1_END < current_step <= PHASE_F2_END)
    repulsion_multiplier = escape_phase ? 2.0 : 1.0

    # Update sheep (Boids)
    dog_positions = [dog.position for dog in env.agents]

    for sheep in env.sheep_agents
        # Compute Boids velocity
        boids_vel = BoidsAgent.compute_boids_velocity(
            sheep, env,
            separation_radius=30.0,
            cohesion_radius=100.0,
            alignment_radius=60.0,
            w_sep=1.5, w_align=1.0, w_coh=1.0
        )

        # Add dog repulsion
        dog_repulsion = BoidsAgent.compute_dog_repulsion(
            sheep, dog_positions, env,
            repulsion_radius=80.0,
            repulsion_strength=repulsion_multiplier  # 2x during escape phase
        )

        # Combine and add noise
        desired_vel = boids_vel + dog_repulsion
        desired_vel = BoidsAgent.apply_environmental_noise(desired_vel, noise_strength=5.0)

        # Limit speed
        speed = norm(desired_vel)
        if speed > sheep.max_speed
            desired_vel = desired_vel / speed * sheep.max_speed
        end

        sheep.velocity = desired_vel
    end

    # Update dogs (ShepherdingEPH)
    spm_params = SPM.SPMParams(d_max=eph_params.fov_range)
    controller = ShepherdingEPH.ShepherdingController(eph_params, shep_params)

    for dog in env.agents
        # Compute SPM (dogs perceive sheep)
        # Create temporary env with sheep as "other agents" for SPM
        temp_env = deepcopy(env)
        temp_env.agents = env.sheep_agents  # SPM sees sheep as obstacles

        dog.previous_spm = dog.current_spm
        spm = SPM.compute_spm(dog, temp_env, spm_params)
        dog.current_spm = spm

        # Decide action
        action = ShepherdingEPH.decide_action(controller, dog, spm, env, predictor)

        dog.last_action = copy(action)
        dog.velocity = action
    end

    # Update positions (both sheep and dogs)
    dt = env.dt
    all_agents = vcat(env.sheep_agents, env.agents)

    for agent in all_agents
        agent.position += agent.velocity * dt
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)

        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end

    env.frame_count += 1
end

# ========================================
# Metrics
# ========================================

function compute_sheep_center(env::Environment)
    center = zeros(2)
    for sheep in env.sheep_agents
        center += sheep.position
    end
    return center / length(env.sheep_agents)
end

function compute_distance_to_target(env::Environment)
    sheep_center = compute_sheep_center(env)
    _, _, dist = MathUtils.toroidal_distance(
        sheep_center, env.target_position, env.width, env.height
    )
    return dist
end

function compute_jerk(velocities::Vector{Vector{Float64}}, dt::Float64)
    if length(velocities) < 3
        return 0.0
    end

    total_jerk = 0.0
    for i in 3:length(velocities)
        # Acceleration: (v_t - v_{t-1}) / dt
        a_t = (velocities[i] - velocities[i-1]) / dt
        a_t_1 = (velocities[i-1] - velocities[i-2]) / dt

        # Jerk: (a_t - a_{t-1}) / dt
        jerk = (a_t - a_t_1) / dt
        total_jerk += norm(jerk)
    end

    return total_jerk
end

# ========================================
# Main Execution
# ========================================

println("╔══════════════════════════════════════════════════════════════╗")
println("║  Shepherding Experiment: EPH Dogs vs Boids Sheep            ║")
println("╚══════════════════════════════════════════════════════════════╝")
println()

# 環境変数から読み込んだパラメータを表示
print_experiment_config()

println("Scenario Configuration:")
println("  Sheep: $N_SHEEP agents (Boids model)")
println("  Dogs: $N_DOGS agents (ShepherdingEPH)")
println("  World size: $(WORLD_SIZE)×$(WORLD_SIZE)")
println("  Target: $TARGET_POSITION (radius: $TARGET_RADIUS)")
println("  Total steps: $N_STEPS")
println()
println("Phase Timing:")
println("  F1 (0-$(PHASE_F1_END÷10)s): Convergence")
println("  F2 ($(PHASE_F1_END÷10)-$(PHASE_F2_END÷10)s): Escape induction (2× sheep repulsion)")
println("  F3 ($(PHASE_F2_END÷10)-$(PHASE_F3_END÷10)s): Recovery")
println()

# EPH parameters for dogs
eph_params = EPHParams(
    β=1.0,
    λ=0.5,  # Higher pragmatic weight for task-oriented behavior
    γ_info=0.5,
    h_max=0.8,
    α=10.0,
    Ω_threshold=0.05,
    max_iter=5,
    η=0.1,
    max_speed=50.0,
    fov_range=150.0,
    predictor_type=:linear,
    collect_data=false,
    enable_online_learning=false
)

# Shepherding-specific parameters
shep_params = ShepherdingEPH.ShepherdingParams(
    w_target=1.0,
    w_density=0.5,
    w_work=0.1,
    target_radius=TARGET_RADIUS,
    density_radius=80.0,
    use_temporal_prediction=false
)

env = initialize_shepherding_scenario()
predictor = SPMPredictor.LinearPredictor(env.dt)

println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("Running simulation...")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

# Data collection
distance_history = Float64[]
sheep_center_history = Vector{Float64}[]

for step in 1:N_STEPS
    step_shepherding!(env, eph_params, shep_params, predictor, step)

    # Log metrics
    dist = compute_distance_to_target(env)
    push!(distance_history, dist)
    push!(sheep_center_history, compute_sheep_center(env))

    # Phase transitions
    if step == PHASE_F1_END
        println("  → Phase F1 complete (convergence)")
        println("    Distance to target: $(round(dist, digits=2))")
    elseif step == PHASE_F2_END
        println("  → Phase F2 complete (escape induction)")
        println("    Distance to target: $(round(dist, digits=2))")
    end

    if step % 200 == 0
        @printf("  Step %4d/%d: Distance = %.2f\n", step, N_STEPS, dist)
    end
end

println()
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println("## Results")
println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
println()

# Metric 1: Recovery time
f2_distance = distance_history[PHASE_F2_END]
recovery_step = findfirst(d -> d < TARGET_RADIUS, distance_history[PHASE_F2_END:end])
recovery_time = isnothing(recovery_step) ? Inf : (recovery_step - 1) * env.dt

@printf("### Metric 1: Recovery Time\n")
@printf("  Distance at F2 end: %.2f\n", f2_distance)
if recovery_time == Inf
    println("  Recovery time: NOT RECOVERED")
else
    @printf("  Recovery time: %.2f seconds\n", recovery_time)
end
println()

# Metric 2: Jerk (smoothness)
velocities_f3 = [sheep_center_history[i+1] - sheep_center_history[i]
                 for i in PHASE_F2_END:(PHASE_F3_END-1)]
total_jerk = compute_jerk(velocities_f3, env.dt)

@printf("### Metric 2: Convergence Smoothness\n")
@printf("  Total jerk (F3): %.2f\n", total_jerk)
println()

# Metric 3: Final distance
final_distance = distance_history[end]

@printf("### Metric 3: Final Distance\n")
@printf("  Final distance to target: %.2f (radius: %.2f)\n", final_distance, TARGET_RADIUS)
if final_distance < TARGET_RADIUS
    println("  Status: ✅ Within target radius")
else
    println("  Status: ❌ Outside target radius")
end
println()

# Save results
metrics = Dict(
    "recovery_time" => recovery_time,
    "total_jerk" => total_jerk,
    "final_distance" => final_distance,
    "distance_history" => distance_history,
    "sheep_center_history" => sheep_center_history,
    "config" => Dict(
        "n_sheep" => N_SHEEP,
        "n_dogs" => N_DOGS,
        "target_position" => TARGET_POSITION,
        "target_radius" => TARGET_RADIUS
    )
)

timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
log_path = joinpath(LOG_DIR, "shepherding_eph_$(timestamp).jld2")
save(log_path, metrics)
println("✓ Saved: $log_path")
println()

println("✅ Shepherding experiment complete")
println()
