module AutoencoderModel

using Flux
using Statistics
using Random

export Autoencoder, encode, decode, ae_loss, compute_haze

"""
Deterministic Autoencoder for SPM reconstruction
Unlike VAE, this uses pure reconstruction objective without KL divergence
"""
struct Autoencoder
    encoder
    decoder
    uncertainty_head  # Separate head for Haze estimation
    latent_dim::Int
end

# Register with Flux to make parameters trainable
Flux.@layer Autoencoder

"""
    Autoencoder(latent_dim::Int=128)

Constructs a Deterministic Autoencoder for 16x16x3 SPM input.
Increased latent dimension (128 vs 32) to preserve more information.
"""
function Autoencoder(latent_dim::Int=128)
    # Encoder: 16x16x3 -> latent_128
    encoder = Chain(
        # 16x16x3 -> 8x8x16
        Conv((3, 3), 3 => 16, relu, pad=1),
        MaxPool((2, 2)),
        
        # 8x8x16 -> 4x4x32
        Conv((3, 3), 16 => 32, relu, pad=1),
        MaxPool((2, 2)),
        
        # Flatten and project to latent space
        Flux.flatten,
        Dense(4 * 4 * 32, latent_dim, relu)
    )
    
    # Decoder: latent_128 -> 16x16x3
    decoder = Chain(
        Dense(latent_dim, 4 * 4 * 32, relu),
        
        # Reshape to 4x4x32
        x -> reshape(x, 4, 4, 32, :),
        
        # 4x4x32 -> 8x8x16 using ConvTranspose
        ConvTranspose((4, 4), 32 => 16, relu, stride=2, pad=1),
        
        # 8x8x16 -> 16x16x3 using ConvTranspose
        ConvTranspose((4, 4), 16 => 3, sigmoid, stride=2, pad=1)
    )
    
    # Uncertainty head: latent -> scalar haze estimate
    # Uses softplus activation to ensure positive output
    uncertainty_head = Chain(
        Dense(latent_dim, 64, relu),
        Dense(64, 1, softplus)
    )
    
    return Autoencoder(encoder, decoder, uncertainty_head, latent_dim)
end

"""
Forward pass through autoencoder
Returns: (reconstruction, haze_estimate)
"""
function (m::Autoencoder)(x)
    z = m.encoder(x)
    x_hat = m.decoder(z)
    haze = m.uncertainty_head(z)
    return x_hat, haze
end

"""
Encode input to latent representation
"""
function encode(m::Autoencoder, x)
    return m.encoder(x)
end

"""
Decode latent representation to reconstruction
"""
function decode(m::Autoencoder, z)
    return m.decoder(z)
end

"""
    ae_loss(m::Autoencoder, x; haze_weight=0.01f0)

Computes autoencoder loss: Reconstruction Loss + Haze Regularization

Unlike VAE, this uses PURE reconstruction objective without KL divergence.
Optional haze regularization keeps uncertainty estimates in reasonable range.
"""
function ae_loss(m::Autoencoder, x; haze_weight=0.01f0)
    x_hat, haze = m(x)
    
    # Pure reconstruction loss (MSE scaled to image dimensions)
    batch_size = size(x, 4)
    recon_loss = Flux.mse(x_hat, x) * (16 * 16 * 3)
    
    # Optional: Regularize haze to be in reasonable range [0, 1]
    # This prevents extreme uncertainty values
    haze_reg = mean((haze .- 0.5f0).^2) * haze_weight
    
    total_loss = recon_loss + haze_reg
    
    return total_loss, recon_loss, haze_reg
end

"""
    compute_haze(m::Autoencoder, x)

Estimates 'Haze' (uncertainty) from the input SPM.
Returns the learned uncertainty estimate from the uncertainty head.
"""
function compute_haze(m::Autoencoder, x)
    z = m.encoder(x)
    haze = m.uncertainty_head(z)
    
    # Return as vector for batch compatibility
    return vec(haze)
end

end # module
