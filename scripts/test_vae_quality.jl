#!/usr/bin/env julia

# Quick Test: Check VAE reconstruction quality

using BSON
using Flux
using Random
using Statistics

include("../src/vae.jl")
using .VAEModel

println("🔍 Testing VAE Model Quality")
println("=" ^ 50)

# Load model
model_path = "models/vae_latest.bson"
if !isfile(model_path)
    println("❌ Model not found at $model_path")
    exit(1)
end

BSON.@load model_path model
println("✅ Model loaded")

# Create test patterns
println("\n📊 Testing reconstruction on known patterns:")

# Test 1: All zeros
x_zeros = zeros(Float32, 16, 16, 3, 1)
x_hat_zeros, _, _ = model(x_zeros)
println("\n1. All Zeros Input:")
println("   Output min=$(minimum(x_hat_zeros)), max=$(maximum(x_hat_zeros)), mean=$(mean(x_hat_zeros))")

# Test 2: All ones
x_ones = ones(Float32, 16, 16, 3, 1)
x_hat_ones, _, _ = model(x_ones)
println("\n2. All Ones Input:")
println("   Output min=$(minimum(x_hat_ones)), max=$(maximum(x_hat_ones)), mean=$(mean(x_hat_ones))")

# Test 3: Random noise
x_random = rand(Float32, 16, 16, 3, 1)
x_hat_random, _, _ = model(x_random)
println("\n3. Random Noise Input:")
println("   Input min=$(minimum(x_random)), max=$(maximum(x_random)), mean=$(mean(x_random))")
println("   Output min=$(minimum(x_hat_random)), max=$(maximum(x_hat_random)), mean=$(mean(x_hat_random))")
println("   MSE= $(Flux.mse(x_hat_random, x_random))")

# Test 4: Checkerboard pattern
x_check = zeros(Float32, 16, 16, 3, 1)
for i in 1:16, j in 1:16
    if (i + j) % 2 == 0
        x_check[i, j, :, 1] .= 1.0f0
    end
end
x_hat_check, _, _ = model(x_check)
println("\n4. Checkerboard Pattern Input:")
println("   Input mean=$(mean(x_check))")
println("   Output mean=$(mean(x_hat_check))")
println("   MSE= $(Flux.mse(x_hat_check, x_check))")

# Test 5: Single hot spot
x_hot = zeros(Float32, 16, 16, 3, 1)
x_hot[8, 8, :, 1] .= 1.0f0  # Center pixel
x_hat_hot, _, _ = model(x_hot)
println("\n5. Single Hot Spot (center):")
println("   Output has $(sum(x_hat_hot .> 0.5)) pixels > 0.5")
println("   Output mean=$(mean(x_hat_hot))")

println("\n=" ^ 50)
println("🔍 Analysis:")

# Check for tiling artifacts
println("\n🔍 Checking for tiling artifacts...")
x_test = rand(Float32, 16, 16, 3, 1)
x_hat_test, _, _ = model(x_test)

# Compare top-left and top-right quadrants
tl = x_hat_test[1:8, 1:8, :, 1]
tr = x_hat_test[1:8, 9:16, :, 1]
bl = x_hat_test[9:16, 1:8, :, 1]
br = x_hat_test[9:16, 9:16, :, 1]

println("Quadrant similarities (MSE, lower = more similar/repetitive):")
println("  TL vs TR: $(Flux.mse(tl, tr))")
println("  TR vs BR: $(Flux.mse(tr, br))")
println("  BR vs BL: $(Flux.mse(br, bl))")
println("  BL vs TL: $(Flux.mse(bl, tl))")

if Flux.mse(tl, tr) < 0.01 && Flux.mse(tr, br) < 0.01
    println("⚠️  WARNING: Quadrants are very similar - possible tiling artifact!")
else
    println("✅ Quadrants are diverse - no obvious tiling")
end

println("\n✅ Test complete")
