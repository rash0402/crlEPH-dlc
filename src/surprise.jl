"""
Surprise Calculation Module for EPH v5.6

Computes Surprise as reconstruction error following Active Inference principles.

Following proposal_v5.6.md Lines 256-273:
    S(u) = ||y[k] - VAE_recon(y[k], u)||²

Where VAE_recon(y, u) = Decoder(Encoder(y, u), u)

This represents how well the VAE can reconstruct the current SPM given the (SPM, action) pair.
High reconstruction error indicates the pair is unfamiliar/OOD.
"""
module SurpriseModule

using Statistics
using LinearAlgebra
using ..ActionVAEModel

export compute_surprise, compute_surprise_batch, compute_prediction_error, compute_surprise_hybrid

"""
    compute_surprise(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64})

Compute Surprise for a single (SPM, action) pair as reconstruction error.

Following proposal_v5.6.md Lines 256-273:
S(u) = ||y[k] - VAE_recon(y[k], u)||²

Where:
VAE_recon(y, u) = Decoder(Encoder(y, u), u)

Steps:
1. Encoder: (y[k], u) → q(z|y,u) = N(μ_z, σ_z²)
2. Use mean μ_z (deterministic)
3. Decoder: (z=μ_z, u) → y_recon
4. Compute squared error between original SPM and reconstruction

This represents the reconstruction error: how well the VAE can reconstruct the current SPM
given the (SPM, action) pair. High reconstruction error indicates the pair is unfamiliar/OOD.

Theory Reference: proposal_v5.6.md Lines 256-280
Active Inference Principle: Agents minimize Surprise = maintain predictable states

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spm`: Current SPM (16, 16, 3)
- `u`: Action vector (2,) [vx, vy]

# Returns
- `surprise::Float64`: Reconstruction MSE (Active Inference standard definition)
"""
function compute_surprise(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64}
)
    # Convert to Float32 and add batch dimension
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Step 1 & 2: Encode (SPM, action) → μ_z (deterministic, use mean)
    μ_z, logσ_z = encode(vae, spm_input, u_input)

    # Step 3: Decode (z=μ_z, u) → SPM_reconstruction
    spm_recon = decode_with_u(vae, μ_z, u_input)

    # Step 4: Compute reconstruction error (MSE)
    # Note: Both spm_input and spm_recon are (16, 16, 3, 1)
    reconstruction_error = mean((spm_input .- spm_recon).^2)

    return Float64(reconstruction_error)
end

"""
    compute_surprise_batch(vae::ActionConditionedVAE, spms::Array{Float64, 4}, us::Matrix{Float64})

Compute Surprise for a batch of (SPM, action) pairs as reconstruction error.

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

    # Encode
    μ, logσ = encode(vae, spms_input, us_input)

    # Decode
    spms_recon = decode_with_u(vae, μ, us_input)

    # Compute reconstruction error for each sample
    surprises = Float64[]
    for i in 1:batch_size
        error_i = mean((spms_input[:, :, :, i] .- spms_recon[:, :, :, i]).^2)
        push!(surprises, Float64(error_i))
    end

    return surprises
end

"""
    compute_prediction_error(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64}, spm_next::Array{Float64, 3})

Compute prediction error: ||y[k+1]_true - ŷ[k+1]||²

NOTE: This requires the NEXT state y[k+1], which is NOT available during runtime control.
This function is ONLY for validation/analysis purposes, NOT for Surprise-based control.

For runtime Surprise, use `compute_surprise()` which uses reconstruction error.

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spm`: Current SPM y[k] (16, 16, 3)
- `u`: Action vector u[k] (2,)
- `spm_next`: Next SPM y[k+1] (16, 16, 3) - REQUIRED

# Returns
- `error::Float64`: Prediction MSE
"""
function compute_prediction_error(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64},
    spm_next::Array{Float64, 3}
)
    # Convert to Float32 and add batch dimension
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))
    spm_next_input = Float32.(reshape(spm_next, 16, 16, 3, 1))

    # Predict next state
    spm_next_pred, _, _ = vae(spm_input, u_input)

    # Compute prediction error
    error = mean((spm_next_input .- spm_next_pred).^2)

    return Float64(error)
end

"""
    compute_surprise_hybrid(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64}; α::Float64=0.5, β::Float64=0.5)

Compute hybrid Surprise combining reconstruction error and latent uncertainty.

For VAE trained on Haze=0 data, this formulation ensures monotonic coupling
between runtime Haze and Surprise through information-theoretic degradation.

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spm`: Current SPM (16, 16, 3)
- `u`: Action vector (2,) [vx, vy]
- `α`: Weight for reconstruction error (default: 0.5)
- `β`: Weight for latent uncertainty (default: 0.5)

# Returns
- `surprise::Float64`: Total Surprise = α·S_reconstruction + β·S_latent

# Theory (v5.6.1)
When VAE is trained on Haze=0 (max resolution) data:
- Runtime Haze>0 → Information loss → Higher reconstruction error
- Larger actions → Higher prediction difficulty
- Monotonic coupling: ∂S/∂Haze > 0 (theoretically guaranteed)
"""
function compute_surprise_hybrid(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64};
    α::Float64=0.5,
    β::Float64=0.5
)
    # Convert to Float32 and add batch dimension
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Encode: (SPM, action) → (μ, logσ)
    μ, logσ = encode(vae, spm_input, u_input)

    # Reconstruction error (primary component)
    spm_recon = decode_with_u(vae, μ, u_input)
    S_reconstruction = mean((spm_input .- spm_recon).^2)

    # Latent uncertainty (secondary component)
    σ² = exp.(2f0 .* logσ)
    S_latent = mean(σ²)

    # Total Surprise
    S_total = α * S_reconstruction + β * S_latent

    return Float64(S_total)
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
