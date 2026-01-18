#!/usr/bin/env julia
"""
Train Action-Conditioned VAE for v7.2: Raw Trajectory Data with Ego-Centric SPM Reconstruction

Architecture:
  - Pattern D (Action-Conditioned)
  - Encoder: q(z | y[k], u[k])
  - Decoder: p(y[k+1] | z, u[k])
  - Latent dim: 32

Key Updates (v7.2):
  - Data: 5D State Space (x, y, vx, vy, θ)
  - Reconstruction: Ego-centric SPM (rotated by Heading)
  - Action: Omnidirectional force [Fx, Fy] (2D)

Dataset:
  - Raw trajectories: data/vae_training/raw_v72/
  - On-the-fly SPM reconstruction via trajectory_loader.jl

Output:
  - Best model: models/action_vae_v72_best.bson
  - Training logs: results/vae_tuning/v72_training_YYYYMMDD_HHMMSS.h5
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
println("Train Action-Conditioned VAE for v7.2: Raw Trajectory Data (Ego-Centric)")
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
const DATA_DIR = joinpath(@__DIR__, "../data/vae_training/raw_v72")
const OUTPUT_DIR = joinpath(@__DIR__, "../results/vae_tuning")
const MODEL_DIR = joinpath(@__DIR__, "../models")
mkpath(OUTPUT_DIR)
mkpath(MODEL_DIR)

# Hyperparameters
const LATENT_DIM = 32
const BETA = 0.5  # KL weight
const LEARNING_RATE = 1e-4
# Use smaller batch size/epochs for initial test if needed, but defaults are fine
const BATCH_SIZE = 128
const N_EPOCHS = 100
const EARLY_STOP_PATIENCE = 15

# Data loading parameters
const STRIDE = 5  # Temporal sampling
const AGENT_SUBSAMPLE = nothing
const MAX_FILES = nothing  # Process all files by default
const TRAIN_VAL_SPLIT = 0.8
const VAL_TEST_SPLIT = 0.5

# VAE architecture parameters
const SPM_SHAPE = (12, 12, 3)
const ACTION_DIM = 2

"""
Load and prepare training data from raw trajectories
"""
function load_training_data(data_dir::String)
    println("="^80)
    println("Loading Raw Trajectory Data")
    println("="^80)
    println("  Data directory: $data_dir")
    println("  Pattern: v72_*.h5")
    println("  Stride: $STRIDE")
    println()
    flush(stdout)

    # Load trajectory files (v7.2 pattern)
    data = load_trajectories_batch(
        data_dir;
        pattern="v72_*.h5",
        stride=STRIDE,
        agent_subsample=AGENT_SUBSAMPLE,
        max_files=MAX_FILES
    )

    y_k = data.y_k    # [N, 16, 16, 3]
    u_k = data.u_k ./ 150.0f0 # Normalize action (approx u_max=150)
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

    n_train = round(Int, n_samples * TRAIN_VAL_SPLIT)
    n_val_test = n_samples - n_train
    n_val = round(Int, n_val_test * VAL_TEST_SPLIT)
    n_test = n_val_test - n_val

    train_idx = indices[1:n_train]
    val_idx = indices[n_train+1:n_train+n_val]
    test_idx = indices[n_train+n_val+1:end]

    # Use view() for memory efficiency
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

    println("  Train: $(size(train_data.spm_current, 1)) samples")
    println("  Val:   $(size(val_data.spm_current, 1)) samples")
    println("  Test:  $(size(test_data.spm_current, 1)) samples")
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

    # KL divergence
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
    opt_state = Flux.setup(optimizer, model)

    best_val_loss = Inf32
    patience_counter = 0
    training_history = []

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    log_path = joinpath(OUTPUT_DIR, "v72_training_$(timestamp).h5")

    println("="^80)
    println("Starting Training")
    println("="^80)
    for epoch in 1:n_epochs
        epoch_loss = 0.0f0
        epoch_recon = 0.0f0
        epoch_kl = 0.0f0

        # Training
        for batch in train_batches
            # Gradient update
            grads = Flux.gradient(model) do m
                vae_loss(m, batch, β)[1]
            end
            Flux.update!(opt_state, model, grads[1])

            # Forward pass for logging
            loss, recon, kl = vae_loss(model, batch, β)
            epoch_loss += loss
            epoch_recon += recon
            epoch_kl += kl
        end

        # Average
        n_batches = length(train_batches)
        epoch_loss /= n_batches
        epoch_recon /= n_batches
        epoch_kl /= n_batches

        # Validation
        val_metrics = evaluate(model, val_batches, β)

        @printf("Epoch %3d/%d | Train: %.4f (R:%.4f) | Val: %.4f (R:%.4f)\n",
                epoch, n_epochs, epoch_loss, epoch_recon, val_metrics.loss, val_metrics.recon)
        flush(stdout)

        # Early stopping
        if val_metrics.loss < best_val_loss
            best_val_loss = val_metrics.loss
            patience_counter = 0
            
            # Save best model
            model_path = joinpath(MODEL_DIR, "action_vae_v72_best.bson")
            cpu_model = model |> cpu
            @save model_path model=cpu_model
        else
            patience_counter += 1
            if patience_counter >= EARLY_STOP_PATIENCE
                println("    ⚠️  Early stopping")
                break
            end
        end
    end
end

# Main execution
println("Loading data...")
train_data, val_data, test_data = load_training_data(DATA_DIR)

println("Creating batches...")
train_batches = create_batches(train_data, BATCH_SIZE; shuffle=true, device=device)
val_batches = create_batches(val_data, BATCH_SIZE; shuffle=false, device=device)
test_batches = create_batches(test_data, BATCH_SIZE; shuffle=false, device=device)

println("Initializing Model...")
model = ActionVAEModel.ActionConditionedVAE(LATENT_DIM, ACTION_DIM) |> device

train_vae(model, train_batches, val_batches, Float32(BETA), Float32(LEARNING_RATE), N_EPOCHS)

println("✅ Training complete")
