using Pkg
Pkg.activate(joinpath(@__DIR__, "../../src_julia"))
Pkg.instantiate()

using Flux
using JLD2
using FileIO
using Statistics
using Random
using LinearAlgebra

# --- Configuration ---
DATA_DIR = joinpath(@__DIR__, "../data/training")
MODEL_DIR = joinpath(@__DIR__, "../data/models")
mkpath(MODEL_DIR)

# Hyperparameters
BATCH_SIZE = 16  # Number of sequences per batch
EPOCHS = 50
LEARNING_RATE = 0.001
HIDDEN_SIZE = 128
SEQ_LEN = 50     # Truncated BPTT length (if sequences are very long)

# --- Data Loading ---
function load_latest_sequences()
    files = readdir(DATA_DIR)
    # Look for spm_sequences prefix
    jld2_files = filter(f -> startswith(f, "spm_sequences") && endswith(f, ".jld2"), files)
    if isempty(jld2_files)
        error("No sequence data found in $DATA_DIR")
    end
    latest_file = sort(jld2_files)[end]
    println("Loading sequences from: $latest_file")
    return load(joinpath(DATA_DIR, latest_file))
end

data_dict = load_latest_sequences()
episodes = data_dict["episodes"] # Vector of Dicts

println("Loaded $(length(episodes)) episodes.")

# --- Preprocessing ---
# Convert episodes to Flux-friendly format: Vector of Vector of inputs
# Input: [SPM_flat; Action] (110)
# Output: SPM_flat_next (108)

spm_flat_size = 6 * 6 * 3
input_size = spm_flat_size + 2

# We will train on sub-sequences for efficiency (Truncated BPTT)
# Or just full sequences if they are short enough.
# Let's use full sequences for now, but batch them.
# Flux expects a batch of sequences to be a Vector of Matrices, where each Matrix is (features, batch).
# Wait, for Recurrent models, Flux expects:
# Input: Vector (time) of Matrix (features, batch)

# Let's prepare data as a list of sequences.
# Each sequence is X: Vector{Vector{Float32}}, Y: Vector{Vector{Float32}}
# Where inner vector is feature vector.

sequences_X = []
sequences_Y = []

for ep in episodes
    spm_t = ep["spm_t"]      # (6,6,3, T)
    action_t = ep["action_t"] # (2, T)
    spm_next = ep["spm_next"] # (6,6,3, T)
    
    T = size(spm_t, 4)
    if T < 10 continue end # Skip very short episodes
    
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

N_seq = length(sequences_X)
println("Prepared $N_seq valid sequences.")

# Split train/test
split_idx = floor(Int, 0.8 * N_seq)
train_X = sequences_X[1:split_idx]
train_Y = sequences_Y[1:split_idx]
test_X = sequences_X[split_idx+1:end]
test_Y = sequences_Y[split_idx+1:end]

# --- Model Definition ---
# --- Model Definition ---
# Decomposed model for manual unrolling
# We wrap layers in a NamedTuple for Flux.setup compatibility
model_container = (
    d1 = Dense(input_size => HIDDEN_SIZE, relu),
    c  = GRUCell(HIDDEN_SIZE => HIDDEN_SIZE),
    d2 = Dense(HIDDEN_SIZE => spm_flat_size)
)

println("Model Architecture: Dense -> GRUCell -> Dense")

# --- Training ---

# Sequence loss with manual unrolling
function sequence_loss(m, x_seq, y_seq)
    # Initial state
    h = zeros(Float32, HIDDEN_SIZE) 
    
    loss = 0.0f0
    len = length(x_seq)
    
    for i in 1:len
        xt = x_seq[i]
        yt = y_seq[i]
        
        # Forward pass using model container m
        x1 = m.d1(xt)
        h, h_out = m.c(h, x1) 
        pred = m.d2(h_out)
        
        loss += Flux.mse(pred, yt)
    end
    
    return loss / len
end

# Setup optimizer for the container
opt = Flux.setup(Flux.Adam(LEARNING_RATE), model_container)

println("Starting training...")

for epoch in 1:EPOCHS
    # Shuffle sequences
    perm = randperm(length(train_X))
    train_X_shuffled = train_X[perm]
    train_Y_shuffled = train_Y[perm]
    
    total_train_loss = 0.0
    count = 0
    
    for i in 1:length(train_X_shuffled)
        x_seq = train_X_shuffled[i]
        y_seq = train_Y_shuffled[i]
        
        # Compute gradient w.r.t model_container
        grads = Flux.gradient(model_container) do m
            sequence_loss(m, x_seq, y_seq)
        end
        
        # Update parameters
        Flux.update!(opt, model_container, grads[1])
        
        # Re-eval for logging
        total_train_loss += sequence_loss(model_container, x_seq, y_seq) 
        count += 1
    end
    
    avg_train_loss = total_train_loss / count
    
    # Validation
    total_test_loss = 0.0
    for i in 1:length(test_X)
        total_test_loss += sequence_loss(model_container, test_X[i], test_Y[i])
    end
    avg_test_loss = isempty(test_X) ? 0.0 : total_test_loss / length(test_X)
    
    if epoch % 1 == 0
        println("Epoch $epoch: Train Loss = $avg_train_loss, Test Loss = $avg_test_loss")
    end
end

# --- Save Model ---
# Reconstruct Chain for compatibility with SPMPredictor loading
# Chain(Dense, Recur(GRUCell), Dense)
final_model = Chain(model_container.d1, Flux.Recur(model_container.c, zeros(Float32, HIDDEN_SIZE)), model_container.d2)

model_path = joinpath(MODEL_DIR, "gru_predictor_model.jld2")
save(model_path, "model", final_model)
println("Model saved to $model_path")
