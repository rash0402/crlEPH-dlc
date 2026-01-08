#!/usr/bin/env julia
# Visualize saved SPM data

using DelimitedFiles
using Plots
using Statistics

println("🎨 Visualizing Real vs Predicted SPM")

# Load step 500 data (where banding is strong)
step = 500
ch = 1  # Occupancy channel

real_data = readdlm("debug/real_spm_step_$(step)_ch$(ch).csv", ',', Float64)
pred_data = readdlm("debug/pred_spm_step_$(step)_ch$(ch).csv", ',', Float64)

println("Real SPM stats:")
println("  Min: $(minimum(real_data)), Max: $(maximum(real_data))")
println("  Mean: $(mean(real_data))")

println("Pred SPM stats:")
println("  Min: $(minimum(pred_data)), Max: $(maximum(pred_data))")
println("  Mean: $(mean(pred_data))")

# Create side-by-side heatmaps
p1 = heatmap(real_data', 
    title="Real SPM (Step $step, Ch$ch)", 
    c=:hot, 
    aspect_ratio=1,
    yflip=true)

p2 = heatmap(pred_data', 
    title="Predicted SPM (Step $step, Ch$ch)", 
    c=:hot, 
    aspect_ratio=1,
    yflip=true)

# Error map
error_map = abs.(real_data - pred_data)
p3 = heatmap(error_map', 
    title="Absolute Error", 
    c=:viridis, 
    aspect_ratio=1,
    yflip=true)

plot(p1, p2, p3, layout=(1,3), size=(1200, 400))
savefig("debug/spm_comparison_step$(step).png")

println("\n✅ Saved visualization to: debug/spm_comparison_step$(step).png")

# Also check if there's a systematic pattern in the error
println("\nError analysis:")
println("  Mean absolute error: $(mean(error_map))")
println("  Max error: $(maximum(error_map))")

# Check column-wise patterns in predicted
col_means_pred = [mean(pred_data[:, i]) for i in 1:16]
println("\nPredicted column means:")
println("  Min: $(minimum(col_means_pred)), Max: $(maximum(col_means_pred))")
println("  Variance: $(var(col_means_pred))")

col_means_real = [mean(real_data[:, i]) for i in 1:16]
println("\nReal column means:")
println("  Min: $(minimum(col_means_real)), Max: $(maximum(col_means_real))")
println("  Variance: $(var(col_means_real))")

if var(col_means_pred) > var(col_means_real) * 1.5
    println("\n⚠️  Predicted has MUCH higher column variance than Real!")
    println("   → This confirms vertical banding in prediction")
end
