#!/usr/bin/env julia
# Comprehensive Model Behavior Analysis

using BSON
using Flux
using Statistics
using Plots

include("../src/autoencoder.jl")
using .AutoencoderModel

println("=" ^ 70)
println("🔬 Comprehensive Model Input-Output Analysis")
println("=" ^ 70)

# Load model
BSON.@load "models/autoencoder_latest.bson" model
ae_model = model
println("\n✅ Model loaded")

# Helper function to analyze vertical/horizontal patterns
function analyze_pattern(data::Array, name::String)
    # Compute column and row variances
    col_vars = Float64[]
    row_vars = Float64[]
    
    for ch in 1:3
        ch_data = data[:, :, ch]
        push!(col_vars, mean([var(ch_data[:, i]) for i in 1:16]))
        push!(row_vars, mean([var(ch_data[i, :]) for i in 1:16]))
    end
    
    avg_col = mean(col_vars)
    avg_row = mean(row_vars)
    ratio = avg_col / max(avg_row, 1e-6)
    
    println("  $name:")
    println("    Col variance: $(round(avg_col, digits=4))")
    println("    Row variance: $(round(avg_row, digits=4))")
    println("    Col/Row ratio: $(round(ratio, digits=2)) $(ratio > 2.0 ? "⚠️ VERTICAL" : ratio < 0.5 ? "⚠️ HORIZONTAL" : "✅")")
    
    return ratio
end

println("\n" * "=" ^ 70)
println("TEST 1: Empty SPM (all zeros)")
println("=" ^ 70)

x1 = zeros(Float32, 16, 16, 3, 1)
y1, h1 = ae_model(x1)
y1_data = Float64.(y1[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x1[:, :, :, 1]), "Empty input")
println("\nOutput:")
ratio1 = analyze_pattern(y1_data, "Output")
println("  Output stats: min=$(round(minimum(y1_data), digits=3)), max=$(round(maximum(y1_data), digits=3)), mean=$(round(mean(y1_data), digits=3))")

println("\n" * "=" ^ 70)
println("TEST 2: Uniform SPM (all 0.5)")
println("=" ^ 70)

x2 = fill(0.5f0, 16, 16, 3, 1)
y2, h2 = ae_model(x2)
y2_data = Float64.(y2[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x2[:, :, :, 1]), "Uniform input")
println("\nOutput:")
ratio2 = analyze_pattern(y2_data, "Output")
println("  Output stats: min=$(round(minimum(y2_data), digits=3)), max=$(round(maximum(y2_data), digits=3)), mean=$(round(mean(y2_data), digits=3))")

println("\n" * "=" ^ 70)
println("TEST 3: Horizontal stripes (row-based pattern)")
println("=" ^ 70)

x3 = zeros(Float32, 16, 16, 3, 1)
for i in 1:16
    if i % 2 == 0
        x3[i, :, :, 1] .= 1.0f0
    end
end
y3, h3 = ae_model(x3)
y3_data = Float64.(y3[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x3[:, :, :, 1]), "Horizontal stripes")
println("\nOutput:")
ratio3 = analyze_pattern(y3_data, "Output")
println("  Output stats: min=$(round(minimum(y3_data), digits=3)), max=$(round(maximum(y3_data), digits=3)), mean=$(round(mean(y3_data), digits=3))")

println("\n" * "=" ^ 70)
println("TEST 4: Vertical stripes (column-based pattern)")
println("=" ^ 70)

x4 = zeros(Float32, 16, 16, 3, 1)
for j in 1:16
    if j % 2 == 0
        x4[:, j, :, 1] .= 1.0f0
    end
end
y4, h4 = ae_model(x4)
y4_data = Float64.(y4[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x4[:, :, :, 1]), "Vertical stripes")
println("\nOutput:")
ratio4 = analyze_pattern(y4_data, "Output")
println("  Output stats: min=$(round(minimum(y4_data), digits=3)), max=$(round(maximum(y4_data), digits=3)), mean=$(round(mean(y4_data), digits=3))")

println("\n" * "=" ^ 70)
println("TEST 5: Random noise")
println("=" ^ 70)

x5 = rand(Float32, 16, 16, 3, 1)
y5, h5 = ae_model(x5)
y5_data = Float64.(y5[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x5[:, :, :, 1]), "Random noise")
println("\nOutput:")
ratio5 = analyze_pattern(y5_data, "Output")
println("  Output stats: min=$(round(minimum(y5_data), digits=3)), max=$(round(maximum(y5_data), digits=3)), mean=$(round(mean(y5_data), digits=3))")

println("\n" * "=" ^ 70)
println("TEST 6: Center hotspot (localized feature)")
println("=" ^ 70)

x6 = zeros(Float32, 16, 16, 3, 1)
x6[7:10, 7:10, :, 1] .= 1.0f0
y6, h6 = ae_model(x6)
y6_data = Float64.(y6[:, :, :, 1])

println("\nInput:")
analyze_pattern(Float64.(x6[:, :, :, 1]), "Center hotspot")
println("\nOutput:")
ratio6 = analyze_pattern(y6_data, "Output")
println("  Output stats: min=$(round(minimum(y6_data), digits=3)), max=$(round(maximum(y6_data), digits=3)), mean=$(round(mean(y6_data), digits=3))")

println("\n" * "=" ^ 70)
println("📊 SUMMARY")
println("=" ^ 70)

println("\nCol/Row Ratios (Input → Output):")
println("  Empty:      N/A → $(round(ratio1, digits=2))")
println("  Uniform:    N/A → $(round(ratio2, digits=2))")
println("  H-stripes:  < 0.5 → $(round(ratio3, digits=2))")
println("  V-stripes:  > 2.0 → $(round(ratio4, digits=2))")
println("  Random:     ~1.0 → $(round(ratio5, digits=2))")
println("  Hotspot:    ~1.0 → $(round(ratio6, digits=2))")

println("\n🔍 Key Observations:")
if all([ratio1, ratio2, ratio3, ratio4, ratio5, ratio6] .> 1.5)
    println("  ⚠️  ALL outputs show vertical bias (col/row > 1.5)")
    println("  ⚠️  Model systematically produces vertical patterns")
    println("  ⚠️  Input pattern does NOT influence output structure")
    println("\n💡 Conclusion: Model learned a BIAS toward vertical patterns")
    println("   Likely cause: Training data has consistent vertical bias")
elseif abs(ratio3 - ratio4) < 0.5
    println("  ⚠️  Model ignores input orientation (H-stripes ≈ V-stripes)")
    println("  ⚠️  Outputs are similar regardless of input")
    println("\n💡 Conclusion: Model does not preserve spatial structure")
    println("   Likely cause: Insufficient training or model capacity")
else
    println("  ✅ Model responds differently to different inputs")
    println("  ✅ Some preservation of input structure")
    println("\n💡 Next step: Analyze real SPM data")
end

println("\n✅ Analysis complete!")
println("=" ^ 70)
