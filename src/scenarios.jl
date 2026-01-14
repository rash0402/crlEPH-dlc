"""
Scenario Module for EPH v5.6
Provides Scramble Crossing and Corridor scenario implementations
"""

module Scenarios

using Random
using LinearAlgebra

# Import parent modules
import ..Dynamics: Agent, AgentGroup, NORTH, SOUTH, EAST, WEST

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
    world_size = (50.0, 50.0)
    center = (25.0, 25.0)

    # 4グループの初期位置とゴール（90度間隔）
    positions = [
        (center[1] - 15.0, center[2]),       # West
        (center[1], center[2] + 15.0),       # North
        (center[1] + 15.0, center[2]),       # East
        (center[1], center[2] - 15.0)        # South
    ]

    goals = [
        (center[1] + 15.0, center[2]),       # West → East
        (center[1], center[2] - 15.0),       # North → South
        (center[1] - 15.0, center[2]),       # East → West
        (center[1], center[2] + 15.0)        # South → North
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
function init_corridor(num_agents_per_group::Int; corridor_width::Float64=10.0)
    world_size = (60.0, 20.0)

    # 2グループ: 左→右、右→左
    positions = [
        (5.0, 10.0),    # Group 1: Left side
        (55.0, 10.0)    # Group 2: Right side
    ]

    goals = [
        (55.0, 10.0),   # Group 1 goal: Right side
        (5.0, 10.0)     # Group 2 goal: Left side
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
    world_size = (50.0, 50.0)
    center = (25.0, 25.0)

    # 4グループの初期位置とゴール（Scrambleと同様だが、障害物回避が必要）
    # 各グループは対角線上の目標に向かう
    positions = [
        (5.0, 5.0),      # Bottom-left
        (5.0, 45.0),     # Top-left
        (45.0, 45.0),    # Top-right
        (45.0, 5.0)      # Bottom-right
    ]

    goals = [
        (45.0, 45.0),    # Bottom-left → Top-right
        (45.0, 5.0),     # Top-left → Bottom-right
        (5.0, 5.0),      # Top-right → Bottom-left
        (5.0, 45.0)      # Bottom-right → Top-left
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
            # グループ内でランダムに分散
            if params.scenario_type == CORRIDOR
                # Corridor: Y方向は通路幅の1/4以内に制限、X方向は2.0m
                corridor_width_param = params.corridor_width === nothing ? 10.0 : params.corridor_width
                y_std = min(1.5, corridor_width_param / 6.0)  # 通路幅の1/6以内（例: 10m→1.67m）
                pos = [start_pos[1] + randn() * 2.0, start_pos[2] + randn() * y_std]
            else
                # Scramble / Random Obstacles: 両方向とも2.0m
                pos = [start_pos[1] + randn() * 2.0, start_pos[2] + randn() * 2.0]
            end

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

    if params.scenario_type == CORRIDOR
        # 通路の壁を障害物として定義
        # 漏斗（Funnel）型: 両端が広く、中央が狭い。斜めの壁でエージェントを誘導
        width = params.corridor_width
        center_y = params.world_size[2] / 2.0
        world_x = params.world_size[1]
        world_y = params.world_size[2]

        # 狭い通路の範囲（中央50%、例: 60mなら15-45m）
        corridor_start = world_x * 0.25  # 15m
        corridor_end = world_x * 0.75    # 45m

        # 障害物密度（1.0m間隔で配置して壁を「埋める」）
        # 0.5m間隔だと2000+個になり計算コストが高すぎる
        spacing = 1.0

        # === 左側: 斜めの壁領域を埋める（開放空間 → 狭い通路） ===
        # 上側の壁領域を埋める (y > 上側斜め壁)
        for x in 0:spacing:corridor_start
            # 上側斜め壁のy座標
            t = x / corridor_start
            wall_y = world_y * (1 - t) + (center_y + width/2.0) * t

            # 壁の上側を障害物で埋める (wall_y < y <= world_y)
            for y in wall_y:spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 下側の壁領域を埋める (y < 下側斜め壁)
        for x in 0:spacing:corridor_start
            t = x / corridor_start
            wall_y = 0.0 * (1 - t) + (center_y - width/2.0) * t

            # 壁の下側を障害物で埋める (0 <= y < wall_y)
            for y in 0:spacing:wall_y
                push!(obstacles, (x, y))
            end
        end

        # === 中央: 水平の壁領域を埋める（狭い通路部分） ===
        # 上側の壁領域を埋める
        for x in corridor_start:spacing:corridor_end
            for y in (center_y + width/2.0):spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 下側の壁領域を埋める
        for x in corridor_start:spacing:corridor_end
            for y in 0:spacing:(center_y - width/2.0)
                push!(obstacles, (x, y))
            end
        end

        # === 右側: 斜めの壁領域を埋める（狭い通路 → 開放空間） ===
        corridor_width_x = world_x - corridor_end

        # 上側の壁領域を埋める
        for x in corridor_end:spacing:world_x
            t = (x - corridor_end) / corridor_width_x
            wall_y = (center_y + width/2.0) * (1 - t) + world_y * t

            # 壁の上側を障害物で埋める
            for y in wall_y:spacing:world_y
                push!(obstacles, (x, y))
            end
        end

        # 下側の壁領域を埋める
        for x in corridor_end:spacing:world_x
            t = (x - corridor_end) / corridor_width_x
            wall_y = (center_y - width/2.0) * (1 - t) + 0.0 * t

            # 壁の下側を障害物で埋める
            for y in 0:spacing:wall_y
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
        # Random circular obstacles of varying sizes
        world_x, world_y = params.world_size
        num_obstacles = params.num_obstacles === nothing ? 50 : params.num_obstacles
        obstacle_seed = params.obstacle_seed === nothing ? 42 : params.obstacle_seed

        # Use separate RNG for obstacle generation (independent of agent seed)
        rng = Random.MersenneTwister(obstacle_seed)

        # Define safe zones (agent start/goal areas, 10m radius around each corner)
        safe_radius = 10.0

        safe_zones = [
            (5.0, 5.0),      # Bottom-left
            (5.0, 45.0),     # Top-left
            (45.0, 45.0),    # Top-right
            (45.0, 5.0)      # Bottom-right
        ]

        spacing = 1.0  # 1.0m spacing for filling circular obstacles

        # Generate random circular obstacles
        attempts = 0
        max_attempts = num_obstacles * 10  # Prevent infinite loop

        while length(obstacles) < num_obstacles * 10 && attempts < max_attempts
            # Random center position (avoid boundaries: 5m margin)
            cx = 5.0 + rand(rng) * (world_x - 10.0)
            cy = 5.0 + rand(rng) * (world_y - 10.0)

            # Random radius (2.0 - 4.0 m) - generate first to check full obstacle boundary
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

                # Fill circular obstacle with 1.0m-spaced points
                # Use grid approach: check all points within bounding box
                x_min = max(0.0, cx - radius)
                x_max = min(world_x, cx + radius)
                y_min = max(0.0, cy - radius)
                y_max = min(world_y, cy + radius)

                for x in x_min:spacing:x_max
                    for y in y_min:spacing:y_max
                        # Check if point is inside circle
                        dist = sqrt((x - cx)^2 + (y - cy)^2)
                        if dist <= radius
                            push!(obstacles, (x, y))
                        end
                    end
                end
            end

            attempts += 1
        end
    end

    return obstacles
end

end # module
