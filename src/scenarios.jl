"""
Scenario Module for EPH v5.6
Provides Scramble Crossing and Corridor scenario implementations
"""

module Scenarios

using Random
using LinearAlgebra

# Import parent modules
import ..Dynamics: Agent, AgentGroup, CircularObstacle, NORTH, SOUTH, EAST, WEST

export ScenarioType, ScenarioParams
export initialize_scenario, get_obstacles
export SCRAMBLE_CROSSING, CORRIDOR, RANDOM_OBSTACLES

"""
Scenario type enumeration
"""
@enum ScenarioType begin
    SCRAMBLE_CROSSING
    CORRIDOR
    RANDOM_OBSTACLES
end

"""
Scenario-specific parameters
"""
struct ScenarioParams
    scenario_type::ScenarioType
    world_size::Tuple{Float64, Float64}
    num_groups::Int
    group_positions::Vector{Tuple{Float64, Float64}}
    group_goals::Vector{Tuple{Float64, Float64}}
    corridor_width::Union{Nothing, Float64}  # Corridorのみ使用
    num_obstacles::Union{Nothing, Int}       # Random Obstaclesのみ使用
    obstacle_seed::Union{Nothing, Int}       # Random Obstacles obstacle generation seed
end

"""
Initialize Scramble Crossing scenario.
4 groups crossing at intersection.

# Arguments
- `num_agents_per_group::Int`: Number of agents per group

# Returns
- `ScenarioParams`: Scenario configuration
"""
function init_scramble_crossing(num_agents_per_group::Int)
    world_size = (100.0, 100.0)  # v7.2: Unified 100×100 world
    center = (50.0, 50.0)

    # 4グループの初期位置とゴール（東西南北の4方向、通路模擬）
    # 中心から30m離れた位置に配置（100×100世界にスケール）
    margin_from_center = 30.0
    positions = [
        (center[1] - margin_from_center, center[2]),       # West (20, 50)
        (center[1], center[2] + margin_from_center),       # North (50, 80)
        (center[1] + margin_from_center, center[2]),       # East (80, 50)
        (center[1], center[2] - margin_from_center)        # South (50, 20)
    ]

    goals = [
        (center[1] + margin_from_center, center[2]),       # West → East (80, 50)
        (center[1], center[2] - margin_from_center),       # North → South (50, 20)
        (center[1] - margin_from_center, center[2]),       # East → West (20, 50)
        (center[1], center[2] + margin_from_center)        # South → North (50, 80)
    ]

    return ScenarioParams(
        SCRAMBLE_CROSSING,
        world_size,
        4,
        positions,
        goals,
        nothing,
        nothing,
        nothing
    )
end

"""
Initialize Corridor scenario.
Bidirectional flow in narrow passage.

# Arguments
- `num_agents_per_group::Int`: Number of agents per group
- `corridor_width::Float64`: Width of corridor (default: 10.0 m)

# Returns
- `ScenarioParams`: Scenario configuration
"""
function init_corridor(num_agents_per_group::Int; corridor_width::Float64=15.0)
    # v7.2: Funnel-shaped corridor with tapered walls
    world_size = (100.0, 50.0)  # 100m long, 50m wide
    center_y = world_size[2] / 2.0  # 25m

    # 2グループ: 左→右、右→左
    # 初期位置は通路中央（Y=25m）で左右端に配置
    positions = [
        (10.0, center_y),    # Group 1: Left side, center of corridor
        (90.0, center_y)     # Group 2: Right side, center of corridor
    ]

    goals = [
        (90.0, center_y),   # Group 1 goal: Right side
        (10.0, center_y)    # Group 2 goal: Left side
    ]

    return ScenarioParams(
        CORRIDOR,
        world_size,
        2,
        positions,
        goals,
        corridor_width,
        nothing,
        nothing
    )
end

"""
Initialize Random Obstacles scenario.
Agents navigate through randomly placed circular obstacles.

# Arguments
- `num_agents_per_group::Int`: Number of agents per group
- `num_obstacles::Int`: Number of circular obstacles (default: 50)
- `obstacle_seed::Int`: Random seed for obstacle generation (default: 42)

# Returns
- `ScenarioParams`: Scenario configuration
"""
function init_random_obstacles(
    num_agents_per_group::Int;
    num_obstacles::Int=50,
    obstacle_seed::Int=42
)
    world_size = (100.0, 100.0)  # v7.2: Unified 100×100 world
    center = (50.0, 50.0)

    # 4グループの初期位置とゴール（Scrambleと同様だが、障害物回避が必要）
    # 各グループは対角線上の目標に向かう（100×100世界にスケール）
    positions = [
        (10.0, 10.0),      # Bottom-left
        (10.0, 90.0),      # Top-left
        (90.0, 90.0),      # Top-right
        (90.0, 10.0)       # Bottom-right
    ]

    goals = [
        (90.0, 90.0),      # Bottom-left → Top-right
        (90.0, 10.0),      # Top-left → Bottom-right
        (10.0, 10.0),      # Top-right → Bottom-left
        (10.0, 90.0)       # Bottom-right → Top-left
    ]

    return ScenarioParams(
        RANDOM_OBSTACLES,
        world_size,
        4,
        positions,
        goals,
        nothing,
        num_obstacles,
        obstacle_seed
    )
end

"""
Initialize agents for given scenario.

# Arguments
- `scenario_type::ScenarioType`: SCRAMBLE_CROSSING, CORRIDOR, or RANDOM_OBSTACLES
- `num_agents_per_group::Int`: Number of agents per group
- `seed::Int`: Random seed for agent initialization reproducibility
- `corridor_width::Float64`: Width of corridor (CORRIDOR only, default: 4.0)
- `num_obstacles::Int`: Number of circular obstacles (RANDOM_OBSTACLES only, default: 50)
- `obstacle_seed::Int`: Random seed for obstacle generation (RANDOM_OBSTACLES only, default: 42)

# Returns
- `agents::Vector{Agent}`: Initialized agents
- `params::ScenarioParams`: Scenario parameters
"""
function initialize_scenario(
    scenario_type::ScenarioType,
    num_agents_per_group::Int;
    seed::Int=42,
    corridor_width::Float64=4.0,
    num_obstacles::Int=50,
    obstacle_seed::Int=42
)
    Random.seed!(seed)

    if scenario_type == SCRAMBLE_CROSSING
        params = init_scramble_crossing(num_agents_per_group)
    elseif scenario_type == CORRIDOR
        params = init_corridor(num_agents_per_group, corridor_width=corridor_width)
    elseif scenario_type == RANDOM_OBSTACLES
        params = init_random_obstacles(
            num_agents_per_group,
            num_obstacles=num_obstacles,
            obstacle_seed=obstacle_seed
        )
    else
        error("Unknown scenario type: $scenario_type")
    end

    # エージェント生成
    agents = Agent[]

    # AgentGroupのマッピング（Scramble/Random: 4グループ、Corridor: 2グループ）
    agent_groups = params.num_groups == 4 ? [WEST, NORTH, EAST, SOUTH] : [WEST, EAST]

    # グループごとの色設定
    group_colors = params.num_groups == 4 ?
        ["red", "blue", "green", "yellow"] :
        ["red", "blue"]

    for group_id in 1:params.num_groups
        start_pos = params.group_positions[group_id]
        goal_pos = params.group_goals[group_id]

        for i in 1:num_agents_per_group
            # グループ内でランダムに分散（v7.2: バラつきを大幅に拡大）
            if params.scenario_type == CORRIDOR
                # Funnel-shaped Corridor: X位置に応じて幅が変化
                narrow_width = params.corridor_width === nothing ? 15.0 : params.corridor_width
                wide_width = 50.0  # 入口/出口の幅
                narrow_x_start = 40.0
                narrow_x_end = 60.0
                world_x = params.world_size[1]
                center_y = params.world_size[2] / 2.0  # World height center

                # X位置をランダムに分散
                x_std = 10.0  # 左右に広く分散
                pos_x = start_pos[1] + randn() * x_std

                # このX位置での通路幅を計算（funnel形状）
                function get_corridor_width_at_x(x)
                    if x < narrow_x_start
                        t = x / narrow_x_start
                        return wide_width - (wide_width - narrow_width) * t
                    elseif x <= narrow_x_end
                        return narrow_width
                    else
                        t = (x - narrow_x_end) / (world_x - narrow_x_end)
                        return narrow_width + (wide_width - narrow_width) * t
                    end
                end

                # 現在のX位置での幅を取得
                current_width = get_corridor_width_at_x(pos_x)
                y_std = min(3.0, current_width / 8.0)  # 通路幅の1/8以内

                # Y座標をランダムに分散
                pos_y = start_pos[2] + randn() * y_std

                # Clamp Y to corridor bounds (center ± width/2), with 2m margin
                y_min = center_y - current_width / 2.0 + 2.0
                y_max = center_y + current_width / 2.0 - 2.0
                pos_y = clamp(pos_y, y_min, y_max)

                pos = [pos_x, pos_y]
            else
                # Scramble / Random Obstacles: 両方向とも±5.0m（10エージェント→約10m四方）
                pos = [start_pos[1] + randn() * 5.0, start_pos[2] + randn() * 5.0]
            end

            # Clamp position to world bounds (prevent out-of-bounds initialization)
            world_x = params.world_size[1]
            world_y = params.world_size[2]
            pos[1] = clamp(pos[1], 0.0, world_x)
            pos[2] = clamp(pos[2], 0.0, world_y)

            # ゴール方向（単位ベクトル）- 位置ではなく方向を指定 (v7.2)
            direction = [goal_pos[1] - start_pos[1], goal_pos[2] - start_pos[2]]
            direction_normalized = direction / norm(direction)

            # 初期速度：ゴール方向に1.0 m/s（heading計算のため）
            vel = direction_normalized * 1.0
            acc = [0.0, 0.0]

            # v7.2: Heading from initial velocity direction
            heading = atan(vel[2], vel[1])

            agent = Agent(
                length(agents) + 1,          # id
                agent_groups[group_id],      # group
                pos,                         # pos
                vel,                         # vel
                heading,                     # heading (v7.2: NEW - Float64 scalar)
                acc,                         # acc
                direction_normalized,        # d_goal: 方向ベクトル（v7.2 renamed from goal）
                group_colors[group_id],      # color
                1.0                          # precision
            )
            push!(agents, agent)
        end
    end

    return agents, params
end

"""
Get scenario-specific obstacles.

# Arguments
- `params::ScenarioParams`: Scenario parameters

# Returns
- `obstacles::Vector{Tuple{Float64, Float64}}`: List of obstacle positions

# Note
- CORRIDOR: Funnel-shaped walls filled with 1.0m-spaced points
- SCRAMBLE_CROSSING: Four 10×10m corner blocks
- RANDOM_OBSTACLES: Randomly placed circular obstacles (2-4m radius)
"""
function get_obstacles(params::ScenarioParams)
    obstacles = Tuple{Float64, Float64}[]

    if params.scenario_type == SCRAMBLE_CROSSING
        # Scramble Crossing: 四隅に障害物を配置（通路の模擬）
        # v7.2: 100×100世界に対応
        world_x, world_y = params.world_size
        obstacle_size = 10.0  # 10m × 10m の障害物（100×100にスケール）

        # 四隅に障害物領域を設定（1m間隔で配置）
        spacing = 1.0

        # 左下コーナー (0-10m, 0-10m)
        for x in 0:spacing:obstacle_size
            for y in 0:spacing:obstacle_size
                push!(obstacles, (x, y))
            end
        end

        # 左上コーナー (0-10m, 90-100m)
        for x in 0:spacing:obstacle_size
            for y in (world_y - obstacle_size):spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 右上コーナー (90-100m, 90-100m)
        for x in (world_x - obstacle_size):spacing:world_x
            for y in (world_y - obstacle_size):spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 右下コーナー (90-100m, 0-10m)
        for x in (world_x - obstacle_size):spacing:world_x
            for y in 0:spacing:obstacle_size
                push!(obstacles, (x, y))
            end
        end

    elseif params.scenario_type == CORRIDOR
        # v7.2: Funnel-shaped corridor with linearly tapered walls
        # 世界サイズ: 100m × 50m
        # 設計:
        #   X=0-40m:   幅50m → 15m (線形遷移、斜め壁)
        #   X=40-60m:  幅15m (狭隘部、一定幅)
        #   X=60-100m: 幅15m → 50m (線形遷移、斜め壁)
        narrow_width = params.corridor_width  # 狭隘部の幅（デフォルト15m）
        wide_width = 50.0  # 入口/出口の幅（50m）
        narrow_x_start = 40.0  # 狭隘部開始X座標
        narrow_x_end = 60.0    # 狭隘部終了X座標

        center_y = params.world_size[2] / 2.0  # 25m
        world_x = params.world_size[1]  # 100m
        world_y = params.world_size[2]  # 50m
        spacing = 1.0  # 1.0m間隔で障害物を配置（高速計算）

        # X位置に応じて通路幅を線形補間で計算
        function get_corridor_width_at_x(x)
            if x < narrow_x_start
                # 入口部: 50m → 15m に線形遷移
                # width(x) = 50 - 35*(x/40)
                t = x / narrow_x_start  # 0→1
                return wide_width - (wide_width - narrow_width) * t
            elseif x <= narrow_x_end
                # 狭隘部: 一定幅15m
                return narrow_width
            else
                # 出口部: 15m → 50m に線形遷移
                # width(x) = 15 + 35*((x-60)/40)
                t = (x - narrow_x_end) / (world_x - narrow_x_end)  # 0→1
                return narrow_width + (wide_width - narrow_width) * t
            end
        end

        # 上側の障害物壁を生成（斜め壁）
        for x in 0:spacing:world_x
            current_width = get_corridor_width_at_x(x)
            upper_wall_y_start = center_y + current_width / 2.0
            for y in upper_wall_y_start:spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 下側の障害物壁を生成（斜め壁）
        for x in 0:spacing:world_x
            current_width = get_corridor_width_at_x(x)
            lower_wall_y_end = center_y - current_width / 2.0
            for y in 0:spacing:lower_wall_y_end
                push!(obstacles, (x, y))
            end
        end

    elseif params.scenario_type == SCRAMBLE_CROSSING
        # Scramble crossing: Four corner obstacles to define intersection boundaries
        # Creates a cross-shaped intersection with open pathways
        world_x, world_y = params.world_size
        center_x, center_y = world_x / 2.0, world_y / 2.0

        # Corner obstacle dimensions (10m x 10m blocks in each corner)
        corner_size = 10.0
        spacing = 1.0  # 1m spacing between obstacle points

        # Top-left corner (0 ≤ x ≤ 10, 40 ≤ y ≤ 50)
        for x in 0:spacing:corner_size
            for y in (world_y - corner_size):spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # Top-right corner (40 ≤ x ≤ 50, 40 ≤ y ≤ 50)
        for x in (world_x - corner_size):spacing:world_x
            for y in (world_y - corner_size):spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # Bottom-left corner (0 ≤ x ≤ 10, 0 ≤ y ≤ 10)
        for x in 0:spacing:corner_size
            for y in 0:spacing:corner_size
                push!(obstacles, (x, y))
            end
        end

        # Bottom-right corner (40 ≤ x ≤ 50, 0 ≤ y ≤ 10)
        for x in (world_x - corner_size):spacing:world_x
            for y in 0:spacing:corner_size
                push!(obstacles, (x, y))
            end
        end

    elseif params.scenario_type == RANDOM_OBSTACLES
        # v7.2: Random circular obstacles (now using CircularObstacle struct)
        # Provides accurate collision detection with true circular geometry
        world_x, world_y = params.world_size
        num_obstacles = params.num_obstacles === nothing ? 50 : params.num_obstacles
        obstacle_seed = params.obstacle_seed === nothing ? 42 : params.obstacle_seed

        # Use separate RNG for obstacle generation (independent of agent seed)
        rng = Random.MersenneTwister(obstacle_seed)

        # Define safe zones (agent start/goal areas, 15m radius around each corner)
        safe_radius = 15.0

        safe_zones = [
            (10.0, 10.0),      # Bottom-left
            (10.0, 90.0),      # Top-left
            (90.0, 90.0),      # Top-right
            (90.0, 10.0)       # Bottom-right
        ]

        # Create CircularObstacle array for Random Obstacles
        circular_obstacles = CircularObstacle[]

        # Generate random circular obstacles
        num_circles_generated = 0
        attempts = 0
        max_attempts = num_obstacles * 10  # Prevent infinite loop

        while num_circles_generated < num_obstacles && attempts < max_attempts
            # Random center position (avoid boundaries: 10m margin for 100×100 world)
            margin = 10.0
            cx = margin + rand(rng) * (world_x - 2 * margin)
            cy = margin + rand(rng) * (world_y - 2 * margin)

            # Random radius (2.0 - 4.0 m)
            radius = 2.0 + rand(rng) * 2.0

            # Check if obstacle (including its radius) overlaps with safe zone
            in_safe_zone = false
            for safe_pos in safe_zones
                dist_to_safe = sqrt((cx - safe_pos[1])^2 + (cy - safe_pos[2])^2)
                # Obstacle center must be at least safe_radius + obstacle_radius away
                if dist_to_safe < safe_radius + radius
                    in_safe_zone = true
                    break
                end
            end

            if !in_safe_zone
                # v7.2: Store as CircularObstacle (no point cloud filling)
                push!(circular_obstacles, CircularObstacle((cx, cy), radius))
                num_circles_generated += 1
            end

            attempts += 1
        end

        # Return CircularObstacle array for Random Obstacles
        return circular_obstacles
    end

    return obstacles
end

end # module
