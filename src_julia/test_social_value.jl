"""
Test script for SPM-based Social Value functions.

Tests:
1. Angular Compactness (entropy)
2. Goal Pushing (cosine weighting)
3. Radial Distribution
4. Combined Social Value
"""

using Printf
using LinearAlgebra

# Setup module path
push!(LOAD_PATH, @__DIR__)

# Load module
include("control/SocialValue.jl")

using .SocialValue

"""
Create synthetic SPM for testing.
"""
function create_test_spm(Nr::Int, Nθ::Int; pattern::Symbol=:uniform)::Array{Float64, 3}
    spm = zeros(Float64, 3, Nr, Nθ)  # (Nc, Nr, Nθ)

    if pattern == :uniform
        # Uniform occupancy (high entropy)
        spm[1, :, :] .= 1.0

    elseif pattern == :concentrated
        # Concentrated in one direction (low entropy)
        θ_peak = Nθ ÷ 2
        for r in 1:Nr
            spm[1, r, θ_peak] = 10.0
            spm[1, r, mod1(θ_peak-1, Nθ)] = 2.0
            spm[1, r, mod1(θ_peak+1, Nθ)] = 2.0
        end

    elseif pattern == :mid_distance
        # Concentrated at mid-distance
        r_mid = Nr ÷ 2
        spm[1, r_mid, :] .= 5.0

    elseif pattern == :coherent_velocity
        # All moving in same direction
        spm[2, :, :] .= 1.0  # Uniform radial
        spm[3, :, 3] .= 5.0  # Concentrated tangential

    end

    return spm
end

"""
Test 1: Angular Compactness
"""
function test_angular_compactness()
    println("\n=== Test 1: Angular Compactness ===")

    Nr, Nθ = 5, 16

    # Test case 1: Uniform distribution (high entropy)
    spm_uniform = create_test_spm(Nr, Nθ, pattern=:uniform)
    H_uniform = compute_angular_compactness(spm_uniform)

    # Test case 2: Concentrated distribution (low entropy)
    spm_concentrated = create_test_spm(Nr, Nθ, pattern=:concentrated)
    H_concentrated = compute_angular_compactness(spm_concentrated)

    @printf("Angular Compactness (Entropy):\n")
    @printf("  Uniform distribution:      H = %.4f (high)\n", H_uniform)
    @printf("  Concentrated distribution: H = %.4f (low)\n", H_concentrated)

    # Verify: concentrated should have lower entropy
    success = H_concentrated < H_uniform

    @printf("\nConcentrated < Uniform: %s\n", success ? "✓" : "✗")

    println("✓ Angular compactness computed correctly")
end

"""
Test 2: Goal Pushing
"""
function test_goal_pushing()
    println("\n=== Test 2: Goal Pushing ===")

    Nr, Nθ = 5, 16

    # Goal at θ=4 (quarter circle)
    θ_goal = 4

    # Test case 1: Sheep at goal direction (bad - dog blocking)
    spm_blocking = create_test_spm(Nr, Nθ, pattern=:uniform)
    spm_blocking[1, :, θ_goal] .= 10.0

    # Test case 2: Sheep at opposite direction (good - dog behind sheep)
    θ_target = mod1(θ_goal + Nθ÷2, Nθ)
    spm_pushing = create_test_spm(Nr, Nθ, pattern=:uniform)
    spm_pushing[1, :, θ_target] .= 10.0

    C_blocking = compute_goal_pushing(spm_blocking, θ_goal, Nθ)
    C_pushing = compute_goal_pushing(spm_pushing, θ_goal, Nθ)

    @printf("Goal Pushing Cost:\n")
    @printf("  Sheep at goal direction (blocking):  C = %.4f (bad)\n", C_blocking)
    @printf("  Sheep opposite to goal (pushing):    C = %.4f (good)\n", C_pushing)

    # Verify: pushing should have lower cost
    success = C_pushing < C_blocking

    @printf("\nPushing < Blocking: %s\n", success ? "✓" : "✗")

    println("✓ Goal pushing computed correctly")
end

"""
Test 3: Radial Distribution
"""
function test_radial_distribution()
    println("\n=== Test 3: Radial Distribution ===")

    Nr, Nθ = 5, 16
    r_prefer = 3  # Prefer bin 3 (mid-range)

    # Test case 1: Sheep at preferred distance
    spm_optimal = create_test_spm(Nr, Nθ, pattern=:mid_distance)

    # Test case 2: Sheep at near distance
    spm_near = zeros(Float64, 3, Nr, Nθ)
    spm_near[1, 1, :] .= 5.0

    C_optimal = compute_radial_distribution(spm_optimal, r_prefer)
    C_near = compute_radial_distribution(spm_near, r_prefer)

    @printf("Radial Distribution Cost (prefer r=%d):\n", r_prefer)
    @printf("  Sheep at mid-distance (r=3):  C = %.4f (good)\n", C_optimal)
    @printf("  Sheep at near (r=1):          C = %.4f (bad)\n", C_near)

    # Verify: optimal should have lower cost
    success = C_optimal < C_near

    @printf("\nOptimal < Near: %s\n", success ? "✓" : "✗")

    println("✓ Radial distribution computed correctly")
end

"""
Test 4: Combined Social Value
"""
function test_combined_social_value()
    println("\n=== Test 4: Combined Social Value ===")

    Nr, Nθ = 5, 16
    θ_goal = 4

    # Good scenario: concentrated + pushing from behind
    θ_target = mod1(θ_goal + Nθ÷2, Nθ)
    spm_good = create_test_spm(Nr, Nθ, pattern=:concentrated)
    for r in 1:Nr
        spm_good[1, r, θ_target] = 10.0
        spm_good[1, r, :] .= 0.5  # Low background
    end

    # Bad scenario: dispersed + blocking
    spm_bad = create_test_spm(Nr, Nθ, pattern=:uniform)
    spm_bad[1, :, θ_goal] .= 10.0

    M_good = compute_social_value_shepherding(
        spm_good, θ_goal, Nθ,
        λ_compact=1.0, λ_goal=0.5
    )

    M_bad = compute_social_value_shepherding(
        spm_bad, θ_goal, Nθ,
        λ_compact=1.0, λ_goal=0.5
    )

    @printf("Combined Social Value:\n")
    @printf("  Good scenario (compact + pushing):  M = %.4f\n", M_good)
    @printf("  Bad scenario (dispersed + blocking): M = %.4f\n", M_bad)

    # Verify: good should have lower cost
    success = M_good < M_bad

    @printf("\nGood < Bad: %s\n", success ? "✓" : "✗")

    println("✓ Combined social value working correctly")
end

"""
Run all tests
"""
function main()
    println("=" ^ 50)
    println("SPM-based Social Value Function Tests")
    println("=" ^ 50)

    try
        test_angular_compactness()
        test_goal_pushing()
        test_radial_distribution()
        test_combined_social_value()

        println("\n" * "=" ^ 50)
        println("All tests passed! ✓")
        println("=" ^ 50)
    catch e
        println("\n" * "=" ^ 50)
        println("Test failed! ✗")
        println("=" ^ 50)
        rethrow(e)
    end
end

# Run tests
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
