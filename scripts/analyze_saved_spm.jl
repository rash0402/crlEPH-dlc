#!/usr/bin/env julia
# Analyze saved SPM data for vertical banding

using DelimitedFiles
using Statistics

println("=" ^ 70)
println("🔍 Analyzing Real vs Predicted SPM Data")
println("=" ^ 70)

# Helper function to analyze pattern
function analyze_spm_file(filepath::String)
    data = readdlm(filepath, ',', Float64)
    
    # Compute column and row variances
    col_vars = [var(data[:, i]) for i in 1:16]
    row_vars = [var(data[i, :]) for i in 1:16]
    
    avg_col = mean(col_vars)
    avg_row = mean(row_vars)
    ratio = avg_col / max(avg_row, 1e-6)
    
    return (
        min=minimum(data),
        max=maximum(data),
        mean=mean(data),
        col_var=avg_col,
        row_var=avg_row,
        ratio=ratio
    )
end

# Analyze files for steps 100, 300, 500
steps = [100, 300, 500]
channels = [1, 2, 3]
ch_names = ["Occupancy", "Proximity Saliency", "Collision Risk"]

for step in steps
    println("\n" * "=" ^ 70)
    println("STEP $step")
    println("=" ^ 70)
    
    for (ch, ch_name) in zip(channels, ch_names)
        println("\n📊 Channel $ch: $ch_name")
        
        # Analyze real SPM
        real_file = "debug/real_spm_step_$(step)_ch$(ch).csv"
        if isfile(real_file)
            real_stats = analyze_spm_file(real_file)
            println("  REAL SPM:")
            println("    Range: [$(round(real_stats.min, digits=3)), $(round(real_stats.max, digits=3))]")
            println("    Mean: $(round(real_stats.mean, digits=3))")
            println("    Col/Row ratio: $(round(real_stats.ratio, digits=2)) $(real_stats.ratio > 2.0 ? "⚠️ VERTICAL BANDING" : real_stats.ratio < 0.5 ? "⚠️ HORIZONTAL" : "✅")")
        else
            println("  REAL SPM: File not found")
        end
        
        # Analyze predicted SPM
        pred_file = "debug/pred_spm_step_$(step)_ch$(ch).csv"
        if isfile(pred_file)
            pred_stats = analyze_spm_file(pred_file)
            println("  PREDICTED SPM:")
            println("    Range: [$(round(pred_stats.min, digits=3)), $(round(pred_stats.max, digits=3))]")
            println("    Mean: $(round(pred_stats.mean, digits=3))")
            println("    Col/Row ratio: $(round(pred_stats.ratio, digits=2)) $(pred_stats.ratio > 2.0 ? "⚠️ VERTICAL BANDING" : pred_stats.ratio < 0.5 ? "⚠️ HORIZONTAL" : "✅")")
        else
            println("  PREDICTED SPM: File not found")
        end
    end
end

println("\n" * "=" ^ 70)
println("📊 SUMMARY")
println("=" ^ 70)

# Aggregate analysis
println("\nAnalyzing all files for pattern...")

real_ratios = Float64[]
pred_ratios = Float64[]

for step in [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    for ch in 1:3
        real_file = "debug/real_spm_step_$(step)_ch$(ch).csv"
        pred_file = "debug/pred_spm_step_$(step)_ch$(ch).csv"
        
        if isfile(real_file)
            stats = analyze_spm_file(real_file)
            if !isnan(stats.ratio) && !isinf(stats.ratio)
                push!(real_ratios, stats.ratio)
            end
        end
        
        if isfile(pred_file)
            stats = analyze_spm_file(pred_file)
            if !isnan(stats.ratio) && !isinf(stats.ratio)
                push!(pred_ratios, stats.ratio)
            end
        end
    end
end

println("\nReal SPM Col/Row Ratios:")
println("  Min: $(round(minimum(real_ratios), digits=2))")
println("  Max: $(round(maximum(real_ratios), digits=2))")
println("  Mean: $(round(mean(real_ratios), digits=2))")
println("  Median: $(round(median(real_ratios), digits=2))")
println("  % with vertical banding (>2.0): $(round(100 * count(x -> x > 2.0, real_ratios) / length(real_ratios), digits=1))%")

println("\nPredicted SPM Col/Row Ratios:")
println("  Min: $(round(minimum(pred_ratios), digits=2))")
println("  Max: $(round(maximum(pred_ratios), digits=2))")
println("  Mean: $(round(mean(pred_ratios), digits=2))")
println("  Median: $(round(median(pred_ratios), digits=2))")
println("  % with vertical banding (>2.0): $(round(100 * count(x -> x > 2.0, pred_ratios) / length(pred_ratios), digits=1))%")

println("\n" * "=" ^ 70)
println("🔬 CONCLUSION")
println("=" ^ 70)

if mean(real_ratios) > 2.0
    println("⚠️  REAL SPM has systematic vertical banding!")
    println("   → Problem is in SPM GENERATION, not the model")
elseif mean(pred_ratios) > 2.0 && mean(real_ratios) < 1.5
    println("⚠️  PREDICTED SPM has vertical banding but REAL SPM doesn't!")
    println("   → Problem is in MODEL or DATA TRANSFER")
else
    println("💡 Both real and predicted SPMs appear balanced")
    println("   → Problem may be in VIEWER DISPLAY")
end

println("\n✅ Analysis complete!")
println("=" ^ 70)
