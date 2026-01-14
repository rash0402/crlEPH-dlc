#!/usr/bin/env julia
"""
Train Action-Conditioned VAE for v6.2: Raw Trajectory Data with On-the-Fly SPM Reconstruction

Architecture:
  - Pattern D (Action-Conditioned)
  - Encoder: q(z | y[k], u[k])
  - Decoder: p(y[k+1] | z, u[k])
  - Latent dim: 32

Key Innovation (v6.2):
  - SPMs reconstructed on-the-fly from raw trajectory data
  - Memory-efficient: No pre-generated SPM dataset
  - Flexible: Easy to adjust SPM parameters

Hyperparameters:
  - β (KL weight): 0.5 (default, can be tuned)
  - Learning rate: 1e-4
  - Batch size: 128
  - Epochs: 100

Dataset:
  - Raw trajectories: data/vae_training/raw_v62/
  - Total: 80 files (20 Scramble + 60 Corridor)
  - On-the-fly SPM reconstruction via trajectory_loader.jl

Output:
  - Best model: models/action_vae_v62_best.bson
  - Training logs: results/vae_tuning/v62_training_YYYYMMDD_HHMMSS.h5

Estimated time: ~4-6 hours (includes SPM reconstruction overhead)
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

# Try to load CUDA, but don't fail if unavailable
try
    using CUDA
catch
    @warn "CUDA not available, using CPU only"
end

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/action_vae.jl")
include("../src/trajectory_loader.jl")

using .Config
using .SPM
using .ActionVAEModel

println("="^80)
println("Train Action-Conditioned VAE for v6.2: Raw Trajectory Data")
println("="^80)
println()
flush(stdout)

# Check GPU availability
device = cpu
if @isdefined(CUDA) && CUDA.functional()
    @info "GPU detected: $(CUDA.name(CUDA.device()))"
    device = gpu
else
    @warn "No GPU detected, using CPU (training will be slow)"
end
flush(stdout)
flush(stderr)

# Configuration
const DATA_DIR = joinpath(@__DIR__, "../data/vae_training/raw_v62")
const OUTPUT_DIR = joinpath(@__DIR__, "../results/vae_tuning")
const MODEL_DIR = joinpath(@__DIR__, "../models")
mkpath(OUTPUT_DIR)
mkpath(MODEL_DIR)

# Hyperparameters
const LATENT_DIM = 32
const BETA = 0.5  # KL weight (can be tuned)
const LEARNING_RATE = 1e-4
const BATCH_SIZE = 128
const N_EPOCHS = 100
const EARLY_STOP_PATIENCE = 15

# Data loading parameters (★ v6.2 memory-efficient settings)
const STRIDE = 5  # Temporal sampling: every 5 timesteps
const AGENT_SUBSAMPLE = nothing  # Use all agents (or set to 2 for every 2nd agent)
const MAX_FILES = nothing  # Limit number of files (20 for testing, nothing for all 80)
const TRAIN_VAL_SPLIT = 0.8  # 80% train, 20% validation
const VAL_TEST_SPLIT = 0.5  # Split validation into val/test (10% each)

# VAE architecture parameters
const SPM_SHAPE = (16, 16, 3)
const ACTION_DIM = 2

"""
Load and prepare training data from raw trajectories
"""
function load_training_data(data_dir::String)
    println("="^80)
    println("Loading Raw Trajectory Data")
    println("="^80)
    println("  Data directory: $data_dir")
    println("  Stride: $STRIDE (sampling every $STRIDE timesteps)")
    println("  Agent subsample: $(isnothing(AGENT_SUBSAMPLE) ? "All agents" : "Every $(AGENT_SUBSAMPLE)th agent")")
    println("  Max files: $(isnothing(MAX_FILES) ? "All files" : "$MAX_FILES files (memory-efficient mode)")")
    println()
    flush(stdout)

    # Load trajectory files with memory-efficient batch processing
    data = load_trajectories_batch(
        data_dir;
        stride=STRIDE,
        agent_subsample=AGENT_SUBSAMPLE,
        max_files=MAX_FILES
    )

    y_k = data.y_k    # [N, 16, 16, 3]
    u_k = data.u_k    # [N, 2]
    y_k1 = data.y_k1  # [N, 16, 16, 3]

    n_samples = size(y_k, 1)
    println()
    println("  Total samples: $n_samples")
    println("  SPM shape: $(size(y_k)[2:end])")
    println("  Action shape: $(size(u_k)[2:end])")
    println()

    # Train/Val/Test split
    println("Splitting into Train/Val/Test...")
    indices = randperm(n_samples)

    # 80% train, 10% val, 10% test
    n_train = round(Int, n_samples * TRAIN_VAL_SPLIT)
    n_val_test = n_samples - n_train
    n_val = round(Int, n_val_test * VAL_TEST_SPLIT)
    n_test = n_val_test - n_val

    train_idx = indices[1:n_train]
    val_idx = indices[n_train+1:n_train+n_val]
    test_idx = indices[n_train+n_val+1:end]

    # v6.2 Memory-Efficient: Use view() to avoid copying large arrays
    # This reduces memory usage from ~12GB to ~5GB during data splitting
    train_data = (
        spm_current = view(y_k, train_idx, :, :, :),
        actions = view(u_k, train_idx, :),
        spm_next = view(y_k1, train_idx, :, :, :)
    )

    val_data = (
        spm_current = view(y_k, val_idx, :, :, :),
        actions = view(u_k, val_idx, :),
        spm_next = view(y_k1, val_idx, :, :, :)
    )

    test_data = (
        spm_current = view(y_k, test_idx, :, :, :),
        actions = view(u_k, test_idx, :),
        spm_next = view(y_k1, test_idx, :, :, :)
    )

    println("  Train: $(size(train_data.spm_current, 1)) samples ($(round(100*n_train/n_samples, digits=1))%)")
    println("  Val: $(size(val_data.spm_current, 1)) samples ($(round(100*n_val/n_samples, digits=1))%)")
    println("  Test: $(size(test_data.spm_current, 1)) samples ($(round(100*n_test/n_samples, digits=1))%)")
    println()

    return train_data, val_data, test_data
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
    μ, logσ² = ActionVAEModel.encode(model, spm_current, actions)

    # Reparameterization trick
    σ = exp.(0.5f0 .* logσ²)
    ε = randn(Float32, size(σ)) |> device
    z = μ .+ σ .* ε

    # Decode: p(y[k+1] | z, u[k])
    spm_next_pred = ActionVAEModel.decode_with_u(model, z, actions)

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
    opt_state = Flux.setup(optimizer, model)  # New Flux API

    best_val_loss = Inf32
    patience_counter = 0
    training_history = []

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    log_path = joinpath(OUTPUT_DIR, "v62_training_$(timestamp).h5")

    println("="^80)
    println("Starting Training")
    println("="^80)
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
            # Forward pass (for metrics)
            loss, recon, kl = vae_loss(model, batch, β)

            # Backward pass (New Flux API)
            grads = Flux.gradient(model) do m
                vae_loss(m, batch, β)[1]  # Return only loss for gradient
            end

            # Update parameters (New Flux API)
            Flux.update!(opt_state, model, grads[1])

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
        flush(stdout)

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
            model_path = joinpath(MODEL_DIR, "action_vae_v62_best.bson")
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
        attributes(file)["stride"] = STRIDE
        attributes(file)["data_version"] = "v6.2"
    end

    println()
    println("✅ Training complete")
    println("  Best val loss: $(round(best_val_loss, digits=4))")
    println("  Training log: $log_path")

    return training_history
end

# Main execution
println("="^80)
println("Configuration Summary")
println("="^80)
println("  Data directory: $DATA_DIR")
println("  Latent dim: $LATENT_DIM")
println("  β (KL weight): $BETA")
println("  Learning rate: $LEARNING_RATE")
println("  Batch size: $BATCH_SIZE")
println("  Epochs: $N_EPOCHS")
println("  Temporal stride: $STRIDE")
println("  Device: $(device == gpu ? "GPU" : "CPU")")
println()

# Load dataset with on-the-fly SPM reconstruction
train_data, val_data, test_data = load_training_data(DATA_DIR)

# Create batches
println("="^80)
println("Creating Batches")
println("="^80)
train_batches = create_batches(train_data, BATCH_SIZE; shuffle=true, device=device)
val_batches = create_batches(val_data, BATCH_SIZE; shuffle=false, device=device)
test_batches = create_batches(test_data, BATCH_SIZE; shuffle=false, device=device)
println("  Train batches: $(length(train_batches))")
println("  Val batches: $(length(val_batches))")
println("  Test batches: $(length(test_batches))")
println()

# Initialize model
println("="^80)
println("Initializing Action-Conditioned VAE (Pattern D)")
println("="^80)
model = ActionVAEModel.ActionConditionedVAE(LATENT_DIM, ACTION_DIM) |> device
n_params = sum(length, Flux.params(model))
println("  Total parameters: $n_params")
println()

# Train
history = train_vae(model, train_batches, val_batches, Float32(BETA), Float32(LEARNING_RATE), N_EPOCHS)

# Final evaluation on test set
println()
println("="^80)
println("Final Test Set Evaluation")
println("="^80)
model_path = joinpath(MODEL_DIR, "action_vae_v62_best.bson")
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
println("  1. Validate model: scripts/validate_haze_v62.jl")
println("  2. Integration test: Run simulations with new VAE")
println("  3. Hyperparameter tuning: Try β ∈ [0.1, 0.3, 0.5, 0.7, 1.0]")
println("  4. Phase 5 preparation: Baseline vs EPH comparison")
println("="^80)
