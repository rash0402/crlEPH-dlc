"""
FEP-based Controller with Active Inference
Free energy minimization for action generation
"""

module Controller

using LinearAlgebra
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

end # module
