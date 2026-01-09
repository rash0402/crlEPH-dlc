#!/usr/bin/env julia

"""
Training Script for Action-Conditioned VAE (EPH v5.4)
Trains the model on (y[k], u[k], y[k+1]) tuples.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using Statistics
using Random
using Flux
using Flux.Optimise
using BSON
using HDF5

# Load Action VAE module
include("../src/action_vae.jl")
using .ActionVAEModel

"""
Load training data from HDF5 file.
"""
function load_training_data(path::String)
    spm_current = h5read(path, "spm_current")
    actions = h5read(path, "actions")
    spm_next = h5read(path, "spm_next")
    n_samples = h5read(path, "n_samples")
    
    println("📂 Loaded training data from: $path")
    println("   Samples: $n_samples")
    println("   SPM shape: $(size(spm_current))")
    println("   Actions shape: $(size(actions))")
    
    return spm_current, actions, spm_next
end

"""
Create data loader for batched training.
"""
function create_dataloader(spm_current, actions, spm_next; batch_size::Int=32, shuffle::Bool=true)
    n_samples = size(spm_current, 4)
    indices = shuffle ? Random.shuffle(1:n_samples) : collect(1:n_samples)
    
    batches = []
    for i in 1:batch_size:n_samples
        batch_end = min(i + batch_size - 1, n_samples)
        batch_idx = indices[i:batch_end]
        
        batch = (
            spm_current[:, :, :, batch_idx],
            actions[:, batch_idx],
            spm_next[:, :, :, batch_idx]
        )
        push!(batches, batch)
    end
    
    return batches
end

"""
Train Action-Conditioned VAE.
"""
function train_action_vae(;
    data_path::String,
    epochs::Int=100,
    batch_size::Int=32,
    learning_rate::Float64=1e-3,
    beta::Float32=0.1f0,  # KL weight (lower for prediction focus)
    latent_dim::Int=32,
    save_interval::Int=10,
    output_dir::String="models"
)
    # Load data
    spm_current, actions, spm_next = load_training_data(data_path)
    
    # Create model
    println("\n🧠 Creating Action-Conditioned VAE...")
    println("   Latent dim: $latent_dim")
    println("   u dim: 2")
    
    model = ActionConditionedVAE(latent_dim, 2)
    
    # Optimizer
    opt = Flux.setup(Flux.Adam(learning_rate), model)
    
    # Training loop
    println("\n🚀 Starting training...")
    println("   Epochs: $epochs")
    println("   Batch size: $batch_size")
    println("   Learning rate: $learning_rate")
    println("   β (KL weight): $beta")
    println()
    
    best_loss = Inf
    
    for epoch in 1:epochs
        # Create batches
        batches = create_dataloader(spm_current, actions, spm_next, batch_size=batch_size)
        
        epoch_loss = 0.0f0
        epoch_pred_loss = 0.0f0
        epoch_kld = 0.0f0
        n_batches = 0
        
        for (x_cur, u, x_next) in batches
            # Compute gradients and update
            loss_val, grads = Flux.withgradient(model) do m
                total, pred, kld = action_vae_loss(m, x_cur, u, x_next, β=beta)
                return total
            end
            
            Flux.update!(opt, model, grads[1])
            
            # Track losses
            _, pred_loss, kld = action_vae_loss(model, x_cur, u, x_next, β=beta)
            epoch_loss += loss_val
            epoch_pred_loss += pred_loss
            epoch_kld += kld
            n_batches += 1
        end
        
        # Average losses
        avg_loss = epoch_loss / n_batches
        avg_pred = epoch_pred_loss / n_batches
        avg_kld = epoch_kld / n_batches
        
        # Print progress
        if epoch % 5 == 0 || epoch == 1
            @printf("Epoch %3d: Loss=%.4f (Pred=%.4f, KLD=%.4f)\n", 
                    epoch, avg_loss, avg_pred, avg_kld)
        end
        
        # Save best model
        if avg_loss < best_loss
            best_loss = avg_loss
            
            # Save model
            mkpath(output_dir)
            model_path = joinpath(output_dir, "action_vae_best.bson")
            BSON.@save model_path model
            
            if epoch % save_interval == 0
                println("   💾 Saved best model (loss=$(@sprintf("%.4f", best_loss)))")
            end
        end
        
        # Save periodic checkpoint
        if epoch % save_interval == 0
            checkpoint_path = joinpath(output_dir, "action_vae_epoch_$(epoch).bson")
            BSON.@save checkpoint_path model
        end
    end
    
    println("\n✅ Training complete!")
    println("   Best loss: $(@sprintf("%.4f", best_loss))")
    println("   Model saved to: $(joinpath(output_dir, "action_vae_best.bson"))")
    
    return model
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    # Find latest training data
    data_dir = "data/vae_training"
    data_files = filter(f -> startswith(f, "action_vae_train") && endswith(f, ".h5"), readdir(data_dir))
    
    if isempty(data_files)
        println("❌ No training data found in $data_dir/")
        println("   Run scripts/collect_action_vae_data.jl first.")
        exit(1)
    end
    
    # Use latest file
    latest_file = joinpath(data_dir, sort(data_files)[end])
    println("📁 Using training data: $latest_file")
    
    # Train model
    train_action_vae(
        data_path=latest_file,
        epochs=200,
        batch_size=64,
        learning_rate=1e-3,
        beta=0.1f0,  # Higher beta for Pattern D (Uncertainty Learning)
        latent_dim=32
    )
end
