#!/usr/bin/env julia
# Test ConvTranspose output for artifacts

using Flux
using Statistics

println("🔍 Testing ConvTranspose for banding artifacts")
println("=" ^ 60)

# Test ConvTranspose configuration from autoencoder
println("\n1. Current Config: kernel=4x4, stride=2, pad=1")
layer1 = ConvTranspose((4, 4), 32 => 16, relu, stride=2, pad=1)

# Create test input: 4x4x32x1
x_test = randn(Float32, 4, 4, 32, 1)
y_test = layer1(x_test)

println("   Input: ", size(x_test))
println("   Output: ", size(y_test))

# Check for column-wise patterns
if size(y_test, 2) == 8
    col_vars = [var(y_test[:, i, :, 1]) for i in 1:8]
    row_vars = [var(y_test[i, :, :, 1]) for i in 1:8]
    ratio = mean(col_vars) / max(mean(row_vars), 1e-6)
    println("   Column/Row variance ratio: ", round(ratio, digits=3))
    if ratio > 1.5 || ratio < 0.67
        println("   ⚠️  ASYMMETRIC PATTERN DETECTED")
    else
        println("   ✅ Symmetric")
    end
end

# Test alternative configurations
println("\n2. Alternative: kernel=3x3, stride=2, pad=0 (standard)")
layer2 = ConvTranspose((3, 3), 32 => 16, relu, stride=2, pad=0)
y_test2 = layer2(x_test)
println("   Input: ", size(x_test))
println("   Output: ", size(y_test2))

println("\n3. Alternative: kernel=2x2, stride=2, pad=0 (no overlap)")
layer3 = ConvTranspose((2, 2), 32 => 16, relu, stride=2, pad=0)
y_test3 = layer3(x_test)
println("   Input: ", size(x_test))
println("   Output: ", size(y_test3))

# Output size formula for ConvTranspose:
# out = (in - 1) * stride - 2*pad + kernel
println("\n📐 Output size formula: out = (in-1)*stride - 2*pad + kernel")
println("   Config 1 (4,4,s=2,p=1): (4-1)*2 - 2*1 + 4 = 6+4-2 = 8 ✅")
println("   Config 2 (3,3,s=2,p=0): (4-1)*2 - 0 + 3 = 6+3 = 9 ❌ (wrong size)")
println("   Config 3 (2,2,s=2,p=0): (4-1)*2 - 0 + 2 = 6+2 = 8 ✅")

println("\n💡 Recommendation:")
println("   kernel=2, stride=2 → No overlap, no checkerboard")
println("   kernel=4, stride=2, pad=1 → Overlap, potential artifacts")

println("\n✅ Test complete")
