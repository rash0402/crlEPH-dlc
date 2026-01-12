#!/usr/bin/env julia
"""
Phase 1 Analysis: Statistical Analysis and Visualization

Analyzes results from test_phase1_v61.jl and generates:
  1. Statistical comparison (t-tests)
  2. Visualizations (box plots, bar charts)
  3. Decision recommendation report
"""

using Pkg
Pkg.activate(".")

using HDF5
using Statistics
using Printf
using Plots
using HypothesisTests

println("="^80)
println("Phase 1 Results Analysis")
println("="^80)
println()

# Find most recent results file
results_dir = joinpath(@__DIR__, "../results/phase1_v61")
if !isdir(results_dir)
    error("Results directory not found: $results_dir")
end

result_files = filter(f -> startswith(f, "phase1_results_") && endswith(f, ".h5"), readdir(results_dir))
if isempty(result_files)
    error("No results files found in: $results_dir")
end

# Use most recent file
result_file = joinpath(results_dir, sort(result_files)[end])
println("Analyzing: $result_file")
println()

# Load results
results = h5open(result_file, "r") do file
    v60 = Dict(
        "collision_rate_mean" => read(file["v60/collision_rate_mean"]),
        "collision_rate_std" => read(file["v60/collision_rate_std"]),
        "freezing_rate_mean" => read(file["v60/freezing_rate_mean"]),
        "freezing_rate_std" => read(file["v60/freezing_rate_std"]),
        "path_efficiency_mean" => read(file["v60/path_efficiency_mean"]),
        "path_efficiency_std" => read(file["v60/path_efficiency_std"]),
        "avg_gradient_mean" => read(file["v60/avg_gradient_mean"]),
        "avg_vae_error_mean" => read(file["v60/avg_vae_error_mean"])
    )

    v61 = Dict(
        "collision_rate_mean" => read(file["v61/collision_rate_mean"]),
        "collision_rate_std" => read(file["v61/collision_rate_std"]),
        "freezing_rate_mean" => read(file["v61/freezing_rate_mean"]),
        "freezing_rate_std" => read(file["v61/freezing_rate_std"]),
        "path_efficiency_mean" => read(file["v61/path_efficiency_mean"]),
        "path_efficiency_std" => read(file["v61/path_efficiency_std"]),
        "avg_gradient_mean" => read(file["v61/avg_gradient_mean"]),
        "avg_vae_error_mean" => read(file["v61/avg_vae_error_mean"])
    )

    Dict("v60" => v60, "v61" => v61)
end

# Print summary table
println("="^80)
println("Summary Statistics")
println("="^80)
println()

println("  Metric                 | v6.0 (Baseline)  | v6.1 (Bin 1-6 H=0) | Change")
println("  -----------------------|------------------|--------------------|---------")

v60 = results["v60"]
v61 = results["v61"]

metrics = [
    ("Collision Rate (%)", "collision_rate_mean", "collision_rate_std", true),
    ("Freezing Rate (%)", "freezing_rate_mean", "freezing_rate_std", true),
    ("Path Efficiency", "path_efficiency_mean", "path_efficiency_std", false),
    ("Avg Gradient", "avg_gradient_mean", nothing, false),
    ("VAE Error", "avg_vae_error_mean", nothing, false)
]

for (name, mean_key, std_key, is_percentage) in metrics
    v60_mean = v60[mean_key]
    v61_mean = v61[mean_key]

    if std_key !== nothing
        v60_std = v60[std_key]
        v61_std = v61[std_key]
        v60_str = @sprintf("%.2f ± %.2f", v60_mean, v60_std)
        v61_str = @sprintf("%.2f ± %.2f", v61_mean, v61_std)
    else
        v60_str = @sprintf("%.3f", v60_mean)
        v61_str = @sprintf("%.3f", v61_mean)
    end

    # Compute change
    if is_percentage
        change = v60_mean - v61_mean  # Positive = improvement for rates
    else
        change = v61_mean - v60_mean  # Positive = improvement for efficiency/gradient
    end

    change_pct = 100.0 * change / abs(v60_mean + 1e-10)
    change_str = @sprintf("%+.1f%%", change_pct)

    @printf("  %-22s | %-16s | %-18s | %s\n", name, v60_str, v61_str, change_str)
end

println()

# Statistical significance tests (placeholder - would need raw data)
println("="^80)
println("Statistical Significance")
println("="^80)
println()
println("NOTE: Detailed t-tests require raw trial data (not just means/stds)")
println("      Assuming n=10 runs, rough significance estimates:")
println()

# Rough effect size estimation
collision_effect = abs(v60["collision_rate_mean"] - v61["collision_rate_mean"]) /
                   sqrt((v60["collision_rate_std"]^2 + v61["collision_rate_std"]^2) / 2)
freezing_effect = abs(v60["freezing_rate_mean"] - v61["freezing_rate_mean"]) /
                  sqrt((v60["freezing_rate_std"]^2 + v61["freezing_rate_std"]^2) / 2)

@printf("  Collision Rate - Cohen's d: %.2f ", collision_effect)
if collision_effect > 0.8
    println("(Large effect)")
elseif collision_effect > 0.5
    println("(Medium effect)")
else
    println("(Small effect)")
end

@printf("  Freezing Rate - Cohen's d: %.2f ", freezing_effect)
if freezing_effect > 0.8
    println("(Large effect)")
elseif freezing_effect > 0.5
    println("(Medium effect)")
else
    println("(Small effect)")
end

println()

# Generate visualizations
gr()

# Figure 1: Collision and Freezing Rate Comparison
p1 = plot(
    title="Phase 1 Results: Collision & Freezing Rates",
    ylabel="Rate (%)",
    xlabel="Condition",
    size=(800, 500),
    legend=:topright,
    grid=true,
    framestyle=:box
)

x = [1, 2]
x_labels = ["v6.0\n(Baseline)", "v6.1\n(Bin 1-6 H=0)"]

# Collision rates
collision_means = [v60["collision_rate_mean"], v61["collision_rate_mean"]]
collision_stds = [v60["collision_rate_std"], v61["collision_rate_std"]]

bar!(p1, x .- 0.2, collision_means,
     yerror=collision_stds,
     bar_width=0.35,
     color=:red,
     alpha=0.7,
     label="Collision Rate")

# Freezing rates
freezing_means = [v60["freezing_rate_mean"], v61["freezing_rate_mean"]]
freezing_stds = [v60["freezing_rate_std"], v61["freezing_rate_std"]]

bar!(p1, x .+ 0.2, freezing_means,
     yerror=freezing_stds,
     bar_width=0.35,
     color=:orange,
     alpha=0.7,
     label="Freezing Rate")

xticks!(p1, x, x_labels)

output_dir = results_dir
savefig(p1, joinpath(output_dir, "phase1_rates_comparison.png"))
println("✅ Saved: $(joinpath(output_dir, "phase1_rates_comparison.png"))")

# Figure 2: Path Efficiency Comparison
p2 = plot(
    title="Phase 1 Results: Path Efficiency",
    ylabel="Efficiency (Optimal / Actual)",
    xlabel="Condition",
    size=(800, 500),
    legend=false,
    grid=true,
    framestyle=:box,
    ylims=(0, 1.2)
)

efficiency_means = [v60["path_efficiency_mean"], v61["path_efficiency_mean"]]
efficiency_stds = [v60["path_efficiency_std"], v61["path_efficiency_std"]]

bar!(p2, x, efficiency_means,
     yerror=efficiency_stds,
     bar_width=0.5,
     color=:green,
     alpha=0.7)

hline!(p2, [1.0], linestyle=:dash, color=:black, linewidth=2, label="Optimal")

xticks!(p2, x, x_labels)

savefig(p2, joinpath(output_dir, "phase1_efficiency_comparison.png"))
println("✅ Saved: $(joinpath(output_dir, "phase1_efficiency_comparison.png"))")

# Figure 3: Gradient Magnitude Comparison
p3 = plot(
    title="Phase 1 Results: Gradient Magnitude (∂Φ_safety/∂u)",
    ylabel="Average Gradient Magnitude",
    xlabel="Condition",
    size=(800, 500),
    legend=false,
    grid=true,
    framestyle=:box
)

gradient_means = [v60["avg_gradient_mean"], v61["avg_gradient_mean"]]

bar!(p3, x, gradient_means,
     bar_width=0.5,
     color=:blue,
     alpha=0.7)

xticks!(p3, x, x_labels)

savefig(p3, joinpath(output_dir, "phase1_gradient_comparison.png"))
println("✅ Saved: $(joinpath(output_dir, "phase1_gradient_comparison.png"))")

println()

# Decision recommendation
println("="^80)
println("Decision Recommendation")
println("="^80)
println()

collision_improvement = v60["collision_rate_mean"] - v61["collision_rate_mean"]
collision_improvement_pct = 100.0 * collision_improvement / v60["collision_rate_mean"]

vae_error_increase = v61["avg_vae_error_mean"] - v60["avg_vae_error_mean"]
vae_error_increase_pct = 100.0 * vae_error_increase / max(v60["avg_vae_error_mean"], 1e-10)

println("Collision Rate Improvement: $(round(collision_improvement_pct, digits=1))%")
println("VAE Error Increase: $(round(vae_error_increase_pct, digits=1))%")
println()

if collision_improvement_pct >= 10.0
    println("✅ PRIMARY CRITERION MET: Collision rate reduced by ≥10%")
    println()

    if abs(vae_error_increase_pct) > 100.0
        println("⚠️  SECONDARY CONCERN: VAE error increased significantly")
        println()
        println("📋 RECOMMENDATION: Proceed to Phase 2 (VAE Retraining)")
        println()
        println("   Rationale:")
        println("   - Bin 1-6 Haze=0 strategy shows collision avoidance improvement")
        println("   - VAE trained on D_max=7.5m struggles with D_max=8.0m")
        println("   - Retraining VAE on D_max=8.0m will optimize performance")
        println()
        println("   Estimated effort: ~13 hours (data collection + training + validation)")
    else
        println("✅ SECONDARY CRITERION MET: VAE error acceptable")
        println()
        println("📋 RECOMMENDATION: SKIP Phase 2, proceed with v6.1")
        println()
        println("   Rationale:")
        println("   - Collision avoidance improved with Bin 1-6 Haze=0")
        println("   - Existing VAE generalizes well to D_max=8.0m")
        println("   - No need for VAE retraining")
        println()
        println("   Next step: Proceed to main experiments with v6.1")
    end
elseif collision_improvement_pct >= 5.0
    println("⚠️  MARGINAL IMPROVEMENT: Collision rate reduced by 5-10%")
    println()
    println("📋 RECOMMENDATION: Further investigation required")
    println()
    println("   Options:")
    println("   - Increase N_RUNS for more statistical power")
    println("   - Analyze gradient quality in detail")
    println("   - Consider alternative rho_index_critical values (e.g., Bin 1-7)")
else
    println("❌ INSUFFICIENT IMPROVEMENT: Collision rate reduction < 5%")
    println()
    println("📋 RECOMMENDATION: Abort v6.1, investigate issues")
    println()
    println("   Possible causes:")
    println("   - Bin 1-6 boundary too narrow (try Bin 1-7)")
    println("   - D_max=8.0m mismatch causing problems")
    println("   - Implementation error in Bin-Based Fixed foveation")
    println()
    println("   Next step: Debug and re-evaluate strategy")
end

println()
println("="^80)
println("Analysis Complete")
println("="^80)
println()
println("Generated files:")
println("  - $(joinpath(output_dir, "phase1_rates_comparison.png"))")
println("  - $(joinpath(output_dir, "phase1_efficiency_comparison.png"))")
println("  - $(joinpath(output_dir, "phase1_gradient_comparison.png"))")
println()
println("Next steps:")
println("  1. Review visualizations and decision recommendation")
println("  2. Decide: Phase 2 (VAE retraining) or Skip Phase 2")
println("  3. Update doc/implementation_plan_v6.1.md with results")
println("="^80)
