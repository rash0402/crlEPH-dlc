module VAEModel

using Flux
using Statistics
using Random

export VAE, encode, decode, reparameterize, vae_loss, compute_haze

struct VAE
    encoder
    decoder
    latent_dim::Int
end

# Register the VAE struct with Flux to make parameters trainable
Flux.@layer VAE

"""
    VAE(input_dim::Tuple, latent_dim::Int)

Constructs a Convolutional VAE for 16x16x3 input.
"""
function VAE(latent_dim::Int=32)
    # Encoder
    # Input: 16x16x3
    enc_conv = Chain(
        # 16x16x3 -> 8x8x16
        Conv((3, 3), 3 => 16, relu, pad=1),
        MaxPool((2, 2)),
        
        # 8x8x16 -> 4x4x32
        Conv((3, 3), 16 => 32, relu, pad=1),
        MaxPool((2, 2)),
        
        Flux.flatten
    )
    
    # Calculate flattened size: 4 * 4 * 32 = 512
    flat_dim = 4 * 4 * 32
    
    # Project to latent space (Mean and Log-Variance)
    enc_dense = Dense(flat_dim, latent_dim * 2)
    
    encoder = Chain(enc_conv, enc_dense)
    
    # Decoder
    dec_dense = Dense(latent_dim, flat_dim, relu)
    
    dec_conv = Chain(
        # Reshape to 4x4x32
        x -> reshape(x, 4, 4, 32, :),
        
        # 4x4x32 -> 8x8x16
        Upsample(2),
        Conv((3, 3), 32 => 16, relu, pad=1),
        
        # 8x8x16 -> 16x16x3
        Upsample(2),
        Conv((3, 3), 16 => 3, sigmoid, pad=1)
    )
    
    decoder = Chain(dec_dense, dec_conv)
    
    return VAE(encoder, decoder, latent_dim)
end

function (m::VAE)(x)
    μ, logσ = encode(m, x)
    z = reparameterize(μ, logσ)
    x_hat = decode(m, z)
    return x_hat, μ, logσ
end

function encode(m::VAE, x)
    # Forward pass through encoder
    stats = m.encoder(x)
    
    # Split into mean (μ) and log-std (logσ)
    # Usually logσ stands for log(std), sometimes log(var).
    # Here we assume output is [μ; logσ]
    
    μ = stats[1:m.latent_dim, :]
    logσ = stats[m.latent_dim+1:end, :]
    
    return μ, logσ
end

function reparameterize(μ, logσ)
    # z = μ + σ * ε
    σ = exp.(logσ)
    ε = randn(eltype(μ), size(μ))
    return μ .+ σ .* ε
end

function decode(m::VAE, z)
    return m.decoder(z)
end

"""
    vae_loss(m::VAE, x; β=1.0)

Computes the VAE loss: Reconstruction Loss + β * KL Divergence.
"""
function vae_loss(m::VAE, x; β=1.0f0)
    x_hat, μ, logσ = m(x)
    
    # Reconstruction Loss (MSE)
    # We use sum over features, mean over batch
    # Input x is typically in range [0, 1] (sigmoid output)
    batch_size = size(x, 4)
    recon = Flux.mse(x_hat, x) * (16 * 16 * 3)
    
    # KL Divergence
    # D_KL(N(μ, σ²) || N(0, 1)) = -0.5 * Σ (1 + log(σ²) - μ² - σ²)
    # log(σ²) = 2 * logσ
    # σ² = exp(2 * logσ)
    kld = -0.5f0 * mean(sum(1 .+ 2 .* logσ .- μ.^2 .- exp.(2 .* logσ), dims=1))
    
    start_loss = recon + β * kld
    
    return start_loss, recon, kld
end

"""
    compute_haze(m::VAE, x)

Estimates 'Haze' (uncertainty) from the input SPM.
Returns the mean variance of the latent distribution.
"""
function compute_haze(m::VAE, x)
    μ, logσ = encode(m, x)
    # Variance = σ² = exp(2 * logσ)
    variance = exp.(2 .* logσ)
    
    # Return mean variance across latent dimensions
    # Result is a vector of size (batch_size,) if x is a batch
    return mean(variance, dims=1)
end

end # module
