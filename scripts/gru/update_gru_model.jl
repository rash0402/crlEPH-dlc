#!/usr/bin/env julia
"""
Update GRU Model Script
Quick script to retrain and update the GRU predictor model.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "../../src_julia"))
Pkg.instantiate()

using JLD2
using FileIO
using Flux
using Statistics
using Random
using LinearAlgebra

println("="^60)
println("GRU Model Update Script")
println("="^60)

# Configuration
const DATA_DIR = joinpath(@__DIR__, "../../data/training")
const MODEL_DIR = joinpath(@__DIR__, "../../data/models")
const HIDDEN_SIZE = 128
const LEARNING_RATE = 0.001
const EPOCHS = 50

mkpath(MODEL_DIR)

# ============================================================================
# Step 1: Load Latest Training Data
# ============================================================================
println("\n[Step 1] Loading training data...")

function load_latest_sequences()
    files = readdir(DATA_DIR)
    seq_files = filter(f -> startswith(f, "spm_sequences") && endswith(f, ".jld2"), files)
    
    if isempty(seq_files)
        error("No sequence data found in $DATA_DIR. Please run simulation with collect_data=true first.")
    end
    
    # Sort by modification time and take the most recent
    seq_files = sort(seq_files, by = f -> stat(joinpath(DATA_DIR, f)).mtime, rev=true)
    
    println("  Found $(length(seq_files)) data files")
    println("  Loading most recent: $(seq_files[1])")
    
    all_episodes = []
    # Load the 3 most recent files for more data
    for file in seq_files[1:min(3, length(seq_files))]
        data = load(joinpath(DATA_DIR, file))
        episodes = data["episodes"]
        append!(all_episodes, episodes)
        println("    Loaded $(length(episodes)) episodes from $file")
    end
    
    println("  Total episodes: $(length(all_episodes))")
    return all_episodes
end

episodes = load_latest_sequences()

# ============================================================================
# Step 2: Prepare Training Sequences
# ============================================================================
println("\n[Step 2] Preparing sequences...")

function episodes_to_sequences(episodes)
    sequences_X = []
    sequences_Y = []
    
    for ep in episodes
        spm_t = ep["spm_t"]
        action_t = ep["action_t"]
        spm_next = ep["spm_next"]
        
        T = size(spm_t, 4)
        if T < 5 continue end
        
        seq_x = Vector{Vector{Float32}}(undef, T)
        seq_y = Vector{Vector{Float32}}(undef, T)
        
        for t in 1:T
            s_t = reshape(spm_t[:,:,:,t], :)
            a_t = action_t[:,t]
            s_next = reshape(spm_next[:,:,:,t], :)
            
            seq_x[t] = vcat(Float32.(s_t), Float32.(a_t))
            seq_y[t] = Float32.(s_next)
        end
        
        push!(sequences_X, seq_x)
        push!(sequences_Y, seq_y)
    end
    
    return sequences_X, sequences_Y
end

sequences_X, sequences_Y = episodes_to_sequences(episodes)
println("  Prepared $(length(sequences_X)) sequences")

# Train/test split
split_idx = Int(floor(0.8 * length(sequences_X)))
train_X = sequences_X[1:split_idx]
train_Y = sequences_Y[1:split_idx]
test_X = sequences_X[split_idx+1:end]
test_Y = sequences_Y[split_idx+1:end]

println("  Train: $(length(train_X)), Test: $(length(test_X))")

# ============================================================================
# Step 3: Define Model
# ============================================================================
println("\n[Step 3] Creating GRU model...")

input_size = 110  # 108 (SPM) + 2 (action)
spm_flat_size = 108

model_container = (
    d1 = Dense(input_size => HIDDEN_SIZE, relu),
    c  = GRUCell(HIDDEN_SIZE => HIDDEN_SIZE),
    d2 = Dense(HIDDEN_SIZE => spm_flat_size)
)

println("  Architecture: Dense($input_size => $HIDDEN_SIZE) -> GRUCell -> Dense($HIDDEN_SIZE => $spm_flat_size)")

# ============================================================================
# Step 4: Training
# ============================================================================
println("\n[Step 4] Training model...")

function sequence_loss(m, x_seq, y_seq)
    h = zeros(Float32, HIDDEN_SIZE)
    loss = 0.0f0
    len = length(x_seq)
    
    for i in 1:len
        x1 = m.d1(x_seq[i])
        h, h_out = m.c(h, x1)
        pred = m.d2(h_out)
        loss += Flux.mse(pred, y_seq[i])
    end
    
    return loss / len
end

opt = Flux.setup(Flux.Adam(LEARNING_RATE), model_container)

for epoch in 1:EPOCHS
    perm = randperm(length(train_X))
    train_X_shuffled = train_X[perm]
    train_Y_shuffled = train_Y[perm]
    
    total_loss = 0.0
    for i in 1:length(train_X_shuffled)
        grads = Flux.gradient(model_container) do m
            sequence_loss(m, train_X_shuffled[i], train_Y_shuffled[i])
        end
        
        Flux.update!(opt, model_container, grads[1])
        total_loss += sequence_loss(model_container, train_X_shuffled[i], train_Y_shuffled[i])
    end
    
    avg_train_loss = total_loss / length(train_X_shuffled)
    
    # Validation
    total_test_loss = 0.0
    for i in 1:length(test_X)
        total_test_loss += sequence_loss(model_container, test_X[i], test_Y[i])
    end
    avg_test_loss = isempty(test_X) ? 0.0 : total_test_loss / length(test_X)
    
    if epoch % 10 == 0 || epoch == 1
        println("  Epoch $epoch: Train Loss = $(round(avg_train_loss, digits=4)), Test Loss = $(round(avg_test_loss, digits=4))")
    end
end

# ============================================================================
# Step 5: Save Model
# ============================================================================
println("\n[Step 5] Saving model...")

# Try to create Recur wrapper, but handle if Recur is not available
try
    # Attempt to create Recur wrapper for GRUCell
    recur_layer = Flux.Recur(model_container.c, zeros(Float32, HIDDEN_SIZE))
    
    final_model = Chain(
        model_container.d1, 
        recur_layer,
        model_container.d2
    )
    
    # Save as the main predictor model
    model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
    save(model_path, "model", final_model)
    
    println("  Model saved to: $model_path")
catch e
    println("  Warning: Could not create Recur wrapper: $e")
    println("  Saving model components directly...")
    
    # Save model components directly
    model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
    save(model_path, Dict(
        "model" => Chain(
            model_container.d1,
            model_container.c,  # Save GRUCell directly
            model_container.d2
        ),
        "hidden_size" => HIDDEN_SIZE
    ))
    
    println("  Model components saved to: $model_path")
end

println("\n" * "="^60)
println("Model Update Complete!")
println("="^60)
println("\nThe updated GRU model is now ready to use.")
println("Restart the simulation to use the new model.")
