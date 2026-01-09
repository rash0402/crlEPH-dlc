#!/usr/bin/env julia

"""
Haze Validation Script for EPH v5.5
Analyzes correlation between Haze and prediction error to validate uncertainty estimation.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Statistics
using LinearAlgebra
using Plots
using BSON
using HDF5

# Load modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/action_vae.jl")

using .Config
using .SPM
using .ActionVAEModel

"""
Compute prediction error for VAE
"""
function compute_prediction_errors(
    vae_model,
    spm_current::Array{Float32, 4},
    actions::Array{Float32, 2},
    spm_next::Array{Float32, 4}
)
    n_samples = size(spm_current, 4)
    prediction_errors = Float64[]
    haze_values = Float64[]
    
    println("Computing prediction errors and Haze values...")
    
    for i in 1:n_samples
        # Get current SPM
        y_curr = spm_current[:, :, :, i:i]
        u = actions[:, i:i]
        y_next_true = spm_next[:, :, :, i]
        
        # Encode to get latent distribution
        μ, logσ = ActionVAEModel.encode(vae_model, y_curr)
        
        # Compute Haze (mean variance)
        variance = exp.(2 .* logσ)
        haze = mean(variance)
        push!(haze_values, Float64(haze))
        
        # Predict next SPM
        z = μ  # Use mean for deterministic prediction
        y_next_pred = ActionVAEModel.decode_with_u(vae_model, z, u)
        
        # Compute prediction error (MSE)
        error = mean((y_next_pred[:, :, :, 1] .- y_next_true).^2)
        push!(prediction_errors, Float64(error))
        
        if i % 1000 == 0
            @printf("  Processed %d / %d samples\\n", i, n_samples)
        end
    end
    
    return haze_values, prediction_errors
end

"""
Compute correlation and calibration metrics
"""
function analyze_haze_validity(
    haze_values::Vector{Float64},
    prediction_errors::Vector{Float64}
)
    # Pearson correlation
    correlation = cor(haze_values, prediction_errors)
    
    # Spearman rank correlation (more robust to outliers)
    spearman = cor(sortperm(haze_values), sortperm(prediction_errors))
    
    # Bin Haze values for calibration curve
    n_bins = 10
    haze_sorted_idx = sortperm(haze_values)
    bin_size = length(haze_values) ÷ n_bins
    
    bin_haze_means = Float64[]
    bin_error_means = Float64[]
    bin_error_stds = Float64[]
    
    for i in 1:n_bins
        start_idx = (i-1) * bin_size + 1
        end_idx = i == n_bins ? length(haze_values) : i * bin_size
        
        bin_indices = haze_sorted_idx[start_idx:end_idx]
        
        push!(bin_haze_means, mean(haze_values[bin_indices]))
        push!(bin_error_means, mean(prediction_errors[bin_indices]))
        push!(bin_error_stds, std(prediction_errors[bin_indices]))
    end
    
    return (
        correlation=correlation,
        spearman=spearman,
        calibration=(
            haze_means=bin_haze_means,
            error_means=bin_error_means,
            error_stds=bin_error_stds
        )
    )
end

"""
Create visualization plots
"""
function create_validation_plots(
    haze_values::Vector{Float64},
    prediction_errors::Vector{Float64},
    analysis_results;
    output_dir::String="results/haze_validation"
)
    mkpath(output_dir)
    
    # 1. Scatter plot: Haze vs Prediction Error
    p1 = scatter(haze_values, prediction_errors,
        xlabel="Haze (Mean Latent Variance)",
        ylabel="Prediction Error (MSE)",
        title="Haze vs Prediction Error\\nr = $(round(analysis_results.correlation, digits=3))",
        alpha=0.3,
        markersize=2,
        legend=false
    )
    savefig(p1, joinpath(output_dir, "haze_vs_error_scatter.png"))
    
    # 2. Calibration curve
    cal = analysis_results.calibration
    p2 = plot(cal.haze_means, cal.error_means,
        ribbon=cal.error_stds,
        xlabel="Haze (binned)",
        ylabel="Mean Prediction Error",
        title="Calibration Curve",
        label="Mean ± Std",
        linewidth=2,
        fillalpha=0.3
    )
    savefig(p2, joinpath(output_dir, "calibration_curve.png"))
    
    # 3. Histograms
    p3 = histogram(haze_values,
        xlabel="Haze",
        ylabel="Frequency",
        title="Haze Distribution",
        bins=50,
        legend=false
    )
    savefig(p3, joinpath(output_dir, "haze_histogram.png"))
    
    p4 = histogram(prediction_errors,
        xlabel="Prediction Error (MSE)",
        ylabel="Frequency",
        title="Prediction Error Distribution",
        bins=50,
        legend=false
    )
    savefig(p4, joinpath(output_dir, "error_histogram.png"))
    
    println("📊 Plots saved to: $output_dir")
end

"""
Visualize extreme cases (Max Error, Max Haze)
"""
function visualize_extreme_cases(
    test_data,
    haze_values::Vector{Float64},
    prediction_errors::Vector{Float64},
    vae_model;
    output_dir::String="results/haze_validation"
)
    # Find indices
    max_error_idx = argmax(prediction_errors)
    min_error_idx = argmin(prediction_errors)
    max_haze_idx = argmax(haze_values)
    min_haze_idx = argmin(haze_values)
    
    indices = [max_error_idx, min_error_idx, max_haze_idx, min_haze_idx]
    titles = ["Max Error", "Min Error", "Max Haze", "Min Haze"]
    
    p = plot(layout=(2, 4), size=(1000, 500))
    
    for (i, idx) in enumerate(indices)
        # Get data
        x = test_data["x"][:, :, :, idx:idx]
        u = test_data["u"][:, idx:idx]
        
        # Original SPM (Channel 1: Ego)
        heatmap!(p[1, i], x[:, :, 1, 1],
            c=:viridis,
            title="$(titles[i])\nErr=$(round(prediction_errors[idx], digits=4))\nHaze=$(round(haze_values[idx], digits=4))",
            axis=false, colorbar=false
        )
        
        # Reconstructed
        x_hat, _, _ = vae_model(x, u)
        heatmap!(p[2, i], x_hat[:, :, 1, 1],
            c=:viridis,
            title="Reconstructed",
            axis=false, colorbar=false
        )
    end
    
    savefig(p, joinpath(output_dir, "extreme_cases_comparison.png"))
    println("🔍 Extreme cases visualization saved.")
end

"""
Generate validation report
"""
function generate_validation_report(
    analysis_results,
    n_samples::Int;
    output_path::String="results/haze_validation/report.md"
)
    mkpath(dirname(output_path))
    
    report = """
    # Haze 検証レポート
    
    ## 概要
    
    - **総サンプル数**: $n_samples
    - **ピアソン相関**: $(round(analysis_results.correlation, digits=4))
    - **スピアマン相関**: $(round(analysis_results.spearman, digits=4))
    
    ## 解釈
    
    ### 相関分析
    
    $(if analysis_results.correlation > 0.5
        "✅ **強い正の相関**が Haze と予測誤差の間に検出されました。これは、Haze が有効な不確実性指標であることを示しています。"
    elseif analysis_results.correlation > 0.3
        "⚠️ **中程度の正の相関**が検出されました。Haze は不確実性指標として一定の妥当性を示していますが、改善の余地があります。"
    elseif analysis_results.correlation < -0.3
        "❌ **負の相関**が検出されました。Haze（潜在分散）が高いほど予測誤差が低くなる傾向があります。モデルの不確実性推定が期待とは逆の振る舞いをしている可能性があります。"
    else
        "❌ **弱い相関**しか検出されませんでした。Haze が予測の不確実性を適切に捉えられていない可能性があります。モデルの改善を検討してください。"
    end)
    
    ### キャリブレーション
    
    キャリブレーションカーブは、Haze の値が大きくなるにつれて予測誤差がどのように変化するかを示しています。
    理想的な不確実性推定器では、Haze と平均予測誤差の間に単調増加の関係が見られるはずです。
    
    ## 推奨事項
    
    $(if analysis_results.correlation > 0.3
        "- Haze は β 変調に使用可能です\\n- EPH 実装を進めてください"
    else
        "- VAE の訓練（データ追加、アーキテクチャ最適化）を再検討してください\\n- 代替の不確実性推定手法を模索してください\\n- アンサンブル法などによる認識的不確実性の導入を検討してください"
    end)
    
    ## キャリブレーションデータ
    
    | Haze (binned) | 平均誤差 | 標準誤差 |
    |---------------|----------|----------|
    """
    
    for i in 1:length(analysis_results.calibration.haze_means)
        h = round(analysis_results.calibration.haze_means[i], digits=6)
        e = round(analysis_results.calibration.error_means[i], digits=6)
        s = round(analysis_results.calibration.error_stds[i], digits=6)
        report *= "| $h | $e | $s |\\n"
    end
    write(output_path, report)
    println("📄 レポートを保存しました: $output_path")
end

function main()
    # Main execution
    println("🔍 Haze Validation Analysis")
    println("=" ^ 60)
    
    # Load VAE model
    println("\n📦 Loading VAE model...")
    vae_path = "models/action_vae_best.bson"
    if !isfile(vae_path)
        error("VAE model not found at: $vae_path. Please train the model first.")
    end
    vae_model = BSON.load(vae_path)[:model]
    println("✅ VAE model loaded")
    
    # Load test data
    println("\n📦 Loading test data...")
    data_files = filter(f -> endswith(f, ".h5") && contains(f, "test"), readdir("data/vae_training", join=true))
    
    if isempty(data_files)
        error("No test data found. Please run collect_diverse_vae_data.jl first.")
    end
    
    test_file = data_files[1]
    println("Using: $test_file")
    
    # Load test data and metadata
    spm_current, actions, spm_next, densities = h5open(test_file, "r") do file
        (
            read(file, "spm_current"),
            read(file, "actions"),
            read(file, "spm_next"),
            read(file, "densities")
        )
    end
    
    test_data = Dict(
        "x" => spm_current,
        "u" => actions,
        "y" => spm_next
    )
    
    n_samples = size(spm_current, 4)
    println("✅ Loaded $n_samples test samples")
    
    # Compute Haze and prediction errors
    println("\n🧮 Computing Haze and prediction errors...")
    haze_values, prediction_errors = compute_prediction_errors(
        vae_model, spm_current, actions, spm_next
    )
    
    # Overall analysis
    println("\n📊 Analyzing Haze validity (Overall)...")
    analysis_results = analyze_haze_validity(haze_values, prediction_errors)
    
    println("\nResults (Overall):")
    println("  Pearson correlation:  $(round(analysis_results.correlation, digits=4))")
    println("  Spearman correlation: $(round(analysis_results.spearman, digits=4))")
    
    # Density-based analysis
    println("\n📊 Density-based Analysis:")
    unique_densities = sort(unique(densities))
    density_results = Dict()
    
    for d in unique_densities
        idx = findall(x -> x == d, densities)
        h_d = haze_values[idx]
        e_d = prediction_errors[idx]
        
        corr = cor(h_d, e_d)
        println("  Density $d (n=$(length(idx))): Correlation = $(round(corr, digits=4))")
        density_results[d] = corr
    end
    
    # Define output directory
    output_dir = "results/haze_validation"
    
    # Create plots
    println("\n📈 Creating validation plots...")
    create_validation_plots(haze_values, prediction_errors, analysis_results, output_dir=output_dir)
    
    # Visualize extreme cases
    println("\n🔍 Visualizing extreme cases...")
    visualize_extreme_cases(test_data, haze_values, prediction_errors, vae_model, output_dir=output_dir)
    
    # Generate report
    println("\n📝 Generating validation report...")
    report_content = """
    
    ## 混雑度別分析 (Density Analysis)
    
    | 混雑度 (Agents/Group) | サンプル数 | 相関係数 |
    |-----------------------|------------|----------|
    """
    for d in unique_densities
        n_density = count(x -> x == d, densities)
        corr_val = round(density_results[d], digits=4)
        report_content *= "| $d | $n_density | $corr_val |\n"
    end
    
    generate_validation_report(analysis_results, n_samples, output_path=joinpath(output_dir, "report.md"))
    
    # Append density analysis to the report
    open(joinpath(output_dir, "report.md"), "a") do f
        write(f, report_content)
    end
    
    println("\n✅ Haze validation complete!")
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
