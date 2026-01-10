#!/usr/bin/env julia

"""
Phase 3: VAE Validation Script for v5.6
Validates prediction accuracy and Surprise computation capability
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Random
using HDF5
using Statistics
using Flux
using BSON
using LinearAlgebra

# Load modules
include("../src/data_schema.jl")
include("../src/action_vae.jl")

using .DataSchema
using .ActionVAEModel

"""
Parse command line arguments
"""
function parse_commandline()
    args = Dict{String, Any}(
        "model" => "models/action_vae_v56_best.bson",
        "dataset" => "data/vae_training/dataset_v56.h5",
        "results_dir" => "results/vae_validation",
        "n_counterfactual_samples" => 100,
        "visualize" => false
    )

    return args
end

"""
Compute Surprise: S(y, u) = ||y - VAE_recon(y, u)||²
"""
function compute_surprise(model::ActionConditionedVAE, spm::Array{Float32, 3}, action::Vector{Float32})
    # Reshape for model
    spm_batch = reshape(spm, 16, 16, 3, 1)
    action_batch = reshape(action, 2, 1)

    # VAE reconstruction
    spm_recon, μ, logσ = model(spm_batch, action_batch)

    # Surprise = reconstruction error
    surprise = sum((spm_batch - spm_recon).^2)

    return Float64(surprise)
end

"""
Evaluate prediction MSE on test set
"""
function evaluate_prediction_mse(
    model::ActionConditionedVAE,
    spms_current::Array{Float32, 4},
    actions::Array{Float32, 2},
    spms_next::Array{Float32, 4}
)
    n_samples = size(spms_current, 1)
    total_mse = 0.0
    channel_mse = zeros(3)

    for i in 1:n_samples
        spm_curr = spms_current[i, :, :, :]
        u = actions[i, :]
        spm_next = spms_next[i, :, :, :]

        # Reshape for model
        spm_curr_batch = reshape(spm_curr, 16, 16, 3, 1)
        u_batch = reshape(u, 2, 1)
        spm_next_batch = reshape(spm_next, 16, 16, 3, 1)

        # Predict
        spm_pred, _, _ = model(spm_curr_batch, u_batch)

        # Overall MSE
        mse_sample = sum((spm_pred - spm_next_batch).^2) / (16 * 16 * 3)
        total_mse += mse_sample

        # Channel-wise MSE
        for ch in 1:3
            ch_error = sum((spm_pred[:, :, ch, :] - spm_next_batch[:, :, ch, :]).^2) / (16 * 16)
            channel_mse[ch] += ch_error
        end
    end

    avg_mse = total_mse / n_samples
    avg_channel_mse = channel_mse / n_samples

    return Float64(avg_mse), [Float64(x) for x in avg_channel_mse]
end

"""
Validate Counterfactual Surprise:
For same SPM, risky action should have higher Surprise than safe action
"""
function validate_counterfactual_surprise(
    model::ActionConditionedVAE,
    spms_current::Array{Float32, 4},
    n_samples::Int
)
    Random.seed!(42)

    success_count = 0
    surprise_safe_list = Float64[]
    surprise_risky_list = Float64[]

    for i in 1:min(n_samples, size(spms_current, 1))
        spm = spms_current[i, :, :, :]

        # Safe action (retreat/slow down)
        u_safe = Float32.([0.0, -1.0])  # Move backward

        # Risky action (advance toward obstacles)
        u_risky = Float32.([1.0, 0.0])  # Move forward

        # Compute Surprise for both actions
        S_safe = compute_surprise(model, spm, u_safe)
        S_risky = compute_surprise(model, spm, u_risky)

        push!(surprise_safe_list, S_safe)
        push!(surprise_risky_list, S_risky)

        # Check if risky action has higher surprise
        if S_risky > S_safe
            success_count += 1
        end
    end

    success_rate = success_count / n_samples

    return success_rate, surprise_safe_list, surprise_risky_list
end

"""
Analyze Surprise-Error correlation
"""
function analyze_surprise_error_correlation(
    model::ActionConditionedVAE,
    spms_current::Array{Float32, 4},
    actions::Array{Float32, 2},
    spms_next::Array{Float32, 4},
    n_samples::Int
)
    surprises = Float64[]
    errors = Float64[]

    for i in 1:min(n_samples, size(spms_current, 1))
        spm_curr = spms_current[i, :, :, :]
        u = actions[i, :]
        spm_next = spms_next[i, :, :, :]

        # Compute Surprise
        S = compute_surprise(model, spm_curr, u)

        # Compute actual prediction error
        spm_curr_batch = reshape(spm_curr, 16, 16, 3, 1)
        u_batch = reshape(u, 2, 1)
        spm_next_batch = reshape(spm_next, 16, 16, 3, 1)

        spm_pred, _, _ = model(spm_curr_batch, u_batch)
        error = sum((spm_pred - spm_next_batch).^2) / (16 * 16 * 3)

        push!(surprises, S)
        push!(errors, Float64(error))
    end

    # Spearman correlation
    # Simple rank correlation (Spearman approximation)
    function spearman_correlation(x::Vector{Float64}, y::Vector{Float64})
        n = length(x)
        rank_x = sortperm(sortperm(x))
        rank_y = sortperm(sortperm(y))

        d_squared_sum = sum((rank_x .- rank_y).^2)
        ρ = 1.0 - (6.0 * d_squared_sum) / (n * (n^2 - 1))

        return ρ
    end

    ρ = spearman_correlation(surprises, errors)

    return ρ, surprises, errors
end

"""
Main validation
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("EPH v5.6 - Phase 3: VAE Validation")
    println("=" ^ 70)
    println("\nConfiguration:")
    println("  Model: $(args["model"])")
    println("  Dataset: $(args["dataset"])")
    println("  Results dir: $(args["results_dir"])")

    # Create output directory
    mkpath(args["results_dir"])

    # Load model
    println("\n📂 Loading VAE model...")
    if !isfile(args["model"])
        println("❌ Error: Model not found: $(args["model"])")
        println("   Please train VAE first:")
        println("   julia --project=. scripts/train_vae_v56.jl")
        exit(1)
    end

    model_data = BSON.load(args["model"])
    model = model_data[:model]
    println("  ✅ Model loaded")

    # Load dataset
    println("\n📂 Loading dataset...")
    if !isfile(args["dataset"])
        println("❌ Error: Dataset not found: $(args["dataset"])")
        exit(1)
    end

    dataset = load_dataset(args["dataset"])
    println("  Test IID: $(size(dataset.test_iid_spms_current, 1)) samples")
    println("  Test OOD: $(size(dataset.test_ood_spms_current, 1)) samples")

    # ===== 3.1: Prediction Accuracy Evaluation =====
    println("\n" * "=" ^ 70)
    println("3.1 Prediction Accuracy Evaluation")
    println("=" ^ 70)

    println("\n🔹 Test IID (In-Distribution):")
    test_iid_mse, test_iid_channel_mse = evaluate_prediction_mse(
        model,
        dataset.test_iid_spms_current,
        dataset.test_iid_actions,
        dataset.test_iid_spms_next
    )
    @printf("  Overall MSE: %.6f\n", test_iid_mse)
    @printf("  Channel 1 (Proximity): %.6f\n", test_iid_channel_mse[1])
    @printf("  Channel 2 (Velocity): %.6f\n", test_iid_channel_mse[2])
    @printf("  Channel 3 (Crossing): %.6f\n", test_iid_channel_mse[3])

    if test_iid_mse < 0.05
        println("  ✅ PASS: Test IID MSE < 0.05")
    else
        println("  ❌ FAIL: Test IID MSE >= 0.05 (Current: $(round(test_iid_mse, digits=6)))")
    end

    println("\n🔹 Test OOD (Out-of-Distribution):")
    test_ood_mse, test_ood_channel_mse = evaluate_prediction_mse(
        model,
        dataset.test_ood_spms_current,
        dataset.test_ood_actions,
        dataset.test_ood_spms_next
    )
    @printf("  Overall MSE: %.6f\n", test_ood_mse)
    @printf("  Channel 1 (Proximity): %.6f\n", test_ood_channel_mse[1])
    @printf("  Channel 2 (Velocity): %.6f\n", test_ood_channel_mse[2])
    @printf("  Channel 3 (Crossing): %.6f\n", test_ood_channel_mse[3])

    if test_ood_mse < 0.1
        println("  ✅ PASS: Test OOD MSE < 0.1")
    else
        println("  ❌ FAIL: Test OOD MSE >= 0.1 (Current: $(round(test_ood_mse, digits=6)))")
    end

    # ===== 3.2: Counterfactual Surprise Validation =====
    println("\n" * "=" ^ 70)
    println("3.2 Counterfactual Surprise Validation")
    println("=" ^ 70)

    success_rate, S_safe_list, S_risky_list = validate_counterfactual_surprise(
        model,
        dataset.test_iid_spms_current,
        args["n_counterfactual_samples"]
    )

    println("\n🔹 Testing $(args["n_counterfactual_samples"]) samples:")
    @printf("  Success Rate: %.1f%%\n", success_rate * 100)
    @printf("  Mean S(safe): %.4f\n", mean(S_safe_list))
    @printf("  Mean S(risky): %.4f\n", mean(S_risky_list))
    @printf("  Ratio S(risky)/S(safe): %.2f\n", mean(S_risky_list) / mean(S_safe_list))

    if success_rate > 0.7
        println("  ✅ PASS: Counterfactual Success Rate > 70%")
    else
        println("  ❌ FAIL: Counterfactual Success Rate <= 70%")
    end

    # ===== 3.3: Surprise-Error Correlation Analysis =====
    println("\n" * "=" ^ 70)
    println("3.3 Surprise-Error Correlation Analysis")
    println("=" ^ 70)

    ρ, surprises, errors = analyze_surprise_error_correlation(
        model,
        dataset.test_iid_spms_current,
        dataset.test_iid_actions,
        dataset.test_iid_spms_next,
        min(500, size(dataset.test_iid_spms_current, 1))
    )

    println("\n🔹 Spearman Correlation (Surprise vs Error):")
    @printf("  ρ = %.4f\n", ρ)

    if ρ > 0.4
        println("  ✅ PASS: Correlation > 0.4")
    else
        println("  ❌ FAIL: Correlation <= 0.4")
    end

    # ===== Summary =====
    println("\n" * "=" ^ 70)
    println("Validation Summary")
    println("=" ^ 70)

    criteria_passed = 0
    total_criteria = 4

    println("\nSuccess Criteria:")
    if test_iid_mse < 0.05
        println("  ✅ [1/4] Test IID MSE < 0.05: $(round(test_iid_mse, digits=6))")
        criteria_passed += 1
    else
        println("  ❌ [1/4] Test IID MSE < 0.05: $(round(test_iid_mse, digits=6))")
    end

    if success_rate > 0.7
        println("  ✅ [2/4] Counterfactual Success > 70%: $(round(success_rate * 100, digits=1))%")
        criteria_passed += 1
    else
        println("  ❌ [2/4] Counterfactual Success > 70%: $(round(success_rate * 100, digits=1))%")
    end

    if ρ > 0.4
        println("  ✅ [3/4] Surprise-Error Correlation > 0.4: $(round(ρ, digits=4))")
        criteria_passed += 1
    else
        println("  ❌ [3/4] Surprise-Error Correlation > 0.4: $(round(ρ, digits=4))")
    end

    if test_ood_mse < 0.1
        println("  ✅ [4/4] Test OOD MSE < 0.1: $(round(test_ood_mse, digits=6))")
        criteria_passed += 1
    else
        println("  ❌ [4/4] Test OOD MSE < 0.1: $(round(test_ood_mse, digits=6))")
    end

    println("\nOverall: $criteria_passed / $total_criteria criteria passed")

    # Save validation report
    report_path = joinpath(args["results_dir"], "validation_report.md")
    open(report_path, "w") do io
        println(io, "# VAE Validation Report (v5.6)")
        println(io, "\n**Date**: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io, "**Model**: $(args["model"])")
        println(io, "\n## 1. Prediction Accuracy")
        println(io, "\n### Test IID (In-Distribution)")
        println(io, "- Overall MSE: $(round(test_iid_mse, digits=6))")
        println(io, "- Channel 1 MSE: $(round(test_iid_channel_mse[1], digits=6))")
        println(io, "- Channel 2 MSE: $(round(test_iid_channel_mse[2], digits=6))")
        println(io, "- Channel 3 MSE: $(round(test_iid_channel_mse[3], digits=6))")
        println(io, "\n### Test OOD (Out-of-Distribution)")
        println(io, "- Overall MSE: $(round(test_ood_mse, digits=6))")
        println(io, "- Channel 1 MSE: $(round(test_ood_channel_mse[1], digits=6))")
        println(io, "- Channel 2 MSE: $(round(test_ood_channel_mse[2], digits=6))")
        println(io, "- Channel 3 MSE: $(round(test_ood_channel_mse[3], digits=6))")
        println(io, "\n## 2. Counterfactual Surprise")
        println(io, "- Success Rate: $(round(success_rate * 100, digits=1))%")
        println(io, "- Mean S(safe): $(round(mean(S_safe_list), digits=4))")
        println(io, "- Mean S(risky): $(round(mean(S_risky_list), digits=4))")
        println(io, "\n## 3. Surprise-Error Correlation")
        println(io, "- Spearman ρ: $(round(ρ, digits=4))")
        println(io, "\n## Success Criteria")
        println(io, "- Test IID MSE < 0.05: $(test_iid_mse < 0.05 ? "✅" : "❌")")
        println(io, "- Counterfactual > 70%: $(success_rate > 0.7 ? "✅" : "❌")")
        println(io, "- Correlation > 0.4: $(ρ > 0.4 ? "✅" : "❌")")
        println(io, "- Test OOD MSE < 0.1: $(test_ood_mse < 0.1 ? "✅" : "❌")")
        println(io, "\n**Overall**: $criteria_passed / $total_criteria passed")
    end

    println("\n📄 Report saved: $report_path")

    if criteria_passed == total_criteria
        println("\n" * "=" ^ 70)
        println("✅ ALL CRITERIA PASSED - Ready for Phase 4!")
        println("=" ^ 70)
        println("\nNext step: Control Integration (Phase 4)")
        println("  Run: julia --project=. scripts/run_simulation_v56.jl")
    else
        println("\n" * "=" ^ 70)
        println("⚠️  Some criteria not met - Consider retraining")
        println("=" ^ 70)
        println("\nRecommendations:")
        if test_iid_mse >= 0.05
            println("  - Increase training epochs or adjust β_KL")
        end
        if success_rate <= 0.7
            println("  - VAE may not capture action-dependent uncertainty well")
        end
        if ρ <= 0.4
            println("  - Surprise may not correlate with actual prediction error")
        end
    end
end

# Run validation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
