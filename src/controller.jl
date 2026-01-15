"""
FEP-based Controller with Active Inference
Free energy minimization for action generation
"""

module Controller

using LinearAlgebra
using Statistics
using ForwardDiff
using ..Config
using ..SPM
using ..Dynamics
using ..Prediction
using ..ActionVAEModel

export compute_action, free_energy, evaluate_collision_risk_ch3, compute_action_predictive
export free_energy_with_surprise, compute_action_with_surprise

"""
Free energy function F(v, goal_vel, spm)
Combines velocity tracking and obstacle avoidance
"""
function free_energy(
    vel::AbstractVector{T},
    goal_vel::Vector{Float64},
    spm::Array{Float64, 3},
    control_params::ControlParams
) where T
    # Velocity tracking term (minimize difference from goal velocity)
    vel_error = vel - goal_vel
    F_vel = 0.5 * norm(vel_error)^2
    
    # Obstacle avoidance term (using SPM saliency channel)
    saliency_sum = sum(spm[:, :, 2])
    F_obstacle = control_params.eta * saliency_sum
    
    # Total free energy
    F = F_vel + F_obstacle
    
    return F
end

"""
Free energy with Surprise term (FEP-aligned).
F = F_vel + F_obstacle + λ * Surprise

The Surprise term encourages actions leading to predictable (low reconstruction error) states.
Lower surprise = more familiar/predictable state-action pair.
"""
function free_energy_with_surprise(
    vel::AbstractVector{T},
    goal_vel::Vector{Float64},
    spm::Array{Float64, 3},
    control_params::ControlParams,
    surprise::Float64;
    λ_surprise::Float64=0.1
) where T
    # Velocity tracking term
    vel_error = vel - goal_vel
    F_vel = 0.5 * norm(vel_error)^2
    
    # Obstacle avoidance term
    saliency_sum = sum(spm[:, :, 2])
    F_obstacle = control_params.eta * saliency_sum
    
    # Surprise term: encourages predictable state-action pairs
    # Lower surprise = more familiar/expected = preferred
    F_surprise = λ_surprise * surprise
    
    return F_vel + F_obstacle + F_surprise
end

"""
Compute control action via gradient descent on free energy
u = -η * ∇_v F
"""
function compute_action(
    agent::Agent,
    spm::Array{Float64, 3},
    control_params::ControlParams,
    agent_params::AgentParams
)
    # Gradient of free energy w.r.t. velocity
    grad_F = ForwardDiff.gradient(
        v -> free_energy(v, agent.goal_vel, spm, control_params),
        agent.vel
    )
    
    # Action: negative gradient (gradient descent)
    u = -control_params.eta .* grad_F
    
    # Clamp to maximum control input
    u_clamped = clamp.(u, -agent_params.u_max, agent_params.u_max)
    
    return u_clamped
end

"""
Compute control action with Surprise minimization (FEP-aligned).
Uses VAE reconstruction error as surprise to guide action selection.

This is a two-stage approach:
1. Compute base action from gradient descent
2. Evaluate and weight by surprise
"""
function compute_action_with_surprise(
    agent::Agent,
    spm::Array{Float64, 3},
    control_params::ControlParams,
    agent_params::AgentParams,
    surprise::Float64;
    λ_surprise::Float64=0.1
)
    # Gradient of free energy with surprise term
    grad_F = ForwardDiff.gradient(
        v -> free_energy_with_surprise(v, agent.goal_vel, spm, control_params, surprise; λ_surprise=λ_surprise),
        agent.vel
    )
    
    # Action: negative gradient (gradient descent)
    u = -control_params.eta .* grad_F
    
    # Clamp to maximum control input
    u_clamped = clamp.(u, -agent_params.u_max, agent_params.u_max)
    
    return u_clamped
end

"""
Simple goal-directed action (fallback for testing)
"""
function compute_simple_action(
    agent::Agent,
    agent_params::AgentParams
)
    # Simple proportional control toward goal
    direction = agent.goal - agent.pos
    u = 2.0 .* direction
    return clamp.(u, -agent_params.u_max, agent_params.u_max)
end

# ===== M4: Predictive Collision Avoidance =====

"""
Evaluate collision risk from predicted SPM (Ch3-focused).
Lower risk = better (safer future state).

Args:
    spm_pred: Predicted SPM (16×16×3) - generic for Dual support

Returns:
    risk: Scalar collision risk value
"""
function evaluate_collision_risk_ch3(spm_pred::AbstractArray{T, 3}) where T
    # Primary: Ch3 (dynamic collision risk) - maximum value
    risk_ch3 = maximum(spm_pred[:, :, 3])
    
    # Secondary: Ch2 (proximity) - safety margin
    risk_ch2 = maximum(spm_pred[:, :, 2])
    
    # Weighted combination (Ch3 dominant)
    total_risk = 0.7 * risk_ch3 + 0.3 * risk_ch2
    
    return total_risk
end

"""
Compute action using predictive Expected Free Energy (EFE) minimization.
Predicts future SPM and evaluates Ch3 collision risk.

Args:
    agent: Current agent
    spm_current: Current SPM
    other_agents: Other agents in environment
    control_params: Control parameters
    agent_params: Agent parameters
    world_params: World parameters
    spm_config: SPM configuration

Returns:
    u: Optimal control input
"""
function compute_action_predictive(
    agent::Agent,
    spm_current::Array{Float64, 3},
    other_agents::Vector{Agent},
    control_params::ControlParams,
    agent_params::AgentParams,
    world_params::WorldParams,
    spm_config::SPMConfig  # Changed from SPMParams
)
    # Start with baseline action (current FEP)
    u_init = compute_action(agent, spm_current, control_params, agent_params)
    
    # Define Expected Free Energy function
    function expected_free_energy(u::AbstractVector{T}) where T
        # 1. Predict future state (ego-motion only for goal tracking)
        # We need next velocity for goal tracking
        # Simple dynamics model: vel_next = (1 - damping/mass*dt) * vel + u/mass*dt
        # Or reuse Dynamics.predict_state which is deterministic for the agent itself
        pos_next, vel_next = Dynamics.predict_state(agent, u, agent_params, world_params)
        
        # 2. Predict SPM using instrumental model (Ego-Warp)
        # This uses the pure visual prediction without accessing other agents' states
        spm_pred = Prediction.predict_next_spm(
            spm_current,
            u,
            spm_config,
            world_params.dt
        )
        
        # 3. Goal tracking term (Instrumental)
        # Prefer states where velocity matches goal
        F_goal = 0.5 * norm(vel_next - agent.goal_vel)^2
        
        # 4. Collision risk term (Instrumental - Safety)
        # Ch3-focused evaluation on predicted SPM
        F_collision = evaluate_collision_risk_ch3(spm_pred)
        
        # 5. Expected Free Energy
        # G = Risk + Ambiguity. (Here we focus on Risk/Instrumental)
        lambda_collision = 10.0  # Weight for collision avoidance (tuned for safety)
        G = F_goal + lambda_collision * F_collision
        
        return G
    end
    
    # Automatic differentiation for gradient
    grad_G = ForwardDiff.gradient(expected_free_energy, u_init)
    
    # Gradient descent
    alpha = 0.5  # Learning rate
    u_optimal = u_init - alpha .* grad_G
    
    # Clamp to limits
    u_clamped = clamp.(u_optimal, -agent_params.u_max, agent_params.u_max)
    
    return u_clamped
end

# ===== v5.4: Action-Conditioned VAE Based Control =====

"""
Compute action using v5.4 Action-Conditioned VAE (Pattern B).
- Encoder is u-independent → Haze/β fixed during optimization
- Decoder is u-conditioned → ∂F/∂u computed through decoder

Args:
    agent: Current agent
    spm_current: Current SPM y[k]
    action_vae: Trained Action-Conditioned VAE model
    control_params: Control parameters
    agent_params: Agent parameters
    world_params: World parameters
    n_iters: Number of gradient descent iterations (default 5)

Returns:
    u: Optimal control input
"""
function compute_action_v54(
    agent::Agent,
    spm_current::Array{Float64, 3},
    action_vae,  # ActionConditionedVAE (not typed to avoid import)
    control_params::ControlParams,
    agent_params::AgentParams,
    world_params::WorldParams;
    n_iters::Int=5,
    learning_rate::Float64=0.5,
    lambda_collision::Float64=10.0
)
    # 1. Encode current SPM (u-independent)
    # Reshape for Flux: (16, 16, 3) → (16, 16, 3, 1)
    spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))
    
    # Get latent distribution (fixed during u optimization)
    μ, logσ = ActionVAEModel.encode(action_vae, spm_input)
    z = μ  # Use mean for deterministic inference
    
    # 2. Compute Haze (u-independent, used for β modulation)
    variance = exp.(2 .* logσ)
    haze = mean(variance)
    
    # Update agent's precision based on Haze (v5.4: fixed during u search)
    agent.precision = 1.0 / (Float64(haze) + control_params.epsilon)
    
    # 3. Initialize u with baseline FEP action
    u_init = compute_action(agent, spm_current, control_params, agent_params)
    u = copy(u_init)
    
    # 4. Gradient descent on u through decoder
    for iter in 1:n_iters
        # Predict future SPM via decoder: (z, u) → ŷ[k+1]
        u_input = Float32.(reshape(u, 2, 1))
        spm_pred = ActionVAEModel.decode_with_u(action_vae, z, u_input)
        
        # Compute Free Energy
        # Goal tracking term
        pos_next, vel_next = Dynamics.predict_state(agent, u, agent_params, world_params)
        F_goal = 0.5 * norm(vel_next - agent.goal_vel)^2
        
        # Collision risk from predicted SPM
        F_collision = evaluate_collision_risk_ch3(spm_pred[:, :, :, 1])
        
        # Total Free Energy
        F = F_goal + lambda_collision * Float64(F_collision)
        
        # Compute gradient ∂F/∂u via ForwardDiff
        function F_of_u(u_vec)
            u_input_ad = Float32.(reshape(u_vec, 2, 1))
            spm_pred_ad = ActionVAEModel.decode_with_u(action_vae, z, u_input_ad)
            
            _, vel_next_ad = Dynamics.predict_state(agent, u_vec, agent_params, world_params)
            F_goal_ad = 0.5 * norm(vel_next_ad - agent.goal_vel)^2
            F_collision_ad = evaluate_collision_risk_ch3(spm_pred_ad[:, :, :, 1])
            
            return F_goal_ad + lambda_collision * Float64(F_collision_ad)
        end
        
        grad_F = ForwardDiff.gradient(F_of_u, u)
        
        # Update u
        u = u - learning_rate .* grad_F
        
        # Clamp to limits
        u = clamp.(u, -agent_params.u_max, agent_params.u_max)
    end
    
    return u
end

# ===== v6.0: Unified Free Energy with Predicted SPM =====

"""
Compute action using v6.0 Unified Free Energy (Pattern D VAE).

Key changes from v5.6:
1. Unified free energy F(u) = Φ_goal(u) + Φ_safety(u) + S(u) (no λ weighting)
2. Direction-based goal: Φ_goal = -v_next · d_pref
3. Predicted SPM for safety: Uses Ch2 + Ch3 from ŷ[k+1](u)
4. Surprise from VAE prediction error
5. Gradient descent optimization

Args:
    agent: Current agent
    spm_current: Current SPM y[k]
    other_agents: Other agents in environment
    action_vae: Trained Pattern D VAE
    control_params: Control parameters
    agent_params: Agent parameters
    world_params: World parameters
    spm_config: SPM configuration
    d_pref: Preferred direction unit vector (e.g., [0.0, 1.0] for North)
    precision: Current precision Π[k] (from Haze)
    k_2: Weight for Ch2 (proximity saliency)
    k_3: Weight for Ch3 (collision risk)
    n_iters: Number of gradient descent iterations (default 10)
    learning_rate: Gradient descent learning rate (default 0.1)

Returns:
    u: Optimal control input
"""
function compute_action_v60(
    agent::Agent,
    spm_current::Array{Float64, 3},
    other_agents::Vector{Agent},
    action_vae,  # ActionConditionedVAE
    control_params::ControlParams,
    agent_params::AgentParams,
    world_params::WorldParams,
    spm_config::SPMConfig,
    d_pref::Vector{Float64},
    precision::Float64,
    k_2::Float64,
    k_3::Float64;
    n_iters::Int=10,
    learning_rate::Float64=0.1
)
    # 1. Encode current SPM to get latent distribution (for Surprise computation)
    spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))

    # 2. Initialize u with zero or previous action
    u = zeros(2)  # Start from zero action

    # 3. Gradient descent optimization
    for iter in 1:n_iters
        # Define free energy as a function of u
        # Note: Use AbstractVector to support ForwardDiff.Dual types
        function F_of_u(u_vec::AbstractVector)
            return compute_free_energy_v60(
                agent, spm_current, u_vec, other_agents,
                action_vae, spm_config, world_params,
                d_pref, precision, k_2, k_3
            )
        end

        # Compute gradient
        grad_F = ForwardDiff.gradient(F_of_u, u)

        # Update u (gradient descent)
        u = u - learning_rate .* grad_F

        # Clamp to limits
        u = clamp.(u, -agent_params.u_max, agent_params.u_max)
    end

    return u
end

"""
Compute unified free energy F(u) for v6.0.

F(u) = Φ_goal(u) + Φ_safety(u) + S(u)

Where:
- Φ_goal(u): Direction-based goal evaluation (minimize -v_next · d_pref)
- Φ_safety(u): Predicted SPM-based safety (Ch2 + Ch3)
- S(u): Surprise from VAE prediction error

Args:
    agent: Current agent
    spm_current: Current SPM y[k]
    u: Action candidate
    other_agents: Other agents
    action_vae: Pattern D VAE
    spm_config: SPM configuration
    world_params: World parameters
    d_pref: Preferred direction unit vector
    precision: Current precision Π[k]
    k_2: Weight for Ch2 (proximity)
    k_3: Weight for Ch3 (collision)

Returns:
    F: Total free energy
"""
function compute_free_energy_v60(
    agent::Agent,
    spm_current::Array{Float64, 3},
    u::AbstractVector,  # Accept both Float64 and ForwardDiff.Dual
    other_agents::Vector{Agent},
    action_vae,
    spm_config::SPMConfig,
    world_params::WorldParams,
    d_pref::Vector{Float64},
    precision::Float64,
    k_2::Float64,
    k_3::Float64
)
    # ===== 1. Φ_goal: Direction-based goal evaluation =====
    # Extract Float64 values for non-differentiable operations (VAE, SPM)
    u_val = [ForwardDiff.value(u[1]), ForwardDiff.value(u[2])]

    # Predict next velocity
    pos_next, vel_next = Dynamics.predict_state(agent, u, AgentParams(), world_params)

    # Φ_goal = -v_next · d_pref (minimize to maximize dot product)
    Φ_goal = -dot(vel_next, d_pref)

    # ===== 2. Φ_safety: Predicted SPM-based safety =====
    # Generate predicted SPM with current precision (β modulation)
    # This is the predicted SPM ŷ[k+1](u) from state dynamics
    # IMPORTANT: Keep Dual numbers for automatic differentiation!
    T = eltype(pos_next)  # Dual or Float64
    agents_rel_pos = Vector{Vector{T}}()
    agents_rel_vel = Vector{Vector{T}}()

    for other in other_agents
        if other.id != agent.id
            # Relative position and velocity in agent's frame
            # Keep as Dual numbers to maintain gradient chain
            rel_pos = other.pos - pos_next
            rel_vel = other.vel - vel_next

            # Push Dual vectors directly (SPM generation is now Dual-compatible)
            push!(agents_rel_pos, rel_pos)
            push!(agents_rel_vel, rel_vel)
        end
    end

    # Generate predicted SPM with β modulation
    spm_pred = SPM.generate_spm_3ch(
        spm_config,
        agents_rel_pos,
        agents_rel_vel,
        AgentParams().r_agent,
        precision
    )

    # Extract Ch2 (Proximity Saliency) and Ch3 (Collision Risk)
    ch2_pred = spm_pred[:, :, 2]
    ch3_pred = spm_pred[:, :, 3]

    # Φ_safety = k_2 * Σ(Ch2) + k_3 * Σ(Ch3)
    Φ_safety = k_2 * sum(ch2_pred) + k_3 * sum(ch3_pred)

    # ===== 3. S(u): Surprise from VAE prediction error =====
    # VAE prediction: decode_with_u(encode(y[k], u), u) → ŷ_vae[k+1]
    spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))
    u_input = Float32.(reshape(u_val, 2, 1))  # Use Float64 values for VAE

    # Encode to get latent
    μ_z, logσ_z = ActionVAEModel.encode(action_vae, spm_input, u_input)
    z = μ_z  # Use mean for deterministic prediction

    # Decode to get VAE's prediction
    spm_vae_pred = ActionVAEModel.decode_with_u(action_vae, z, u_input)

    # Surprise = MSE between physical prediction and VAE prediction
    # Extract Float64 values from spm_pred for VAE comparison (∂S/∂u ≈ 0)
    spm_pred_val = map(ForwardDiff.value, spm_pred)
    spm_pred_batch = Float32.(reshape(spm_pred_val, 16, 16, 3, 1))
    S = mean((spm_pred_batch .- spm_vae_pred).^2) * (16 * 16 * 3)  # Scale to match typical range

    # ===== Total Free Energy =====
    F = Φ_goal + Φ_safety + Float64(S)

    return F
end

# ============================================================================
# v6.1: Adaptive Foveation with Dual-Zone Strategy
# ============================================================================

"""
Compute Dual-Zone Haze map based on distance to each agent.

Args:
    agent_pos: Ego agent position
    other_agents: List of other agents
    R_ps: Personal Space radius (Foveal/Peripheral boundary)
    h_foveal: Haze value in Foveal Zone (typically 0.0)
    h_peripheral: Haze value in Peripheral Zone (e.g., 0.3, 0.5, 0.7)
    k_blend: Sigmoid blending sharpness

Returns:
    Dict{Int, Float64}: Mapping from agent ID to Haze value
"""
function compute_dual_zone_haze(
    agent_pos::Vector{Float64},
    other_agents::Vector{Agent},
    spm_config::SPMConfig,
    rho_index_ps::Int = 4,
    h_foveal::Float64 = 0.0,
    h_peripheral::Float64 = 0.5,
    k_blend::Float64 = 5.0
)
    haze_map = Dict{Int, Float64}()
    params = spm_config.params
    n_rho = params.n_rho

    for other in other_agents
        r = norm(other.pos - agent_pos)

        # Map distance r to SPM grid index (find nearest rho_grid value)
        rho_r = log(r)  # Log distance
        rho_index = 1
        min_diff = abs(rho_r - spm_config.rho_grid[1])

        for i in 2:n_rho
            diff = abs(rho_r - spm_config.rho_grid[i])
            if diff < min_diff
                min_diff = diff
                rho_index = i
            end
        end

        # Sigmoid blending weight based on grid index
        # w(i) = 1 / (1 + exp(-k_blend * (i - rho_index_ps) / n_rho))
        # When i < rho_index_ps: w ≈ 0 → Haze ≈ h_foveal (Foveal Zone)
        # When i > rho_index_ps: w ≈ 1 → Haze ≈ h_peripheral (Peripheral Zone)
        delta_i = float(rho_index - rho_index_ps)
        w = 1.0 / (1.0 + exp(-k_blend * delta_i / n_rho))

        # Blended Haze
        haze = h_foveal * (1 - w) + h_peripheral * w

        haze_map[other.id] = haze
    end

    return haze_map
end

"""
Compute spatial Precision map for Precision-Weighted Surprise (v6.2 Sigmoid Blending).

For each SPM cell (i, j), compute Π[i,j] = 1 / (Haze[i] + ε) where Haze
is determined by a sigmoid blending function:
  - Haze(ρ) = h_crit + (h_peri - h_crit) · σ((ρ - ρ_crit) / τ)
  - σ(x) = 1 / (1 + exp(-x)) is the logistic sigmoid
  - Smooth transition centered at ρ_crit = rho_index_critical + 0.5

v6.2 Improvements over v6.1:
  1. Mathematical rigor: C∞-smooth → differentiable for ForwardDiff.jl
  2. Neuroscientific validity: Continuous PPS boundary (exponential decay)
  3. Control stability: Satisfies Gain Scheduling smoothness requirement

Theoretical grounding (unchanged from v6.1):
  1. Neuroscience: Peripersonal Space (PPS) 0.5-2.0m with margin
  2. Active Inference: High precision required for survival-critical predictions
  3. Empirical research: Avoidance initiation 2-3m (Moussaïd et al., 2011)
  4. Control theory: TTC 1s (predictive control) → 2.1m → Bin 6

Args:
    spm_config: SPM configuration (contains rho_grid)
    rho_index_critical: Critical zone bin threshold (transition center at +0.5)
    h_critical: Haze in critical zone (typically 0.0)
    h_peripheral: Haze in peripheral zone (typically 0.5)
    tau: Sigmoid transition smoothness (1.0 = default, 0.5 = steep, 2.0 = gentle)

Returns:
    Array{Float64, 2}: Precision map [n_rho × n_theta]
"""
function compute_precision_map(
    spm_config::SPMConfig,
    rho_index_critical::Int = 6,  # v6.2: Critical zone up to Bin 6 (0-2.18m @ D_max=8m)
    h_critical::Float64 = 0.0,
    h_peripheral::Float64 = 0.5,
    tau::Float64 = 1.0  # v6.2: Sigmoid transition smoothness (1.0 = default)
)
    params = spm_config.params
    n_rho = params.n_rho
    n_theta = params.n_theta

    precision_map = zeros(Float64, n_rho, n_theta)
    epsilon = 1e-6

    for i in 1:n_rho
        # v6.2 Sigmoid Blending (Smooth Transition)
        # Replaces v6.1 step function with C∞-smooth sigmoid blend
        #
        # Mathematical form: Haze(ρ) = h_crit + (h_peri - h_crit) · σ((ρ - ρ_crit) / τ)
        # where σ(x) = 1 / (1 + exp(-x)) is the logistic sigmoid
        #
        # Advantages over step function:
        #   1. Mathematical rigor: C∞-smooth → differentiable for ForwardDiff.jl
        #   2. Neuroscientific validity: PPS neural response is continuous (exponential decay)
        #   3. Control stability: Satisfies Gain Scheduling smoothness requirement
        #
        # Theoretical justification (unchanged from v6.1):
        #   - Peripersonal Space (PPS): 0.5-2.0m with margin
        #   - Avoidance initiation: 2-3m (Moussaïd et al., 2011)
        #   - TTC 1s (predictive control): 2.1m → Bin 6
        rho_crit = rho_index_critical + 0.5  # Transition center at bin boundary
        sigmoid_val = 1.0 / (1.0 + exp(-(i - rho_crit) / tau))
        haze_i = h_critical + (h_peripheral - h_critical) * sigmoid_val

        # Compute Precision: Π[i] = 1 / (Haze[i] + ε)
        precision_i = 1.0 / (haze_i + epsilon)

        # All theta cells at this rho have the same precision
        for j in 1:n_theta
            precision_map[i, j] = precision_i
        end
    end

    return precision_map
end

"""
Compute unified free energy F(u) for v6.1 with Precision-Weighted Surprise.

F(u) = Φ_goal(u) + Φ_safety(u) + S(u)

Changes from v6.0:
- S(u) now uses Precision-Weighted MSE: S = 1/2 Σ Π_{m,n} · (ŷ - ŷ_VAE)^2
- This ensures near-distance prediction errors are amplified, far-distance errors are tolerated

Args:
    agent: Current agent
    spm_current: Current SPM y[k]
    u: Action candidate
    other_agents: Other agents
    action_vae: Pattern D VAE
    spm_config: SPM configuration
    world_params: World parameters
    d_pref: Preferred direction unit vector
    precision: Current precision Π[k] (for SPM generation, not for weighting)
    k_2: Weight for Ch2 (proximity)
    k_3: Weight for Ch3 (collision)
    precision_map: Spatial Precision map [n_rho × n_theta] (for Surprise weighting)

Returns:
    F: Total free energy
"""
function compute_free_energy_v61(
    agent::Agent,
    spm_current::Array{Float64, 3},
    u::AbstractVector,  # Accept both Float64 and ForwardDiff.Dual
    other_agents::Vector{Agent},
    action_vae,
    spm_config::SPMConfig,
    world_params::WorldParams,
    d_pref::Vector{Float64},
    precision::Float64,
    k_2::Float64,
    k_3::Float64,
    precision_map::Array{Float64, 2}  # ★ v6.1 new parameter
)
    # ===== 1. Φ_goal: Direction-based goal evaluation (v6.0と同じ) =====
    # Extract Float64 values for non-differentiable operations (VAE, SPM)
    u_val = [ForwardDiff.value(u[1]), ForwardDiff.value(u[2])]

    pos_next, vel_next = Dynamics.predict_state(agent, u, AgentParams(), world_params)
    Φ_goal = -dot(vel_next, d_pref)

    # ===== 2. Φ_safety: Predicted SPM-based safety (v6.0と同じ) =====
    # IMPORTANT: Keep Dual numbers for automatic differentiation!
    T = eltype(pos_next)  # Dual or Float64
    agents_rel_pos = Vector{Vector{T}}()
    agents_rel_vel = Vector{Vector{T}}()

    for other in other_agents
        if other.id != agent.id
            # Keep as Dual numbers to maintain gradient chain
            rel_pos = other.pos - pos_next
            rel_vel = other.vel - vel_next
            # Push Dual vectors directly (SPM generation is now Dual-compatible)
            push!(agents_rel_pos, rel_pos)
            push!(agents_rel_vel, rel_vel)
        end
    end

    spm_pred = SPM.generate_spm_3ch(
        spm_config,
        agents_rel_pos,
        agents_rel_vel,
        AgentParams().r_agent,
        precision
    )

    ch2_pred = spm_pred[:, :, 2]
    ch3_pred = spm_pred[:, :, 3]

    # ===== 2.5. Precision-Weighted Safety (★ v6.2新規) =====
    # Apply spatial importance weight Π(ρ) to safety term
    # Φ_safety = Σ_{i,j} Π(ρ_i) · [k_2·ch2(i,j) + k_3·ch3(i,j)]
    # This amplifies collision avoidance in Critical Zone (Bin 1-6, Haze=0, Π≈100)
    Φ_safety = sum(precision_map .* (k_2 .* ch2_pred .+ k_3 .* ch3_pred))

    # ===== 3. S(u): Precision-Weighted Surprise (★ v6.1更新) =====
    # Skip if action_vae is nothing (data collection mode)
    S = 0.0

    if action_vae !== nothing
        # VAE operations are non-differentiable, so extract Float64 values
        # This means ∂S/∂u ≈ 0 (Surprise treated as locally constant)
        spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))
        u_input = Float32.(reshape(u_val, 2, 1))

        μ_z, logσ_z = ActionVAEModel.encode(action_vae, spm_input, u_input)
        z = μ_z  # Use mean for deterministic prediction

        spm_vae_pred = ActionVAEModel.decode_with_u(action_vae, z, u_input)

        # Extract Float64 values from spm_pred for VAE comparison
        spm_pred_val = map(ForwardDiff.value, spm_pred)
        spm_pred_batch = Float32.(reshape(spm_pred_val, 16, 16, 3, 1))

        # Precision-Weighted MSE
        # S = 1/2 Σ_{m,n,c} Π_{m,n} · (ŷ_{m,n,c} - ŷ_VAE_{m,n,c})^2
        #
        # Note: precision_map is [n_rho × n_theta], we need to apply it to each channel
        n_rho, n_theta, n_ch = size(spm_pred)

        for c in 1:n_ch
            for j in 1:n_theta
                for i in 1:n_rho
                    error_sq = (spm_pred_batch[i, j, c, 1] - spm_vae_pred[i, j, c, 1])^2
                    S += precision_map[i, j] * error_sq
                end
            end
        end

        S = S * 0.5  # Factor of 1/2
    end

    # ===== Total Free Energy =====
    F = Φ_goal + Φ_safety + Float64(S)

    return F
end

"""
Compute optimal action using v6.2 controller with Sigmoid Blending Foveation.

v6.2 Updates:
- Sigmoid blending replaces step function for smooth Haze(ρ) transition
- C∞-smooth differentiability for ForwardDiff.jl stability
- Neuroscientifically plausible continuous PPS boundary

Args:
    agent: Current agent
    spm_current: Current SPM y[k]
    other_agents: Other agents
    action_vae: Pattern D VAE
    control_params: Control parameters
    agent_params: Agent parameters
    world_params: World parameters
    spm_config: SPM configuration
    d_pref: Preferred direction unit vector
    precision: Current precision Π[k]
    k_2: Weight for Ch2 (proximity)
    k_3: Weight for Ch3 (collision)
    rho_index_critical: Bin index threshold (Critical zone center, default: 6)
    h_critical: Critical Zone Haze (default: 0.0)
    h_peripheral: Peripheral Zone Haze (default: 0.5)
    tau: Sigmoid transition smoothness (default: 1.0, range: 0.5-2.0)
    n_iters: Number of gradient descent iterations
    learning_rate: Gradient descent learning rate

Returns:
    u: Optimal action
"""
function compute_action_v61(
    agent::Agent,
    spm_current::Array{Float64, 3},
    other_agents::Vector{Agent},
    action_vae,  # ActionConditionedVAE
    control_params::ControlParams,
    agent_params::AgentParams,
    world_params::WorldParams,
    spm_config::SPMConfig,
    d_pref::Vector{Float64},
    precision::Float64,
    k_2::Float64,
    k_3::Float64;
    rho_index_critical::Int = 6,
    h_critical::Float64 = 0.0,
    h_peripheral::Float64 = 0.5,
    tau::Float64 = 1.0,  # v6.2: Sigmoid transition smoothness (1.0 = default)
    n_iters::Int = 10,
    learning_rate::Float64 = 0.1
)
    # 1. Compute Precision Map for Precision-Weighted Surprise (v6.2 Sigmoid Blending)
    precision_map = compute_precision_map(
        spm_config,
        rho_index_critical,
        h_critical,
        h_peripheral,
        tau  # v6.2: Sigmoid transition smoothness
    )

    # 2. Initialize u with zero or previous action
    u = zeros(2)  # Start from zero action

    # 3. Gradient descent optimization
    for iter in 1:n_iters
        # Define free energy as a function of u
        # Note: Use AbstractVector to support ForwardDiff.Dual types
        function F_of_u(u_vec::AbstractVector)
            return compute_free_energy_v61(
                agent, spm_current, u_vec, other_agents,
                action_vae, spm_config, world_params,
                d_pref, precision, k_2, k_3,
                precision_map  # Pass precision map
            )
        end

        # Compute gradient
        grad_F = ForwardDiff.gradient(F_of_u, u)

        # Update u (gradient descent)
        u = u - learning_rate .* grad_F

        # Clamp to limits
        u = clamp.(u, -agent_params.u_max, agent_params.u_max)
    end

    return u
end

export compute_action_v54, compute_action_v60, compute_free_energy_v60
export compute_dual_zone_haze, compute_precision_map  # v6.1 utility functions
export compute_action_v61, compute_free_energy_v61    # v6.1 main functions
export compute_action_random_collision_free  # v6.3 controller-bias-free function
export generate_action_candidates_v72, compute_goal_term_progress, compute_action_v72  # v7.2 EPH controller


"""
v7.2: Random Walk with Geometric Collision Avoidance (Discrete Candidates)
    
Purpose:
  Generate training data for VAE.
  Selects action from 100 discrete candidates (20 angles × 5 magnitudes).
  Ensures geometric safety (collision free).

Method:
  1. Generate 100 action candidates.
  2. Filter candidates that lead to geometric collision (within safety_threshold).
  3. Select from safe candidates using Softmax on (Alignment with d_goal + Random Noise).
     - Encourages exploration but maintains general direction.
  4. If no safe candidates, select the "least unsafe" one (max distance to nearest obstacle).

Arguments:
  - agent: Current agent
  - other_agents: List of other agents
  - obstacles: List of obstacle positions (Tuple)
  - agent_params: Agent parameters
  - world_params: World parameters
  - exploration_noise: Temperature for Softmax (higher = more random) (default: 1.0)
  - safety_threshold: Safety buffer (default: 1.0m)
  - repulsion_strength: (Not used in discrete selection)

Returns:
  - u: Selected [Fx, Fy] from candidates
"""
function compute_action_random_collision_free(
    agent::Agent,
    other_agents::Vector{Agent},
    obstacles::Vector{Tuple{Float64, Float64}},
    agent_params::AgentParams,
    world_params::WorldParams;
    exploration_noise::Float64=1.0,  # Acts as temperature for Softmax
    safety_threshold::Float64=1.0,
    repulsion_strength::Float64=1.0  # Deprecated in this logic
)
    # 1. Generate 100 candidates
    candidates = generate_action_candidates_v72(F_max=agent_params.u_max)
    
    # 2. Evaluate candidates
    safe_indices = Int[]
    scores = Float64[]
    min_dist_vals = Float64[]  # Track min dist for each candidate (fallback)
    
    # Current State
    state_curr = [agent.pos[1], agent.pos[2], agent.vel[1], agent.vel[2], agent.heading]
    
    for (idx, u) in enumerate(candidates)
        # Predict next position (using simple approximation for speed or RK4)
        # Using RK4 for accuracy since we have it
        state_next = Dynamics.dynamics_rk4(state_curr, u, agent_params, world_params)
        pos_next = [state_next[1], state_next[2]]
        
        # Check safety (Geometric)
        min_dist = Inf
        
        # Obstacles (walls)
        for obs in obstacles
            obs_pos = [obs[1], obs[2]]
            dist = norm(pos_next - obs_pos) - agent_params.r_agent
            min_dist = min(min_dist, dist)
        end
        
        # Other Agents
        for other in other_agents
            rel_pos = Dynamics.relative_position(pos_next, other.pos, world_params)
            dist = norm(rel_pos) - 2 * agent_params.r_agent
            min_dist = min(min_dist, dist)
        end
        
        push!(min_dist_vals, min_dist)
        
        if min_dist > 0.0  # Collision free
           # Use user-defined safety_threshold (default 1.0m)
           # If threshold is too strict, fallback mechanism will activate
           if min_dist > safety_threshold
               push!(safe_indices, idx)
               
               # Score: Alignment with d_goal + Randomness
               # d_goal is direction vector. u is force vector.
               # Normalize u for alignment check? Or use raw dot product (prefer larger force in good direction)
               alignment = dot(u, agent.d_goal)
               
               # Random score: Alignment + Noise
               # exploration_noise scales the randomness
               score = alignment + randn() * (agent_params.u_max * exploration_noise)
               push!(scores, score)
           end
        end
    end
    
    # 3. Select Action
    if !isempty(safe_indices)
        # Pick the one with highest score
        best_idx_local = argmax(scores)
        best_global_idx = safe_indices[best_idx_local]
        return candidates[best_global_idx]
    else
        # No strictly safe action found (within threshold)
        # Fallback: Maximize minimum distance (Survival Mode)
        # But we must ensure it's at least collision free (dist > 0)
        # If all candidates collide (min_dist <= 0), we still pick max min_dist
        best_fallback_idx = argmax(min_dist_vals)
        return candidates[best_fallback_idx]
    end
end

# ===== v7.2: EPH Controller with Discrete Candidate Evaluation =====

"""
v7.2: Generate 100 action candidates in polar coordinates.

Candidates = 20 directions × 5 magnitudes = 100 candidates

Args:
    F_max: Maximum force magnitude [N] (default: 150.0)
    n_angles: Number of direction angles (default: 20)
    n_magnitudes: Number of force magnitudes (default: 5)

Returns:
    candidates: Array of [Fx, Fy] vectors (100 × 2)
"""
function generate_action_candidates_v72(;
    F_max::Float64=150.0,
    n_angles::Int=20,
    n_magnitudes::Int=5
)
    angles = LinRange(0.0, 2π, n_angles + 1)[1:end-1]  # Exclude 2π (same as 0)
    magnitudes = LinRange(0.0, F_max, n_magnitudes)

    candidates = Vector{Vector{Float64}}()

    for angle in angles
        for F_mag in magnitudes
            Fx = F_mag * cos(angle)
            Fy = F_mag * sin(angle)
            push!(candidates, [Fx, Fy])
        end
    end

    return candidates
end

"""
v7.2: Compute progress-based goal term.

Φ_goal(u) = (P_pred(u) - P_target)² / (2σ_P²)

where:
  P_pred(u) = v_pred(u) · d_goal  (progress velocity)
  d_goal: Preferred direction unit vector
  P_target: Target progress velocity (default: 1.0 m/s)
  σ_P: Tolerance (default: 0.5 m/s)

Args:
    v_pred: Predicted velocity [vx, vy]
    d_goal: Preferred direction unit vector [dx, dy]
    P_target: Target progress velocity (default: 1.0)
    sigma_P: Tolerance (default: 0.5)

Returns:
    Phi_goal: Goal term value
"""
function compute_goal_term_progress(
    v_pred::Vector{Float64},
    d_goal::Vector{Float64};
    P_target::Float64=1.0,
    sigma_P::Float64=0.5
)
    # Progress velocity: dot product with preferred direction
    P_pred = dot(v_pred, d_goal)

    # Quadratic penalty
    Phi_goal = (P_pred - P_target)^2 / (2.0 * sigma_P^2)

    return Phi_goal
end

"""
v7.2: EPH action selection via discrete candidate evaluation.

Evaluates 100 action candidates and selects the one with minimum free energy:
  F(u) = Φ_goal(u) + Φ_safety(u) + λ_smooth·‖u‖²

Args:
    agent: Current agent
    spm_current: Current SPM (12×12×3)
    other_agents: Other agents in environment
    agent_params: Agent parameters
    world_params: World parameters
    spm_config: SPM configuration
    k_2: Weight for Ch2 (proximity saliency) (default: 1.0)
    k_3: Weight for Ch3 (collision risk) (default: 10.0)
    lambda_smooth: Smoothness weight (default: 0.01)
    P_target: Target progress velocity (default: 1.0 m/s)
    sigma_P: Progress tolerance (default: 0.5 m/s)

Returns:
    u_best: Optimal control input [Fx, Fy]
"""
function compute_action_v72(
    agent::Agent,
    spm_current::Array{Float64, 3},
    other_agents::Vector{Agent},
    agent_params::AgentParams,
    world_params::WorldParams,
    spm_config;  # SPMConfig
    vae_model=nothing,  # Optional VAE model
    k_2::Float64=1.0,
    k_3::Float64=10.0,
    lambda_smooth::Float64=0.01,
    P_target::Float64=1.0,
    sigma_P::Float64=0.5
)
    # Generate 100 action candidates
    candidates = generate_action_candidates_v72(F_max=agent_params.u_max)
    n_candidates = length(candidates)

    # 1. Goal Term (Progress) - Compute for all candidates
    # Can be parallelized or vectorized if critical, but loop is fine for 100 items
    Phi_goal_all = zeros(n_candidates)
    
    # 2. Safety Term & Haze - Needs VAE
    Phi_safety_all = zeros(n_candidates)
    
    if !isnothing(vae_model)
        # Prepare Batch Inputs for VAE
        # SPM: (12, 12, 3) -> (12, 12, 3, 100)
        x_batch = repeat(reshape(Float32.(spm_current), 12, 12, 3, 1), 1, 1, 1, n_candidates)
        
        # Action: Vector of Vectors -> Matrix (2, 100)
        u_batch = zeros(Float32, 2, n_candidates)
        for i in 1:n_candidates
            u_batch[:, i] .= candidates[i]
        end
        
        # Run VAE Prediction (Forward Pass)
        # Returns: x_hat, mu, logsigma
        # We assume model is on CPU
        x_hat_batch, mu_batch, logsigma_batch = vae_model(x_batch, u_batch)
        
        # Process Outputs
        # Haze: mean of variance = mean(exp(2*logsigma))
        # logsigma shape: (LatentDim, Batch)
        variance = exp.(2f0 .* logsigma_batch)
        haze_batch = mean(variance, dims=1)  # (1, 100)
        
        # Safety Score from Predicted SPM
        # x_hat_batch shape: (12, 12, 3, 100)
        # Sum ch2 and ch3 for each candidate
        # We can sum dims 1,2 to get (3, 100)
        spm_sums = sum(x_hat_batch, dims=(1,2)) 
        
        for i in 1:n_candidates
            # Haze Modulation
            h = haze_batch[1, i]
            # Beta (Precision): Inverse of Haze (Simple Model)
            # β = 1 / (1 + Haze)
            beta = 1.0 / (1.0 + h)
            
            # Predicted Safety Cost
            cost_safe = k_2 * spm_sums[1, 1, 2, i] + k_3 * spm_sums[1, 1, 3, i]
            
            # Modulated Safety Term
            Phi_safety_all[i] = beta * cost_safe
        end
    else
        # Fallback: Use Current SPM (No Prediction, No Haze)
        # Constant safety cost for all candidates (except for potential geometric check?)
        # For pure VAE logic fallback, we just use current SPM cost
        cost_safe_current = k_2 * sum(spm_current[:, :, 2]) + k_3 * sum(spm_current[:, :, 3])
        Phi_safety_all .= cost_safe_current
    end

    # Loop for Goal Term and Total Selection
    F_min = Inf
    u_best = candidates[1]

    for i in 1:n_candidates
        u = candidates[i]
        
        # 1. Predict state (Dynamics Model for Goal Term calculation)
        state_current = [agent.pos[1], agent.pos[2], agent.vel[1], agent.vel[2], agent.heading]
        state_pred = Dynamics.dynamics_rk4(state_current, u, agent_params, world_params)
        v_pred = [state_pred[3], state_pred[4]]
        
        # Goal Term
        Phi_goal = compute_goal_term_progress(v_pred, agent.d_goal; P_target=P_target, sigma_P=sigma_P)
        
        # Smoothness
        S = lambda_smooth * (u[1]^2 + u[2]^2)
        
        # Total Free Energy
        F_val = Phi_goal + Phi_safety_all[i] + S
        
        if F_val < F_min
            F_min = F_val
            u_best = u
        end
    end

    return u_best
end


# ============================================================================
# v7.2: Action-Conditioned VAE with Haze-Modulated Precision (Pattern D)
# ============================================================================

"""
Compute action using v7.2 Controller (Model A + Pattern D VAE).
Implements the "Freezing Robot" solution via Haze-based Precision Modulation.

Core Logic:
1. Sample candidate actions (u_{proposed})
2. Predict future SPM (y_{k+1}) and Haze (H) using VAE
   - Haze H = Agg(σ²_z) (Alertness/Ambiguity)
3. Modulate Precision β = 1 / (1 + H)
4. Evaluate Free Energy F(u) = F_{goal}(u) + β · F_{safety}(y_{k+1})
5. Select u* = argmin F(u)

Args:
    agent: Current agent
    spm: Current SPM (12x12x3)
    others: Other agents (for geometric fallbacks if needed)
    agent_params: Agent parameters
    world_params: World parameters
    spm_config: SPM configuration
    vae_model: Trained ActionConditionedVAE (BSON loaded)

Returns:
    u_opt: Optimal action vector [ux, uy]
"""
function compute_action_v72(
    agent::Agent,
    spm::Array{Float64, 3},
    others::Vector{Agent},
    agent_params::AgentParams,
    world_params::WorldParams,
    spm_config::SPMConfig;
    vae_model=nothing,
    n_candidates::Int=100,
    k_2::Float64=1.0,  # Proximity weight
    k_3::Float64=5.0,  # Collision weight (Risk)
    lambda_goal::Float64=1.0,
    u_max::Float64=150.0 # Force limit (v7.2 uses Force)
)
    # Define candidates: Random Sampling from [-u_max, u_max]
    # Simple Monte Carlo optimization (robust to non-convexity)
    
    # 1. Generate Candidates
    candidates = Vector{Vector{Float64}}(undef, n_candidates)
    for i in 1:n_candidates
        # Uniform sampling
        candidates[i] = (rand(2) .- 0.5) .* 2.0 .* u_max
    end
    
    # Include zero action and simple goal direction for robustness
    # Goal direction unit vector
    d_goal_vec = agent.d_goal # v7.2: d_goal is already a unit vector [dx, dy]
    # Simple approach force
    v_pref_mag = 1.3 # Standard walking speed [m/s]
    goal_vel = v_pref_mag .* d_goal_vec
    u_simple = 2.0 .* (goal_vel .- agent.vel) # P-controlish
    u_simple = clamp.(u_simple, -u_max, u_max)
    
    candidates[1] = [0.0, 0.0]
    candidates[2] = u_simple
    # candidates[3] = d_goal_vec .* u_max * 0.5
    
    # Storage for scores
    scores = Vector{Float64}(undef, n_candidates)
    
    # Precompute terms
    # Goal Term: Minimize velocity error relative to preferred velocity
    # v_pref = v_max * d_goal
    v_pref = v_pref_mag .* d_goal_vec
    
    # 2. VAE Prediction (Batch)
    # If VAE is available, use it for Safety + Haze
    if !isnothing(vae_model)
        # Prepare inputs
        # SPM: Repeat (H, W, C) -> (H, W, C, N)
        n_rho, n_theta, n_ch = size(spm)
        spm_float32 = Float32.(spm)
        x_batch = reshape(repeat(spm_float32, n_candidates), n_rho, n_theta, n_ch, n_candidates)
        
        # Action: (2, N) - Normalize to [~-1, 1] range used in training (div by 150.0)
        u_batch = zeros(Float32, 2, n_candidates)
        for i in 1:n_candidates
            u_batch[:, i] .= candidates[i] ./ 150.0f0 # Normalize!
        end
        
        # Forward Pass
        # x_hat: (12, 12, 3, N), mu, logsigma: (Latent, N)
        x_hat_batch, mu_batch, logsigma_batch = vae_model(x_batch, u_batch)
        
        # Haze Calculation
        # H = mean(exp(2*logsigma)) per sample
        variance = exp.(2f0 .* logsigma_batch)
        haze_batch = mean(variance, dims=1) # (1, N)
        
        # Safety Cost from Predicted SPM
        # Sum Ch2 (Proximity) and Ch3 (Risk)
        # spm_pred: (12, 12, 3, N)
        
        # Extract Ch2 and Ch3 sums
        # x_hat_batch is on CPU/GPU depending on model. Assuming CPU.
        # Ensure we work with arrays
        x_hat_arr = Array(x_hat_batch)
        haze_arr = Array(haze_batch)
        
        for i in 1:n_candidates
            h = Float64(haze_arr[1, i])
            
            # Beta Modulation
            # If H is high (uncertain), beta is low -> Worry less about safety (Unfreeze)
            beta = 1.0 / (1.0 + h * 10.0) # Tunable sensitivity factor
            
            # Predicted Safety Cost
            # Note: Model Output might be standardized or raw [0,1].
            # Training used MSE on [0,1] data.
            # Clamp to [0,1] to be safe
            spm_pred = clamp.(x_hat_arr[:, :, :, i], 0.0f0, 1.0f0)
            
            cost_ch2 = sum(spm_pred[:, :, 2]) # Proximity
            cost_ch3 = sum(spm_pred[:, :, 3]) # Risk
            
            F_safety = k_2 * cost_ch2 + k_3 * cost_ch3
            
            # Goal Term evaluation
            # Predict next velocity using Dynamics (deterministic physics)
            state_curr = [agent.pos[1], agent.pos[2], agent.vel[1], agent.vel[2], agent.heading]
            state_next = Dynamics.dynamics_rk4(state_curr, candidates[i], agent_params, world_params)
            v_next = [state_next[3], state_next[4]]
            
            F_goal = 0.5 * norm(v_next - v_pref)^2
            
            # Control Effort (Smoothness)
            F_effort = 0.001 * norm(candidates[i])^2
            
            # Total Free Energy
            scores[i] = lambda_goal * F_goal + beta * F_safety + F_effort
        end
        
    else
        # Fallback (No VAE): Standard Force-based or simple avoidance
        # Just use simple potential field on current state geometry
        # For now, just return simple P-control
        return u_simple
    end
    
    # 3. Selection
    best_idx = argmin(scores)
    return candidates[best_idx]
end

end # module
