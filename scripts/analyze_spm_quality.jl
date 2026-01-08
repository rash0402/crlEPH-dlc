#!/usr/bin/env julia
# Deep analysis of SPM data characteristics

using HDF5
using Statistics
using Printf

println("🔍 Analyzing SPM Training Data Quality")
println("=" ^ 60)

# Find most recent data file
data_files = filter(f -> endswith(f, ".h5"), readdir("data", join=true))
if isempty(data_files)
    println("❌ No HDF5 data files found")
    exit(1)
end

latest_file = data_files[end]
println("📂 Analyzing: $latest_file")

h5open(latest_file, "r") do file
    # Read SPM data
    spms = read(file, "spm")  # Should be (16, 16, 3, n_agents, n_steps)
    
    println("\n📊 Data Shape: $(size(spms))")
    
    # Analyze each channel
    for ch in 1:3
        channel_names = ["Occupancy", "Proximity Saliency", "Collision Risk"]
        println("\n" * "=" * 60)
        println("Channel $ch: $(channel_names[ch])")
        println("=" * 60)
        
        ch_data = spms[:, :, ch, :, :]
        
        println("  Min: $(minimum(ch_data))")
        println("  Max: $(maximum(ch_data))")
        println("  Mean: $(mean(ch_data))")
        println("  Std: $(std(ch_data))")
        
        # Check for zero variance
        n_zeros = sum(ch_data .== 0.0)
        total = length(ch_data)
        @printf("  Zero pixels: %d / %d (%.1f%%)\n", n_zeros, total, 100.0 * n_zeros / total)
        
        # Check for saturation
        n_ones = sum(ch_data .== 1.0)
        @printf("  Saturated pixels: %d / %d (%.1f%%)\n", n_ones, total, 100.0 * n_ones / total)
        
        # Spatial analysis - check for repetitive patterns
        println("\n  Spatial Pattern Analysis:")
        
        # Take first few samples
        for sample_idx in [1, 100, 500]
            if sample_idx > size(spms, 5)
                break
            end
            
            sample = spms[:, :, ch, 1, sample_idx]
            
            # Check for vertical repetition
            left_half = sample[:, 1:8]
            right_half = sample[:, 9:16]
            vertical_similarity = mean(abs.(left_half - right_half))
            
            # Check for horizontal repetition
            top_half = sample[1:8, :]
            bottom_half = sample[9:16, :]
            horizontal_similarity = mean(abs.(top_half - bottom_half))
            
            @printf("    Sample %d: V-sim=%.3f, H-sim=%.3f\n", 
                    sample_idx, vertical_similarity, horizontal_similarity)
        end
    end
    
    # Overall diversity check
    println("\n" * "=" * 60)
    println("Overall Diversity Analysis")
    println("=" * 60)
    
    # Flatten all samples
    n_samples = size(spms, 4) * size(spms, 5)
    println("  Total samples: $n_samples")
    
    # Check unique patterns (using first 100 samples)
    n_check = min(100, n_samples)
    unique_count = 0
    seen_patterns = Set()
    
    for i in 1:n_check
        agent_idx = ((i-1) % size(spms, 4)) + 1
        step_idx = ((i-1) ÷ size(spms, 4)) + 1
        
        if step_idx > size(spms, 5)
            break
        end
        
        pattern = spms[:, :, :, agent_idx, step_idx]
        pattern_hash = hash(pattern)
        
        if !(pattern_hash in seen_patterns)
            unique_count += 1
            push!(seen_patterns, pattern_hash)
        end
    end
    
    @printf("  Unique patterns in first %d: %d (%.1f%%)\n", 
            n_check, unique_count, 100.0 * unique_count / n_check)
end

println("\n✅ Analysis complete")
