#!/usr/bin/env julia
# VAE Evaluation Script
# Evaluates prediction accuracy and gradient computations

using Pkg
Pkg.activate(".")

include("../src/vae.jl")
include("../src/data_loader.jl")

using .VAEModel
using .DataLoader
using Flux
using BSON
using Statistics
using LinearAlgebra
using Printf

# ========== Configuration ==========
const MODEL_PATH = "models/vae_latest.bson"
const DATA_DIR = "data"
const N_SAMPLES = 10  # Number of samples to visualize

println("🔍 VAE Evaluation Script")
println("=" ^ 60)

# ========== Load Model ==========
println("\n📦 Loading trained model...")
if !isfile(MODEL_PATH)
    error("❌ Model not found at $MODEL_PATH. Train the model first with scripts/train_vae.jl")
end

BSON.@load MODEL_PATH model
println("✅ Model loaded from: $MODEL_PATH")

# ========== Load Data ==========
println("\n📂 Loading test data...")
data = load_spm_data(DATA_DIR)
if data === nothing
    error("❌ No data found. Run simulation first to generate data.")
end

# Create test set
_, test_loader = get_data_loader(data, 32, shuffle=false, split_ratio=0.8)
println("✅ Test data loaded: $(length(test_loader)) batches")

# ========== 1. Reconstruction Accuracy ==========
println("\n" * "=" ^ 60)
println("📊 1. RECONSTRUCTION ACCURACY")
println("=" ^ 60)

total_mse = 0.0f0
total_mae = 0.0f0
n_batches = 0

for x_batch in test_loader
    x_hat, _, _ = model(x_batch)
    
    # MSE (Mean Squared Error)
    mse = mean((x_hat .- x_batch).^2)
    global total_mse += mse
    
    # MAE (Mean Absolute Error)
    mae = mean(abs.(x_hat .- x_batch))
    global total_mae += mae
    
    global n_batches += 1
end

avg_mse = total_mse / n_batches
avg_mae = total_mae / n_batches

println("Average Reconstruction Error:")
@printf("  MSE: %.6f\n", avg_mse)
@printf("  MAE: %.6f\n", avg_mae)
@printf("  RMSE: %.6f\n", sqrt(avg_mse))

# ========== 2. Sample Visualization ==========
println("\n" * "=" ^ 60)
println("📸 2. SAMPLE RECONSTRUCTIONS")
println("=" ^ 60)

# Get first batch for visualization
x_sample = first(test_loader)
x_recon, μ, logσ = model(x_sample)

println("\nShowing first $N_SAMPLES samples:")
for i in 1:min(N_SAMPLES, size(x_sample, 4))
    original = x_sample[:, :, :, i]
    reconstructed = x_recon[:, :, :, i]
    
    # Compute per-sample error
    sample_mse = mean((reconstructed .- original).^2)
    sample_mae = mean(abs.(reconstructed .- original))
    
    # Channel-wise statistics
    ch1_orig = mean(original[:, :, 1])
    ch1_recon = mean(reconstructed[:, :, 1])
    
    @printf("\nSample %d:\n", i)
    @printf("  MSE: %.6f, MAE: %.6f\n", sample_mse, sample_mae)
    @printf("  Ch1 Original mean: %.4f, Reconstructed mean: %.4f\n", ch1_orig, ch1_recon)
end

# ========== 3. Gradient Check ==========
println("\n" * "=" ^ 60)
println("🔬 3. GRADIENT FLOW CHECK")
println("=" ^ 60)

# Take a small batch
x_test = x_sample[:, :, :, 1:5]

# Compute gradients
loss, grads = Flux.withgradient(model) do m
    total_loss, recon, kld = vae_loss(m, x_test)
    total_loss
end

println("\nGradient Statistics:")
if grads[1] !== nothing
    # Compute gradient norm for the entire model
    grad_norm = norm([norm(g) for g in Flux.destructure(grads[1])[1] if !isnothing(g)])
    
    @printf("  Model gradient norm: %.6f\n", grad_norm)
    
    if grad_norm > 0
        println("\n✅ Gradients are flowing (non-zero norm detected)")
    else
        println("\n⚠️  Warning: Gradient norm is zero")
    end
else
    println("⚠️  Warning: No gradients computed")
end

# ========== 4. Latent Space Analysis ==========
println("\n" * "=" ^ 60)
println("🌌 4. LATENT SPACE ANALYSIS")
println("=" ^ 60)

# Encode all test samples
all_μ = []
all_σ = []

for x_batch in test_loader
    μ_batch, logσ_batch = encode(model, x_batch)
    push!(all_μ, μ_batch)
    push!(all_σ, exp.(logσ_batch))
end

# Concatenate
μ_all = hcat(all_μ...)
σ_all = hcat(all_σ...)

println("\nLatent Space Statistics:")
@printf("  Mean of μ: %.6f (should be close to 0)\n", mean(μ_all))
@printf("  Std of μ: %.6f (should be close to 1)\n", std(μ_all))
@printf("  Mean of σ: %.6f (should be close to 1)\n", mean(σ_all))
@printf("  Std of σ: %.6f\n", std(σ_all))

# Check for posterior collapse
collapsed_dims = sum(std(μ_all, dims=2) .< 0.01)
@printf("\n  Collapsed dimensions (std < 0.01): %d / %d\n", collapsed_dims, size(μ_all, 1))

if collapsed_dims > size(μ_all, 1) / 2
    println("  ⚠️  Warning: More than half of latent dimensions have collapsed!")
else
    println("  ✅ Latent space is well-utilized")
end

# ========== 5. Loss Components ==========
println("\n" * "=" ^ 60)
println("📈 5. LOSS COMPONENT ANALYSIS")
println("=" ^ 60)

total_loss_val = 0.0f0
total_recon_val = 0.0f0
total_kld_val = 0.0f0

for x_batch in test_loader
    loss_val, recon_val, kld_val = vae_loss(model, x_batch)
    total_loss_val += loss_val
    total_recon_val += recon_val
    total_kld_val += kld_val
end

n_test = length(test_loader)
@printf("\nAverage Loss Components:\n")
@printf("  Total Loss: %.4f\n", total_loss_val / n_test)
@printf("  Reconstruction: %.4f\n", total_recon_val / n_test)
@printf("  KL Divergence: %.4f\n", total_kld_val / n_test)
@printf("  Recon/KLD Ratio: %.4f\n", (total_recon_val / n_test) / (total_kld_val / n_test))

# ========== Summary ==========
println("\n" * "=" ^ 60)
println("📋 EVALUATION SUMMARY")
println("=" ^ 60)

println("\n✅ Reconstruction Quality:")
if avg_mse < 0.01
    println("  Excellent (MSE < 0.01)")
elseif avg_mse < 0.05
    println("  Good (MSE < 0.05)")
elseif avg_mse < 0.1
    println("  Acceptable (MSE < 0.1)")
else
    println("  ⚠️  Poor (MSE ≥ 0.1) - Consider retraining")
end

println("\n✅ Latent Space:")
if collapsed_dims < size(μ_all, 1) / 4
    println("  Healthy (< 25% collapsed dimensions)")
else
    println("  ⚠️  Needs attention (many collapsed dimensions)")
end

println("\n🎉 Evaluation complete!")
