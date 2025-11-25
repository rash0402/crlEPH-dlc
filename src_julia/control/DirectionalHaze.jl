"""
DirectionalHaze - Angular Selective Haze Modulation

方向選択的ヘイズ変調：SPMの角度方向に応じて異なるヘイズ値を適用。

用途:
- 中央視野（前方）の障害物を無視 → 直進性向上
- 周辺視野の障害物を重視 → 側面回避強化

理論的背景:
- 生物の視覚注意は方向選択的（中心窩 vs 周辺視野）
- タスク依存の注意配分（探索 vs 回避）
"""
module DirectionalHaze

using LinearAlgebra
using Statistics
using ..Types

export apply_directional_haze_mask, DirectionalHazeParams

"""
Directional Haze parameters for angular selective attention.
"""
Base.@kwdef struct DirectionalHazeParams
    # Angular region definitions (in radians)
    central_angle_range::Float64 = 20.0 * π / 180.0  # ±20 degrees

    # Haze multipliers for each region
    central_haze_multiplier::Float64 = 2.0    # Increase haze in central vision
    peripheral_haze_multiplier::Float64 = 0.0  # Decrease haze in peripheral vision

    # Transition smoothing
    smooth_transition::Bool = true             # Smooth vs hard boundary
    transition_width::Float64 = 10.0 * π / 180.0  # Transition zone width
end

"""
    apply_directional_haze_mask(
        haze_matrix::Matrix{Float64},
        params::DirectionalHazeParams,
        Nr::Int,
        Nθ::Int
    )

Apply angular-dependent haze modulation to a 2D haze matrix.

Arguments:
- haze_matrix: (Nr, Nθ) spatial haze matrix
- params: Directional haze parameters
- Nr: Number of radial bins
- Nθ: Number of angular bins

Returns:
- modulated_haze: Haze matrix with directional modulation applied
"""
function apply_directional_haze_mask(
    haze_matrix::Matrix{Float64},
    params::DirectionalHazeParams,
    Nr::Int,
    Nθ::Int
)::Matrix{Float64}

    modulated_haze = copy(haze_matrix)

    # Angular bin size (assuming symmetric around 0)
    θ_range = 2π
    dθ = θ_range / Nθ

    for θ_idx in 1:Nθ
        # Compute angle for this bin (centered at 0, forward direction)
        # Assuming θ=0 is forward, range is [-π, π]
        θ = -π + (θ_idx - 0.5) * dθ

        # Normalize to [-π, π]
        θ = atan(sin(θ), cos(θ))

        # Compute haze multiplier based on angle
        multiplier = if params.smooth_transition
            # Smooth transition using sigmoid
            compute_smooth_multiplier(abs(θ), params)
        else
            # Hard boundary
            compute_hard_multiplier(abs(θ), params)
        end

        # Apply multiplier to all radial bins in this angular column
        for r_idx in 1:Nr
            modulated_haze[r_idx, θ_idx] *= multiplier
        end
    end

    return modulated_haze
end

"""
Compute smooth multiplier using sigmoid transition.
"""
function compute_smooth_multiplier(abs_angle::Float64, params::DirectionalHazeParams)::Float64
    central_angle = params.central_angle_range
    transition_width = params.transition_width

    # Sigmoid transition
    # x < central_angle → 1.0 (central)
    # x > central_angle + transition_width → 0.0 (peripheral)

    if abs_angle < central_angle
        # Central region
        t = 1.0
    elseif abs_angle > central_angle + transition_width
        # Peripheral region
        t = 0.0
    else
        # Transition zone
        x = (abs_angle - central_angle) / transition_width
        t = 1.0 - x  # Linear transition
        # Or use smooth sigmoid: t = 1.0 / (1.0 + exp(10.0 * (x - 0.5)))
    end

    # Interpolate between central and peripheral multipliers
    multiplier = t * params.central_haze_multiplier + (1.0 - t) * params.peripheral_haze_multiplier

    return multiplier
end

"""
Compute hard boundary multiplier (no transition).
"""
function compute_hard_multiplier(abs_angle::Float64, params::DirectionalHazeParams)::Float64
    if abs_angle <= params.central_angle_range
        return params.central_haze_multiplier
    else
        return params.peripheral_haze_multiplier
    end
end

"""
    apply_directional_haze_to_tensor(
        haze_tensor::Array{Float64, 3},
        params::DirectionalHazeParams
    )

Apply directional haze modulation to a 3D haze tensor (for Phase 3 Full Tensor Haze).

Arguments:
- haze_tensor: (3, Nr, Nθ) full tensor haze
- params: Directional haze parameters

Returns:
- modulated_tensor: Haze tensor with directional modulation applied to all channels
"""
function apply_directional_haze_to_tensor(
    haze_tensor::Array{Float64, 3},
    params::DirectionalHazeParams
)::Array{Float64, 3}

    Nc, Nr, Nθ = size(haze_tensor)
    modulated_tensor = copy(haze_tensor)

    # Apply directional modulation to each channel
    for c in 1:Nc
        modulated_tensor[c, :, :] = apply_directional_haze_mask(
            haze_tensor[c, :, :],
            params,
            Nr,
            Nθ
        )
    end

    return modulated_tensor
end

end  # module DirectionalHaze
