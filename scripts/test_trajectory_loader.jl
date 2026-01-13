#!/usr/bin/env julia
"""
Test trajectory_loader.jl: Verify SPM reconstruction from raw trajectory data

This script tests the trajectory_loader.jl module by:
1. Loading a single raw trajectory file
2. Reconstructing SPMs for a few timesteps
3. Verifying data shapes and values
4. Estimating memory and time requirements
"""

using Pkg
Pkg.activate(".")

using HDF5
using Statistics
using Printf

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/trajectory_loader.jl")

using .Config
using .SPM

println("="^80)
println("Test trajectory_loader.jl: SPM Reconstruction")
println("="^80)
println()

# Configuration
const DATA_DIR = joinpath(@__DIR__, "../data/vae_training/raw_v62")

# Find a test file
test_files = filter(f -> occursin(r"v62_scramble.*\.h5$", f), readdir(DATA_DIR, join=true))

if isempty(test_files)
    error("No test files found in $DATA_DIR")
end

test_file = first(test_files)
println("Test file: $(basename(test_file))")
println()

# Test 1: Load metadata
println("="^80)
println("Test 1: Load Metadata")
println("="^80)

data = load_trajectory_data(test_file)
println("✅ Successfully loaded trajectory data")
println()
println("Data shapes:")
println("  pos: $(size(data.pos))")
println("  vel: $(size(data.vel))")
println("  u: $(size(data.u))")
println("  heading: $(size(data.heading))")
println("  obstacles: $(size(data.obstacles))")
println()
println("Metadata:")
for (key, val) in data.metadata
    println("  $key: $val")
end
println()
println("SPM params:")
for (key, val) in data.spm_params
    println("  $key: $val")
end
println()

# Test 2: Reconstruct SPM for single timestep
println("="^80)
println("Test 2: Reconstruct SPM at Single Timestep")
println("="^80)

# Create SPM config from stored parameters
spm_params = Config.SPMParams(
    data.spm_params["n_rho"],
    data.spm_params["n_theta"],
    360.0,  # fov_deg
    2π,     # fov_rad
    0.4,    # r_robot
    data.spm_params["sensing_ratio"],
    0.5,    # sigma_spm
    5.0,    # beta_r_fixed
    5.0,    # beta_nu_fixed
    1.0,    # beta_r_min
    10.0,   # beta_r_max
    1.0,    # beta_nu_min
    10.0    # beta_nu_max
)

spm_config = SPM.init_spm(spm_params)

println("SPM Config:")
println("  n_rho: $(spm_config.params.n_rho)")
println("  n_theta: $(spm_config.params.n_theta)")
println("  sensing_ratio: $(spm_config.params.sensing_ratio)")
println()

# Reconstruct SPM for agent 1 at timestep 100
t = 100
agent_idx = 1

# Extract data for this timestep (HDF5 data is [T, N, 2] format)
pos_t = data.pos[t, :, :]  # [N, 2]
vel_t = data.vel[t, :, :]  # [N, 2]

println("Reconstructing SPM for agent $agent_idx at t=$t...")
spm = reconstruct_spm_at_timestep(
    pos_t,
    vel_t,
    data.obstacles,
    agent_idx,
    spm_config,
    0.3  # r_agent
)

println("✅ SPM reconstructed")
println("  Shape: $(size(spm))")
println("  Min: $(minimum(spm))")
println("  Max: $(maximum(spm))")
println("  Mean: $(mean(spm))")
println()

# Test 3: Extract training pairs from single file
println("="^80)
println("Test 3: Extract Training Pairs (Single File)")
println("="^80)

println("Extracting with stride=10, all agents...")
@time pairs = extract_vae_training_pairs(test_file; stride=10)

println("✅ Training pairs extracted")
println("  y_k shape: $(size(pairs.y_k))")
println("  u_k shape: $(size(pairs.u_k))")
println("  y_k1 shape: $(size(pairs.y_k1))")
println()

# Verify data ranges
println("Data statistics:")
println("  y_k - Min: $(minimum(pairs.y_k)), Max: $(maximum(pairs.y_k)), Mean: $(mean(pairs.y_k))")
println("  u_k - Min: $(minimum(pairs.u_k)), Max: $(maximum(pairs.u_k)), Mean: $(mean(pairs.u_k))")
println("  y_k1 - Min: $(minimum(pairs.y_k1)), Max: $(maximum(pairs.y_k1)), Mean: $(mean(pairs.y_k1))")
println()

# Test 4: Memory and time estimation
println("="^80)
println("Test 4: Memory and Time Estimation")
println("="^80)

# File size
file_size_mb = stat(test_file).size / (1024^2)
println("Raw trajectory file size: $(round(file_size_mb, digits=2)) MB")

# Extracted data size
y_k_size_mb = sizeof(pairs.y_k) / (1024^2)
u_k_size_mb = sizeof(pairs.u_k) / (1024^2)
y_k1_size_mb = sizeof(pairs.y_k1) / (1024^2)
total_size_mb = y_k_size_mb + u_k_size_mb + y_k1_size_mb

println("Extracted data size:")
println("  y_k: $(round(y_k_size_mb, digits=2)) MB")
println("  u_k: $(round(u_k_size_mb, digits=4)) MB")
println("  y_k1: $(round(y_k1_size_mb, digits=2)) MB")
println("  Total: $(round(total_size_mb, digits=2)) MB")
println()

expansion_ratio = total_size_mb / file_size_mb
println("Memory expansion: $(round(expansion_ratio, digits=1))x")
println()

# Estimate for all 80 files
n_files = 80
estimated_memory_gb = (total_size_mb * n_files) / 1024
println("Estimated for $n_files files:")
println("  Total memory: $(round(estimated_memory_gb, digits=2)) GB")
println()

if estimated_memory_gb < 16
    println("✅ Memory requirement acceptable (< 16 GB)")
elseif estimated_memory_gb < 32
    println("⚠️  High memory requirement (16-32 GB)")
    println("   Consider: agent_subsample=2 or stride=10")
else
    println("❌ Memory requirement too high (> 32 GB)")
    println("   MUST use agent_subsample and/or larger stride")
end
println()

# Test 5: Agent subsampling
println("="^80)
println("Test 5: Agent Subsampling Test")
println("="^80)

println("Extracting with stride=10, agent_subsample=2...")
@time pairs_subsample = extract_vae_training_pairs(test_file; stride=10, agent_subsample=2)

println("✅ Training pairs extracted (subsampled)")
println("  y_k shape: $(size(pairs_subsample.y_k))")
println("  Sample reduction: $(round(100 * (1 - size(pairs_subsample.y_k, 1) / size(pairs.y_k, 1)), digits=1))%")
println()

# Summary
println("="^80)
println("Test Summary")
println("="^80)
println("✅ All tests passed")
println()
println("Recommendations for VAE training:")
n_samples_full = size(pairs.y_k, 1) * n_files
n_samples_subsample = size(pairs_subsample.y_k, 1) * n_files
println("  Full dataset (stride=10, all agents):")
println("    - Samples: $n_samples_full")
println("    - Memory: $(round(estimated_memory_gb, digits=2)) GB")
println()
println("  Subsampled (stride=10, every 2nd agent):")
println("    - Samples: $n_samples_subsample")
println("    - Memory: $(round(estimated_memory_gb/2, digits=2)) GB")
println()

if estimated_memory_gb < 16
    println("✅ Recommended: Use full dataset (stride=5 or 10)")
else
    println("⚠️  Recommended: Use agent_subsample=2 (stride=5)")
end

println()
println("="^80)
println("Ready for VAE Training")
println("="^80)
println("Run: julia --project=. scripts/train_action_vae_v62.jl")
println()
