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
    spm_pred: Predicted SPM (16×16×3)

Returns:
    risk: Scalar collision risk value
"""
function evaluate_collision_risk_ch3(spm_pred::Array{Float64, 3})
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
    function expected_free_energy(u::Vector{Float64})
        # 1. Predict future state
        pos_next, vel_next = Dynamics.predict_state(agent, u, agent_params, world_params)
        
        # 2. Predict other agents (constant velocity)
        other_predictions = Dynamics.predict_other_agents(other_agents, world_params)
        
        # 3. Generate predicted SPM
        # Compute relative positions and velocities
        rel_positions = Vector{Float64}[]
        rel_velocities = Vector{Float64}[]
        
        for (other_pos, other_vel) in other_predictions
            rel_pos = Dynamics.relative_position(pos_next, other_pos, world_params)
            rel_vel = other_vel - vel_next
            push!(rel_positions, rel_pos)
            push!(rel_velocities, rel_vel)
        end
        
        # Generate predicted SPM
        spm_pred = SPM.generate_spm_3ch(
            spm_config,
            rel_positions,
            rel_velocities,
            agent_params.r_agent,
            precision=agent.precision
        )
        
        # 4. Goal tracking term
        F_goal = 0.5 * norm(vel_next - agent.goal_vel)^2
        
        # 5. Collision risk term (Ch3-focused)
        F_collision = evaluate_collision_risk_ch3(spm_pred)
        
        # 6. Expected Free Energy
        lambda_collision = 5.0  # Weight for collision avoidance
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

end # module
