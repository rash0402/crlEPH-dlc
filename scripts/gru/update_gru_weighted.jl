#!/usr/bin/env julia
"""
Update GRU Model with Importance Weighting
Training script that uses FOV occupancy for importance weighting.
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
println("GRU Model Update with Importance Weighting")
println("="^60)

# Configuration
const DATA_DIR = joinpath(@__DIR__, "../data/training")
const MODEL_DIR = joinpath(@__DIR__, "../data/models")
const HIDDEN_SIZE = 128
const LEARNING_RATE = 0.001
const EPOCHS = 50
const MIN_VISIBLE_FOR_FULL_WEIGHT = 2  # Minimum visible agents for full weight

mkpath(MODEL_DIR)

# ============================================================================
# Step 1: Load Latest Training Data
# ============================================================================
println("\n[Step 1] Loading training data...")

function load_latest_sequences()
    files = readdir(DATA_DIR)
    seq_files = filter(f -> startswith(f, "spm_sequences") && endswith(f, ".jld2"), files)
    
    if isempty(seq_files)
        error("No sequence data found in $DATA_DIR")
    end
    
    seq_files = sort(seq_files, by = f -> stat(joinpath(DATA_DIR, f)).mtime, rev=true)
    
    println("  Found $(length(seq_files)) data files")
    println("  Loading most recent: $(seq_files[1])")
    
    all_episodes = []
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
# Step 2: Prepare Training Sequences with Importance Weights
# ============================================================================
println("\n[Step 2] Preparing sequences with importance weights...")

function episodes_to_weighted_sequences(episodes)
    sequences_X = []
    sequences_Y = []
    sequences_W = []  # Importance weights
    
    for ep in episodes
        spm_t = ep["spm_t"]
        action_t = ep["action_t"]
        spm_next = ep["spm_next"]
        visible_agents = get(ep, "visible_agents", nothing)
        
        T = size(spm_t, 4)
        if T < 5 continue end
        
        seq_x = Vector{Vector{Float32}}(undef, T)
        seq_y = Vector{Vector{Float32}}(undef, T)
        seq_w = Vector{Float32}(undef, T)
        
        for t in 1:T
            s_t = reshape(spm_t[:,:,:,t], :)
            a_t = action_t[:,t]
            s_next = reshape(spm_next[:,:,:,t], :)
            
            seq_x[t] = vcat(Float32.(s_t), Float32.(a_t))
            seq_y[t] = Float32.(s_next)
            
            # Compute importance weight based on visible agents
            if visible_agents !== nothing
                n_visible = visible_agents[t]
                # Weight: 0.1 if no agents, 1.0 if >= MIN_VISIBLE_FOR_FULL_WEIGHT agents
                weight = max(0.1, min(1.0, n_visible / MIN_VISIBLE_FOR_FULL_WEIGHT))
                seq_w[t] = Float32(weight)
            else
                seq_w[t] = 1.0f0  # Default weight for old data
            end
        end
        
        push!(sequences_X, seq_x)
        push!(sequences_Y, seq_y)
        push!(sequences_W, seq_w)
    end
    
    return sequences_X, sequences_Y, sequences_W
end

sequences_X, sequences_Y, sequences_W = episodes_to_weighted_sequences(episodes)
println("  Prepared $(length(sequences_X)) sequences")

# Compute weight statistics
all_weights = vcat(sequences_W...)
println("  Weight statistics:")
println("    Mean: $(round(mean(all_weights), digits=3))")
println("    Min: $(round(minimum(all_weights), digits=3))")
println("    Max: $(round(maximum(all_weights), digits=3))")

# Train/test split
split_idx = Int(floor(0.8 * length(sequences_X)))
train_X = sequences_X[1:split_idx]
train_Y = sequences_Y[1:split_idx]
train_W = sequences_W[1:split_idx]
test_X = sequences_X[split_idx+1:end]
test_Y = sequences_Y[split_idx+1:end]
test_W = sequences_W[split_idx+1:end]

println("  Train: $(length(train_X)), Test: $(length(test_X))")

# ============================================================================
# Step 3: Define Model
# ============================================================================
println("\n[Step 3] Creating GRU model...")

input_size = 110
spm_flat_size = 108

model_container = (
    d1 = Dense(input_size => HIDDEN_SIZE, relu),
    c  = GRUCell(HIDDEN_SIZE => HIDDEN_SIZE),
    d2 = Dense(HIDDEN_SIZE => spm_flat_size)
)

println("  Architecture: Dense($input_size => $HIDDEN_SIZE) -> GRUCell -> Dense($HIDDEN_SIZE => $spm_flat_size)")

# ============================================================================
# Step 4: Training with Importance Weighting
# ============================================================================
println("\n[Step 4] Training model with importance weighting...")

function weighted_sequence_loss(m, x_seq, y_seq, w_seq)
    h = zeros(Float32, HIDDEN_SIZE)
    loss = 0.0f0
    total_weight = 0.0f0
    
    for i in 1:length(x_seq)
        x1 = m.d1(x_seq[i])
        h, h_out = m.c(h, x1)
        pred = m.d2(h_out)
        
        # Weighted MSE
        sample_loss = Flux.mse(pred, y_seq[i])
        loss += w_seq[i] * sample_loss
        total_weight += w_seq[i]
    end
    
    return loss / max(total_weight, 1.0f0)
end

opt = Flux.setup(Flux.Adam(LEARNING_RATE), model_container)

for epoch in 1:EPOCHS
    perm = randperm(length(train_X))
    train_X_shuffled = train_X[perm]
    train_Y_shuffled = train_Y[perm]
    train_W_shuffled = train_W[perm]
    
    total_loss = 0.0
    for i in 1:length(train_X_shuffled)
        grads = Flux.gradient(model_container) do m
            weighted_sequence_loss(m, train_X_shuffled[i], train_Y_shuffled[i], train_W_shuffled[i])
        end
        
        Flux.update!(opt, model_container, grads[1])
        total_loss += weighted_sequence_loss(model_container, train_X_shuffled[i], 
                                            train_Y_shuffled[i], train_W_shuffled[i])
    end
    
    avg_train_loss = total_loss / length(train_X_shuffled)
    
    # Validation
    total_test_loss = 0.0
    for i in 1:length(test_X)
        total_test_loss += weighted_sequence_loss(model_container, test_X[i], test_Y[i], test_W[i])
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

try
    recur_layer = Flux.Recur(model_container.c, zeros(Float32, HIDDEN_SIZE))
    final_model = Chain(model_container.d1, recur_layer, model_container.d2)
    model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
    save(model_path, "model", final_model)
    println("  Model saved to: $model_path")
catch e
    println("  Warning: Could not create Recur wrapper: $e")
    println("  Saving model components directly...")
    model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
    save(model_path, Dict(
        "model" => Chain(model_container.d1, model_container.c, model_container.d2),
        "hidden_size" => HIDDEN_SIZE
    ))
    println("  Model components saved to: $model_path")
end

println("\n" * "="^60)
println("Model Update Complete!")
println("="^60)
println("\nThe updated GRU model with importance weighting is ready.")
println("Restart the simulation to use the new model.")
