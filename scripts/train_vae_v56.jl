#!/usr/bin/env julia

"""
Phase 2: VAE Training Script for v5.6
Trains Action-Dependent VAE (Pattern D) for Surprise-based control
"""

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Random
using HDF5
using Statistics
using Flux
using BSON
using Flux: DataLoader
using Flux.Losses: mse
using ProgressMeter

# Load modules
include("../src/data_schema.jl")
include("../src/action_vae.jl")

using .DataSchema
using .ActionVAEModel

"""
Parse command line arguments
"""
function parse_commandline()
    args = Dict{String, Any}(
        "dataset" => "data/vae_training/dataset_v56.h5",
        "output_dir" => "models",
        "results_dir" => "results/vae_training",
        "latent_dim" => 32,
        "beta_kl" => 0.1,
        "learning_rate" => 1e-3,
        "batch_size" => 32,
        "epochs" => 200,
        "early_stop_patience" => 10,
        "checkpoint_every" => 10,
        "device" => "cpu"  # "cpu" or "gpu"
    )

    # Override with command line args if provided
    for i in 1:2:length(ARGS)
        if i+1 <= length(ARGS)
            key = replace(ARGS[i], "--" => "")
            val = ARGS[i+1]

            # Parse value type
            if key in ["latent_dim", "batch_size", "epochs", "early_stop_patience", "checkpoint_every"]
                args[key] = parse(Int, val)
            elseif key in ["beta_kl", "learning_rate"]
                args[key] = parse(Float64, val)
            else
                args[key] = val
            end
        end
    end

    return args
end

"""
Create data loaders from dataset
"""
function create_dataloaders(dataset::VAEDataset, batch_size::Int)
    # Training data
    train_data = [
        (dataset.train_spms_current[i, :, :, :],
         dataset.train_actions[i, :],
         dataset.train_spms_next[i, :, :, :])
        for i in 1:size(dataset.train_spms_current, 1)
    ]

    # Validation data
    val_data = [
        (dataset.val_spms_current[i, :, :, :],
         dataset.val_actions[i, :],
         dataset.val_spms_next[i, :, :, :])
        for i in 1:size(dataset.val_spms_current, 1)
    ]

    train_loader = DataLoader(train_data, batchsize=batch_size, shuffle=true)
    val_loader = DataLoader(val_data, batchsize=batch_size, shuffle=false)

    return train_loader, val_loader
end

"""
VAE loss function: Reconstruction + KL divergence
"""
function vae_loss(model::ActionConditionedVAE, spm_current, action, spm_next, β_kl::Float64)
    batch_size = size(spm_current, 4)

    # Forward pass
    spm_recon, μ, logσ = model(spm_current, action)

    # Reconstruction loss (MSE)
    recon_loss = mse(spm_recon, spm_next) * (16 * 16 * 3)  # Scale by dimension

    # KL divergence: KL[q(z|y,u) || p(z)] where p(z) = N(0,1)
    # KL = -0.5 * sum(1 + 2*logσ - μ² - exp(2*logσ))
    kl_div = -0.5f0 * mean(sum(1f0 .+ 2f0 .* logσ .- μ.^2 .- exp.(2f0 .* logσ), dims=1))

    # Total loss
    total_loss = recon_loss + β_kl * kl_div

    return total_loss, recon_loss, kl_div
end

"""
Evaluate validation loss
"""
function evaluate_val_loss(model::ActionConditionedVAE, val_loader, β_kl::Float64)
    total_loss = 0.0f0
    total_recon = 0.0f0
    total_kl = 0.0f0
    n_batches = 0

    for batch in val_loader
        # Unpack and stack batch
        spm_curr_batch = cat([b[1] for b in batch]..., dims=4)
        u_batch = hcat([b[2] for b in batch]...)
        spm_next_batch = cat([b[3] for b in batch]..., dims=4)

        loss, recon, kl = vae_loss(model, spm_curr_batch, u_batch, spm_next_batch, β_kl)

        total_loss += loss
        total_recon += recon
        total_kl += kl
        n_batches += 1
    end

    return total_loss / n_batches, total_recon / n_batches, total_kl / n_batches
end

"""
Main training loop
"""
function main()
    args = parse_commandline()

    println("=" ^ 70)
    println("EPH v5.6 - Phase 2: VAE Training")
    println("=" ^ 70)
    println("\nConfiguration:")
    println("  Dataset: $(args["dataset"])")
    println("  Latent dim: $(args["latent_dim"])")
    println("  β_KL: $(args["beta_kl"])")
    println("  Learning rate: $(args["learning_rate"])")
    println("  Batch size: $(args["batch_size"])")
    println("  Epochs: $(args["epochs"])")
    println("  Device: $(args["device"])")

    # Create output directories
    mkpath(args["output_dir"])
    mkpath(args["results_dir"])
    checkpoint_dir = joinpath(args["output_dir"], "action_vae_v56_checkpoints")
    mkpath(checkpoint_dir)

    # Load dataset
    println("\n📂 Loading dataset...")
    if !isfile(args["dataset"])
        println("❌ Error: Dataset not found: $(args["dataset"])")
        println("   Please run data collection first:")
        println("   julia --project=. scripts/collect_vae_data_v56.jl")
        println("   julia --project=. scripts/create_dataset_v56.jl")
        exit(1)
    end

    dataset = load_dataset(args["dataset"])
    println("  Train: $(size(dataset.train_spms_current, 1)) samples")
    println("  Val: $(size(dataset.val_spms_current, 1)) samples")

    # Create data loaders
    println("\n🔄 Creating data loaders...")
    train_loader, val_loader = create_dataloaders(dataset, args["batch_size"])
    println("  Train batches: $(length(train_loader))")
    println("  Val batches: $(length(val_loader))")

    # Initialize model
    println("\n🧠 Initializing VAE model...")
    model = ActionConditionedVAE(args["latent_dim"], 2)  # latent_dim, u_dim=2
    println("  Latent dimension: $(args["latent_dim"])")
    println("  Parameters: $(sum(length, Flux.params(model)))")

    # Optimizer
    opt = Flux.setup(Adam(args["learning_rate"]), model)

    # Training log
    training_log = []
    best_val_loss = Inf
    patience_counter = 0

    println("\n🚀 Starting training...\n")

    for epoch in 1:args["epochs"]
        # Training phase
        train_loss = 0.0f0
        train_recon = 0.0f0
        train_kl = 0.0f0
        n_train_batches = 0

        for batch in train_loader
            # Unpack and stack batch
            batch_size_actual = length(batch)
            spm_curr_batch = cat([b[1] for b in batch]..., dims=4)
            u_batch = hcat([b[2] for b in batch]...)
            spm_next_batch = cat([b[3] for b in batch]..., dims=4)

            # Compute loss and gradients
            loss, grads = Flux.withgradient(model) do m
                l, r, k = vae_loss(m, spm_curr_batch, u_batch, spm_next_batch, args["beta_kl"])
                train_recon += r
                train_kl += k
                l
            end

            # Update parameters
            Flux.update!(opt, model, grads[1])

            train_loss += loss
            n_train_batches += 1
        end

        # Average training metrics
        avg_train_loss = train_loss / n_train_batches
        avg_train_recon = train_recon / n_train_batches
        avg_train_kl = train_kl / n_train_batches

        # Validation phase
        val_loss, val_recon, val_kl = evaluate_val_loss(model, val_loader, args["beta_kl"])

        # Log metrics
        log_entry = Dict(
            "epoch" => epoch,
            "train_loss" => avg_train_loss,
            "train_recon" => avg_train_recon,
            "train_kl" => avg_train_kl,
            "val_loss" => val_loss,
            "val_recon" => val_recon,
            "val_kl" => val_kl
        )
        push!(training_log, log_entry)

        # Print progress
        @printf("Epoch %3d/%d | Train: %.4f (R:%.4f, KL:%.4f) | Val: %.4f (R:%.4f, KL:%.4f)\n",
                epoch, args["epochs"],
                avg_train_loss, avg_train_recon, avg_train_kl,
                val_loss, val_recon, val_kl)

        # Save checkpoint
        if epoch % args["checkpoint_every"] == 0
            checkpoint_path = joinpath(checkpoint_dir, "action_vae_epoch_$(epoch).bson")
            BSON.@save checkpoint_path model
        end

        # Early stopping
        if val_loss < best_val_loss
            best_val_loss = val_loss
            best_model_path = joinpath(args["output_dir"], "action_vae_v56_best.bson")
            BSON.@save best_model_path model
            println("  ✅ New best model saved (Val loss: $(round(val_loss, digits=4)))")
            patience_counter = 0
        else
            patience_counter += 1
            if patience_counter >= args["early_stop_patience"]
                println("\n⏹️  Early stopping at epoch $epoch (patience: $(args["early_stop_patience"]))")
                break
            end
        end
    end

    # Save training log
    log_path = joinpath(args["results_dir"], "training_log.csv")
    open(log_path, "w") do io
        println(io, "epoch,train_loss,train_recon,train_kl,val_loss,val_recon,val_kl")
        for entry in training_log
            println(io, "$(entry["epoch"]),$(entry["train_loss"]),$(entry["train_recon"]),$(entry["train_kl"]),$(entry["val_loss"]),$(entry["val_recon"]),$(entry["val_kl"])")
        end
    end

    println("\n" * "=" ^ 70)
    println("✅ Training Complete!")
    println("=" ^ 70)
    println("  Best model: models/action_vae_v56_best.bson")
    println("  Best val loss: $(round(best_val_loss, digits=4))")
    println("  Training log: $log_path")
    println("\nNext step: VAE Validation (Phase 3)")
    println("  Run: julia --project=. scripts/validate_vae_v56.jl")
end

# Run training
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
