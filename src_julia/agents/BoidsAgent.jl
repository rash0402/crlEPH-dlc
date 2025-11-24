"""
Boids-based agent model for shepherding scenario (sheep agents).

Implements Reynolds' Boids rules:
1. Separation: Avoid crowding neighbors
2. Alignment: Steer towards average heading of neighbors
3. Cohesion: Steer towards average position of neighbors

Plus environmental noise for realistic behavior.
"""
module BoidsAgent

using LinearAlgebra
using ..Types
using ..MathUtils

export compute_boids_velocity, apply_environmental_noise

"""
Compute Boids-based velocity for a sheep agent.

# Arguments
- `agent::Agent`: The sheep agent
- `env::Environment`: Environment containing other sheep
- `separation_radius::Float64`: Distance for separation rule (default: 30.0)
- `cohesion_radius::Float64`: Distance for cohesion rule (default: 100.0)
- `alignment_radius::Float64`: Distance for alignment rule (default: 60.0)
- `w_sep::Float64`: Weight for separation (default: 1.5)
- `w_align::Float64`: Weight for alignment (default: 1.0)
- `w_coh::Float64`: Weight for cohesion (default: 1.0)

# Returns
- `Vector{Float64}`: Desired velocity (2D vector)
"""
function compute_boids_velocity(
    agent::Agent,
    env::Environment;
    separation_radius::Float64 = 30.0,
    cohesion_radius::Float64 = 100.0,
    alignment_radius::Float64 = 60.0,
    w_sep::Float64 = 1.5,
    w_align::Float64 = 1.0,
    w_coh::Float64 = 1.0
)::Vector{Float64}

    # Get neighbors (other sheep agents)
    sheep_agents = if env.scenario_type == :shepherding && !isnothing(env.sheep_agents)
        env.sheep_agents
    else
        env.agents  # Fallback for exploration scenario
    end

    # Rule 1: Separation (avoid crowding)
    separation = zeros(2)
    n_sep = 0

    # Rule 2: Alignment (match velocity)
    alignment = zeros(2)
    n_align = 0

    # Rule 3: Cohesion (move towards center)
    cohesion_center = zeros(2)
    n_coh = 0

    for other in sheep_agents
        if other.id == agent.id
            continue
        end

        dx, dy, dist = MathUtils.toroidal_distance(
            agent.position, other.position, env.width, env.height
        )

        # Separation: repel from nearby agents
        if dist < separation_radius && dist > 0.0
            repulsion = [dx, dy] / dist  # Normalized direction
            separation -= repulsion / dist  # Stronger when closer
            n_sep += 1
        end

        # Alignment: match velocity of nearby agents
        if dist < alignment_radius
            alignment += other.velocity
            n_align += 1
        end

        # Cohesion: move towards center of nearby group
        if dist < cohesion_radius
            cohesion_center += other.position
            n_coh += 1
        end
    end

    # Normalize by number of neighbors
    if n_sep > 0
        separation /= n_sep
    end

    if n_align > 0
        alignment /= n_align
    end

    if n_coh > 0
        cohesion_center /= n_coh
        # Vector towards cohesion center
        dx, dy, _ = MathUtils.toroidal_distance(
            agent.position, cohesion_center, env.width, env.height
        )
        cohesion = [dx, dy]
    else
        cohesion = zeros(2)
    end

    # Combine three rules with weights
    desired_velocity = w_sep * separation + w_align * alignment + w_coh * cohesion

    # Limit to max speed
    speed = norm(desired_velocity)
    if speed > agent.max_speed
        desired_velocity = desired_velocity / speed * agent.max_speed
    end

    return desired_velocity
end

"""
Apply environmental noise to velocity (represents unpredictable sheep behavior).

# Arguments
- `velocity::Vector{Float64}`: Current desired velocity
- `noise_strength::Float64`: Standard deviation of Gaussian noise (default: 5.0)

# Returns
- `Vector{Float64}`: Velocity with added noise
"""
function apply_environmental_noise(
    velocity::Vector{Float64};
    noise_strength::Float64 = 5.0
)::Vector{Float64}
    noise = randn(2) * noise_strength
    return velocity + noise
end

"""
Compute dog repulsion force for sheep (used during escape induction phase).

# Arguments
- `agent::Agent`: The sheep agent
- `dog_positions::Vector{Vector{Float64}}`: Positions of dog agents
- `env::Environment`: Environment
- `repulsion_radius::Float64`: Distance within which dogs repel sheep (default: 80.0)
- `repulsion_strength::Float64`: Strength of repulsion (default: 2.0)

# Returns
- `Vector{Float64}`: Repulsion force vector
"""
function compute_dog_repulsion(
    agent::Agent,
    dog_positions::Vector{Vector{Float64}},
    env::Environment;
    repulsion_radius::Float64 = 80.0,
    repulsion_strength::Float64 = 2.0
)::Vector{Float64}

    repulsion = zeros(2)

    for dog_pos in dog_positions
        dx, dy, dist = MathUtils.toroidal_distance(
            agent.position, dog_pos, env.width, env.height
        )

        if dist < repulsion_radius && dist > 0.0
            # Repel from dog (direction away from dog)
            repulsion_dir = [dx, dy] / dist
            # Stronger repulsion when closer
            repulsion -= repulsion_dir * repulsion_strength * (repulsion_radius - dist) / repulsion_radius
        end
    end

    return repulsion
end

end  # module BoidsAgent
