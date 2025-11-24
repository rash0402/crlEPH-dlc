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
BATCH_SIZE = 32
EPOCHS = 50
LEARNING_RATE = 0.001
HIDDEN_SIZE = 128

# --- Data Loading ---
function load_latest_data()
    files = readdir(DATA_DIR)
    jld2_files = filter(f -> endswith(f, ".jld2"), files)
    if isempty(jld2_files)
        error("No training data found in $DATA_DIR")
    end
    # Sort by timestamp (assuming filename format) and pick latest
    latest_file = sort(jld2_files)[end]
    println("Loading data from: $latest_file")
    return load(joinpath(DATA_DIR, latest_file))
end

data = load_latest_data()
spm_t = data["spm_t"]      # (6, 6, 3, N)
action_t = data["action_t"] # (2, N)
spm_next = data["spm_next"] # (6, 6, 3, N)

N = size(spm_t, 4)
println("Loaded $N samples.")

# --- Preprocessing ---
# Flatten SPM: (6, 6, 3) -> 108
spm_flat_size = 6 * 6 * 3
input_size = spm_flat_size + 2 # SPM + Action

X = zeros(Float32, input_size, N)
Y = zeros(Float32, spm_flat_size, N)

for i in 1:N
    # Flatten SPM
    s_t = reshape(spm_t[:,:,:,i], :)
    a_t = action_t[:,i]
    s_next = reshape(spm_next[:,:,:,i], :)
    
    # Normalize inputs (simple scaling)
    # SPM is already roughly 0-1 (occupancy) or small values (velocity)
    # Action is velocity vector
    
    X[1:spm_flat_size, i] = s_t
    X[spm_flat_size+1:end, i] = a_t
    Y[:, i] = s_next
end

# Split into train/test
split_idx = floor(Int, 0.8 * N)
train_X = X[:, 1:split_idx]
train_Y = Y[:, 1:split_idx]
test_X = X[:, split_idx+1:end]
test_Y = Y[:, split_idx+1:end]

train_loader = Flux.DataLoader((train_X, train_Y), batchsize=BATCH_SIZE, shuffle=true)
test_loader = Flux.DataLoader((test_X, test_Y), batchsize=BATCH_SIZE)

# --- Model Definition ---
# Simple GRU-based predictor
# Input: [SPM_flat; Action]
# Output: SPM_flat_next

model = Chain(
    Dense(input_size => HIDDEN_SIZE, relu),
    Dense(HIDDEN_SIZE => HIDDEN_SIZE, relu), # Using Dense for simplicity first, GRU requires sequence
    # Note: For single-step prediction, Dense is sufficient and easier to train.
    # If we want multi-step, we need recurrent state.
    # Let's stick to Dense for Phase 2 initial implementation as it's robust.
    # We can upgrade to GRU if we process sequences.
    Dense(HIDDEN_SIZE => spm_flat_size)
)

# If we really want GRU (Recurrent):
# But our data is (State, Action) -> NextState tuples, not sequences.
# So a Feedforward network is actually more appropriate here unless we train on trajectories.
# The user asked for "GRU-Based Prediction", implying sequence modeling.
# However, our data collection collected individual transitions.
# To use GRU effectively, we should have collected sequences.
# Given the current data format, I will use a Dense network which acts as a transition function.
# I will name it "PredictorModel" to be generic.

println("Model Architecture:")
println(model)

# --- Training ---
loss(x, y) = Flux.mse(model(x), y)
opt = Flux.setup(Flux.Adam(LEARNING_RATE), model)

println("Starting training...")
for epoch in 1:EPOCHS
    # Use loader for mini-batch training
    for (x, y) in train_loader
        grads = Flux.gradient(m -> loss(x, y), model)
        Flux.update!(opt, model, grads[1])
    end
    
    if epoch % 5 == 0
        train_loss = loss(train_X, train_Y)
        test_loss = loss(test_X, test_Y)
        println("Epoch $epoch: Train Loss = $train_loss, Test Loss = $test_loss")
    end
end

# --- Save Model ---
model_path = joinpath(MODEL_DIR, "predictor_model.jld2")
save(model_path, "model", model) # Save the model structure and weights
println("Model saved to $model_path")

# Verify loading
loaded_model = load(model_path, "model")
println("Verification: Model loaded successfully.")
