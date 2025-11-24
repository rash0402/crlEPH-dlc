"""
Verify Training Data

Quick script to verify the collected GRU training data.
"""

using JLD2
using Statistics

println("╔════════════════════════════════════════════════════════════╗")
println("║  GRU Training Data Verification                            ║")
println("╚════════════════════════════════════════════════════════════╝")
println()

# Find all training files (use absolute path from project root)
# @__DIR__ is src_julia/, so dirname(@__DIR__) is project root
project_root = dirname(@__DIR__)
training_dir = joinpath(project_root, "data", "training")

if !isdir(training_dir)
    println("❌ Training directory not found: $training_dir")
    exit(1)
end

training_files = sort(filter(f -> endswith(f, ".jld2"),
                            readdir(training_dir, join=true)))

if isempty(training_files)
    println("❌ No training data files found!")
    exit(1)
end

println("Found $(length(training_files)) training data files")
println()

# Aggregate statistics
global_total_episodes = 0
global_total_transitions = 0
global_all_visible = Int[]

println("File Details:")
println("─────────────────────────────────────────────────────────────")

for (i, file) in enumerate(training_files)
    data = load(file)

    if haskey(data, "episodes")
        episodes = data["episodes"]
        num_episodes = length(episodes)
        num_transitions = sum(size(ep["spm_t"], 4) for ep in episodes)

        global global_total_episodes += num_episodes
        global global_total_transitions += num_transitions

        # Collect visible agent counts
        for ep in episodes
            append!(global_all_visible, ep["visible_agents"])
        end

        file_size_mb = filesize(file) / 1024 / 1024

        println("[$i] $(basename(file))")
        println("    Episodes: $num_episodes | Transitions: $num_transitions | Size: $(round(file_size_mb, digits=1)) MB")
    else
        println("[$i] $(basename(file)) - WARNING: No episodes key found!")
    end
end

println()
println("═══════════════════════════════════════════════════════════")
println("  Overall Statistics")
println("═══════════════════════════════════════════════════════════")
println()
println("Total Training Data:")
println("  Files: $(length(training_files))")
println("  Episodes: $global_total_episodes")
println("  Transitions: $global_total_transitions")
println()

if !isempty(global_all_visible)
    println("Visible Agents Distribution:")
    println("  Range: $(minimum(global_all_visible)) - $(maximum(global_all_visible))")
    println("  Mean:  $(round(mean(global_all_visible), digits=2))")
    println("  Median: $(Int(median(global_all_visible)))")
    println()

    println("Breakdown by visible agents count:")
    for count in 0:maximum(global_all_visible)
        n = sum(global_all_visible .== count)
        pct = round(100 * n / length(global_all_visible), digits=1)
        bar = repeat("■", Int(round(pct / 2)))
        println("  $count agents: $(lpad(n, 6)) ($pct%) $bar")
    end
    println()
end

# Data quality metrics
if !isempty(training_files)
    # Sample one file for detailed inspection
    sample_data = load(training_files[1])

    if haskey(sample_data, "episodes") && !isempty(sample_data["episodes"])
        sample_ep = sample_data["episodes"][1]

        println("Data Format:")
        println("  SPM shape:    $(size(sample_ep["spm_t"]))")
        println("  Action shape: $(size(sample_ep["action_t"]))")
        println()

        # Check for data quality
        spm_min = minimum(sample_ep["spm_t"])
        spm_max = maximum(sample_ep["spm_t"])

        println("Value Ranges (sample):")
        println("  SPM:    $(round(spm_min, digits=2)) to $(round(spm_max, digits=2))")
        println("  Action: $(round(minimum(sample_ep["action_t"]), digits=2)) to $(round(maximum(sample_ep["action_t"]), digits=2))")
        println()

        # Check for NaN/Inf
        has_nan = any(isnan, sample_ep["spm_t"]) || any(isnan, sample_ep["action_t"])
        has_inf = any(isinf, sample_ep["spm_t"]) || any(isinf, sample_ep["action_t"])

        if has_nan || has_inf
            println("  ⚠️  WARNING: NaN or Inf detected in data!")
        else
            println("  ✓ No NaN or Inf values detected")
        end
    end
end

println()
println("═══════════════════════════════════════════════════════════")
println()

# Final assessment
if global_total_transitions >= 10000
    println("✅ Sufficient training data collected (>= 10,000 transitions)")
    println("   Ready for GRU training!")
elseif global_total_transitions >= 5000
    println("⚠️  Moderate amount of data (>= 5,000 transitions)")
    println("   Can proceed with training, but more data recommended.")
else
    println("❌ Insufficient training data (< 5,000 transitions)")
    println("   Recommend collecting more data before training.")
end

println()
