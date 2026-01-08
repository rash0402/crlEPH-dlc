#!/usr/bin/env julia
# Quick test of new Autoencoder vs old VAE

using BSON
using Flux
using Statistics

include("../src/autoencoder.jl")
include("../src/vae.jl")

using .AutoencoderModel
using .VAEModel

println("🔍 Comparing Autoencoder vs VAE")
println("=" ^ 60)

# Test patterns
patterns = [
    ("Checkerboard", begin
        x = zeros(Float32, 16, 16, 3, 1)
        for i in 1:16, j in 1:16
            if (i + j) % 2 == 0
                x[i, j, :, 1] .= 1.0f0
            end
        end
        x
    end),
    ("Single Hotspot", begin
        x = zeros(Float32, 16, 16, 3, 1)
        x[8, 8, :, 1] .= 1.0f0
        x
    end),
    ("Random Noise", rand(Float32, 16, 16, 3, 1))
]

# Load models
println("Loading models...")
if isfile("models/autoencoder_latest.bson")
    BSON.@load "models/autoencoder_latest.bson" model
    ae_model = model
    println("✅ Autoencoder loaded")
else
    println("⚠️  Autoencoder not found, skipping")
    ae_model = nothing
end

if isfile("models/vae_latest.bson")
    BSON.@load "models/vae_latest.bson" model  
    vae_model = model
    println("✅ VAE loaded")
else
    println("⚠️  VAE not found, skipping")
    vae_model = nothing
end

println("\n" * "=" ^ 60)

for (name, x) in patterns
    println("\nPattern: $name")
    println("  Input mean: $(mean(x))")
    
    if ae_model !== nothing
        x_hat_ae, haze_ae = ae_model(x)
        mse_ae = Flux.mse(x_hat_ae, x)
        println("  Autoencoder:")
        println("    Output mean: $(mean(x_hat_ae))")
        println("    MSE: $(round(mse_ae, digits=4))")
        println("    Haze: $(round(Float64(haze_ae[1]), digits=4))")
    end
    
    if vae_model !== nothing
        x_hat_vae, μ, logσ = vae_model(x)
        mse_vae = Flux.mse(x_hat_vae, x)
        variance = exp.(2 .* logσ)
        haze_vae = mean(variance)
        println("  VAE:")
        println("   Output mean: $(mean(x_hat_vae))")
        println("    MSE: $(round(mse_vae, digits=4))")
        println("    Haze: $(round(Float64(haze_vae), digits=4))")
    end
end

println("\n" * "=" ^ 60)
println("✅ Comparison complete")
