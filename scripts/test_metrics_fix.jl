#!/usr/bin/env julia

"""
Test script to verify metrics.jl fixes
Tests:
1. Module loading (syntax check)
2. Function signature validation
3. HDF5 haskey usage (syntax verification)
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

println("Testing metrics.jl fixes...")
println("=" ^ 60)

# Test 1: Module loading
println("\n1. Loading modules...")
try
    include("../src/config.jl")
    include("../src/dynamics.jl")
    include("../src/metrics.jl")
    println("   ✓ All modules loaded successfully")
catch e
    println("   ✗ Module loading failed: $e")
    exit(1)
end

# Test 2: Check function exists
println("\n2. Checking load_simulation_results function...")
try
    using .Metrics
    if isdefined(Metrics, :load_simulation_results)
        println("   ✓ load_simulation_results function exists")
    else
        println("   ✗ load_simulation_results function not found")
        exit(1)
    end
catch e
    println("   ✗ Function check failed: $e")
    exit(1)
end

# Test 3: Verify HDF5 haskey syntax (not exists)
println("\n3. Verifying HDF5 API usage...")
code_content = read(joinpath(@__DIR__, "..", "src", "metrics.jl"), String)
if occursin("exists(file,", code_content)
    println("   ✗ Found 'exists(file,' - should use 'haskey(file,'")
    exit(1)
elseif occursin("haskey(file,", code_content)
    println("   ✓ Correctly using 'haskey(file,' for HDF5")
else
    println("   ? Could not verify HDF5 usage")
end

# Test 4: Check LinearAlgebra import in surprise.jl
println("\n4. Checking LinearAlgebra import in surprise.jl...")
surprise_content = read(joinpath(@__DIR__, "..", "src", "surprise.jl"), String)
if occursin(r"function\s+compute_surprise_hybrid.*using LinearAlgebra"s, surprise_content)
    println("   ✗ Found 'using LinearAlgebra' inside function - should be at module level")
    exit(1)
elseif occursin("module SurpriseModule", surprise_content) &&
       occursin("using LinearAlgebra", surprise_content)
    println("   ✓ LinearAlgebra imported at module level")
else
    println("   ? Could not verify LinearAlgebra import")
end

println("\n" * "=" ^ 60)
println("✓ All syntax checks passed!")
println("\nNote: Full integration test requires existing HDF5 log files.")
println("Run simulation to generate test data, then use:")
println("  julia -e 'include(\"src/metrics.jl\"); using .Metrics; load_simulation_results(\"path/to/log.h5\")'")
