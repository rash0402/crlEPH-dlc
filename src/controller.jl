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

export compute_action, free_energy

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

end # module
