"""
FullTensorHaze - Phase 4: Full 3D Tensor Haze Implementation

3次元ヘイズテンソル H(r, θ, c) を用いた高度な精度制御。
各チャネル（占有、速度、接近性）に独立したヘイズ値を持ち、
チャネル毎に異なる信頼度を設定可能。

理論的背景:
- 「障害物は見えるが無視する」（占有チャネルのhaze増加）
- 「速度情報のみを重視する」（速度チャネルの精度向上）
- Per-channel precision modulation for advanced cognitive bias

データ構造:
- Haze Tensor: H(r, θ, c) ∈ [0,1]^(Nr × Nθ × Nc)
  - c=1: Occupancy channel
  - c=2: Radial velocity channel
  - c=3: Tangential velocity channel
"""
module FullTensorHaze

using LinearAlgebra
using Statistics
using ..Types
using ..MathUtils

export compute_full_tensor_haze, compute_channel_precision, FullTensorHazeParams
export apply_channel_mask, compute_weighted_surprise, compute_channel_entropy

"""
Full Tensor Haze parameters for per-channel control.
"""
Base.@kwdef struct FullTensorHazeParams
    # Per-channel haze weights
    w_occupancy::Float64 = 1.0      # Weight for occupancy channel
    w_radial_vel::Float64 = 0.5     # Weight for radial velocity channel
    w_tangential_vel::Float64 = 0.5 # Weight for tangential velocity channel

    # Per-channel thresholds
    Ω_threshold_occ::Float64 = 0.05  # Occupancy threshold
    Ω_threshold_rad::Float64 = 0.03  # Radial velocity threshold
    Ω_threshold_tan::Float64 = 0.03  # Tangential velocity threshold

    # Sigmoid parameters (per channel)
    α_occ::Float64 = 10.0           # Occupancy sensitivity
    α_rad::Float64 = 8.0            # Radial velocity sensitivity
    α_tan::Float64 = 8.0            # Tangential velocity sensitivity

    # Maximum haze levels (per channel)
    h_max_occ::Float64 = 0.8        # Max haze for occupancy
    h_max_rad::Float64 = 0.6        # Max haze for radial velocity
    h_max_tan::Float64 = 0.6        # Max haze for tangential velocity

    # Precision modulation exponent
    γ::Float64 = 2.0                # Haze attenuation exponent
end

"""
    compute_full_tensor_haze(spm::Array{Float64, 3}, params::FullTensorHazeParams)

Compute 3D haze tensor H(r, θ, c) with per-channel precision control.

Arguments:
- spm: SPM tensor (3, Nr, Nθ) - [Occupancy, Radial Vel, Tangential Vel]
- params: Full tensor haze parameters

Returns:
- haze_tensor: (3, Nr, Nθ) array of haze values
"""
function compute_full_tensor_haze(
    spm::Array{Float64, 3},
    params::FullTensorHazeParams
)::Array{Float64, 3}

    Nc, Nr, Nθ = size(spm)
    @assert Nc == 3 "SPM must have 3 channels"

    # Initialize haze tensor
    haze_tensor = zeros(Float64, Nc, Nr, Nθ)

    # Channel 1: Occupancy-based haze
    Ω_occ = sum(spm[1, :, :])
    x_occ = -params.α_occ * (Ω_occ - params.Ω_threshold_occ)
    h_occ = params.h_max_occ / (1.0 + exp(-x_occ))
    haze_tensor[1, :, :] .= h_occ * params.w_occupancy

    # Channel 2: Radial velocity-based haze
    Ω_rad = sum(abs.(spm[2, :, :]))
    x_rad = -params.α_rad * (Ω_rad - params.Ω_threshold_rad)
    h_rad = params.h_max_rad / (1.0 + exp(-x_rad))
    haze_tensor[2, :, :] .= h_rad * params.w_radial_vel

    # Channel 3: Tangential velocity-based haze
    Ω_tan = sum(abs.(spm[3, :, :]))
    x_tan = -params.α_tan * (Ω_tan - params.Ω_threshold_tan)
    h_tan = params.h_max_tan / (1.0 + exp(-x_tan))
    haze_tensor[3, :, :] .= h_tan * params.w_tangential_vel

    return haze_tensor
end

"""
    compute_channel_precision(
        spm::Array{Float64, 3},
        haze_tensor::Array{Float64, 3},
        params::FullTensorHazeParams
    )

Compute per-channel precision matrix modulated by haze tensor.

Arguments:
- spm: SPM tensor (3, Nr, Nθ)
- haze_tensor: Haze tensor (3, Nr, Nθ)
- params: Full tensor haze parameters

Returns:
- precision_tensor: (3, Nr, Nθ) array of precision values
"""
function compute_channel_precision(
    spm::Array{Float64, 3},
    haze_tensor::Array{Float64, 3},
    params::FullTensorHazeParams
)::Array{Float64, 3}

    Nc, Nr, Nθ = size(spm)
    @assert size(haze_tensor) == (Nc, Nr, Nθ) "Haze tensor must match SPM size"

    # Compute per-channel precision
    precision_tensor = zeros(Float64, Nc, Nr, Nθ)

    for c in 1:Nc
        for r in 1:Nr
            for θ in 1:Nθ
                # Precision modulation: Π = Π_base * (1 - h)^γ
                h = clamp(haze_tensor[c, r, θ], 0.0, 1.0)
                precision_tensor[c, r, θ] = (1.0 - h)^params.γ
            end
        end
    end

    return precision_tensor
end

"""
    apply_channel_mask(
        haze_tensor::Array{Float64, 3},
        channel_mask::Vector{Float64}
    )

Apply channel-wise mask to haze tensor for selective attention.

Example:
- [1.0, 0.0, 0.0]: Only occupancy channel is active (ignore velocity)
- [0.0, 1.0, 1.0]: Only velocity channels are active (ignore obstacles)

Arguments:
- haze_tensor: (3, Nr, Nθ) haze tensor
- channel_mask: (3,) vector of weights [0, 1]

Returns:
- masked_haze: Haze tensor with channel mask applied
"""
function apply_channel_mask(
    haze_tensor::Array{Float64, 3},
    channel_mask::Vector{Float64}
)::Array{Float64, 3}

    Nc, Nr, Nθ = size(haze_tensor)
    @assert length(channel_mask) == Nc "Channel mask must match number of channels"

    masked_haze = copy(haze_tensor)
    for c in 1:Nc
        masked_haze[c, :, :] .*= channel_mask[c]
    end

    return masked_haze
end

"""
    compute_weighted_surprise(
        spm_current::Array{Float64, 3},
        spm_previous::Array{Float64, 3},
        precision_tensor::Array{Float64, 3},
        channel_weights::Vector{Float64}
    )

Compute channel-weighted surprise (temporal prediction error).

Arguments:
- spm_current: Current SPM (3, Nr, Nθ)
- spm_previous: Previous SPM (3, Nr, Nθ)
- precision_tensor: Per-channel precision (3, Nr, Nθ)
- channel_weights: Per-channel importance weights (3,)

Returns:
- surprise: Scalar surprise value
"""
function compute_weighted_surprise(
    spm_current::Array{Float64, 3},
    spm_previous::Array{Float64, 3},
    precision_tensor::Array{Float64, 3},
    channel_weights::Vector{Float64}
)::Float64

    Nc, Nr, Nθ = size(spm_current)
    @assert size(spm_previous) == (Nc, Nr, Nθ) "SPM dimensions must match"
    @assert size(precision_tensor) == (Nc, Nr, Nθ) "Precision dimensions must match"
    @assert length(channel_weights) == Nc "Channel weights must match number of channels"

    surprise = 0.0

    for c in 1:Nc
        for r in 1:Nr
            for θ in 1:Nθ
                # Prediction error
                error = spm_current[c, r, θ] - spm_previous[c, r, θ]

                # Precision-weighted squared error
                precision = precision_tensor[c, r, θ]
                weight = channel_weights[c]

                surprise += weight * precision * error^2
            end
        end
    end

    return surprise
end

"""
    compute_channel_entropy(
        precision_tensor::Array{Float64, 3},
        channel_weights::Vector{Float64}
    )

Compute channel-weighted belief entropy.

H[q(s)] ∝ -log(det(Π)) ≈ -sum(log(Π_c))

Arguments:
- precision_tensor: Per-channel precision (3, Nr, Nθ)
- channel_weights: Per-channel importance weights (3,)

Returns:
- entropy: Scalar entropy value
"""
function compute_channel_entropy(
    precision_tensor::Array{Float64, 3},
    channel_weights::Vector{Float64}
)::Float64

    Nc, Nr, Nθ = size(precision_tensor)
    @assert length(channel_weights) == Nc "Channel weights must match number of channels"

    entropy = 0.0

    for c in 1:Nc
        for r in 1:Nr
            for θ in 1:Nθ
                # Avoid log(0)
                precision = max(precision_tensor[c, r, θ], 1e-8)
                weight = channel_weights[c]

                entropy -= weight * log(precision)
            end
        end
    end

    return entropy
end

end  # module FullTensorHaze
