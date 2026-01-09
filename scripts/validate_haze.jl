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
        # Get current SPM and action
        y_curr = spm_current[:, :, :, i:i]
        u = actions[:, i:i]
        y_next_true = spm_next[:, :, :, i]
        
        # Encode with (y, u) -> Pattern D
        μ, logσ = ActionVAEModel.encode(vae_model, y_curr, u)
        
        # Compute Haze (mean variance)
        variance = exp.(2 .* logσ)
        haze = mean(variance)
        push!(haze_values, Float64(haze))
        
        # Predict next SPM (using mean z)
        z = μ  
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
Analyze Counterfactual Haze (Action Dependency)
Check if different actions lead to different Haze variances for the same state.
"""
function analyze_counterfactual_haze(
    vae_model,
    spm_current::Array{Float32, 4}
)
    println("\n🔄 Analyzing Counterfactual Haze...")
    
    n_samples = min(100, size(spm_current, 4)) # Analyze first 100 samples
    haze_variations = Float64[]
    
    # Define test actions (Stop, Forward, Turn Left, Turn Right)
    test_actions = [
        [0.0, 0.0],   # Stop
        [1.0, 0.0],   # Forward Max
        [0.5, 0.5],   # Right Turn
        [0.5, -0.5]   # Left Turn
    ]
    
    for i in 1:n_samples
        y = spm_current[:, :, :, i:i]
        hazes = Float64[]
        
        for u_vec in test_actions
            u = reshape(Float32.(u_vec), :, 1)
            μ, logσ = ActionVAEModel.encode(vae_model, y, u)
            variance = mean(exp.(2 .* logσ))
            push!(hazes, variance)
        end
        
        # Calculate variation (Max - Min Haze for this state)
        variation = maximum(hazes) - minimum(hazes)
        push!(haze_variations, variation)
    end
    
    avg_variation = mean(haze_variations)
    println("  Average Haze Variation across actions: $(round(avg_variation, digits=6))")
    
    if avg_variation > 1e-6
        println("✅ Haze is Action-Dependent (Pattern D confirmed).")
    else
        println("⚠️ Haze shows little action dependency. Check model training.")
    end
    
    return avg_variation
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
    
    # Spearman rank correlation
    spearman = cor(sortperm(haze_values), sortperm(prediction_errors))
    
    # Bin Haze values
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
    
    # Scatter plot
    p1 = scatter(haze_values, prediction_errors,
        xlabel="Haze (Action-Dependent)",
        ylabel="Prediction Error (MSE)",
        title="Haze vs Error (r=$(round(analysis_results.correlation, digits=3)))",
        alpha=0.3, markersize=2, legend=false
    )
    savefig(p1, joinpath(output_dir, "haze_vs_error_scatter.png"))
    
    # Calibration curve
    cal = analysis_results.calibration
    p2 = plot(cal.haze_means, cal.error_means,
        ribbon=cal.error_stds,
        xlabel="Haze (binned)",
        ylabel="Mean Prediction Error",
        title="Calibration Curve",
        linewidth=2, fillalpha=0.3, legend=false
    )
    savefig(p2, joinpath(output_dir, "calibration_curve.png"))
    
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
    
    indices = [max_error_idx, min_error_idx, max_haze_idx]
    titles = ["Max Error", "Min Error", "Max Haze"]
    
    p = plot(layout=(2, 3), size=(900, 600))
    
    for (i, idx) in enumerate(indices)
        x = test_data["x"][:, :, :, idx:idx]
        u = test_data["u"][:, idx:idx]
        
        # Original
        heatmap!(p[1, i], x[:, :, 1, 1], c=:viridis, title="$(titles[i])\nErr=$(round(prediction_errors[idx], digits=4))", axis=false)
        
        # Reconstructed
        x_hat, _, _ = vae_model(x, u)
        heatmap!(p[2, i], x_hat[:, :, 1, 1], c=:viridis, title="Reconstructed", axis=false)
    end
    
    savefig(p, joinpath(output_dir, "extreme_cases_comparison.png"))
    println("🔍 Extreme cases visualization saved.")
end

"""
Generate validation report
"""
function generate_validation_report(
    analysis_results,
    cf_variation::Float64,
    n_samples::Int;
    output_path::String="results/haze_validation/report.md"
)
    mkpath(dirname(output_path))
    
    report = """
    # Haze 検証レポート (Pattern D)
    
    ## 概要
    - **総サンプル数**: $n_samples
    - **ピアソン相関**: $(round(analysis_results.correlation, digits=4))
    - **Action Dependency**: $(round(cf_variation, digits=6)) (Mean Variation)
    
    ## 解釈
    $(if analysis_results.correlation > 0.0
        "✅ **正の相関**が検出されました。Haze は不確実性を捉えています。"
    else
        "⚠️ **負の相関**または相関なし。さらなる調整が必要です。"
    end)
    
    $(if cf_variation > 1e-5
        "✅ **Action Dependency 確認**: 行動によって Haze が変動しており、Pattern D は正常に機能しています。"
    else
        "⚠️ **Action Dependency 低**: Haze が行動に依存していません。"
    end)
    """
    
    write(output_path, report)
    println("📄 レポートを保存しました: $output_path")
end

function main()
    println("🔍 Haze Validation Analysis (Pattern D)")
    println("=" ^ 60)
    
    # Load VAE model
    vae_path = "models/action_vae_best.bson"
    if !isfile(vae_path)
        # Check checkpoints 
        checkpoints = readdir("models/checkpoints", join=true)
        if !isempty(checkpoints)
            vae_path = sort(checkpoints, by=mtime)[end]
            println("⚠️ Best model not found, using latest checkpoint: $vae_path")
        else
            error("No VAE model found. Train first.")
        end
    end
    vae_model = BSON.load(vae_path)[:model]
    println("✅ VAE model loaded")
    
    # Load test data
    data_dir = "data/vae_training"
    test_files = filter(f -> contains(f, "test") && endswith(f, ".h5"), readdir(data_dir, join=true))
    if isempty(test_files); error("No test data found."); end
    test_file = test_files[1]
    
    println("Using: $test_file")
    
    spm_current, actions, spm_next, densities = h5open(test_file, "r") do file
        (read(file, "spm_current"), read(file, "actions"), read(file, "spm_next"), read(file, "densities"))
    end
    
    test_data = Dict("x" => spm_current, "u" => actions, "y" => spm_next)
    
    # Counterfactual Analysis
    cf_variation = analyze_counterfactual_haze(vae_model, spm_current)
    
    # Correlation Analysis
    haze_values, prediction_errors = compute_prediction_errors(vae_model, spm_current, actions, spm_next)
    analysis_results = analyze_haze_validity(haze_values, prediction_errors)
    
    println("Results: Correlation = $(round(analysis_results.correlation, digits=4))")
    
    create_validation_plots(haze_values, prediction_errors, analysis_results)
    visualize_extreme_cases(test_data, haze_values, prediction_errors, vae_model)
    generate_validation_report(analysis_results, cf_variation, size(spm_current, 4))
    
    println("\n✅ Haze validation complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
