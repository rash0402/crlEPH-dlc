"""
EPH v5.6 Configuration
Extended parameters for Surprise integration and Haze modulation
"""

module ConfigV56

using ..Config: SPMParams, WorldParams, AgentParams, CommParams
using ..Config: DEFAULT_SPM, DEFAULT_WORLD, DEFAULT_AGENT, DEFAULT_COMM

export ControlParamsV56, ExperimentConditionV56
export DEFAULT_CONTROL_V56
export A0_BASELINE, A1_HAZE_ONLY, A2_SURPRISE_ONLY, A3_EPH_V56

# ===== v5.6 Experiment Conditions =====
"""
v5.6 Experiment conditions for ablation study
- A0_BASELINE: No Haze, No Surprise (complete baseline)
- A1_HAZE_ONLY: Fixed Haze modulation only
- A2_SURPRISE_ONLY: Surprise term only (no Haze)
- A3_EPH_V56: Full EPH v5.6 (Haze + Surprise)
"""
@enum ExperimentConditionV56 begin
    A0_BASELINE = 0
    A1_HAZE_ONLY = 1
    A2_SURPRISE_ONLY = 2
    A3_EPH_V56 = 3
end

# ===== Control Parameters for v5.6 =====
struct ControlParamsV56
    # Existing parameters
    eta::Float64                    # Learning rate for gradient descent
    sigma_safe::Float64             # Safety distance for saliency calculation
    T_th::Float64                   # TTC threshold for risk calculation
    beta_ttc::Float64               # Sigmoid steepness for TTC
    epsilon::Float64                # Small value for numerical stability
    exploration_rate::Float64       # Probability of random action
    exploration_noise::Float64      # Std of Gaussian noise added to actions

    # v5.6 New parameters
    lambda_goal::Float64            # Goal attraction weight
    lambda_safety::Float64          # Safety/collision avoidance weight
    lambda_surprise::Float64        # Surprise penalty weight ★NEW★
    haze_fixed::Float64             # Fixed Haze value (Phase 1-5) ★NEW★
    n_candidates::Int               # Number of action candidates for sampling-based optimization ★NEW★
    sigma_noise::Float64            # Noise std for candidate generation ★NEW★

    # Experiment configuration
    experiment_condition::ExperimentConditionV56  # Ablation study condition
    use_vae::Bool                   # Enable VAE for prediction & Surprise
end

function ControlParamsV56(;
    # Existing parameters
    eta=1.0,
    sigma_safe=3.0,
    T_th=2.0,
    beta_ttc=2.0,
    epsilon=1e-6,
    exploration_rate=0.0,
    exploration_noise=0.0,

    # v5.6 New parameters
    lambda_goal=1.0,
    lambda_safety=10.0,           # 衝突回避の重み（チューニング対象）
    lambda_surprise=1.0,           # Surprise の重み（チューニング対象）★NEW★
    haze_fixed=0.5,                # 固定Haze値（Phase 1-5）★NEW★
    n_candidates=10,               # サンプル数（チューニング対象）★NEW★
    sigma_noise=0.3,               # 候補生成ノイズ（チューニング対象）★NEW★

    # Experiment configuration
    experiment_condition=A3_EPH_V56,  # Default: full EPH v5.6
    use_vae=true                      # Default: VAE enabled
)
    ControlParamsV56(
        eta, sigma_safe, T_th, beta_ttc, epsilon,
        exploration_rate, exploration_noise,
        lambda_goal, lambda_safety, lambda_surprise,
        haze_fixed, n_candidates, sigma_noise,
        experiment_condition, use_vae
    )
end

# ===== Free Energy Components (for v5.6) =====
"""
Free Energy computation helpers
F(u) = λ_goal·F_goal(u) + λ_safety·F_safety(u) + λ_surprise·S(u)
"""
module FreeEnergyV56

"""
Goal-seeking term: F_goal(u) = ||v + u*dt - v_goal||²
"""
function compute_goal_term(vel::Vector{Float64}, action::Vector{Float64},
                          goal_vel::Vector{Float64}, dt::Float64)
    predicted_vel = vel + action * dt
    return sum((predicted_vel - goal_vel).^2)
end

"""
Safety term: F_safety(u) = sum of collision risks
Uses SPM-based saliency calculation
"""
function compute_safety_term(spm::Array{Float64, 3},
                            sigma_safe::Float64, T_th::Float64, beta_ttc::Float64)
    # 3チャンネルSPM: [proximity, velocity, crossing]
    # Safety = sum of saliency across all channels
    # Implementation depends on specific saliency calculation
    # Placeholder: sum of proximity channel
    return sum(spm[:, :, 1])  # Channel 1 = proximity
end

"""
Surprise term: S(u) = ||y[k] - VAE_recon(y[k], u)||²
Reconstruction error from Action-Dependent VAE
"""
function compute_surprise(spm_current::Array{Float64, 3},
                         spm_reconstructed::Array{Float64, 3})
    return sum((spm_current - spm_reconstructed).^2)
end

"""
Haze modulation: β(H) for SPM aggregation
β_r(H), β_ν(H) ∈ [β_min, β_max]
"""
function modulate_beta(haze::Float64, beta_min::Float64, beta_max::Float64)
    # Linear interpolation: Low Haze → High β (sharp), High Haze → Low β (smooth)
    return beta_max - haze * (beta_max - beta_min)
end

end # FreeEnergyV56

# ===== Default Configuration for v5.6 =====
const DEFAULT_CONTROL_V56 = ControlParamsV56()

end # module
