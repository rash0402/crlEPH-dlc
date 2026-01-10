#!/usr/bin/env julia

"""
Phase 4.5: Automated VAE Hyperparameter Tuning for v5.6
Performs grid search over key hyperparameters and selects best configuration
"""

using Printf
using Dates
using Statistics
using JSON

"""
Configuration for hyperparameter tuning
"""
struct TuningConfig
    beta_kl_values::Vector{Float64}
    latent_dim_values::Vector{Int}
    batch_size::Int
    learning_rate::Float64
    epochs::Int
    early_stop_patience::Int
    checkpoint_every::Int
end

"""
Results for a single hyperparameter configuration
"""
struct TuningResult
    config_id::Int
    beta_kl::Float64
    latent_dim::Int
    best_val_loss::Float64
    final_epoch::Int
    train_time_sec::Float64
    model_path::String
end

"""
Default tuning configuration
"""
function get_default_tuning_config()
    return TuningConfig(
        [0.1, 0.5, 1.0],           # beta_kl: Low, Medium, High
        [32, 64],                   # latent_dim: Standard, Large
        64,                         # batch_size: Fixed at 64 for stability
        1e-3,                       # learning_rate: Fixed
        200,                        # epochs: Max epochs
        10,                         # early_stop_patience
        10                          # checkpoint_every
    )
end

"""
Generate all hyperparameter combinations
"""
function generate_configs(tuning_config::TuningConfig)
    configs = []
    config_id = 1

    for beta_kl in tuning_config.beta_kl_values
        for latent_dim in tuning_config.latent_dim_values
            push!(configs, (
                id = config_id,
                beta_kl = beta_kl,
                latent_dim = latent_dim,
                batch_size = tuning_config.batch_size,
                learning_rate = tuning_config.learning_rate,
                epochs = tuning_config.epochs,
                early_stop_patience = tuning_config.early_stop_patience,
                checkpoint_every = tuning_config.checkpoint_every
            ))
            config_id += 1
        end
    end

    return configs
end

"""
Run training for a single configuration
"""
function run_training(config, output_dir::String, results_dir::String)
    println("\n" * "=" ^ 70)
    println("Configuration $(config.id): β_KL=$(config.beta_kl), latent_dim=$(config.latent_dim)")
    println("=" ^ 70)

    # Create output directories for this config
    config_output_dir = joinpath(output_dir, "config_$(config.id)")
    config_results_dir = joinpath(results_dir, "config_$(config.id)")
    mkpath(config_output_dir)
    mkpath(config_results_dir)

    # Build command
    cmd = `julia --project=. scripts/train_vae_v56.jl
        --output_dir $config_output_dir
        --results_dir $config_results_dir
        --latent_dim $(config.latent_dim)
        --beta_kl $(config.beta_kl)
        --learning_rate $(config.learning_rate)
        --batch_size $(config.batch_size)
        --epochs $(config.epochs)
        --early_stop_patience $(config.early_stop_patience)
        --checkpoint_every $(config.checkpoint_every)`

    # Run training and measure time
    start_time = time()
    try
        run(cmd)
        elapsed_time = time() - start_time

        # Parse training log to get best validation loss
        log_path = joinpath(config_results_dir, "training_log.csv")
        best_val_loss, final_epoch = parse_training_log(log_path)

        # Model path
        model_path = joinpath(config_output_dir, "action_vae_v56_best.bson")

        println("\n✅ Configuration $(config.id) completed:")
        println("   Best Val Loss: $(round(best_val_loss, digits=4))")
        println("   Final Epoch: $final_epoch")
        println("   Training Time: $(round(elapsed_time/60, digits=1)) min")

        return TuningResult(
            config.id,
            config.beta_kl,
            config.latent_dim,
            best_val_loss,
            final_epoch,
            elapsed_time,
            model_path
        )
    catch e
        println("\n❌ Configuration $(config.id) failed: $e")
        return nothing
    end
end

"""
Parse training log to extract best validation loss and final epoch
"""
function parse_training_log(log_path::String)
    if !isfile(log_path)
        return Inf, 0
    end

    lines = readlines(log_path)
    if length(lines) <= 1
        return Inf, 0
    end

    best_val_loss = Inf
    final_epoch = 0

    for line in lines[2:end]  # Skip header
        parts = split(line, ',')
        if length(parts) >= 5
            epoch = parse(Int, parts[1])
            val_loss = parse(Float64, parts[5])

            if val_loss < best_val_loss
                best_val_loss = val_loss
            end
            final_epoch = epoch
        end
    end

    return best_val_loss, final_epoch
end

"""
Generate tuning report
"""
function generate_report(results::Vector{TuningResult}, output_path::String)
    # Sort by best validation loss
    sorted_results = sort(results, by = r -> r.best_val_loss)

    open(output_path, "w") do io
        println(io, "# VAE Hyperparameter Tuning Report (v5.6)")
        println(io, "")
        println(io, "Generated: $(now())")
        println(io, "")
        println(io, "## Summary")
        println(io, "")
        println(io, "Total configurations tested: $(length(results))")
        println(io, "")

        # Best configuration
        best = sorted_results[1]
        println(io, "### Best Configuration")
        println(io, "")
        println(io, "- **Config ID**: $(best.config_id)")
        println(io, "- **β_KL**: $(best.beta_kl)")
        println(io, "- **Latent Dim**: $(best.latent_dim)")
        println(io, "- **Best Val Loss**: $(round(best.best_val_loss, digits=4))")
        println(io, "- **Final Epoch**: $(best.final_epoch)")
        println(io, "- **Training Time**: $(round(best.train_time_sec/60, digits=1)) min")
        println(io, "- **Model Path**: $(best.model_path)")
        println(io, "")

        # Full results table
        println(io, "## All Configurations")
        println(io, "")
        println(io, "| Rank | Config ID | β_KL | Latent Dim | Best Val Loss | Final Epoch | Time (min) |")
        println(io, "|------|-----------|------|------------|---------------|-------------|------------|")

        for (rank, result) in enumerate(sorted_results)
            @printf(io, "| %d | %d | %.1f | %d | %.4f | %d | %.1f |\n",
                    rank,
                    result.config_id,
                    result.beta_kl,
                    result.latent_dim,
                    result.best_val_loss,
                    result.final_epoch,
                    result.train_time_sec / 60)
        end

        println(io, "")

        # Analysis by parameter
        println(io, "## Analysis by β_KL")
        println(io, "")
        beta_groups = Dict{Float64, Vector{TuningResult}}()
        for result in results
            if !haskey(beta_groups, result.beta_kl)
                beta_groups[result.beta_kl] = []
            end
            push!(beta_groups[result.beta_kl], result)
        end

        for beta in sort(collect(keys(beta_groups)))
            group = beta_groups[beta]
            avg_loss = mean([r.best_val_loss for r in group])
            println(io, "- **β_KL = $beta**: Avg Val Loss = $(round(avg_loss, digits=4)) (n=$(length(group)))")
        end

        println(io, "")
        println(io, "## Analysis by Latent Dimension")
        println(io, "")
        latent_groups = Dict{Int, Vector{TuningResult}}()
        for result in results
            if !haskey(latent_groups, result.latent_dim)
                latent_groups[result.latent_dim] = []
            end
            push!(latent_groups[result.latent_dim], result)
        end

        for latent_dim in sort(collect(keys(latent_groups)))
            group = latent_groups[latent_dim]
            avg_loss = mean([r.best_val_loss for r in group])
            println(io, "- **Latent Dim = $latent_dim**: Avg Val Loss = $(round(avg_loss, digits=4)) (n=$(length(group)))")
        end

        println(io, "")
        println(io, "## Recommendation")
        println(io, "")
        println(io, "Based on validation loss, use Configuration $(best.config_id) for Phase 3 validation:")
        println(io, "```bash")
        println(io, "# Copy best model to standard location")
        println(io, "cp $(best.model_path) models/action_vae_v56_best.bson")
        println(io, "")
        println(io, "# Run validation")
        println(io, "julia --project=. scripts/validate_vae_v56.jl --model models/action_vae_v56_best.bson")
        println(io, "```")
    end

    println("\n📊 Report saved to: $output_path")
end

"""
Save results as JSON for programmatic access
"""
function save_results_json(results::Vector{TuningResult}, output_path::String)
    results_dict = [
        Dict(
            "config_id" => r.config_id,
            "beta_kl" => r.beta_kl,
            "latent_dim" => r.latent_dim,
            "best_val_loss" => r.best_val_loss,
            "final_epoch" => r.final_epoch,
            "train_time_sec" => r.train_time_sec,
            "model_path" => r.model_path
        )
        for r in results
    ]

    open(output_path, "w") do io
        JSON.print(io, results_dict, 4)
    end

    println("📄 JSON results saved to: $output_path")
end

"""
Main tuning loop
"""
function main()
    println("=" ^ 70)
    println("EPH v5.6 - Phase 4.5: Automated VAE Hyperparameter Tuning")
    println("=" ^ 70)
    println()

    # Setup
    tuning_config = get_default_tuning_config()
    configs = generate_configs(tuning_config)

    output_base_dir = "models/vae_tuning"
    results_base_dir = "results/vae_tuning"
    mkpath(output_base_dir)
    mkpath(results_base_dir)

    println("Tuning Configuration:")
    println("  β_KL values: $(tuning_config.beta_kl_values)")
    println("  Latent dim values: $(tuning_config.latent_dim_values)")
    println("  Batch size: $(tuning_config.batch_size)")
    println("  Total configurations: $(length(configs))")
    println()

    # Estimate total time
    est_time_per_config = 60  # minutes (conservative estimate)
    est_total_time = length(configs) * est_time_per_config
    println("⏱️  Estimated total time: $(round(est_total_time/60, digits=1)) hours")
    println("   (assuming ~$est_time_per_config min per config with early stopping)")
    println()
    println("🚀 Starting automated tuning...")
    println()

    # Run tuning
    start_time = time()
    results = TuningResult[]

    for (i, config) in enumerate(configs)
        println("\n" * "🔧" ^ 35)
        println("Progress: $i / $(length(configs))")
        println("🔧" ^ 35)

        result = run_training(config, output_base_dir, results_base_dir)
        if !isnothing(result)
            push!(results, result)
        end
    end

    total_time = time() - start_time

    # Generate reports
    println("\n" * "=" ^ 70)
    println("✅ Tuning Complete!")
    println("=" ^ 70)
    println("  Total time: $(round(total_time/3600, digits=2)) hours")
    println("  Successful configs: $(length(results)) / $(length(configs))")
    println()

    if !isempty(results)
        report_path = joinpath(results_base_dir, "tuning_report.md")
        json_path = joinpath(results_base_dir, "tuning_results.json")

        generate_report(results, report_path)
        save_results_json(results, json_path)

        # Show best result
        best = sort(results, by = r -> r.best_val_loss)[1]
        println("\n🏆 Best Configuration:")
        println("   Config ID: $(best.config_id)")
        println("   β_KL: $(best.beta_kl)")
        println("   Latent Dim: $(best.latent_dim)")
        println("   Best Val Loss: $(round(best.best_val_loss, digits=4))")
        println("   Model: $(best.model_path)")
        println()
        println("Next step: Run validation with best model")
        println("  julia --project=. scripts/validate_vae_v56.jl --model $(best.model_path)")
    else
        println("\n❌ No successful configurations. Please check errors above.")
    end
end

# Run tuning
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
