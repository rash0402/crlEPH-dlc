#!/usr/bin/env julia

"""
Phase 1: Create Unified VAE Training Dataset
Combines individual simulation logs into dataset_v56.h5 with Train/Val/Test splits
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Random
using HDF5
using Statistics

# Load data schema module
include("../src/data_schema.jl")
using .DataSchema

"""
Parse command line arguments
"""
function parse_commandline()
    if length(ARGS) > 0 && ARGS[1] == "--help"
        println("""
Usage: julia --project=. scripts/create_dataset_v56.jl

Creates unified dataset_v56.h5 from individual simulation logs in data/vae_training/raw/

Data splits:
  - Train: densities [5,10,15], seeds [1-3]   (70%)
  - Val:   densities [5,10,15], seed [4]      (15%)
  - Test:  densities [5,10,15], seed [5]      (10%)
  - OOD:   densities [20,25], seed [1]        (5%)

Output: data/vae_training/dataset_v56.h5
""")
        exit(0)
    end
end

"""
Extract (SPM[k], action[k], SPM[k+1]) samples from HDF5 log
"""
function extract_samples_from_log(filepath::String)
    samples = VAEDataSample[]

    h5open(filepath, "r") do file
        # Read data: (n_steps, n_agents, ...)
        spm_data = read(file, "/data/spm")       # (n_steps, n_agents, 16, 16, 3)
        action_data = read(file, "/data/actions") # (n_steps, n_agents, 2)

        n_steps, n_agents, _, _, _ = size(spm_data)

        # Extract sequential pairs for all agents
        for step in 1:(n_steps-1)
            for agent_id in 1:n_agents
                spm_current = Float32.(spm_data[step, agent_id, :, :, :])
                action = Float32.(action_data[step, agent_id, :])
                spm_next = Float32.(spm_data[step+1, agent_id, :, :, :])

                push!(samples, VAEDataSample(spm_current, action, spm_next))
            end
        end
    end

    return samples
end

"""
Main dataset creation
"""
function main()
    parse_commandline()

    println("=" ^ 70)
    println("Creating Unified VAE Training Dataset v5.6")
    println("=" ^ 70)

    # Define data split strategy
    train_densities = [5, 10, 15]
    train_seeds = [1, 2, 3]
    val_densities = [5, 10, 15]
    val_seeds = [4]
    test_iid_densities = [5, 10, 15]
    test_iid_seeds = [5]
    test_ood_densities = [20, 25]
    test_ood_seeds = [1]

    scenarios = ["scramble", "corridor"]

    # Collect samples for each split
    train_samples = VAEDataSample[]
    val_samples = VAEDataSample[]
    test_iid_samples = VAEDataSample[]
    test_ood_samples = VAEDataSample[]

    println("\n📂 Scanning simulation logs...\n")

    # Train split
    println("🔹 Train split (densities: $train_densities, seeds: $train_seeds)")
    for scenario in scenarios
        for density in train_densities
            for seed in train_seeds
                filepath = joinpath("data/vae_training/raw", scenario, "sim_d$(density)_s$(seed).h5")
                if isfile(filepath)
                    samples = extract_samples_from_log(filepath)
                    append!(train_samples, samples)
                    println("  ✅ $scenario/d$(density)_s$(seed): $(length(samples)) samples")
                else
                    println("  ⚠️  $scenario/d$(density)_s$(seed): Not found")
                end
            end
        end
    end

    # Val split
    println("\n🔹 Val split (densities: $val_densities, seeds: $val_seeds)")
    for scenario in scenarios
        for density in val_densities
            for seed in val_seeds
                filepath = joinpath("data/vae_training/raw", scenario, "sim_d$(density)_s$(seed).h5")
                if isfile(filepath)
                    samples = extract_samples_from_log(filepath)
                    append!(val_samples, samples)
                    println("  ✅ $scenario/d$(density)_s$(seed): $(length(samples)) samples")
                else
                    println("  ⚠️  $scenario/d$(density)_s$(seed): Not found")
                end
            end
        end
    end

    # Test IID split
    println("\n🔹 Test IID split (densities: $test_iid_densities, seeds: $test_iid_seeds)")
    for scenario in scenarios
        for density in test_iid_densities
            for seed in test_iid_seeds
                filepath = joinpath("data/vae_training/raw", scenario, "sim_d$(density)_s$(seed).h5")
                if isfile(filepath)
                    samples = extract_samples_from_log(filepath)
                    append!(test_iid_samples, samples)
                    println("  ✅ $scenario/d$(density)_s$(seed): $(length(samples)) samples")
                else
                    println("  ⚠️  $scenario/d$(density)_s$(seed): Not found")
                end
            end
        end
    end

    # Test OOD split
    println("\n🔹 Test OOD split (densities: $test_ood_densities, seeds: $test_ood_seeds)")
    for scenario in scenarios
        for density in test_ood_densities
            for seed in test_ood_seeds
                filepath = joinpath("data/vae_training/raw", scenario, "sim_d$(density)_s$(seed).h5")
                if isfile(filepath)
                    samples = extract_samples_from_log(filepath)
                    append!(test_ood_samples, samples)
                    println("  ✅ $scenario/d$(density)_s$(seed): $(length(samples)) samples")
                else
                    println("  ⚠️  $scenario/d$(density)_s$(seed): Not found")
                end
            end
        end
    end

    # Summary
    n_train = length(train_samples)
    n_val = length(val_samples)
    n_test_iid = length(test_iid_samples)
    n_test_ood = length(test_ood_samples)
    n_total = n_train + n_val + n_test_iid + n_test_ood

    println("\n" * "=" ^ 70)
    println("Dataset Summary:")
    println("=" ^ 70)
    println("  Train:    $(n_train) samples ($(round(n_train/n_total*100, digits=1))%)")
    println("  Val:      $(n_val) samples ($(round(n_val/n_total*100, digits=1))%)")
    println("  Test IID: $(n_test_iid) samples ($(round(n_test_iid/n_total*100, digits=1))%)")
    println("  Test OOD: $(n_test_ood) samples ($(round(n_test_ood/n_total*100, digits=1))%)")
    println("  Total:    $(n_total) samples")

    if n_total == 0
        println("\n❌ Error: No samples found!")
        println("   Please run data collection first:")
        println("   julia --project=. scripts/collect_vae_data_v56.jl")
        exit(1)
    end

    # Convert to arrays
    println("\n📦 Converting to arrays...")

    function samples_to_arrays(samples::Vector{VAEDataSample})
        n = length(samples)
        spms_current = zeros(Float32, n, 16, 16, 3)
        actions = zeros(Float32, n, 2)
        spms_next = zeros(Float32, n, 16, 16, 3)

        for (i, sample) in enumerate(samples)
            spms_current[i, :, :, :] = sample.spm_current
            actions[i, :] = sample.action
            spms_next[i, :, :, :] = sample.spm_next
        end

        return spms_current, actions, spms_next
    end

    train_spms_current, train_actions, train_spms_next = samples_to_arrays(train_samples)
    val_spms_current, val_actions, val_spms_next = samples_to_arrays(val_samples)
    test_iid_spms_current, test_iid_actions, test_iid_spms_next = samples_to_arrays(test_iid_samples)
    test_ood_spms_current, test_ood_actions, test_ood_spms_next = samples_to_arrays(test_ood_samples)

    # Create dataset
    dataset = VAEDataset(
        train_spms_current, train_actions, train_spms_next, Dict{String, Any}(),
        val_spms_current, val_actions, val_spms_next, Dict{String, Any}(),
        test_iid_spms_current, test_iid_actions, test_iid_spms_next, Dict{String, Any}(),
        test_ood_spms_current, test_ood_actions, test_ood_spms_next, Dict{String, Any}()
    )

    # Save to HDF5
    output_path = "data/vae_training/dataset_v56.h5"
    mkpath(dirname(output_path))

    println("\n💾 Saving to: $output_path")
    save_dataset(output_path, dataset)

    # File size
    filesize_mb = round(stat(output_path).size / 1024^2, digits=2)
    println("  File size: $(filesize_mb) MB")

    println("\n" * "=" ^ 70)
    println("✅ Dataset Creation Complete!")
    println("=" ^ 70)
    println("\nNext step: Train VAE model")
    println("  Run: julia --project=. scripts/train_vae_v56.jl")
end

# Run dataset creation
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
