"""
Social Value Functions for Active Inference (Phase 4 - Shepherding).

Implements SPM-based Pragmatic Value (Social Value) as described in
doc/technical_notes/SocialValue_ActiveInference.md v1.2

Key principles:
1. Action-dependent: M_social(a) via SPM prediction
2. Perceptually-grounded: Computed from SPM Occupancy channel
3. Biologically plausible: Agent-centric view (not omniscient)
4. Differentiable: Full gradient ∇_a M_social via Zygote

Feature functions:
- Angular Compactness: Entropy of SPM_occ angular distribution
- Goal Pushing: Cosine weighting to encourage rear positioning
- Radial Distribution: Preferred distance maintenance (optional)
- Velocity Coherence: SPM_radi/tang variance (optional)
"""
module SocialValue

using LinearAlgebra

export compute_angular_compactness, compute_goal_pushing
export compute_radial_distribution, compute_velocity_coherence
export compute_social_value_shepherding

"""
Angular Compactness from SPM Occupancy channel.

Computes entropy of angular occupancy distribution:
    H = -Σ P(θ) log P(θ)

Low entropy = compact (sheep clustered in specific direction)
High entropy = dispersed (sheep spread across all directions)

# Arguments
- `spm::Array{Float64, 3}`: Predicted SPM tensor (Nr, Nθ, Nc)
- `eps::Float64`: Small constant for numerical stability

# Returns
- `Float64`: Angular entropy (minimize for compactness)
"""
function compute_angular_compactness(
    spm::Array{Float64, 3};
    eps::Float64 = 1e-10
)::Float64

    # Extract occupancy channel (channel 1)
    # Shape: spm is (Nc, Nr, Nθ) in our implementation
    occ = spm[1, :, :]  # Shape: (Nr, Nθ)

    # Sum over radial bins to get angular distribution
    O_θ = vec(sum(occ, dims=1))  # Shape: (Nθ,)

    # Total occupancy
    total = sum(O_θ)

    if total < eps
        # No sheep visible → return neutral cost
        return 0.0
    end

    # Normalize to probability distribution
    P_θ = O_θ / total

    # Compute Shannon entropy
    H = 0.0
    for p in P_θ
        if p > eps
            H -= p * log(p)
        end
    end

    return H
end

"""
Goal Pushing: Encourage sheep to be positioned opposite to goal direction.

This creates incentive for dog to position itself behind sheep
(between sheep and goal is bad, behind sheep is good).

Uses cosine weighting to prefer occupancy at θ_target = θ_goal + π

# Arguments
- `spm::Array{Float64, 3}`: Predicted SPM tensor
- `θ_goal_idx::Int`: Goal direction in SPM angular coordinates (1-based)
- `Nθ::Int`: Number of angular bins

# Returns
- `Float64`: Goal pushing cost (minimize → sheep at θ_goal + π)
"""
function compute_goal_pushing(
    spm::Array{Float64, 3},
    θ_goal_idx::Int,
    Nθ::Int
)::Float64

    # Extract occupancy channel
    occ = spm[1, :, :]  # Shape: (Nr, Nθ)

    # Sum over radial bins
    O_θ = vec(sum(occ, dims=1))  # Shape: (Nθ,)

    # Target direction: opposite to goal (dog should be behind sheep)
    θ_target = mod1(θ_goal_idx + Nθ ÷ 2, Nθ)

    # Compute weighted cost
    cost = 0.0
    for θ in 1:Nθ
        # Angular distance from target (shortest path on circle)
        Δθ = min(abs(θ - θ_target), Nθ - abs(θ - θ_target))

        # Cosine weight (1.0 at target, -1.0 at opposite)
        w = cos(2π * Δθ / Nθ)

        # Minimize → wants high occupancy at θ_target
        # (negative sign: high occupancy at target → low cost)
        cost -= w * O_θ[θ]
    end

    return cost
end

"""
Radial Distribution: Prefer sheep at specific distance range.

Penalizes sheep that are too close (might scatter) or too far (lose control).

# Arguments
- `spm::Array{Float64, 3}`: Predicted SPM tensor
- `r_prefer::Int`: Preferred radial bin (1-based)

# Returns
- `Float64`: Radial distribution cost (minimize for preferred distance)
"""
function compute_radial_distribution(
    spm::Array{Float64, 3},
    r_prefer::Int
)::Float64

    # Extract occupancy
    occ = spm[1, :, :]  # Shape: (Nr, Nθ)

    Nr = size(occ, 1)

    # Sum over angular bins to get radial distribution
    O_r = vec(sum(occ, dims=2))  # Shape: (Nr,)

    # Weighted squared distance from preferred radius
    cost = 0.0
    for r in 1:Nr
        cost += (r - r_prefer)^2 * O_r[r]
    end

    return cost
end

"""
Velocity Coherence: Prefer unified sheep motion direction.

Uses SPM radial and tangential channels to assess velocity distribution.
Low variance = coherent motion (good for driving phase).

# Arguments
- `spm::Array{Float64, 3}`: Predicted SPM tensor

# Returns
- `Float64`: Velocity variance (minimize for coherent motion)
"""
function compute_velocity_coherence(
    spm::Array{Float64, 3}
)::Float64

    # Extract velocity channels
    radi = spm[2, :, :]  # Radial velocity
    tang = spm[3, :, :]  # Tangential velocity

    # Angular distribution of velocities
    V_radi_θ = vec(sum(radi, dims=1))
    V_tang_θ = vec(sum(tang, dims=1))

    # Variance across angles
    var_radi = var(V_radi_θ)
    var_tang = var(V_tang_θ)

    # Combined variance (minimize for coherent motion)
    return var_radi + var_tang
end

"""
Compute Social Value for Shepherding task.

Combines Angular Compactness and Goal Pushing with adaptive weights.

M_social(a) = λ_compact * H_angular + λ_goal * C_goal

# Arguments
- `spm_predicted::Array{Float64, 3}`: Predicted SPM from action a
- `θ_goal_idx::Int`: Goal direction in SPM coordinates
- `Nθ::Int`: Number of angular bins
- `λ_compact::Float64`: Weight for compactness term
- `λ_goal::Float64`: Weight for goal pushing term

# Returns
- `Float64`: Total social value (minimize)
"""
function compute_social_value_shepherding(
    spm_predicted::Array{Float64, 3},
    θ_goal_idx::Int,
    Nθ::Int;
    λ_compact::Float64 = 1.0,
    λ_goal::Float64 = 0.5
)::Float64

    # 1. Angular Compactness (entropy)
    M_compact = compute_angular_compactness(spm_predicted)

    # 2. Goal Pushing (cosine weighting)
    M_goal = compute_goal_pushing(spm_predicted, θ_goal_idx, Nθ)

    # 3. Combined Social Value
    M_social = λ_compact * M_compact + λ_goal * M_goal

    return M_social
end

end  # module SocialValue
