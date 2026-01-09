"""
Action-Dependent Uncertainty VAE Module for EPH v5.5 (Pattern D)
Pattern D: Encoder is u-dependent, Decoder is u-conditioned.

Key differences from Pattern B:
- Encoder: (y[k], u[k]) → q(z|y, u) = N(μ_z, σ_z²)
  - Latent distribution depends on ACTION as well as state.
  - This allows "Haze" (uncertainty) to be action-dependent (Counterfactual Haze).
  
- Decoder: (z, u[k]) → ŷ[k+1]
  - Predicts future SPM given latent state and action.
"""
module ActionVAEModel

using Flux
using Statistics
using Random

export ActionConditionedVAE, encode, decode, decode_with_u, reparameterize, action_vae_loss, compute_haze

"""
Action-Dependent VAE struct.
- encoder_conv: Process SPM component of input
- encoder_u: Process action component of input
- encoder_joint: Combine features → (μ, logσ)
- z_to_features: z → features (first part of decoder)
- u_projection: u → u_features (project control input for decoder)
- decoder_conv: combined features → ŷ
"""
struct ActionConditionedVAE
    # Encoder components
    encoder_conv     # y → y_features
    encoder_u        # u → u_enc_features
    encoder_joint    # (y_feat, u_enc_feat) → (μ, logσ)
    
    # Decoder components
    z_to_features    # z → z_features
    u_projection     # u → u_dec_features
    decoder_conv     # (z_feat, u_dec_feat) → ŷ
    
    latent_dim::Int
    u_dim::Int
end

# Register with Flux for parameter tracking
Flux.@layer ActionConditionedVAE

"""
    ActionConditionedVAE(latent_dim::Int=32, u_dim::Int=2)

Constructs an Action-Dependent VAE (Pattern D).
"""
function ActionConditionedVAE(latent_dim::Int=32, u_dim::Int=2)
    # ===== Encoder (Action-Dependent) =====
    # 1. Process SPM
    enc_conv = Chain(
        Conv((3, 3), 3 => 16, relu, pad=1),
        MaxPool((2, 2)),
        Conv((3, 3), 16 => 32, relu, pad=1),
        MaxPool((2, 2)),
        Flux.flatten
    )
    flat_dim = 4 * 4 * 32  # 512
    
    # 2. Process Action (for encoder)
    enc_u = Dense(u_dim, 64, relu)
    
    # 3. Joint processing -> Latent
    enc_joint_input = flat_dim + 64
    enc_joint = Chain(
        Dense(enc_joint_input, 256, relu),
        Dense(256, latent_dim * 2) # Output μ and logσ
    )
    
    # ===== Decoder (Action-Conditioned) =====
    # Split into: z processing + u processing + combined decoding
    
    # Project z to base features
    z_hidden_dim = 256
    z_to_features = Dense(latent_dim, z_hidden_dim, relu)
    
    # Project u to features (for decoder)
    u_dec = Dense(u_dim, 64, relu)
    
    # Combined features (z_features + u_features) → reconstruct
    combined_dim = z_hidden_dim + 64
    
    decoder_conv = Chain(
        Dense(combined_dim, flat_dim, relu),
        x -> reshape(x, 4, 4, 32, :),
        ConvTranspose((4, 4), 32 => 16, relu, stride=2, pad=1),
        ConvTranspose((4, 4), 16 => 3, sigmoid, stride=2, pad=1)
    )
    
    return ActionConditionedVAE(enc_conv, enc_u, enc_joint, z_to_features, u_dec, decoder_conv, latent_dim, u_dim)
end

"""
Forward pass: encode current SPM+Action, decode with same u to predict future SPM.
x: Current SPM
u: Action taken
"""
function (m::ActionConditionedVAE)(x, u)
    μ, logσ = encode(m, x, u)
    z = reparameterize(μ, logσ)
    x_hat = decode_with_u(m, z, u)
    return x_hat, μ, logσ
end

"""
Encode input SPM AND Action to latent distribution parameters.
Pattern D: Latent space depends on action.
"""
function encode(m::ActionConditionedVAE, x, u)
    # Process SPM
    y_feat = m.encoder_conv(x)
    
    # Process Action
    if ndims(u) == 1
        u = reshape(u, :, 1)  # Add batch dimension
    end
    u_feat = m.encoder_u(u)
    
    # Concatenate
    joint_feat = vcat(y_feat, u_feat)
    
    # Predict Latent Params
    stats = m.encoder_joint(joint_feat)
    
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
Predicts future SPM given z (which encodes (y,u) transition context) and u.
"""
function decode_with_u(m::ActionConditionedVAE, z, u)
    # Process z
    z_features = m.z_to_features(z)
    
    # Process u 
    if ndims(u) == 1
        u = reshape(u, :, 1)
    end
    u_features = m.u_projection(u)
    
    # Concatenate features
    combined = vcat(z_features, u_features)
    
    # Decode to future SPM
    return m.decoder_conv(combined)
end

"""
Standard decode (for compatibility, uses zero action).
WARNING: In Pattern D, z is learned conditioned on non-zero actions. 
Using zero action here gives the prediction for "Stopping".
"""
function decode(m::ActionConditionedVAE, z)
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
    pred_loss = Flux.mse(x_hat, x_next) * (16 * 16 * 3)
    
    # KL Divergence
    kld = -0.5f0 * mean(sum(1 .+ 2 .* logσ .- μ.^2 .- exp.(2 .* logσ), dims=1))
    
    total_loss = pred_loss + β * kld
    
    return total_loss, pred_loss, kld
end

"""
Compute Haze from current SPM AND Action (Pattern D).
Returns mean variance of latent distribution.
"""
function compute_haze(m::ActionConditionedVAE, x, u)
    μ, logσ = encode(m, x, u)
    variance = exp.(2 .* logσ)
    return mean(variance, dims=1)
end

end # module
