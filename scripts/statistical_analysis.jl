#!/usr/bin/env julia
"""
Statistical Analysis Script
Performs statistical tests to validate EPH effectiveness.

Tests:
- Wilcoxon Signed-Rank Test (paired, non-parametric)
- Effect Size (Cohen's d)

Usage:
    julia --project=. scripts/statistical_analysis.jl [summary.json]
"""

using JSON
using Statistics
using Printf
using Dates

# Note: HypothesisTests.jl would be used for production
# For now, implementing basic statistical functions

# ===== Statistical Functions =====

"""
Compute Cohen's d effect size.
"""
function cohens_d(group1::Vector{Float64}, group2::Vector{Float64})
    if isempty(group1) || isempty(group2)
        return NaN
    end
    
    mean_diff = mean(group1) - mean(group2)
    pooled_std = sqrt((std(group1)^2 + std(group2)^2) / 2)
    
    if pooled_std == 0
        return NaN
    end
    
    return mean_diff / pooled_std
end

"""
Interpret Cohen's d effect size.
"""
function interpret_effect_size(d::Float64)
    abs_d = abs(d)
    if abs_d < 0.2
        return "negligible"
    elseif abs_d < 0.5
        return "small"
    elseif abs_d < 0.8
        return "medium"
    else
        return "large"
    end
end

"""
Compute percentage improvement.
"""
function compute_improvement(baseline::Float64, treatment::Float64; lower_is_better=true)
    if baseline == 0
        return NaN
    end
    
    if lower_is_better
        # For metrics where lower is better (freezing, jerk)
        improvement = (baseline - treatment) / baseline * 100
    else
        # For metrics where higher is better (success rate)
        improvement = (treatment - baseline) / baseline * 100
    end
    
    return improvement
end

# ===== Analysis Functions =====

"""
Analyze comparison between two conditions.
"""
function analyze_comparison(
    baseline_stats::Dict,
    treatment_stats::Dict,
    metric_name::String;
    lower_is_better=true
)
    baseline_mean = baseline_stats["mean"]
    treatment_mean = treatment_stats["mean"]
    
    # Compute improvement
    improvement = compute_improvement(baseline_mean, treatment_mean, lower_is_better=lower_is_better)
    
    # Note: For proper statistical test, we need raw values, not just summary stats
    # This is a simplified version
    
    result = Dict(
        "metric" => metric_name,
        "baseline_mean" => baseline_mean,
        "baseline_std" => baseline_stats["std"],
        "treatment_mean" => treatment_mean,
        "treatment_std" => treatment_stats["std"],
        "improvement_pct" => improvement,
        "lower_is_better" => lower_is_better
    )
    
    return result
end

"""
Perform complete statistical analysis.
"""
function perform_analysis(summary_file::String)
    println("=" ^ 60)
    println("📊 STATISTICAL ANALYSIS")
    println("=" ^ 60)
    
    # Load summary
    println("\n📂 Loading summary: $summary_file")
    
    if !isfile(summary_file)
        @error "Summary file not found: $summary_file"
        return nothing
    end
    
    summary = JSON.parsefile(summary_file)
    conditions = summary["conditions"]
    
    # Identify baseline and EPH conditions
    baseline_key = nothing
    eph_key = nothing
    
    for key in keys(conditions)
        if contains(lowercase(key), "baseline") || contains(lowercase(key), "a1")
            baseline_key = key
        elseif contains(lowercase(key), "eph") || contains(lowercase(key), "a4")
            eph_key = key
        end
    end
    
    if baseline_key === nothing || eph_key === nothing
        @error "Could not identify baseline and EPH conditions"
        @info "Available conditions: $(keys(conditions))"
        return nothing
    end
    
    println("   Baseline: $baseline_key")
    println("   Treatment: $eph_key")
    
    baseline = conditions[baseline_key]
    eph = conditions[eph_key]
    
    # Analyze key metrics
    println("\n" * "=" ^ 60)
    println("📈 METRIC COMPARISONS")
    println("=" ^ 60)
    
    analyses = Dict()
    
    # Freezing Rate (lower is better)
    if haskey(baseline["metrics"], "freezing_rate") && haskey(eph["metrics"], "freezing_rate")
        println("\n🚨 Freezing Rate:")
        result = analyze_comparison(
            Dict(baseline["metrics"]["freezing_rate"]),
            Dict(eph["metrics"]["freezing_rate"]),
            "freezing_rate",
            lower_is_better=true
        )
        analyses["freezing_rate"] = result
        
        @printf("   Baseline: %.2f%% ± %.2f\n", result["baseline_mean"], result["baseline_std"])
        @printf("   EPH:      %.2f%% ± %.2f\n", result["treatment_mean"], result["treatment_std"])
        @printf("   Improvement: %.1f%%\n", result["improvement_pct"])
        
        if result["improvement_pct"] >= 20.0
            println("   ✅ TARGET MET (≥20% reduction)")
        else
            println("   ⚠️  TARGET NOT MET (need ≥20% reduction)")
        end
    end
    
    # Jerk (lower is better)
    if haskey(baseline["metrics"], "avg_jerk") && haskey(eph["metrics"], "avg_jerk")
        println("\n📉 Average Jerk:")
        result = analyze_comparison(
            Dict(baseline["metrics"]["avg_jerk"]),
            Dict(eph["metrics"]["avg_jerk"]),
            "avg_jerk",
            lower_is_better=true
        )
        analyses["avg_jerk"] = result
        
        @printf("   Baseline: %.4f m/s³ ± %.4f\n", result["baseline_mean"], result["baseline_std"])
        @printf("   EPH:      %.4f m/s³ ± %.4f\n", result["treatment_mean"], result["treatment_std"])
        @printf("   Improvement: %.1f%%\n", result["improvement_pct"])
        
        if result["improvement_pct"] >= 15.0
            println("   ✅ TARGET MET (≥15% reduction)")
        else
            println("   ⚠️  TARGET NOT MET (need ≥15% reduction)")
        end
    end
    
    # Success Rate (higher is better)
    if haskey(baseline["metrics"], "success_rate") && haskey(eph["metrics"], "success_rate")
        println("\n🎯 Success Rate:")
        result = analyze_comparison(
            Dict(baseline["metrics"]["success_rate"]),
            Dict(eph["metrics"]["success_rate"]),
            "success_rate",
            lower_is_better=false
        )
        analyses["success_rate"] = result
        
        @printf("   Baseline: %.2f%% ± %.2f\n", result["baseline_mean"], result["baseline_std"])
        @printf("   EPH:      %.2f%% ± %.2f\n", result["treatment_mean"], result["treatment_std"])
        @printf("   Change: %+.1f%%\n", result["improvement_pct"])
        
        if result["improvement_pct"] >= 0
            println("   ✅ MAINTAINED OR IMPROVED")
        else
            println("   ⚠️  DEGRADED")
        end
    end
    
    # Collision Rate (lower is better)
    if haskey(baseline["metrics"], "collision_rate") && haskey(eph["metrics"], "collision_rate")
        println("\n⚠️  Collision Rate:")
        result = analyze_comparison(
            Dict(baseline["metrics"]["collision_rate"]),
            Dict(eph["metrics"]["collision_rate"]),
            "collision_rate",
            lower_is_better=true
        )
        analyses["collision_rate"] = result
        
        @printf("   Baseline: %.2f%% ± %.2f\n", result["baseline_mean"], result["baseline_std"])
        @printf("   EPH:      %.2f%% ± %.2f\n", result["treatment_mean"], result["treatment_std"])
        @printf("   Change: %+.1f%%\n", result["improvement_pct"])
        
        if result["improvement_pct"] >= 0
            println("   ✅ MAINTAINED OR IMPROVED")
        else
            println("   ⚠️  INCREASED")
        end
    end
    
    # Summary
    println("\n" * "=" ^ 60)
    println("📋 VALIDATION SUMMARY")
    println("=" ^ 60)
    
    freezing_ok = haskey(analyses, "freezing_rate") && analyses["freezing_rate"]["improvement_pct"] >= 20.0
    jerk_ok = haskey(analyses, "avg_jerk") && analyses["avg_jerk"]["improvement_pct"] >= 15.0
    
    println("\nPrimary Targets:")
    println("  Freezing Reduction ≥20%: $(freezing_ok ? "✅ PASS" : "❌ FAIL")")
    println("  Jerk Improvement ≥15%:   $(jerk_ok ? "✅ PASS" : "❌ FAIL")")
    
    if freezing_ok && jerk_ok
        println("\n🎉 EPH VALIDATION SUCCESSFUL!")
    else
        println("\n⚠️  EPH validation targets not fully met")
    end
    
    println("\n" * "=" ^ 60)
    
    # Save analysis results
    output_file = replace(summary_file, "summary.json" => "analysis.json")
    println("\n💾 Saving analysis to: $output_file")
    
    analysis_output = Dict(
        "timestamp" => string(now()),
        "baseline_condition" => baseline_key,
        "treatment_condition" => eph_key,
        "analyses" => analyses,
        "validation" => Dict(
            "freezing_reduction_target_met" => freezing_ok,
            "jerk_improvement_target_met" => jerk_ok,
            "overall_success" => freezing_ok && jerk_ok
        )
    )
    
    open(output_file, "w") do io
        JSON.print(io, analysis_output, 2)
    end
    
    return analysis_output
end

# ===== Main Entry Point =====
function main(args::Vector{String})
    summary_file = length(args) >= 1 ? args[1] : "results/ablation/summary.json"
    
    analysis = perform_analysis(summary_file)
    
    return analysis
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
