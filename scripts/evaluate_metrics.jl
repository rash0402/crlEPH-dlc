#!/usr/bin/env julia

"""
Evaluation Script for EPH v5.5
Computes all metrics including Freezing Rate for simulation results.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Statistics
using HDF5
using Plots
using DataFrames
using LinearAlgebra
using ArgParse

# Load modules
include("../src/config.jl")
include("../src/metrics.jl")

using .Config
using .Metrics

"""
Load episode data from HDF5 simulation results (Multi-Agent format)
"""
function load_episode_data(filepath::String)
    all_episodes = Dict{String, Any}[]
    
    h5open(filepath, "r") do file
        # Check if this is the multi-agent format
        if !haskey(file, "data")
            @warn "Skip $filepath: Not a multi-agent data file (missing 'data' group)"
            return []
        end
        
        # Read metadata from attributes
        n_agents = read_attribute(file, "num_agents")
        n_steps = read_attribute(file, "actual_steps")
        
        # Read trajectory data: (dims, agents, steps)
        pos_all = Float64.(read(file, "data/position"))
        vel_all = Float64.(read(file, "data/velocity"))
        acc_all = Float64.(read(file, "data/action"))
        
        # Read collision counts (if available)
        collision_counts = zeros(Int, n_agents)
        if haskey(file, "data/collision_counts")
            collision_counts = Int.(read(file, "data/collision_counts"))
        end
        
        # Determine dimension order
        if size(pos_all, 1) != 2
            pos_all = permutedims(pos_all, (3, 2, 1))
            vel_all = permutedims(vel_all, (3, 2, 1))
            acc_all = permutedims(acc_all, (3, 2, 1))
        end
        
        # Process each agent as a separate episode
        for a in 1:n_agents
            # Extract trajectories for this agent
            pos_traj = [Vector{Float64}(pos_all[:, a, t]) for t in 1:n_steps]
            vel_traj = [Vector{Float64}(vel_all[:, a, t]) for t in 1:n_steps]
            acc_traj = [Vector{Float64}(acc_all[:, a, t]) for t in 1:n_steps]
            
            # Collision flag: true if this agent had any collision
            had_collision = collision_counts[a] > 0
            
            # For scramble crossing, goal is center region
            push!(all_episodes, Dict(
                "velocities" => vel_traj,
                "accelerations" => acc_traj,
                "positions" => pos_traj,
                "goal" => [50.0, 50.0],
                "collision" => had_collision,
                "collision_count" => collision_counts[a],
                "agent_id" => a
            ))
        end
    end
    
    return all_episodes
end

"""
Load multiple episode files
"""
function load_multiple_episodes(data_dir::String; pattern::String="eph_sim_*.h5")
    files = filter(f -> occursin(Regex(replace(pattern, "*" => ".*")), f), 
                   readdir(data_dir, join=true))
    
    all_episodes = Dict{String, Any}[]
    
    for file in files
        try
            episodes = load_episode_data(file)
            append!(all_episodes, episodes)
        catch e
            @warn "Failed to load $file: $e"
        end
    end
    
    return all_episodes
end


"""
Evaluate metrics and generate report
Returns: metrics object
"""
function evaluate_and_report(
    episode_data::Vector{Dict{String, Any}};
    output_dir::String="results/evaluation",
    method_name::String="EPH",
    silent::Bool=false
)
    mkpath(output_dir)
    
    if !silent
        println("📊 Evaluating metrics for: $method_name")
        println("   Episodes: $(length(episode_data))")
    end
    
    # Configure freeze detector
    freeze_detector = FreezeDetector(
        velocity_threshold=0.1,
        duration_threshold=2.0,
        dt=0.033
    )
    
    # Compute all metrics
    metrics = compute_episode_metrics(
        episode_data,
        freeze_detector=freeze_detector,
        goal_threshold=1.0,
        safety_radius=0.5
    )
    
    # Print results
    if !silent
        println("\n📈 Results:")
        println("=" ^ 60)
    println("Primary Outcome:")
    @printf("  Freezing Rate:          %.2f%% (%d / %d episodes)\n", 
            metrics.freezing_rate * 100, metrics.n_frozen, metrics.n_episodes)
    @printf("  Mean Freeze Duration:   %.2f s\n", metrics.mean_freeze_duration)
    
    println("\nSecondary Outcomes:")
    @printf("  Success Rate:           %.2f%%\n", metrics.success_rate * 100)
    @printf("  Collision Rate:         %.2f%%\n", metrics.collision_rate * 100)
    @printf("  Mean Jerk:              %.4f m/s³\n", metrics.mean_jerk)
    @printf("  Min TTC:                %.2f s\n", metrics.min_ttc)
    end
    
    # Create visualizations
    create_metric_plots(episode_data, metrics, output_dir, method_name)
    
    # Generate markdown report
    generate_metric_report(metrics, output_dir, method_name)
    
    return metrics
end

"""
Create visualization plots
"""
function create_metric_plots(
    episode_data::Vector{Dict{String, Any}},
    metrics::EpisodeMetrics,
    output_dir::String,
    method_name::String
)
    # 1. Freezing detection visualization
    freeze_detector = FreezeDetector()
    
    # Find a frozen episode for visualization
    frozen_idx = findfirst(ep -> begin
        result = detect_freezing(ep["velocities"], freeze_detector)
        result.is_frozen
    end, episode_data)
    
    if frozen_idx !== nothing
        ep = episode_data[frozen_idx]
        speeds = [norm(v) for v in ep["velocities"]]
        times = collect(0:length(speeds)-1) .* 0.033
        
        p1 = plot(times, speeds,
            xlabel="Time (s)",
            ylabel="Speed (m/s)",
            title="Freezing Detection Example",
            label="Speed",
            linewidth=2
        )
        hline!([freeze_detector.velocity_threshold], 
               label="Freeze Threshold", 
               linestyle=:dash, 
               color=:red)
        
        savefig(p1, joinpath(output_dir, "$(method_name)_freezing_example.png"))
    end
    
    # 2. Speed distribution across all episodes
    all_speeds = vcat([norm.(ep["velocities"]) for ep in episode_data]...)
    p2 = histogram(all_speeds,
        xlabel="Speed (m/s)",
        ylabel="Frequency",
        title="Speed Distribution - $method_name",
        bins=50,
        legend=false
    )
    savefig(p2, joinpath(output_dir, "$(method_name)_speed_distribution.png"))
    
    # 3. Jerk distribution
    all_jerks = Float64[]
    for ep in episode_data
        jerk = compute_jerk(ep["accelerations"])
        push!(all_jerks, jerk)
    end
    
    p3 = histogram(all_jerks,
        xlabel="Jerk (m/s³)",
        ylabel="Frequency",
        title="Jerk Distribution - $method_name",
        bins=30,
        legend=false
    )
    savefig(p3, joinpath(output_dir, "$(method_name)_jerk_distribution.png"))
    
    println("📊 Plots saved to: $output_dir")
end

"""
Generate markdown report
"""
function generate_metric_report(
    metrics::EpisodeMetrics,
    output_dir::String,
    method_name::String
)
    report = """
    # 評価レポート: $method_name
    
    ## 主要指標 (Primary Outcome)
    
    ### フリーズ率 (Freezing Rate)
    
    - **フリーズ率**: $(round(metrics.freezing_rate * 100, digits=2))%
    - **フリーズ発生エピソード数**: $(metrics.n_frozen) / $(metrics.n_episodes)
    - **平均フリーズ継続時間**: $(round(metrics.mean_freeze_duration, digits=2)) 秒
    
    $(if metrics.freezing_rate < 0.1
        "✅ **優秀**: フリーズ率が非常に低く、堅牢なナビゲーションが行われています。"
    elseif metrics.freezing_rate < 0.3
        "⚠️ **許容範囲**: フリーズが一定数発生しており、改善の余地があります。"
    else
        "❌ **要改善**: フリーズ率が高く、ナビゲーションに深刻な問題があります。"
    end)
    
    ## 副次指標 (Secondary Outcomes)
    
    | 指標 | 値 | ステータス |
    |------|----|-----------|
    | 成功率 (Success Rate) | $(round(metrics.success_rate * 100, digits=2))% | $(metrics.success_rate > 0.8 ? "✅" : "⚠️") |
    | 衝突率 (Collision Rate) | $(round(metrics.collision_rate * 100, digits=2))% | $(metrics.collision_rate < 0.1 ? "✅" : "❌") |
    | 平均ジャーク (Mean Jerk) | $(round(metrics.mean_jerk, digits=4)) m/s³ | $(metrics.mean_jerk < 5.0 ? "✅" : "⚠️") |
    | 最小 TTC (Min TTC) | $(round(metrics.min_ttc, digits=2)) s | $(metrics.min_ttc > 1.0 ? "✅" : "⚠️") |
    
    ## 解釈
    
    ### フリーズ分析
    
    $(if metrics.freezing_rate < 0.1
        "システムは最小限のフリーズで非常に優れたパフォーマンスを示しています。適応的な知覚解像度制御が効果的に機能しているようです。"
    else
        "フリーズが顕著に発生しています。以下の対策を検討してください：\\n- 訓練時の探索率の向上\\n- β 変調パラメータの調整\\n- VAE の予測精度の向上"
    end)
    
    ### 安全性と滑らかさ
    
    - **衝突率**: $(metrics.collision_rate < 0.05 ? "優れた安全性能" : "安全性の向上が必要")
    - **ジャーク**: $(metrics.mean_jerk < 3.0 ? "スムーズな動き" : "さらなる平滑化の余地あり")
    - **TTC**: $(metrics.min_ttc > 2.0 ? "十分な安全マージン" : "接近事案が検出されました")
    
    ## 推奨事項
    
    $(if metrics.freezing_rate < 0.1 && metrics.collision_rate < 0.05
        "- ベースライン比較の準備が整いました\\n- OOD（分布外）評価に進んでください\\n- 実環境への展開テストを検討してください"
    else
        "- より多様なデータを用いた VAE の再訓練\\n- β 変調パラメータのチューニング\\n- 失敗ケースの詳細な分析"
    end)
    """
    
    output_path = joinpath(output_dir, "$(method_name)_evaluation_report.md")
    write(output_path, report)
    println("📄 レポートを保存しました: $output_path")
end



"""
Aggregate batch results by density
"""
function aggregate_batch_results(data_dir::String, output_dir::String)
    println("\n🔄 Aggregating batch results from: $data_dir")
    
    files = filter(f -> endswith(f, ".h5") && occursin("sim_", f), readdir(data_dir, join=true))
    
    if isempty(files)
        println("   No batch files found.")
        return
    end
    
    # Regex to parse filename: sim_d{Density}_s{Seed}.h5
    # e.g., sim_d10_s001.h5
    regex = r"sim_d(\d+)_s(\d+)\.h5"
    
    results = DataFrame(Density=[], Seed=[], FreezingRate=[], SuccessRate=[], CollisionRate=[], Jerk=[])
    
    for file in files
        m = match(regex, basename(file))
        if m !== nothing
            density = parse(Int, m[1])
            seed = parse(Int, m[2])
            
            # Load and evaluate (silent)
            ep_data = load_episode_data(file)
            if !isempty(ep_data)
                metrics = evaluate_and_report(ep_data, output_dir=joinpath(output_dir, "individual"), method_name="d$(density)_s$(seed)", silent=true)
                push!(results, (density, seed, metrics.freezing_rate, metrics.success_rate, metrics.collision_rate, metrics.mean_jerk))
            end
        end
    end
    
    # Sort by density
    sort!(results, :Density)
    
    println("\n📊 Aggregate Results:")
    println(results)
    
    # Plot Freezing Rate vs Density
    # Group by density and compute mean/std
    gdf = groupby(results, :Density)
    stats = combine(gdf, :FreezingRate => mean, :FreezingRate => std, :CollisionRate => mean)
    
    p = plot(stats.Density, stats.FreezingRate_mean .* 100, 
             yerror=stats.FreezingRate_std .* 100,
             xlabel="Density (Agents/Group)", ylabel="Freezing Rate (%)",
             title="Freezing Rate vs Density",
             marker=:circle, linewidth=2, label="Freezing Rate",
             legend=:topleft)
    
    savefig(p, joinpath(output_dir, "freezing_vs_density.png"))
    println("📈 Saved density plot to: " * joinpath(output_dir, "freezing_vs_density.png"))
end

# Main execution
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--input"
            help = "Input directory or file"
            default = "data/logs"
        "--batch"
            help = "Run batch aggregation mode"
            action = :store_true
    end
    return parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    args = parse_commandline()
    
    if args["batch"]
        aggregate_batch_results(args["input"], "results/evaluation")
    else
        # ... existing single file logic ...
        target_path = args["input"]
        if isdir(target_path)
             # Get latest
             all_files = filter(f -> endswith(f, ".h5") && contains(f, "eph_sim_"), readdir(target_path))
             if isempty(all_files)
                 error("No simulation data found in $target_path")
             end
             target_path = joinpath(target_path, sort(all_files)[end])
        end
        
        println("Using file: $target_path")
        episode_data = load_episode_data(target_path)
        metrics = evaluate_and_report(episode_data, output_dir="results/evaluation", method_name="EPH")
    end
end
