#!/usr/bin/env julia
"""
GRU Pre-training Pipeline
Implements comprehensive training strategy with:
- Diverse data collection
- Data augmentation
- Curriculum learning
- Evaluation and fine-tuning
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, "../../src_julia"))
Pkg.instantiate()

using JLD2
using FileIO
using Flux
using Statistics
using Random
using Dates
using LinearAlgebra

# Add project modules to path
push!(LOAD_PATH, joinpath(@__DIR__, "../../src_julia"))
include("../src_julia/utils/DataAugmentation.jl")
using .DataAugmentation

# Configuration
const DATA_DIR = joinpath(@__DIR__, "../data/training")
const MODEL_DIR = joinpath(@__DIR__, "../data/models")
const AUGMENTED_DIR = joinpath(@__DIR__, "../data/training/augmented")
mkpath(DATA_DIR)
mkpath(MODEL_DIR)
mkpath(AUGMENTED_DIR)

# Hyperparameters
const HIDDEN_SIZE = 128
const LEARNING_RATE_INITIAL = 0.001
const LEARNING_RATE_FINETUNE = 0.0001
const EPOCHS_PER_STAGE = 20
const BATCH_SIZE = 1  # Sequence-level batching

println("="^60)
println("GRU Pre-training Pipeline")
println("="^60)

# ============================================================================
# Phase 1: Load and Prepare Data
# ============================================================================
println("\n[Phase 1] Loading collected data...")

function load_all_sequences()
    files = readdir(DATA_DIR)
    seq_files = filter(f -> startswith(f, "spm_sequences") && endswith(f, ".jld2"), files)
    
    if isempty(seq_files)
        error("No sequence data found in $DATA_DIR. Please run data collection first.")
    end
    
    all_episodes = []
    for file in seq_files
        println("  Loading: $file")
        data = load(joinpath(DATA_DIR, file))
        episodes = data["episodes"]
        append!(all_episodes, episodes)
    end
    
    println("  Total episodes loaded: $(length(all_episodes))")
    return all_episodes
end

episodes = load_all_sequences()

# ============================================================================
# Phase 2: Data Augmentation
# ============================================================================
println("\n[Phase 2] Augmenting data...")

function augment_episodes(episodes; max_augmentations_per_episode=12)
    augmented_episodes = []
    
    for (ep_idx, episode) in enumerate(episodes)
        if ep_idx % 10 == 0
            println("  Augmenting episode $ep_idx/$(length(episodes))...")
        end
        
        T = size(episode["spm_t"], 4)
        if T < 5
            continue  # Skip very short episodes
        end
        
        # Original episode
        push!(augmented_episodes, episode)
        
        # Create augmented versions
        # We'll augment each transition and reconstruct episodes
        for aug_idx in 1:min(max_augmentations_per_episode, 11)  # 11 augmentations per transition
            aug_spm_t = zeros(Float64, size(episode["spm_t"]))
            aug_action_t = zeros(Float64, size(episode["action_t"]))
            aug_spm_next = zeros(Float64, size(episode["spm_next"]))
            
            for t in 1:T
                spm_t = episode["spm_t"][:,:,:,t]
                action_t = episode["action_t"][:,t]
                spm_next = episode["spm_next"][:,:,:,t]
                
                # Generate augmentations
                augs = augment_spm_transition(spm_t, action_t, spm_next, include_original=false)
                
                if aug_idx <= length(augs)
                    aug_spm_t[:,:,:,t] = augs[aug_idx][1]
                    aug_action_t[:,t] = augs[aug_idx][2]
                    aug_spm_next[:,:,:,t] = augs[aug_idx][3]
                end
            end
            
            aug_episode = Dict(
                "spm_t" => aug_spm_t,
                "action_t" => aug_action_t,
                "spm_next" => aug_spm_next
            )
            push!(augmented_episodes, aug_episode)
        end
    end
    
    println("  Original episodes: $(length(episodes))")
    println("  Augmented episodes: $(length(augmented_episodes))")
    
    return augmented_episodes
end

augmented_episodes = augment_episodes(episodes, max_augmentations_per_episode=5)

# Save augmented data
timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
aug_filename = joinpath(AUGMENTED_DIR, "augmented_data_$(timestamp).jld2")
save(aug_filename, Dict("episodes" => augmented_episodes))
println("  Saved augmented data to: $aug_filename")

# ============================================================================
# Phase 3: Prepare Training Data
# ============================================================================
println("\n[Phase 3] Preparing training sequences...")

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

sequences_X, sequences_Y = episodes_to_sequences(augmented_episodes)
println("  Total sequences: $(length(sequences_X))")

# Compute difficulty metric (sequence length)
difficulties = [length(seq) for seq in sequences_X]
difficulty_percentiles = [quantile(difficulties, p) for p in [0.33, 0.67]]

println("  Difficulty distribution:")
println("    Easy (< $(difficulty_percentiles[1])): $(sum(difficulties .< difficulty_percentiles[1]))")
println("    Medium ($(difficulty_percentiles[1])-$(difficulty_percentiles[2])): $(sum(difficulty_percentiles[1] .<= difficulties .< difficulty_percentiles[2]))")
println("    Hard (>= $(difficulty_percentiles[2])): $(sum(difficulties .>= difficulty_percentiles[2]))")

# Split by difficulty
easy_indices = findall(d -> d < difficulty_percentiles[1], difficulties)
medium_indices = findall(d -> difficulty_percentiles[1] <= d < difficulty_percentiles[2], difficulties)
hard_indices = findall(d -> d >= difficulty_percentiles[2], difficulties)

# ============================================================================
# Phase 4: Model Definition
# ============================================================================
println("\n[Phase 4] Defining model...")

input_size = 110  # 108 (SPM) + 2 (action)
spm_flat_size = 108

model_container = (
    d1 = Dense(input_size => HIDDEN_SIZE, relu),
    c  = GRUCell(HIDDEN_SIZE => HIDDEN_SIZE),
    d2 = Dense(HIDDEN_SIZE => spm_flat_size)
)

println("  Model: Dense($input_size => $HIDDEN_SIZE) -> GRUCell($HIDDEN_SIZE => $HIDDEN_SIZE) -> Dense($HIDDEN_SIZE => $spm_flat_size)")

# ============================================================================
# Phase 5: Training Functions
# ============================================================================

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

function train_stage(model, X, Y, stage_name; epochs=EPOCHS_PER_STAGE, lr=LEARNING_RATE_INITIAL)
    println("\n  Training stage: $stage_name")
    println("    Sequences: $(length(X))")
    println("    Epochs: $epochs")
    println("    Learning rate: $lr")
    
    opt = Flux.setup(Flux.Adam(lr), model)
    
    for epoch in 1:epochs
        perm = randperm(length(X))
        X_shuffled = X[perm]
        Y_shuffled = Y[perm]
        
        total_loss = 0.0
        for i in 1:length(X_shuffled)
            grads = Flux.gradient(model) do m
                sequence_loss(m, X_shuffled[i], Y_shuffled[i])
            end
            
            Flux.update!(opt, model, grads[1])
            total_loss += sequence_loss(model, X_shuffled[i], Y_shuffled[i])
        end
        
        avg_loss = total_loss / length(X_shuffled)
        
        if epoch % 5 == 0 || epoch == 1
            println("      Epoch $epoch: Loss = $(round(avg_loss, digits=4))")
        end
    end
    
    return model
end

# ============================================================================
# Phase 6: Curriculum Learning
# ============================================================================
println("\n[Phase 5] Curriculum Learning...")

# Stage 1: Easy sequences
println("\n  === Stage 1: Easy Sequences ===")
train_stage(model_container, sequences_X[easy_indices], sequences_Y[easy_indices], 
            "Easy", epochs=EPOCHS_PER_STAGE, lr=LEARNING_RATE_INITIAL)

# Stage 2: Easy + Medium
println("\n  === Stage 2: Easy + Medium Sequences ===")
combined_indices = vcat(easy_indices, medium_indices)
train_stage(model_container, sequences_X[combined_indices], sequences_Y[combined_indices], 
            "Easy+Medium", epochs=EPOCHS_PER_STAGE, lr=LEARNING_RATE_INITIAL)

# Stage 3: All sequences
println("\n  === Stage 3: All Sequences ===")
train_stage(model_container, sequences_X, sequences_Y, 
            "All", epochs=EPOCHS_PER_STAGE, lr=LEARNING_RATE_INITIAL)

# ============================================================================
# Phase 7: Fine-tuning
# ============================================================================
println("\n[Phase 6] Fine-tuning with low learning rate...")
train_stage(model_container, sequences_X, sequences_Y, 
            "Fine-tune", epochs=30, lr=LEARNING_RATE_FINETUNE)

# ============================================================================
# Phase 8: Evaluation
# ============================================================================
println("\n[Phase 7] Evaluating model...")

# Test on random subset
test_size = min(50, length(sequences_X))
test_indices = randperm(length(sequences_X))[1:test_size]

global total_test_loss = 0.0
channel_losses = zeros(3)  # Occupancy, radial vel, tangential vel

for idx in test_indices
    global total_test_loss
    loss = sequence_loss(model_container, sequences_X[idx], sequences_Y[idx])
    total_test_loss += loss
end

avg_test_loss = total_test_loss / test_size
println("  Average test loss: $(round(avg_test_loss, digits=4))")

# ============================================================================
# Phase 9: Save Model
# ============================================================================
println("\n[Phase 8] Saving model...")

final_model = Chain(
    model_container.d1, 
    Flux.Recur(model_container.c, zeros(Float32, HIDDEN_SIZE)), 
    model_container.d2
)

model_path = joinpath(MODEL_DIR, "gru_predictor_pretrained.jld2")
save(model_path, "model", final_model)

println("  Model saved to: $model_path")
println("\n" * "="^60)
println("Pre-training Complete!")
println("="^60)
println("\nTo use the pre-trained model:")
println("  1. Set predictor_type = :neural in Types.jl")
println("  2. Update load_predictor to use 'gru_predictor_pretrained.jld2'")
println("  3. Run ./scripts/run_experiment.sh")
