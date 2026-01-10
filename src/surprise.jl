"""
Surprise Calculation Module for EPH v5.6
Computes Surprise as epistemic uncertainty in latent representation.

For Pattern D VAE (which predicts NEXT states), Surprise is computed as:
    S(u) = mean(σ²(z | y[k], u[k]))

Where σ² is the latent variance from the encoder.
High uncertainty → High Surprise → Conservative behavior via Haze modulation.
"""
module SurpriseModule

using Statistics
using ..ActionVAEModel

export compute_surprise, compute_surprise_batch, compute_prediction_error

"""
    compute_surprise(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64})

Compute Surprise for a single (SPM, action) pair based on epistemic uncertainty.

For Pattern D VAE (decoder predicts NEXT state), Surprise is:
    S(u) = mean(σ²(z | y[k], u[k]))

This represents how uncertain the encoder is about the latent representation.
High uncertainty indicates the (state, action) pair is unfamiliar/risky.

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spm`: Current SPM (16, 16, 3)
- `u`: Action vector (2,) [vx, vy]

# Returns
- `surprise::Float64`: Average latent variance (epistemic uncertainty)
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

    # Compute variance: σ² = exp(2 * logσ)
    σ² = exp.(2f0 .* logσ)

    # Average variance across latent dimensions
    surprise = mean(σ²)

    return Float64(surprise)
end

"""
    compute_surprise_batch(vae::ActionConditionedVAE, spms::Array{Float64, 4}, us::Matrix{Float64})

Compute Surprise for a batch of (SPM, action) pairs based on epistemic uncertainty.

# Arguments
- `vae`: Trained ActionConditionedVAE model
- `spms`: Batch of SPMs (16, 16, 3, batch_size)
- `us`: Batch of actions (2, batch_size)

# Returns
- `surprises::Vector{Float64}`: Latent uncertainties for each sample
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

    # Compute variance: σ² = exp(2 * logσ)
    σ² = exp.(2f0 .* logσ)

    # Compute mean variance for each sample
    surprises = Float64[]
    for i in 1:batch_size
        surprise_i = mean(σ²[:, i])
        push!(surprises, Float64(surprise_i))
    end

    return surprises
end

"""
    compute_prediction_error(vae::ActionConditionedVAE, spm::Array{Float64, 3}, u::Vector{Float64}, spm_next::Array{Float64, 3})

Compute prediction error: ||y[k+1]_true - ŷ[k+1]||²

NOTE: This requires the NEXT state y[k+1], which is NOT available during runtime control.
This function is ONLY for validation/analysis purposes, NOT for Surprise-based control.

For runtime Surprise, use `compute_surprise()` which uses latent uncertainty.

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
