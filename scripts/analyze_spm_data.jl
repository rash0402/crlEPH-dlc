#!/usr/bin/env julia
# SPM Data Distribution Analysis
# Checks if SPM data is mostly empty (no agents in FOV)

using Pkg
Pkg.activate(".")

include("../src/data_loader.jl")
using .DataLoader
using Statistics
using Printf

println("📊 SPM Data Distribution Analysis")
println("=" ^ 60)

# Load data
println("\n📂 Loading SPM data...")
data = load_spm_data("data")

if data === nothing
    error("❌ No data found")
end

n_samples = size(data, 4)
println("✅ Loaded $n_samples samples")

# Analyze sparsity
println("\n" * "=" ^ 60)
println("🔍 SPARSITY ANALYSIS")
println("=" ^ 60)

empty_count = 0
sparse_count = 0  # < 10% non-zero
moderate_count = 0  # 10-50% non-zero
dense_count = 0  # > 50% non-zero

ch1_means = Float32[]
ch1_maxs = Float32[]
nonzero_ratios = Float32[]

for i in 1:n_samples
    spm = data[:, :, :, i]
    ch1 = spm[:, :, 1]
    
    # Count non-zero cells
    nonzero = sum(ch1 .> 0.001)
    total_cells = length(ch1)
    ratio = nonzero / total_cells
    
    push!(nonzero_ratios, ratio)
    push!(ch1_means, mean(ch1))
    push!(ch1_maxs, maximum(ch1))
    
    # Categorize
    if ratio == 0
        global empty_count += 1
    elseif ratio < 0.1
        global sparse_count += 1
    elseif ratio < 0.5
        global moderate_count += 1
    else
        global dense_count += 1
    end
end

@printf("\nSample Distribution:\n")
@printf("  Empty (0%% non-zero):        %5d (%5.1f%%)\n", empty_count, 100*empty_count/n_samples)
@printf("  Sparse (< 10%% non-zero):    %5d (%5.1f%%)\n", sparse_count, 100*sparse_count/n_samples)
@printf("  Moderate (10-50%% non-zero): %5d (%5.1f%%)\n", moderate_count, 100*moderate_count/n_samples)
@printf("  Dense (> 50%% non-zero):     %5d (%5.1f%%)\n", dense_count, 100*dense_count/n_samples)

println("\n" * "=" ^ 60)
println("📈 CHANNEL 1 (Occupancy) STATISTICS")
println("=" ^ 60)

@printf("\nNon-zero Ratio:\n")
@printf("  Mean: %.4f (%.1f%%)\n", mean(nonzero_ratios), 100*mean(nonzero_ratios))
@printf("  Std:  %.4f\n", std(nonzero_ratios))
@printf("  Min:  %.4f\n", minimum(nonzero_ratios))
@printf("  Max:  %.4f\n", maximum(nonzero_ratios))

@printf("\nChannel 1 Mean Values:\n")
@printf("  Mean: %.6f\n", mean(ch1_means))
@printf("  Std:  %.6f\n", std(ch1_means))

@printf("\nChannel 1 Max Values:\n")
@printf("  Mean: %.6f\n", mean(ch1_maxs))
@printf("  Std:  %.6f\n", std(ch1_maxs))

# Show examples
println("\n" * "=" ^ 60)
println("📸 SAMPLE EXAMPLES")
println("=" ^ 60)

# Find examples of each category
empty_idx = findfirst(nonzero_ratios .== 0)
sparse_idx = findfirst(0 .< nonzero_ratios .< 0.1)
moderate_idx = findfirst(0.1 .<= nonzero_ratios .< 0.5)
dense_idx = findfirst(nonzero_ratios .>= 0.5)

if empty_idx !== nothing
    println("\nEmpty SPM example (sample $empty_idx):")
    @printf("  Non-zero ratio: %.4f, Ch1 mean: %.6f, Ch1 max: %.6f\n", 
            nonzero_ratios[empty_idx], ch1_means[empty_idx], ch1_maxs[empty_idx])
end

if sparse_idx !== nothing
    println("\nSparse SPM example (sample $sparse_idx):")
    @printf("  Non-zero ratio: %.4f, Ch1 mean: %.6f, Ch1 max: %.6f\n", 
            nonzero_ratios[sparse_idx], ch1_means[sparse_idx], ch1_maxs[sparse_idx])
end

if moderate_idx !== nothing
    println("\nModerate SPM example (sample $moderate_idx):")
    @printf("  Non-zero ratio: %.4f, Ch1 mean: %.6f, Ch1 max: %.6f\n", 
            nonzero_ratios[moderate_idx], ch1_means[moderate_idx], ch1_maxs[moderate_idx])
end

if dense_idx !== nothing
    println("\nDense SPM example (sample $dense_idx):")
    @printf("  Non-zero ratio: %.4f, Ch1 mean: %.6f, Ch1 max: %.6f\n", 
            nonzero_ratios[dense_idx], ch1_means[dense_idx], ch1_maxs[dense_idx])
end

# Assessment
println("\n" * "=" ^ 60)
println("⚠️  ASSESSMENT")
println("=" ^ 60)

if empty_count + sparse_count > n_samples * 0.7
    println("\n❌ WARNING: Data is too sparse!")
    println("   > 70% of samples have few or no agents in FOV")
    println("   This makes VAE reconstruction artificially easy")
    println("\n💡 Recommendations:")
    println("   1. Increase agent density in simulation")
    println("   2. Reduce sensing range to capture more interactions")
    println("   3. Collect data during high-density scenarios")
elseif empty_count + sparse_count > n_samples * 0.5
    println("\n⚠️  CAUTION: Data is moderately sparse")
    println("   > 50% of samples have few or no agents in FOV")
    println("   VAE may be learning mostly empty patterns")
else
    println("\n✅ Data distribution looks reasonable")
    println("   Good mix of empty and populated SPMs")
end

println("\n🎉 Analysis complete!")
