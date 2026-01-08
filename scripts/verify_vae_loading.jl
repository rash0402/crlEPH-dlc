
# Script to verify loading of trained VAE model
using BSON
using Flux
using Statistics
include("../src/vae.jl")
using .VAEModel

function verify_loading()
    model_path = "models/vae_latest.bson"
    println("🔍 Verifying VAE Model Loading from: $model_path")
    
    if !isfile(model_path)
        println("❌ Model file not found!")
        return
    end
    
    try
        # Load model
        # Note: We need to know the variable name used during saving.
        # Usually it's 'model'.
        loaded_data = BSON.load(model_path)
        keys_found = collect(keys(loaded_data))
        println("   Keys in BSON file: $keys_found")
        
        if :model in keys_found
            model = loaded_data[:model]
        else
            println("⚠️ 'model' key not found. Trying to extract first value...")
            model = first(values(loaded_data))
        end
        
        println("✅ Model loaded structure: $(typeof(model))")
        
        # Test inference
        println("Testing inference with random input...")
        # Shape: (16, 16, 3, 1) - Single sample
        x = rand(Float32, 16, 16, 3, 1)
        
        x_hat, μ, logσ = model(x)
        
        println("✅ Inference successful!")
        println("   Input range: $(minimum(x)) - $(maximum(x))")
        println("   Output range: $(minimum(x_hat)) - $(maximum(x_hat))")
        println("   Latent mean range: $(minimum(μ)) - $(maximum(μ))")
        
        if maximum(x_hat) == 0.0 && minimum(x_hat) == 0.0
            println("⚠️ WARNING: Output is all zeros!")
        else
            println("✅ Output contains non-zero values.")
        end
        
    catch e
        println("❌ Error during loading or inference:")
        showerror(stdout, e)
        println()
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

verify_loading()
