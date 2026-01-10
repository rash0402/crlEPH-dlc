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
export SCRAMBLE_CROSSING, CORRIDOR

"""
Scenario type enumeration
"""
@enum ScenarioType begin
    SCRAMBLE_CROSSING
    CORRIDOR
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
        nothing
    )
end

"""
Initialize Corridor scenario.
Bidirectional flow in narrow passage.

# Arguments
- `num_agents_per_group::Int`: Number of agents per group
- `corridor_width::Float64`: Width of corridor (default: 4.0 m)

# Returns
- `ScenarioParams`: Scenario configuration
"""
function init_corridor(num_agents_per_group::Int; corridor_width::Float64=4.0)
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
        corridor_width
    )
end

"""
Initialize agents for given scenario.

# Arguments
- `scenario_type::ScenarioType`: SCRAMBLE_CROSSING or CORRIDOR
- `num_agents_per_group::Int`: Number of agents per group
- `seed::Int`: Random seed for reproducibility

# Returns
- `agents::Vector{Agent}`: Initialized agents
- `params::ScenarioParams`: Scenario parameters
"""
function initialize_scenario(
    scenario_type::ScenarioType,
    num_agents_per_group::Int;
    seed::Int=42,
    corridor_width::Float64=4.0
)
    Random.seed!(seed)

    if scenario_type == SCRAMBLE_CROSSING
        params = init_scramble_crossing(num_agents_per_group)
    elseif scenario_type == CORRIDOR
        params = init_corridor(num_agents_per_group, corridor_width=corridor_width)
    else
        error("Unknown scenario type: $scenario_type")
    end

    # エージェント生成
    agents = Agent[]

    # AgentGroupのマッピング（Scramble用: 4グループ、Corridor用: 2グループ）
    agent_groups = params.num_groups == 4 ? [WEST, NORTH, EAST, SOUTH] : [WEST, EAST]

    # グループごとの色設定
    group_colors = params.num_groups == 4 ?
        ["red", "blue", "green", "yellow"] :
        ["red", "blue"]

    for group_id in 1:params.num_groups
        start_pos = params.group_positions[group_id]
        goal_pos = params.group_goals[group_id]

        for i in 1:num_agents_per_group
            # グループ内でランダムに分散（標準偏差2.0m）
            pos = [start_pos[1] + randn() * 2.0, start_pos[2] + randn() * 2.0]
            vel = [0.0, 0.0]
            acc = [0.0, 0.0]

            # ゴール方向の速度（1.0 m/s）
            direction = [goal_pos[1] - start_pos[1], goal_pos[2] - start_pos[2]]
            direction_normalized = direction / norm(direction)
            goal_vel = direction_normalized * 1.0

            agent = Agent(
                length(agents) + 1,          # id
                agent_groups[group_id],      # group
                pos,                         # pos
                vel,                         # vel
                acc,                         # acc
                [goal_pos[1], goal_pos[2]],  # goal
                goal_vel,                    # goal_vel
                group_colors[group_id],      # color
                1.0                          # precision
            )
            push!(agents, agent)
        end
    end

    return agents, params
end

"""
Get scenario-specific obstacles (for Corridor).

# Arguments
- `params::ScenarioParams`: Scenario parameters

# Returns
- `obstacles::Vector{Tuple{Float64, Float64}}`: List of obstacle positions
"""
function get_obstacles(params::ScenarioParams)
    if params.scenario_type == CORRIDOR
        # 通路の壁を障害物として定義
        obstacles = Tuple{Float64, Float64}[]
        width = params.corridor_width
        center_y = params.world_size[2] / 2.0

        # 上側の壁（連続障害物）
        for x in 0:1.0:params.world_size[1]
            push!(obstacles, (x, center_y + width/2.0))
        end

        # 下側の壁
        for x in 0:1.0:params.world_size[1]
            push!(obstacles, (x, center_y - width/2.0))
        end

        return obstacles
    else
        # Scrambleには壁なし
        return Tuple{Float64, Float64}[]
    end
end

end # module
