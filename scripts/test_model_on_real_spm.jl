#!/usr/bin/env julia
# Direct pixel-by-pixel comparison of what model produces vs what viewer shows

using BSON
using Flux

include("../src/autoencoder.jl")
using .AutoencoderModel

# Load model
BSON.@load "models/autoencoder_latest.bson" model
ae_model = model

# Load real SPM from step 500
using DelimitedFiles
using Statistics
using Plots
real_spm = readdlm("debug/real_spm_step_500_ch1.csv", ',', Float64)

println("🔬 Testing model on ACTUAL simulation SPM")
println("=" ^ 70)

# Convert to model input format
spm_3ch = zeros(Float64, 16, 16, 3)
spm_3ch[:, :, 1] = real_spm
spm_3ch[:, :, 2] = readdlm("debug/real_spm_step_500_ch2.csv", ',', Float64)
spm_3ch[:, :, 3] = readdlm("debug/real_spm_step_500_ch3.csv", ',', Float64)

# Run through model EXACTLY as in simulation
spm_input = Float32.(reshape(spm_3ch, 16, 16, 3, 1))
x_hat, haze = ae_model(spm_input)
spm_recon = Float64.(x_hat[:, :, :, 1])

# Compare with saved prediction
saved_pred = readdlm("debug/pred_spm_step_500_ch1.csv", ',', Float64)

println("\n📊 Channel 1 Comparison:")
println("  Real SPM mean: $(mean(real_spm))")
println("  Saved Pred mean: $(mean(saved_pred))")
println("  Fresh model output mean: $(mean(spm_recon[:, :, 1]))")

println("\n🔍 Checking if saved prediction matches fresh inference:")
diff = abs.(saved_pred - spm_recon[:, :, 1])
println("  Max difference: $(maximum(diff))")
println("  Mean difference: $(mean(diff))")

if maximum(diff) < 1e-6
    println("  ✅ MATCH - Saved prediction equals fresh model output")
else
    println("  ⚠️  MISMATCH - Saved prediction differs from fresh output!")
end

# Analyze column patterns in fresh output
col_means_fresh = [mean(spm_recon[:, i, 1]) for i in 1:16]
col_means_real = [mean(real_spm[:, i]) for i in 1:16]

println("\n📈 Column-wise analysis:")
println("  Real col variance: $(var(col_means_real))")
println("  Fresh pred col variance: $(var(col_means_fresh))")

# Check for systematic column banding
using Plots
p = plot(1:16, col_means_real, label="Real", marker=:o, linewidth=2)
plot!(p, 1:16, col_means_fresh, label="Fresh Pred", marker=:x, linewidth=2)
xlabel!(p, "Column Index")
ylabel!(p, "Mean Value")
title!(p, "Column Means Comparison")
savefig(p, "debug/column_means_comparison.png")
println("\n✅ Saved column comparison to: debug/column_means_comparison.png")

# Visualize fresh output
using Plots
p1 = heatmap(real_spm', title="Real", c=:hot, aspect_ratio=1, yflip=true)
p2 = heatmap(spm_recon[:,:,1]', title="Fresh Pred", c=:hot, aspect_ratio=1, yflip=true)
p3 = heatmap(abs.(real_spm - spm_recon[:,:,1])', title="Error", c=:viridis, aspect_ratio=1, yflip=true)
plot(p1, p2, p3, layout=(1,3), size=(1200, 400))
savefig("debug/fresh_model_output.png")
println("✅ Saved fresh model visualization to: debug/fresh_model_output.png")
