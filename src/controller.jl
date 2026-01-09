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

export compute_action, free_energy, evaluate_collision_risk_ch3, compute_action_predictive

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
    μ, logσ = action_vae.encode(action_vae, spm_input)
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
        spm_pred = action_vae.decode_with_u(action_vae, z, u_input)
        
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
            spm_pred_ad = action_vae.decode_with_u(action_vae, z, u_input_ad)
            
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

export compute_action_v54

end # module
