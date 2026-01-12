#!/usr/bin/env julia
"""
Train Action-Conditioned VAE for v6.1: Bin 1-6 Haze=0 Fixed Strategy

Architecture:
  - Pattern D (Action-Conditioned)
  - Encoder: q(z | y[k], u[k])
  - Decoder: p(y[k+1] | z, u[k])
  - Latent dim: 32

Hyperparameters (from v6.0 best config):
  - β (KL weight): 0.5
  - Learning rate: 1e-4
  - Batch size: 128
  - Epochs: 100

Dataset:
  - D_max = 8.0m (2³)
  - Bin 1-6 Haze=0 Fixed (step function)
  - Input: data/vae_training/dataset_v61.h5

Output:
  - Best model: models/action_vae_v61_best.bson
  - Training logs: results/vae_tuning/v61_training_YYYYMMDD_HHMMSS.h5

Estimated time: ~4 hours on GPU
"""

using Pkg
Pkg.activate(".")

using Flux
using BSON: @save, @load
using HDF5
using Statistics
using Printf
using Dates
using Random
using CUDA

# Load project modules
include("../src/config.jl")
include("../src/action_vae.jl")

using .Config
using .ActionVAE

println("="^80)
println("Train Action-Conditioned VAE for v6.1: Bin 1-6 Haze=0 Fixed")
println("="^80)
println()

# Check GPU availability
if CUDA.functional()
    @info "GPU detected: $(CUDA.name(CUDA.device()))"
    device = gpu
else
    @warn "No GPU detected, using CPU (training will be slow)"
    device = cpu
end

# Configuration
const DATASET_PATH = joinpath(@__DIR__, "../data/vae_training/dataset_v61.h5")
const OUTPUT_DIR = joinpath(@__DIR__, "../results/vae_tuning")
const MODEL_DIR = joinpath(@__DIR__, "../models")
mkpath(OUTPUT_DIR)
mkpath(MODEL_DIR)

# Hyperparameters (v6.0 best config)
const LATENT_DIM = 32
const BETA = 0.5  # KL weight
const LEARNING_RATE = 1e-4
const BATCH_SIZE = 128
const N_EPOCHS = 100
const EARLY_STOP_PATIENCE = 15

# VAE architecture parameters
const SPM_SHAPE = (16, 16, 3)
const ACTION_DIM = 2

"""
Load dataset from HDF5
"""
function load_dataset(path::String)
    println("Loading dataset: $path")

    h5open(path, "r") do file
        train = (
            spm_current = read(file["train/spm_current"]),
            actions = read(file["train/actions"]),
            spm_next = read(file["train/spm_next"])
        )

        val = (
            spm_current = read(file["val/spm_current"]),
            actions = read(file["val/actions"]),
            spm_next = read(file["val/spm_next"])
        )

        test = (
            spm_current = read(file["test/spm_current"]),
            actions = read(file["test/actions"]),
            spm_next = read(file["test/spm_next"])
        )

        println("  Train: $(size(train.spm_current, 1)) samples")
        println("  Val: $(size(val.spm_current, 1)) samples")
        println("  Test: $(size(test.spm_current, 1)) samples")

        return train, val, test
    end
end

"""
Create data batches
"""
function create_batches(data, batch_size::Int; shuffle::Bool=true, device=cpu)
    n_samples = size(data.spm_current, 1)
    indices = shuffle ? randperm(n_samples) : collect(1:n_samples)

    batches = []
    for i in 1:batch_size:n_samples
        batch_end = min(i + batch_size - 1, n_samples)
        batch_indices = indices[i:batch_end]

        # Extract batch
        spm_current_batch = data.spm_current[batch_indices, :, :, :]
        actions_batch = data.actions[batch_indices, :]
        spm_next_batch = data.spm_next[batch_indices, :, :, :]

        # Reshape for Conv2d: (H, W, C, N)
        spm_current_batch = permutedims(spm_current_batch, (2, 3, 4, 1))
        spm_next_batch = permutedims(spm_next_batch, (2, 3, 4, 1))
        actions_batch = permutedims(actions_batch, (2, 1))

        # Move to device
        batch = (
            spm_current = device(Float32.(spm_current_batch)),
            actions = device(Float32.(actions_batch)),
            spm_next = device(Float32.(spm_next_batch))
        )

        push!(batches, batch)
    end

    return batches
end

"""
Compute VAE loss: Reconstruction + β * KL divergence
"""
function vae_loss(model, batch, β::Float32)
    spm_current = batch.spm_current
    actions = batch.actions
    spm_next = batch.spm_next

    # Encode: q(z | y[k], u[k])
    μ, logσ² = model.encoder(spm_current, actions)

    # Reparameterization trick
    σ = exp.(0.5f0 .* logσ²)
    ε = randn(Float32, size(σ)) |> device
    z = μ .+ σ .* ε

    # Decode: p(y[k+1] | z, u[k])
    spm_next_pred = model.decoder(z, actions)

    # Reconstruction loss (MSE)
    recon_loss = Flux.mse(spm_next_pred, spm_next)

    # KL divergence: KL(q(z|y,u) || N(0,I))
    kl_loss = -0.5f0 * sum(1f0 .+ logσ² .- μ.^2 .- exp.(logσ²)) / size(μ, 2)

    # Total loss
    loss = recon_loss + β * kl_loss

    return loss, recon_loss, kl_loss
end

"""
Evaluate model on validation set
"""
function evaluate(model, val_batches, β::Float32)
    total_loss = 0.0f0
    total_recon = 0.0f0
    total_kl = 0.0f0
    n_batches = length(val_batches)

    Flux.testmode!(model)

    for batch in val_batches
        loss, recon, kl = vae_loss(model, batch, β)
        total_loss += loss
        total_recon += recon
        total_kl += kl
    end

    Flux.trainmode!(model)

    return (
        loss = total_loss / n_batches,
        recon = total_recon / n_batches,
        kl = total_kl / n_batches
    )
end

"""
Training loop
"""
function train_vae(model, train_batches, val_batches, β::Float32, lr::Float32, n_epochs::Int)
    optimizer = Adam(lr)
    params = Flux.params(model)

    best_val_loss = Inf32
    patience_counter = 0
    training_history = []

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    log_path = joinpath(OUTPUT_DIR, "v61_training_$(timestamp).h5")

    println("\nStarting training...")
    println("  Epochs: $n_epochs")
    println("  Batch size: $BATCH_SIZE")
    println("  Learning rate: $lr")
    println("  β (KL weight): $β")
    println("  Early stop patience: $EARLY_STOP_PATIENCE")
    println()

    for epoch in 1:n_epochs
        epoch_loss = 0.0f0
        epoch_recon = 0.0f0
        epoch_kl = 0.0f0

        # Training
        for (batch_idx, batch) in enumerate(train_batches)
            # Forward pass
            loss, recon, kl = vae_loss(model, batch, β)

            # Backward pass
            grads = Flux.gradient(params) do
                vae_loss(model, batch, β)[1]
            end

            Flux.Optimise.update!(optimizer, params, grads)

            epoch_loss += loss
            epoch_recon += recon
            epoch_kl += kl
        end

        # Average over batches
        n_batches = length(train_batches)
        epoch_loss /= n_batches
        epoch_recon /= n_batches
        epoch_kl /= n_batches

        # Validation
        val_metrics = evaluate(model, val_batches, β)

        # Print progress
        @printf("Epoch %3d/%d | Train Loss: %.4f (Recon: %.4f, KL: %.4f) | Val Loss: %.4f (Recon: %.4f, KL: %.4f)\n",
                epoch, n_epochs,
                epoch_loss, epoch_recon, epoch_kl,
                val_metrics.loss, val_metrics.recon, val_metrics.kl)

        # Save history
        push!(training_history, Dict(
            "epoch" => epoch,
            "train_loss" => epoch_loss,
            "train_recon" => epoch_recon,
            "train_kl" => epoch_kl,
            "val_loss" => val_metrics.loss,
            "val_recon" => val_metrics.recon,
            "val_kl" => val_metrics.kl
        ))

        # Early stopping check
        if val_metrics.loss < best_val_loss
            best_val_loss = val_metrics.loss
            patience_counter = 0

            # Save best model
            model_path = joinpath(MODEL_DIR, "action_vae_v61_best.bson")
            cpu_model = model |> cpu
            @save model_path model=cpu_model
            println("    ✅ Best model saved: $model_path")
        else
            patience_counter += 1

            if patience_counter >= EARLY_STOP_PATIENCE
                println("    ⚠️  Early stopping triggered (patience=$EARLY_STOP_PATIENCE)")
                break
            end
        end
    end

    # Save training history
    h5open(log_path, "w") do file
        n_hist = length(training_history)

        epochs = [h["epoch"] for h in training_history]
        train_losses = [h["train_loss"] for h in training_history]
        train_recons = [h["train_recon"] for h in training_history]
        train_kls = [h["train_kl"] for h in training_history]
        val_losses = [h["val_loss"] for h in training_history]
        val_recons = [h["val_recon"] for h in training_history]
        val_kls = [h["val_kl"] for h in training_history]

        file["epochs"] = epochs
        file["train_loss"] = train_losses
        file["train_recon"] = train_recons
        file["train_kl"] = train_kls
        file["val_loss"] = val_losses
        file["val_recon"] = val_recons
        file["val_kl"] = val_kls

        attributes(file)["best_val_loss"] = best_val_loss
        attributes(file)["best_epoch"] = epochs[argmin(val_losses)]
        attributes(file)["beta"] = β
        attributes(file)["learning_rate"] = lr
        attributes(file)["batch_size"] = BATCH_SIZE
    end

    println()
    println("✅ Training complete")
    println("  Best val loss: $(round(best_val_loss, digits=4))")
    println("  Training log: $log_path")

    return training_history
end

# Main execution
println("="^80)
println("Configuration")
println("="^80)
println("  Dataset: $DATASET_PATH")
println("  Latent dim: $LATENT_DIM")
println("  β (KL weight): $BETA")
println("  Learning rate: $LEARNING_RATE")
println("  Batch size: $BATCH_SIZE")
println("  Epochs: $N_EPOCHS")
println("  Device: $(device == gpu ? "GPU" : "CPU")")
println()

# Load dataset
train_data, val_data, test_data = load_dataset(DATASET_PATH)
println()

# Create batches
println("Creating batches...")
train_batches = create_batches(train_data, BATCH_SIZE; shuffle=true, device=device)
val_batches = create_batches(val_data, BATCH_SIZE; shuffle=false, device=device)
test_batches = create_batches(test_data, BATCH_SIZE; shuffle=false, device=device)
println("  Train batches: $(length(train_batches))")
println("  Val batches: $(length(val_batches))")
println("  Test batches: $(length(test_batches))")
println()

# Initialize model
println("Initializing Action-Conditioned VAE (Pattern D)...")
model = ActionVAE.create_action_vae(LATENT_DIM) |> device
println("  Encoder parameters: $(sum(length, Flux.params(model.encoder)))")
println("  Decoder parameters: $(sum(length, Flux.params(model.decoder)))")
println()

# Train
history = train_vae(model, train_batches, val_batches, Float32(BETA), Float32(LEARNING_RATE), N_EPOCHS)

# Final evaluation on test set
println()
println("="^80)
println("Final Test Set Evaluation")
println("="^80)
model_path = joinpath(MODEL_DIR, "action_vae_v61_best.bson")
@load model_path model
model = model |> device

test_metrics = evaluate(model, test_batches, Float32(BETA))
@printf("  Test Loss: %.4f\n", test_metrics.loss)
@printf("  Test Recon (MSE): %.4f\n", test_metrics.recon)
@printf("  Test KL: %.4f\n", test_metrics.kl)
println()

if test_metrics.recon < 0.05
    println("✅ SUCCESS: Reconstruction quality meets criterion (MSE < 0.05)")
else
    println("⚠️  WARNING: Reconstruction quality below criterion (MSE >= 0.05)")
    println("   Consider: (1) More epochs, (2) Lower β, (3) Larger model")
end

println()
println("="^80)
println("Training Complete")
println("="^80)
println("  Best model: $model_path")
println()
println("Next steps:")
println("  1. Validate model: Check latent space structure")
println("  2. Integration test: Run Phase 1 tests with new VAE")
println("  3. Compare performance: v6.1 (new VAE) vs v6.0 (old VAE)")
println("="^80)
