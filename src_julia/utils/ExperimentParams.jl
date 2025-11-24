"""
ExperimentParams - 環境変数から実験パラメータを読み取るヘルパー

GUIまたはコマンドラインから環境変数を通じてパラメータを設定可能:
- EPH_N_AGENTS: エージェント数
- EPH_SIM_TIME: シミュレーション時間 (秒)
- EPH_WORLD_SIZE: ワールドサイズ (ピクセル)
- EPH_HAZE_DECAY: ヘイズ減衰率 (0.8-0.999)
- EPH_HAZE_DEPOSIT: ヘイズ堆積量 (0.0-1.0)

設定されていない場合はデフォルト値を使用
"""
module ExperimentParams

export get_n_agents, get_sim_time, get_world_size, get_haze_decay, get_haze_deposit
export get_n_steps, print_experiment_config

"""
    get_n_agents(default=10)

エージェント数を取得。ENV["EPH_N_AGENTS"]が設定されていればその値を、なければdefaultを返す。
"""
function get_n_agents(default::Int=10)::Int
    return haskey(ENV, "EPH_N_AGENTS") ? parse(Int, ENV["EPH_N_AGENTS"]) : default
end

"""
    get_sim_time(default=200.0)

シミュレーション時間（秒）を取得。ENV["EPH_SIM_TIME"]が設定されていればその値を、なければdefaultを返す。
"""
function get_sim_time(default::Float64=200.0)::Float64
    return haskey(ENV, "EPH_SIM_TIME") ? parse(Float64, ENV["EPH_SIM_TIME"]) : default
end

"""
    get_n_steps(default_sim_time=200.0, dt=0.1)

シミュレーションステップ数を計算。sim_time / dt
"""
function get_n_steps(default_sim_time::Float64=200.0, dt::Float64=0.1)::Int
    sim_time = get_sim_time(default_sim_time)
    return round(Int, sim_time / dt)
end

"""
    get_world_size(default=400.0)

ワールドサイズ（ピクセル）を取得。ENV["EPH_WORLD_SIZE"]が設定されていればその値を、なければdefaultを返す。
"""
function get_world_size(default::Float64=400.0)::Float64
    return haskey(ENV, "EPH_WORLD_SIZE") ? parse(Float64, ENV["EPH_WORLD_SIZE"]) : default
end

"""
    get_haze_decay(default=0.99)

ヘイズ減衰率を取得。ENV["EPH_HAZE_DECAY"]が設定されていればその値を、なければdefaultを返す。
"""
function get_haze_decay(default::Float64=0.99)::Float64
    return haskey(ENV, "EPH_HAZE_DECAY") ? parse(Float64, ENV["EPH_HAZE_DECAY"]) : default
end

"""
    get_haze_deposit(default=0.2)

ヘイズ堆積量を取得。ENV["EPH_HAZE_DEPOSIT"]が設定されていればその値を、なければdefaultを返す。
"""
function get_haze_deposit(default::Float64=0.2)::Float64
    return haskey(ENV, "EPH_HAZE_DEPOSIT") ? parse(Float64, ENV["EPH_HAZE_DEPOSIT"]) : default
end

"""
    print_experiment_config()

現在の実験設定を表示
"""
function print_experiment_config()
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("Experiment Configuration:")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("  N Agents:     ", get_n_agents())
    println("  Sim Time:     ", get_sim_time(), "s")
    println("  N Steps:      ", get_n_steps())
    println("  World Size:   ", get_world_size(), "px")
    println("  Haze Decay:   ", get_haze_decay())
    println("  Haze Deposit: ", get_haze_deposit())
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()
end

end  # module ExperimentParams
