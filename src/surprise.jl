"""
Surprise Calculation Module for EPH v5.6
Computes Surprise as VAE reconstruction error: S(u) = ||y[k] - VAE_recon(y[k], u[k])||²
"""
module SurpriseModule

using Statistics
using ..ActionVAEModel

export compute_surprise, compute_surprise_batch

"""
    compute_surprise(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64})

Compute Surprise for a single (SPM, action) pair.

Surprise is defined as the VAE reconstruction error:
    S(u) = ||y[k] - VAE_reconstruct(y[k], u[k])||²

This measures how "surprising" or unexpected the action is given the current state.
High Surprise → risky/unexpected action → should reduce precision (increase Haze).

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spm`: Current SPM (16, 16, 3)
- `u`: Action vector (2,) [vx, vy]

# Returns
- `surprise::Float64`: Reconstruction error (MSE)
"""
function compute_surprise(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64}
)
    # Convert to Float32 and add batch dimension
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Encode: (SPM, action) → (μ, logσ)
    μ, logσ = encode(vae, spm_input, u_input)

    # Use mean of latent distribution (deterministic)
    z = μ

    # Decode: (z, action) → reconstructed SPM_next
    # Note: This reconstructs the NEXT state, not current state
    # For Surprise, we want to measure how well (SPM, action) can be encoded
    # So we use the reconstruction path through the VAE
    spm_recon, _, _ = vae(spm_input, u_input)

    # Compute reconstruction error (MSE)
    # This measures prediction error: ||y[k+1]_true - y[k+1]_predicted||²
    # For Surprise based on current state encoding, we could also use KL divergence
    # But reconstruction error is simpler and more interpretable
    surprise = mean((spm_input .- spm_recon).^2)

    return Float64(surprise)
end

"""
    compute_surprise_batch(vae::ActionConditionedVAE, spms::Array{Float64, 4}, us::Matrix{Float64})

Compute Surprise for a batch of (SPM, action) pairs.

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spms`: Batch of SPMs (16, 16, 3, batch_size)
- `us`: Batch of actions (2, batch_size)

# Returns
- `surprises::Vector{Float64}`: Reconstruction errors for each sample
"""
function compute_surprise_batch(
    vae::ActionConditionedVAE,
    spms::Array{Float64, 4},
    us::Matrix{Float64}
)
    batch_size = size(spms, 4)

    # Convert to Float32
    spms_input = Float32.(spms)
    us_input = Float32.(us)

    # Forward pass
    spms_recon, μ, logσ = vae(spms_input, us_input)

    # Compute reconstruction error for each sample
    surprises = Float64[]
    for i in 1:batch_size
        spm_i = spms_input[:, :, :, i]
        spm_recon_i = spms_recon[:, :, :, i]
        surprise_i = mean((spm_i .- spm_recon_i).^2)
        push!(surprises, Float64(surprise_i))
    end

    return surprises
end

"""
    compute_surprise_from_latent_uncertainty(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64})

Alternative Surprise measure based on latent uncertainty (σ²).
This represents epistemic uncertainty in the latent representation.

Higher uncertainty → higher Surprise → more Haze needed.

# Returns
- `surprise::Float64`: Average latent variance
"""
function compute_surprise_from_latent_uncertainty(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64}
)
    # Convert to Float32 and add batch dimension
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Encode: (SPM, action) → (μ, logσ)
    μ, logσ = encode(vae, spm_input, u_input)

    # Compute variance: σ² = exp(2 * logσ)
    σ² = exp.(2f0 .* logσ)

    # Average variance across latent dimensions
    surprise = mean(σ²)

    return Float64(surprise)
end

"""
    normalize_surprise(surprise::Float64; s_min::Float64=0.0, s_max::Float64=1.0)

Normalize Surprise to [0, 1] range for stable control integration.

# Arguments
- `surprise`: Raw Surprise value
- `s_min`: Expected minimum Surprise (from calibration)
- `s_max`: Expected maximum Surprise (from calibration)

# Returns
- `normalized_surprise::Float64`: Surprise in [0, 1]
"""
function normalize_surprise(
    surprise::Float64;
    s_min::Float64=0.0,
    s_max::Float64=1.0
)
    if s_max <= s_min
        return 0.0
    end

    normalized = (surprise - s_min) / (s_max - s_min)
    return clamp(normalized, 0.0, 1.0)
end

end # module
