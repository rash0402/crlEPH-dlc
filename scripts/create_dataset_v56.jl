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
function extract_samples_from_log(filepath::String;
                                      step_interval::Int=5,
                                      max_agents_per_step::Int=3,
                                      max_samples_per_file::Int=5000)
    """
    Extract samples with smart sampling to reduce memory usage while preserving diversity.

    Args:
        step_interval: Sample every N steps (default: 5) to avoid temporal redundancy
        max_agents_per_step: Max agents to sample per step (default: 3) for diversity
        max_samples_per_file: Hard limit on samples per file (default: 5000)
    """
    samples = VAEDataSample[]

    h5open(filepath, "r") do file
        # Read data: (n_steps, n_agents, ...)
        spm_data = read(file, "/data/spm")       # (n_steps, n_agents, 16, 16, 3)
        action_data = read(file, "/data/actions") # (n_steps, n_agents, 2)

        n_steps, n_agents, _, _, _ = size(spm_data)

        # Sampling strategy for diversity
        sample_count = 0

        # Sample every `step_interval` steps to avoid temporal redundancy
        for step in 1:step_interval:(n_steps-1)
            if sample_count >= max_samples_per_file
                break
            end

            # Randomly select subset of agents for diversity
            n_sample_agents = min(max_agents_per_step, n_agents)
            sampled_agents = sort(rand(1:n_agents, n_sample_agents))

            for agent_id in sampled_agents
                spm_current = Float32.(spm_data[step, agent_id, :, :, :])
                action = Float32.(action_data[step, agent_id, :])
                spm_next = Float32.(spm_data[step+1, agent_id, :, :, :])

                push!(samples, VAEDataSample(spm_current, action, spm_next))
                sample_count += 1

                if sample_count >= max_samples_per_file
                    break
                end
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

    # Define data split strategy (ALL available data)
    # Scramble: d5,d10,d15,d20 × s1-5 (exploratory data)
    # Corridor: d5,d10,d15,d20 × s1-5 (exploratory data)
    scramble_densities = [5, 10, 15, 20]
    corridor_densities = [5, 10, 15, 20]

    train_seeds = [1, 2, 3]
    val_seeds = [4]
    test_seeds = [5]

    scenarios = ["scramble", "corridor"]

    # Collect samples for each split
    train_samples = VAEDataSample[]
    val_samples = VAEDataSample[]
    test_samples = VAEDataSample[]

    println("\n📂 Scanning simulation logs...\n")

    # Helper function to load samples for a scenario
    function load_scenario_samples(scenario::String, densities::Vector{Int}, seeds::Vector{Int})
        samples = VAEDataSample[]
        for density in densities
            for seed in seeds
                filepath = joinpath("data/vae_training/exploratory", scenario, "sim_d$(density)_s$(seed).h5")
                if isfile(filepath)
                    file_samples = extract_samples_from_log(filepath)
                    append!(samples, file_samples)
                    println("  ✅ $scenario/d$(density)_s$(seed): $(length(file_samples)) samples")
                else
                    println("  ⚠️  $scenario/d$(density)_s$(seed): Not found (skipped)")
                end
            end
        end
        return samples
    end

    # Train split
    println("🔹 Train split (seeds: $train_seeds)")
    println("  Scramble densities: $scramble_densities")
    append!(train_samples, load_scenario_samples("scramble", scramble_densities, train_seeds))
    println("  Corridor densities: $corridor_densities")
    append!(train_samples, load_scenario_samples("corridor", corridor_densities, train_seeds))

    # Val split
    println("\n🔹 Val split (seeds: $val_seeds)")
    println("  Scramble densities: $scramble_densities")
    append!(val_samples, load_scenario_samples("scramble", scramble_densities, val_seeds))
    println("  Corridor densities: $corridor_densities")
    append!(val_samples, load_scenario_samples("corridor", corridor_densities, val_seeds))

    # Test split
    println("\n🔹 Test split (seeds: $test_seeds)")
    println("  Scramble densities: $scramble_densities")
    append!(test_samples, load_scenario_samples("scramble", scramble_densities, test_seeds))
    println("  Corridor densities: $corridor_densities")
    append!(test_samples, load_scenario_samples("corridor", corridor_densities, test_seeds))

    # Summary
    n_train = length(train_samples)
    n_val = length(val_samples)
    n_test = length(test_samples)
    n_total = n_train + n_val + n_test

    println("\n" * "=" ^ 70)
    println("Dataset Summary:")
    println("=" ^ 70)
    println("  Train:  $(n_train) samples ($(round(n_train/n_total*100, digits=1))%)")
    println("  Val:    $(n_val) samples ($(round(n_val/n_total*100, digits=1))%)")
    println("  Test:   $(n_test) samples ($(round(n_test/n_total*100, digits=1))%)")
    println("  Total:  $(n_total) samples")

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
    test_spms_current, test_actions, test_spms_next = samples_to_arrays(test_samples)

    # Create dataset (using test for both test_iid and test_ood for compatibility)
    dataset = VAEDataset(
        train_spms_current, train_actions, train_spms_next, Dict{String, Any}(),
        val_spms_current, val_actions, val_spms_next, Dict{String, Any}(),
        test_spms_current, test_actions, test_spms_next, Dict{String, Any}(),
        test_spms_current, test_actions, test_spms_next, Dict{String, Any}()  # Duplicate for compatibility
    )

    # Save to HDF5
    output_path = "data/vae_training/dataset_v56_exploratory.h5"
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
