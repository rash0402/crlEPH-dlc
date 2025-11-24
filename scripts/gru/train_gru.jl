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
DATA_DIR = joinpath(@__DIR__, "../../data/training")
MODEL_DIR = joinpath(@__DIR__, "../../data/models")
mkpath(MODEL_DIR)

# Hyperparameters (from environment variables or defaults)
BATCH_SIZE = parse(Int, get(ENV, "GRU_BATCH_SIZE", "16"))
EPOCHS = parse(Int, get(ENV, "GRU_EPOCHS", "50"))
LEARNING_RATE = parse(Float64, get(ENV, "GRU_LEARNING_RATE", "0.0001"))
HIDDEN_SIZE = parse(Int, get(ENV, "GRU_HIDDEN_SIZE", "128"))
SEQ_LEN = 50     # Truncated BPTT length (if sequences are very long)
GRADIENT_CLIP = parse(Float64, get(ENV, "GRU_GRADIENT_CLIP", "5.0"))

println("Hyperparameters:")
println("  BATCH_SIZE = $BATCH_SIZE")
println("  EPOCHS = $EPOCHS")
println("  LEARNING_RATE = $LEARNING_RATE")
println("  HIDDEN_SIZE = $HIDDEN_SIZE")
println("  GRADIENT_CLIP = $GRADIENT_CLIP")
println()

# --- Data Loading ---
function load_latest_sequences()
    files = readdir(DATA_DIR)
    # Look for spm_sequences prefix
    jld2_files = filter(f -> startswith(f, "spm_sequences") && endswith(f, ".jld2"), files)
    if isempty(jld2_files)
        error("No sequence data found in $DATA_DIR")
    end

    # Sort by modification time (newest first)
    jld2_files = sort(jld2_files, by = f -> stat(joinpath(DATA_DIR, f)).mtime, rev=true)

    # Check if specific file selection is provided via environment variable
    file_option = get(ENV, "GRU_DATA_FILES", "latest_1")

    selected_files = []

    if file_option == "latest_1"
        selected_files = [jld2_files[1]]
    elseif file_option == "latest_2"
        selected_files = jld2_files[1:min(2, length(jld2_files))]
    elseif file_option == "latest_3"
        selected_files = jld2_files[1:min(3, length(jld2_files))]
    elseif file_option == "all"
        selected_files = jld2_files
    elseif startswith(file_option, "date:")
        # Date-based selection: date:YYYY-MM-DD
        target_date = replace(file_option, "date:" => "")
        # Filter files by date prefix in filename
        selected_files = filter(f -> startswith(f, "spm_sequences_" * target_date), jld2_files)
        if isempty(selected_files)
            @warn "No files found for date $target_date, using latest file"
            selected_files = [jld2_files[1]]
        else
            println("  Date filter: $target_date → $(length(selected_files)) files found")
        end
    elseif endswith(file_option, ".jld2")
        # Specific file selected
        if file_option in jld2_files
            selected_files = [file_option]
        else
            @warn "Specified file $file_option not found, using latest file"
            selected_files = [jld2_files[1]]
        end
    else
        @warn "Unknown file option: $file_option, using latest file"
        selected_files = [jld2_files[1]]
    end

    println("Loading sequences from $(length(selected_files)) file(s):")
    for f in selected_files
        println("  - $f")
    end

    # Load all selected files and combine episodes
    all_episodes = []
    for file in selected_files
        data = load(joinpath(DATA_DIR, file))
        episodes = data["episodes"]
        append!(all_episodes, episodes)
        println("    Loaded $(length(episodes)) episodes from $file")
    end

    return Dict("episodes" => all_episodes)
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

# --- Data Normalization ---
# Collect all data for computing statistics
all_spm = []
all_actions = []

for ep in episodes
    spm_t = ep["spm_t"]
    action_t = ep["action_t"]
    push!(all_spm, vec(spm_t))
    push!(all_actions, vec(action_t))
end

spm_mean = mean(vcat(all_spm...))
spm_std = std(vcat(all_spm...)) + 1e-8
action_mean = mean(vcat(all_actions...))
action_std = std(vcat(all_actions...)) + 1e-8

println("Data Statistics:")
println("  SPM: mean=$spm_mean, std=$spm_std")
println("  Action: mean=$action_mean, std=$action_std")
println()

# Prepare normalized sequences
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

        # Normalize data
        s_t_norm = (s_t .- spm_mean) ./ spm_std
        a_t_norm = (a_t .- action_mean) ./ action_std
        s_next_norm = (s_next .- spm_mean) ./ spm_std

        seq_x[t] = vcat(Float32.(s_t_norm), Float32.(a_t_norm))
        seq_y[t] = Float32.(s_next_norm)
    end

    push!(sequences_X, seq_x)
    push!(sequences_Y, seq_y)
end

# Save normalization parameters
norm_params = Dict(
    "spm_mean" => spm_mean,
    "spm_std" => spm_std,
    "action_mean" => action_mean,
    "action_std" => action_std
)

N_seq = length(sequences_X)
println("Prepared $N_seq valid sequences (episodes).")

# Split train/test based on number of sequences
# Strategy: Use 80% of agents for training, 20% for testing
if N_seq == 1
    println()
    println("⚠️  Warning: Only 1 sequence available.")
    println("   Using same data for both train and test (not ideal).")
    println("   → Cannot detect overfitting")
    println("   → Recommendation: Collect data from multiple agents (5+ agents)")
    println()
    train_X = sequences_X
    train_Y = sequences_Y
    test_X = sequences_X
    test_Y = sequences_Y
elseif N_seq < 5
    println()
    println("⚠️  Warning: Only $N_seq sequences available.")
    println("   Using 1 sequence for test, rest for training.")
    println("   → Limited test set")
    println("   → Recommendation: Collect data from 10+ agents for better evaluation")
    println()
    split_idx = N_seq - 1  # Keep last sequence for test
    train_X = sequences_X[1:split_idx]
    train_Y = sequences_Y[1:split_idx]
    test_X = sequences_X[split_idx+1:end]
    test_Y = sequences_Y[split_idx+1:end]
else
    # Good: Multiple sequences, use proper 80/20 split
    split_idx = max(1, floor(Int, 0.8 * N_seq))
    train_X = sequences_X[1:split_idx]
    train_Y = sequences_Y[1:split_idx]
    test_X = sequences_X[split_idx+1:end]
    test_Y = sequences_Y[split_idx+1:end]

    println()
    println("✅ Good: $N_seq sequences available for diverse training")
    println("   Using 80/20 train/test split")
    println()
end

println("Training set: $(length(train_X)) sequences (agents)")
println("Test set: $(length(test_X)) sequences (agents)")
println()

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

        # Gradient clipping (simple approach - clip each parameter individually)
        if grads[1] !== nothing
            clipped_grad = Flux.fmap(grads[1]) do x
                if x isa AbstractArray
                    # Clip each gradient element to [-GRADIENT_CLIP, GRADIENT_CLIP]
                    return clamp.(x, -GRADIENT_CLIP, GRADIENT_CLIP)
                else
                    return x
                end
            end
            Flux.update!(opt, model_container, clipped_grad)
        end

        # Re-eval for logging
        loss_val = sequence_loss(model_container, x_seq, y_seq)
        if !isnan(loss_val)
            total_train_loss += loss_val
            count += 1
        end
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
# Save model container and normalization parameters
# Modern Flux (v0.14+) doesn't use Recur, so save the NamedTuple directly
model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
save(model_path, Dict(
    "model" => model_container,
    "norm_params" => norm_params,
    "hidden_size" => HIDDEN_SIZE
))
println("Model saved to $model_path")
println("  - Model container (d1, c, d2)")
println("  - Normalization parameters")
println("  - Hidden size: $HIDDEN_SIZE")
