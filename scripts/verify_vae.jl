
# Script to verify VAE implementation
include("../src/vae.jl")
using .VAEModel
using Flux
using Random

function test_vae()
    println("🔍 Testing VAE Architecture...")
    
    # 1. Instantiate
    latent_dim = 32
    model = VAE(latent_dim)
    println("✅ VAE instantiated. Latent dim: $latent_dim")
    
    # 2. Create dummy input (Batch size 5)
    # Shape: (16, 16, 3, 5)
    x = rand(Float32, 16, 16, 3, 5)
    println("✅ Dummy input created: $(size(x))")
    
    # 3. Forward pass
    x_hat, μ, logσ = model(x)
    println("✅ Forward pass successful.")
    println("   Output shape: $(size(x_hat))")
    println("   Mean shape: $(size(μ))")
    println("   LogVar shape: $(size(logσ))")
    
    # 4. Check dimensions
    @assert size(x_hat) == size(x) "Output shape mismatch!"
    @assert size(μ) == (latent_dim, 5) "Latent mean shape mismatch!"
    
    # 5. Test Loss function
    loss, recon, kld = vae_loss(model, x)
    println("✅ Loss calculation successful.")
    println("   Total Loss: $loss")
    println("   Recon Loss: $recon")
    println("   KLD: $kld")
    
    # 6. Test Haze computation
    haze = compute_haze(model, x)
    println("✅ Haze computation successful.")
    println("   Haze shape: $(size(haze))")
    println("   Haze values: $haze")
    
    println("🎉 VAE Verification Complete!")
end

test_vae()
