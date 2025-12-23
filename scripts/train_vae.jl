#!/usr/bin/env julia
# VAE Training Script for EPH Project
# Trains a Variational Autoencoder on collected SPM data

using Pkg
Pkg.activate(".")

include("../src/vae.jl")
include("../src/data_loader.jl")

using .VAEModel
using .DataLoader
using Flux
using BSON
using Printf
using Dates
using Statistics

# ========== Configuration ==========
const LATENT_DIM = 32
const BATCH_SIZE = 64
const EPOCHS = 50
const LEARNING_RATE = 1e-3
const DATA_DIR = "data"
const SAVE_DIR = "models"
const β = 1.0f0  # KL divergence weight

# ========== Setup ==========
println("🚀 EPH VAE Training Script")
println("=" ^ 50)
println("Configuration:")
println("  Latent Dim: $LATENT_DIM")
println("  Batch Size: $BATCH_SIZE")
println("  Epochs: $EPOCHS")
println("  Learning Rate: $LEARNING_RATE")
println("  β (KL weight): $β")
println("=" ^ 50)

# Create save directory
mkpath(SAVE_DIR)

# ========== Load Data ==========
println("\n📂 Loading SPM data from $DATA_DIR...")
data = load_spm_data(DATA_DIR)

if data === nothing
    error("❌ No data found. Please run simulation to generate data first.")
end

println("✅ Data loaded: $(size(data))")

# Create data loaders
train_loader, test_loader = get_data_loader(data, BATCH_SIZE, shuffle=true, split_ratio=0.8)
println("✅ Train/Test split created")
println("  Train batches: $(length(train_loader))")
println("  Test batches: $(length(test_loader))")

# ========== Initialize Model ==========
println("\n🔧 Initializing VAE model...")
model = VAE(LATENT_DIM)
println("✅ Model initialized")

# Setup optimizer
opt_state = Flux.setup(Flux.Adam(LEARNING_RATE), model)
println("✅ Optimizer configured (Adam, lr=$LEARNING_RATE)")

# ========== Training Loop ==========
println("\n🏋️  Starting training...")
println("=" ^ 50)

train_losses = Float32[]
test_losses = Float32[]

for epoch in 1:EPOCHS
    epoch_start = now()
    
    # Training
    train_loss_sum = 0.0f0
    train_recon_sum = 0.0f0
    train_kld_sum = 0.0f0
    
    for (batch_idx, x_batch) in enumerate(train_loader)
        # Compute loss and gradients
        loss, grads = Flux.withgradient(model) do m
            total_loss, recon, kld = vae_loss(m, x_batch, β=β)
            total_loss
        end
        
        # Update parameters
        Flux.update!(opt_state, model, grads[1])
        
        # Accumulate losses
        total_loss, recon, kld = vae_loss(model, x_batch, β=β)
        train_loss_sum += total_loss
        train_recon_sum += recon
        train_kld_sum += kld
    end
    
    # Average training loss
    n_train = length(train_loader)
    avg_train_loss = train_loss_sum / n_train
    avg_train_recon = train_recon_sum / n_train
    avg_train_kld = train_kld_sum / n_train
    push!(train_losses, avg_train_loss)
    
    # Validation
    test_loss_sum = 0.0f0
    for x_batch in test_loader
        total_loss, _, _ = vae_loss(model, x_batch, β=β)
        test_loss_sum += total_loss
    end
    avg_test_loss = test_loss_sum / length(test_loader)
    push!(test_losses, avg_test_loss)
    
    # Timing
    epoch_time = (now() - epoch_start).value / 1000  # seconds
    
    # Print progress
    @printf("Epoch %3d/%d | Train Loss: %.4f (Recon: %.4f, KLD: %.4f) | Test Loss: %.4f | Time: %.2fs\n",
            epoch, EPOCHS, avg_train_loss, avg_train_recon, avg_train_kld, avg_test_loss, epoch_time)
    
    # Save checkpoint every 10 epochs
    if epoch % 10 == 0
        checkpoint_path = joinpath(SAVE_DIR, "vae_epoch_$(epoch).bson")
        BSON.@save checkpoint_path model
        println("  💾 Checkpoint saved: $checkpoint_path")
    end
end

println("=" ^ 50)
println("✅ Training complete!")

# ========== Save Final Model ==========
final_path = joinpath(SAVE_DIR, "vae_latest.bson")
BSON.@save final_path model
println("\n💾 Final model saved: $final_path")

# ========== Summary ==========
println("\n📊 Training Summary:")
println("  Initial Train Loss: $(train_losses[1])")
println("  Final Train Loss: $(train_losses[end])")
println("  Final Test Loss: $(test_losses[end])")
println("  Improvement: $(train_losses[1] - train_losses[end])")

println("\n🎉 Training script completed successfully!")
