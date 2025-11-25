"""
SelfHaze Module - Self-Hazing Computation for Active Inference

Implements self-haze computation as belief entropy modulation:
- h_self(Ω) = h_max · σ(-α(Ω - Ω_threshold))
- Π(r,θ; h) = Π_base(r,θ) · (1-h)^γ

When agents perceive fewer neighbors (low occupancy Ω), self-haze increases,
reducing precision and increasing belief entropy H[q(s)], which drives
epistemic foraging (information-seeking exploration).
"""
module SelfHaze

using ..Types
using LinearAlgebra

export compute_self_haze, compute_self_haze_matrix, compute_precision_matrix, compute_precision_matrix_exponential, compute_belief_entropy

"""
    compute_self_haze(spm::Array{Float64, 3}, params::EPHParams) -> Float64

Compute self-haze level based on SPM occupancy using sigmoid function.

# Arguments
- `spm::Array{Float64, 3}`: Saliency Polar Map (3, Nr, Nθ)
- `params::EPHParams`: EPH parameters

# Returns
- `h_self::Float64`: Self-haze level in [0, h_max]

# Theory
When occupancy Ω < Ω_threshold, self-haze increases:
    h_self(Ω) = h_max · σ(-α(Ω - Ω_threshold))
    where σ(x) = 1 / (1 + exp(-x))

Low occupancy → High self-haze → Low precision → High entropy → Exploration
"""
function compute_self_haze(spm::Array{Float64, 3}, params::EPHParams)::Float64
    # Extract occupancy channel (first channel of SPM)
    occupancy = spm[1, :, :]

    # Compute normalized occupancy Ω
    # Ω ∈ [0, 1] representing the fraction of FOV occupied
    Ω = sum(occupancy) / length(occupancy)

    # Sigmoid function: σ(x) = 1 / (1 + exp(-x))
    # Note: Negative sign ensures h_self increases when Ω decreases
    logit = -params.α * (Ω - params.Ω_threshold)
    h_self = params.h_max / (1.0 + exp(-logit))

    return h_self
end

"""
    compute_self_haze_matrix(spm::Array{Float64, 3}, params::EPHParams) -> Matrix{Float64}

Compute 2D spatial self-haze matrix based on local occupancy per SPM bin.

# Arguments
- `spm::Array{Float64, 3}`: Saliency Polar Map (3, Nr, Nθ)
- `params::EPHParams`: EPH parameters

# Returns
- `h_matrix::Matrix{Float64}`: Self-haze matrix (Nr, Nθ) ∈ [0, h_max]

# Theory (Phase 2 Implementation)
Spatial haze modulation based on local occupancy:
    h_self(r, θ) = h_max · σ(-α(Ω(r,θ) - Ω_threshold))

This allows directional and distance-dependent precision control:
- High occupancy bins (obstacles present) → Low haze → High precision → Strong avoidance
- Low occupancy bins (free space) → High haze → Low precision → Weak constraints

# Notes
- For Phase 1 compatibility, use mean(h_matrix) to get scalar haze
- Currently uses same sigmoid for all bins; future: distance-dependent α, Ω_threshold
"""
function compute_self_haze_matrix(spm::Array{Float64, 3}, params::EPHParams)::Matrix{Float64}
    Nr = size(spm, 2)
    Nθ = size(spm, 3)

    # Extract occupancy channel
    occupancy = spm[1, :, :]  # (Nr, Nθ)

    # Initialize haze matrix
    h_matrix = zeros(Float64, Nr, Nθ)

    # Compute haze for each SPM bin based on local occupancy
    for r in 1:Nr
        for θ in 1:Nθ
            # Local occupancy value (already normalized in SPM computation)
            Ω_local = occupancy[r, θ]

            # Sigmoid function: h increases when occupancy is LOW
            # (inverse relationship: low Ω → high h → low Π → exploration)
            logit = -params.α * (Ω_local - params.Ω_threshold)
            h_matrix[r, θ] = params.h_max / (1.0 + exp(-logit))
        end
    end

    return h_matrix
end

"""
    compute_precision_matrix(spm::Array{Float64, 3}, h_self::Float64, params::EPHParams) -> Matrix{Float64}

Compute haze-modulated precision matrix for SPM observations.

# Arguments
- `spm::Array{Float64, 3}`: Saliency Polar Map (3, Nr, Nθ)
- `h_self::Float64`: Current self-haze level
- `params::EPHParams`: EPH parameters

# Returns
- `Π::Matrix{Float64}`: Diagonal precision matrix (flattened SPM dimension)

# Theory
Precision matrix is modulated by self-haze:
    Π(r,θ; h) = Π_base(r,θ) · (1-h)^γ

High haze → Low precision → High uncertainty → Entropy-driven exploration

The base precision Π_base(r,θ) decays with distance:
    Π_base(r,θ) = Π_max · exp(-decay_rate · r)
"""
function compute_precision_matrix(spm::Array{Float64, 3}, h_self::Float64,
                                   params::EPHParams)::Matrix{Float64}
    Nr = size(spm, 2)
    Nθ = size(spm, 3)

    # Haze modulation factor: (1-h)^γ
    haze_factor = (1.0 - h_self)^params.γ

    # Create vector of normalized radii: (0 to Nr-1) / (Nr-1)
    r_indices = collect(0:(Nr-1))
    r_norm = r_indices ./ max(Nr - 1, 1)
    
    # Compute base precision for each radius (vector of length Nr)
    Π_base_vec = params.Π_max .* exp.(-params.decay_rate .* r_norm)
    
    # Expand to (Nr, Nθ) matrix
    # Use repeat to replicate across theta dimension
    Π_base_mat = repeat(Π_base_vec, 1, Nθ)
    
    # Apply haze modulation and ensure numerical stability
    Π = max.(Π_base_mat .* haze_factor, 1e-6)

    return Π
end

"""
    compute_precision_matrix(spm::Array{Float64, 3}, h_matrix::Matrix{Float64}, params::EPHParams) -> Matrix{Float64}

Compute haze-modulated precision matrix using 2D spatial haze (Phase 2).

# Arguments
- `spm::Array{Float64, 3}`: Saliency Polar Map (3, Nr, Nθ)
- `h_matrix::Matrix{Float64}`: Spatial self-haze matrix (Nr, Nθ)
- `params::EPHParams`: EPH parameters

# Returns
- `Π::Matrix{Float64}`: Spatially-varying precision matrix (Nr, Nθ)

# Theory
Spatial precision modulation:
    Π(r,θ) = Π_base(r,θ) · (1-h(r,θ))^γ

Each SPM bin has independent precision based on local haze:
- h(r,θ) high → Π(r,θ) low → ignore that direction (lubricant)
- h(r,θ) low → Π(r,θ) high → pay attention (repellent)
"""
function compute_precision_matrix(spm::Array{Float64, 3}, h_matrix::Matrix{Float64},
                                   params::EPHParams)::Matrix{Float64}
    Nr = size(spm, 2)
    Nθ = size(spm, 3)

    # Check dimension consistency
    if size(h_matrix) != (Nr, Nθ)
        error("Haze matrix dimensions $(size(h_matrix)) do not match SPM dimensions ($Nr, $Nθ)")
    end

    # Haze modulation factor for each bin: (1-h)^γ
    haze_factor = (1.0 .- h_matrix).^params.γ

    # Create vector of normalized radii
    r_indices = collect(0:(Nr-1))
    r_norm = r_indices ./ max(Nr - 1, 1)

    # Compute base precision for each radius (vector of length Nr)
    Π_base_vec = params.Π_max .* exp.(-params.decay_rate .* r_norm)

    # Expand to (Nr, Nθ) matrix
    Π_base_mat = repeat(Π_base_vec, 1, Nθ)

    # Apply spatially-varying haze modulation and ensure numerical stability
    Π = max.(Π_base_mat .* haze_factor, 1e-6)

    return Π
end

"""
    compute_precision_matrix_exponential(spm::Array{Float64, 3}, h_matrix::Matrix{Float64},
                                         params::EPHParams; α::Float64=2.0) -> Matrix{Float64}

Compute haze-modulated precision matrix using EXPONENTIAL decay function (mathematically robust).

# Arguments
- `spm::Array{Float64, 3}`: Saliency Polar Map (3, Nr, Nθ)
- `h_matrix::Matrix{Float64}`: Spatial self-haze matrix (Nr, Nθ)
- `params::EPHParams`: EPH parameters
- `α::Float64`: Decay rate parameter (default: 2.0)

# Returns
- `Π::Matrix{Float64}`: Spatially-varying precision matrix (Nr, Nθ)

# Theory
Exponential precision modulation (h ∈ [0, ∞) domain):
    Π(r,θ) = Π_base(r,θ) · exp(-α·h(r,θ))

Advantages over (1-h)^γ:
- Valid for ANY h value (no h > 1.0 breakdown)
- Smooth decay for h > 1.0
- Theoretically consistent with Free Energy Principle

Decay behavior:
- h = 0.0 → exp(0) = 1.0 (no modulation)
- h = 0.5 → exp(-1.0) = 0.368 (moderate reduction)
- h = 1.0 → exp(-2.0) = 0.135 (strong reduction)
- h = 5.0 → exp(-10.0) ≈ 0.0 (nearly zero)

Each SPM bin has independent precision based on local haze:
- h(r,θ) high → Π(r,θ) low → ignore that direction (lubricant)
- h(r,θ) low → Π(r,θ) high → pay attention (repellent)
"""
function compute_precision_matrix_exponential(
    spm::Array{Float64, 3},
    h_matrix::Matrix{Float64},
    params::EPHParams;
    α::Float64=2.0
)::Matrix{Float64}
    Nr = size(spm, 2)
    Nθ = size(spm, 3)

    # Check dimension consistency
    if size(h_matrix) != (Nr, Nθ)
        error("Haze matrix dimensions $(size(h_matrix)) do not match SPM dimensions ($Nr, $Nθ)")
    end

    # Exponential haze modulation factor: exp(-α·h)
    # This is valid for ANY h ∈ [0, ∞), unlike (1-h)^γ which breaks at h > 1.0
    haze_factor = exp.(-α .* h_matrix)

    # Create vector of normalized radii
    r_indices = collect(0:(Nr-1))
    r_norm = r_indices ./ max(Nr - 1, 1)

    # Compute base precision for each radius (vector of length Nr)
    Π_base_vec = params.Π_max .* exp.(-params.decay_rate .* r_norm)

    # Expand to (Nr, Nθ) matrix
    Π_base_mat = repeat(Π_base_vec, 1, Nθ)

    # Apply exponential haze modulation and ensure numerical stability
    Π = max.(Π_base_mat .* haze_factor, 1e-6)

    return Π
end

"""
    compute_belief_entropy(Π::Matrix{Float64}) -> Float64

Compute belief entropy H[q(s)] from precision matrix.

# Arguments
- `Π::Matrix{Float64}`: Precision matrix (inverse covariance)

# Returns
- `H::Float64`: Belief entropy (in nats)

# Theory
For Gaussian belief q(s) ~ N(μ, Σ):
    H[q(s)] = (1/2) log det(2πe·Σ)
           = (1/2) log det(2πe) - (1/2) log det(Π)
           ≈ -(1/2) log det(Π)  [ignoring constant]

High precision → Low entropy (confident)
Low precision → High entropy (uncertain)
"""
function compute_belief_entropy(Π::Matrix{Float64})::Float64
    # Flatten precision matrix for determinant computation
    # Here we approximate: det(Π) ≈ prod(diag(Π)) for diagonal matrix
    Π_vec = vec(Π)

    # Compute log determinant (sum of log eigenvalues for diagonal)
    # H = -(1/2) log det(Π) = -(1/2) Σ log(Π_i)
    log_det_Π = sum(log.(Π_vec .+ 1e-10))  # Add epsilon for numerical stability

    H = -0.5 * log_det_Π

    return max(H, 0.0)  # Entropy cannot be negative
end

"""
    compute_occupancy_stats(spm::Array{Float64, 3}) -> Dict{String, Float64}

Compute occupancy statistics for debugging and analysis.

# Returns
Dictionary with:
- "total_occupancy": Sum of all occupancy values
- "normalized_occupancy": Occupancy normalized by FOV size
- "max_occupancy": Maximum occupancy in any bin
- "num_occupied_bins": Number of bins with occupancy > threshold
"""
function compute_occupancy_stats(spm::Array{Float64, 3})::Dict{String, Float64}
    occupancy = spm[1, :, :]

    return Dict(
        "total_occupancy" => sum(occupancy),
        "normalized_occupancy" => sum(occupancy) / length(occupancy),
        "max_occupancy" => maximum(occupancy),
        "num_occupied_bins" => count(x -> x > 0.1, occupancy)
    )
end

end  # module SelfHaze
