#!/usr/bin/env julia
--project=.

using Flux
using BSON: @save
using Statistics
using Printf
using Dates

# Include modules
include("../src/config.jl")
include("../src/vae.jl")
include("../src/data_loader.jl")

using .Config
using .VAEModel
using .DataLoader

function train_vae()
    println("============================================================")
    println("EPH VAE Training")
    println("============================================================")
    
    # 1. Load Data
    # 1. Load Data
    data_dir = "log" # Load data from the log directory
    # Users ran logs in root folder?
    # Let's check where .h5 files are.
    # User's requests showed "Output: data_20251220_084923.h5" in root.
    
    println("🔍 Loading data from $data_dir...")
    spm_data = load_spm_data(data_dir)
    
    if isnothing(spm_data)
        println("❌ No data found. Please run simulation to generate .h5 logs.")
        exit(1)
    end
    
    # Check data volume
    n_samples = size(spm_data, 4)
    if n_samples < 100
        println("⚠️  Warning: Only $n_samples samples found. Training might be unstable.")
    end
    
    # Create DataLoaders
    batch_size = 64
    train_loader, test_loader = get_data_loader(spm_data, batch_size)
    
    println("📊 Data: $n_samples samples")
    println("   Train batches: $(length(train_loader))")
    println("   Test batches: $(length(test_loader))")
    
    # 2. Initialize Model
    latent_dim = 32
    model = VAE(latent_dim)
    
    println("🧠 Model Initialized (Latent Dim = $latent_dim)")
    
    # 3. Setup Optimizer
    learning_rate = 1e-3
    opt_state = Flux.setup(Flux.Adam(learning_rate), model)
    
    # 4. Training Loop
    epochs = 20
    best_loss = Inf
    
    # Check for models dir
    if !isdir("data/models")
        mkpath("data/models")
    end
    
    println("\n🚀 Starting training for $epochs epochs...")
    
    for epoch in 1:epochs
        # Train
        train_loss = 0.0
        count = 0
        
        for x_batch in train_loader
            # Compute gradient
            loss, grads = Flux.withgradient(model) do m
                l, recon, kld = vae_loss(m, x_batch; β=1.0f0)
                return l
            end
            
            # Update parameters
            Flux.update!(opt_state, model, grads[1])
            
            train_loss += loss
            count += 1
        end
        
        avg_train_loss = train_loss / count
        
        # Validation
        val_loss = 0.0
        val_recon = 0.0
        val_kld = 0.0
        val_count = 0
        
        for x_val in test_loader
            l, recon, kld = vae_loss(model, x_val; β=1.0f0)
            val_loss += l
            val_recon += recon
            val_kld += kld
            val_count += 1
        end
        
        if val_count > 0
            avg_val_loss = val_loss / val_count
            avg_val_recon = val_recon / val_count
            avg_val_kld = val_kld / val_count
            
            @printf("Epoch %2d: Train=%.4f Val=%.4f (Recon=%.4f, KLD=%.4f)\n", 
                epoch, avg_train_loss, avg_val_loss, avg_val_recon, avg_val_kld)
            
            # Save best model
            if avg_val_loss < best_loss
                best_loss = avg_val_loss
                model_path = "data/models/vae_best.bson"
                # Need to bring model to CPU if on GPU (current is CPU)
                model_cpu = cpu(model)
                @save model_path model_cpu
                # print("  (Saved best)")
            end
        else
            @printf("Epoch %2d: Train=%.4f (No validation data)\n", epoch, avg_train_loss)
        end
    end
    
    println("\n✅ Training Complete!")
end

# Run
if abspath(PROGRAM_FILE) == @__FILE__
    train_vae()
end
