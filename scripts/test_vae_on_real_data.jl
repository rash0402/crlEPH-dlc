#!/usr/bin/env julia
# Visual inspection of actual VAE inference during simulation

using BSON
using Flux
using Statistics
using HDF5

include("../src/vae.jl")
using .VAEModel

println("🔍 Simulating Real Inference Path")
println("=" ^ 60)

# Load model
BSON.@load "models/vae_latest.bson" model
println("✅ Model loaded")

# Load actual SPM data from recent simulation
data_files = filter(f -> endswith(f, ".h5"), readdir("data", join=true))
latest_file = data_files[end]
println("📂 Loading SPM from: $latest_file")

h5open(latest_file, "r") do file
    spms = read(file, "spm")
    
    # Test on several real SPM samples
    println("\n📊 Testing on Real SPM Samples:")
    
    for sample_idx in [10, 50, 100, 500]
        if sample_idx > size(spms, 5)
            break
        end
        
        # Get SPM for agent 1 at this step
        spm = spms[:, :, :, 1, sample_idx]
        
        # EXACTLY replicate inference path from run_simulation.jl
        spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
        x_hat, μ, logσ = model(spm_input)
        spm_recon = Float64.(x_hat[:, :, :, 1])
        
        # Analyze reconstruction
        println("\n  Sample $sample_idx:")
        println("    Input: min=$(minimum(spm)), max=$(maximum(spm)), mean=$(mean(spm))")
        println("    Recon: min=$(minimum(spm_recon)), max=$(maximum(spm_recon)), mean=$(mean(spm_recon))")
        println("    MSE: $(mean((spm - spm_recon).^2))")
        
        # Check for vertical banding in reconstruction
        left = spm_recon[:, 1:8, :]
        right = spm_recon[:, 9:16, :]
        col_similarity = mean(abs.(left - right))
        println("    Vertical banding metric: $col_similarity")
        
        # Check channel-wise
        for ch in 1:3
            ch_input = spm[:, :, ch]
            ch_recon = spm_recon[:, :, ch]
            
            # Analyze column-wise variance
            col_vars = [var(ch_recon[:, i]) for i in 1:16]
            mean_col_var = mean(col_vars)
            
            # Analyze row-wise variance
            row_vars = [var(ch_recon[i, :]) for i in 1:16]
            mean_row_var = mean(row_vars)
            
            println("    Ch$ch: col_var=$(round(mean_col_var, digits=4)), row_var=$(round(mean_row_var, digits=4))")
            
            # If col_var >> row_var, we have vertical banding
            if mean_row_var > 0 && mean_col_var / mean_row_var > 2.0
                println("      ⚠️  VERTICAL BANDING DETECTED (col_var/row_var = $(round(mean_col_var/mean_row_var, digits=2)))")
            end
        end
    end
end

println("\n✅ Analysis complete")
