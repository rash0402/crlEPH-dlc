#!/usr/bin/env julia
"""
Test Sigmoid Blending Implementation (v6.2)

Verifies that the sigmoid blending function produces smooth transitions
and matches theoretical expectations.
"""

using Printf

println("="^80)
println("Test Sigmoid Blending (v6.2)")
println("="^80)

# Test sigmoid function directly
function test_sigmoid(rho_index_critical=6, h_critical=0.0, h_peripheral=0.5, tau=1.0)
    println("\nParameters:")
    println("  ρ_crit: $(rho_index_critical + 0.5)")
    println("  h_critical: $h_critical")
    println("  h_peripheral: $h_peripheral")
    println("  τ: $tau")
    println()

    println("Bin | ρ_crit_offset | Sigmoid(σ) | Haze(ρ)  | Precision(Π)")
    println("----|---------------|------------|----------|-------------")

    for i in 1:16
        rho_crit = rho_index_critical + 0.5
        sigmoid_val = 1.0 / (1.0 + exp(-(i - rho_crit) / tau))
        haze_i = h_critical + (h_peripheral - h_critical) * sigmoid_val
        precision_i = 1.0 / (haze_i + 1e-6)

        offset = i - rho_crit
        @printf("%3d | %+7.2f      | %8.4f   | %8.4f | %11.2f\n",
                i, offset, sigmoid_val, haze_i, precision_i)
    end
end

# Test with default parameters
println("\n📊 Test 1: Default parameters (τ=1.0)")
test_sigmoid(6, 0.0, 0.5, 1.0)

# Test with steeper transition
println("\n📊 Test 2: Steeper transition (τ=0.5)")
test_sigmoid(6, 0.0, 0.5, 0.5)

# Test with gentler transition
println("\n📊 Test 3: Gentler transition (τ=2.0)")
test_sigmoid(6, 0.0, 0.5, 2.0)

# Verify smoothness (check derivatives)
println("\n🔍 Smoothness Check:")
println("Verifying that dHaze/dρ is continuous...")

function compute_numerical_derivative(f, x, h=0.01)
    return (f(x + h) - f(x - h)) / (2 * h)
end

function haze_func(rho, rho_crit=6.5, h_critical=0.0, h_peripheral=0.5, tau=1.0)
    sigmoid_val = 1.0 / (1.0 + exp(-(rho - rho_crit) / tau))
    return h_critical + (h_peripheral - h_critical) * sigmoid_val
end

# Check derivative around critical boundary
rho_test_points = [5.0, 6.0, 6.5, 7.0, 8.0]
println("\nρ     | Haze(ρ)  | dHaze/dρ")
println("------|----------|----------")
for rho in rho_test_points
    haze = haze_func(rho)
    dhaze = compute_numerical_derivative(x -> haze_func(x), rho)
    @printf("%.1f  | %.4f   | %.4f\n", rho, haze, dhaze)
end

# Comparison: Step function vs Sigmoid
println("\n📈 Comparison: Step Function vs Sigmoid (at boundary)")
println("\nBin | Step Haze | Sigmoid Haze | Difference")
println("----|-----------|--------------|------------")
for i in 4:9
    step_haze = (i <= 6) ? 0.0 : 0.5
    sigmoid_haze = haze_func(Float64(i))
    diff = abs(sigmoid_haze - step_haze)
    @printf("%3d | %9.4f | %12.4f | %10.4f\n", i, step_haze, sigmoid_haze, diff)
end

println("\n✅ Sigmoid blending test completed")
println("="^80)
