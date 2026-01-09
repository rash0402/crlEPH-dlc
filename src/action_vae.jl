"""
Action-Conditioned VAE Module for EPH v5.4
Pattern B: Encoder is u-independent, Decoder is u-conditioned.

Key differences from standard VAE:
- Encoder: y[k] → q(z|y) = N(μ_z, σ_z²)  (u-independent)
- Decoder: (z, u) → ŷ[k+1]  (u-conditioned, predicts future SPM)
"""
module ActionVAEModel

using Flux
using Statistics
using Random

export ActionConditionedVAE, encode, decode, decode_with_u, reparameterize, action_vae_loss, compute_haze

"""
Action-Conditioned VAE struct.
- encoder: Maps y[k] → (μ_z, logσ_z) (u-independent)
- decoder: Maps (z, u) → ŷ[k+1] (u-conditioned)
"""
struct ActionConditionedVAE
    encoder          # y → (μ, logσ)
    z_to_features    # z → features (first part of decoder)
    u_projection     # u → u_features (project control input)
    decoder_conv     # combined features → ŷ
    latent_dim::Int
    u_dim::Int
end

# Register with Flux for parameter tracking
Flux.@layer ActionConditionedVAE

"""
    ActionConditionedVAE(latent_dim::Int=32, u_dim::Int=2)

Constructs an Action-Conditioned VAE for 16x16x3 SPM input.
- latent_dim: Dimension of latent space
- u_dim: Dimension of control input (default 2 for [ux, uy])
"""
function ActionConditionedVAE(latent_dim::Int=32, u_dim::Int=2)
    # ===== Encoder (u-independent) =====
    # Same structure as standard VAE
    enc_conv = Chain(
        Conv((3, 3), 3 => 16, relu, pad=1),
        MaxPool((2, 2)),
        Conv((3, 3), 16 => 32, relu, pad=1),
        MaxPool((2, 2)),
        Flux.flatten
    )
    
    flat_dim = 4 * 4 * 32  # 512
    enc_dense = Dense(flat_dim, latent_dim * 2)
    encoder = Chain(enc_conv, enc_dense)
    
    # ===== Decoder (u-conditioned) =====
    # Split into: z processing + u processing + combined decoding
    
    # Project z to base features
    z_hidden_dim = 256
    z_to_features = Dense(latent_dim, z_hidden_dim, relu)
    
    # Project u to features (small projection)
    u_projection = Dense(u_dim, 64, relu)
    
    # Combined features (z_features + u_features) → reconstruct
    combined_dim = z_hidden_dim + 64
    
    decoder_conv = Chain(
        Dense(combined_dim, flat_dim, relu),
        x -> reshape(x, 4, 4, 32, :),
        ConvTranspose((4, 4), 32 => 16, relu, stride=2, pad=1),
        ConvTranspose((4, 4), 16 => 3, sigmoid, stride=2, pad=1)
    )
    
    return ActionConditionedVAE(encoder, z_to_features, u_projection, decoder_conv, latent_dim, u_dim)
end

"""
Forward pass: encode current SPM, decode with given u to predict future SPM.
"""
function (m::ActionConditionedVAE)(x, u)
    μ, logσ = encode(m, x)
    z = reparameterize(μ, logσ)
    x_hat = decode_with_u(m, z, u)
    return x_hat, μ, logσ
end

"""
Encode input SPM to latent distribution parameters.
This is u-independent.
"""
function encode(m::ActionConditionedVAE, x)
    stats = m.encoder(x)
    μ = stats[1:m.latent_dim, :]
    logσ = stats[m.latent_dim+1:end, :]
    return μ, logσ
end

"""
Reparameterization trick: z = μ + σ * ε
"""
function reparameterize(μ, logσ)
    σ = exp.(logσ)
    ε = randn(eltype(μ), size(μ))
    return μ .+ σ .* ε
end

"""
Decode with control input u.
This is the u-conditioned part that predicts future SPM.
"""
function decode_with_u(m::ActionConditionedVAE, z, u)
    # Process z
    z_features = m.z_to_features(z)
    
    # Process u (ensure correct shape)
    if ndims(u) == 1
        u = reshape(u, :, 1)  # Add batch dimension
    end
    u_features = m.u_projection(u)
    
    # Concatenate features
    combined = vcat(z_features, u_features)
    
    # Decode to future SPM
    return m.decoder_conv(combined)
end

"""
Standard decode (for compatibility, uses zero action).
"""
function decode(m::ActionConditionedVAE, z)
    # Use zero action as default
    batch_size = size(z, 2)
    u_zero = zeros(Float32, m.u_dim, batch_size)
    return decode_with_u(m, z, u_zero)
end

"""
Training loss: Prediction loss + KL divergence.
- x_current: Current SPM y[k]
- u: Control input u[k]
- x_next: Next SPM y[k+1] (target)
"""
function action_vae_loss(m::ActionConditionedVAE, x_current, u, x_next; β=1.0f0)
    x_hat, μ, logσ = m(x_current, u)
    
    # Prediction Loss (MSE between predicted and actual next SPM)
    batch_size = size(x_current, 4)
    pred_loss = Flux.mse(x_hat, x_next) * (16 * 16 * 3)
    
    # KL Divergence (same as standard VAE)
    kld = -0.5f0 * mean(sum(1 .+ 2 .* logσ .- μ.^2 .- exp.(2 .* logσ), dims=1))
    
    total_loss = pred_loss + β * kld
    
    return total_loss, pred_loss, kld
end

"""
Compute Haze from current SPM (u-independent).
Returns mean variance of latent distribution.
"""
function compute_haze(m::ActionConditionedVAE, x)
    μ, logσ = encode(m, x)
    variance = exp.(2 .* logσ)
    return mean(variance, dims=1)
end

end # module
