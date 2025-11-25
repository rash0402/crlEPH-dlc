"""
Sheep Agent for Shepherding Task (Phase 4).

Implements BOIDS-based autonomous behavior with flee-from-dog response.
Supports time-varying BOIDS parameters to test EPH dog's environmental adaptation.

Key features:
- Reynolds' BOIDS (Separation, Alignment, Cohesion)
- Exponential-decay flee response to dog proximity
- Time-varying BOIDS weights (phase-dependent)
- Independent agent structure (not using EPH Agent type)
"""
module SheepAgent

using LinearAlgebra
using ..MathUtils

export SheepParams, Sheep, BOIDSForces
export compute_boids_forces, compute_flee_force, update_sheep!
export create_sheep_flock, adjust_boids_weights_temporal!
export compute_center_of_mass, compute_compactness

"""
Parameters for sheep BOIDS behavior.
"""
Base.@kwdef mutable struct SheepParams
    # BOIDS radii
    separation_radius::Float64 = 30.0
    alignment_radius::Float64 = 60.0
    cohesion_radius::Float64 = 100.0

    # BOIDS weights (time-varying)
    w_separation::Float64 = 1.5
    w_alignment::Float64 = 1.0
    w_cohesion::Float64 = 1.0

    # Flee-from-dog parameters
    flee_range::Float64 = 120.0        # Maximum flee distance
    k_flee::Float64 = 150.0            # Flee force magnitude
    r_fear::Float64 = 40.0             # Exponential decay scale

    # Physical constraints
    max_speed::Float64 = 40.0
    max_acceleration::Float64 = 80.0
    radius::Float64 = 8.0

    # Environmental noise
    noise_strength::Float64 = 3.0

    # Simulation
    dt::Float64 = 0.1
    world_size::Float64 = 400.0
end

"""
Sheep agent structure (independent from EPH Agent).
"""
mutable struct Sheep
    id::Int
    position::Vector{Float64}
    velocity::Vector{Float64}
    radius::Float64

    # Time-varying BOIDS weights (for adaptation testing)
    boids_weights::Vector{Float64}  # [w_sep, w_ali, w_coh]

    function Sheep(id::Int, x::Float64, y::Float64;
                   vx::Float64=0.0, vy::Float64=0.0,
                   radius::Float64=8.0,
                   boids_weights::Vector{Float64}=[1.5, 1.0, 1.0])
        new(id, [x, y], [vx, vy], radius, boids_weights)
    end
end

"""
BOIDS forces structure (for cleaner code).
"""
struct BOIDSForces
    separation::Vector{Float64}
    alignment::Vector{Float64}
    cohesion::Vector{Float64}
end

"""
Compute BOIDS forces for a single sheep.

Returns BOIDSForces struct with three components.
"""
function compute_boids_forces(
    sheep::Sheep,
    flock::Vector{Sheep},
    params::SheepParams
)::BOIDSForces

    sep = zeros(2)
    ali = zeros(2)
    coh_center = zeros(2)

    n_sep = 0
    n_ali = 0
    n_coh = 0

    for other in flock
        if other.id == sheep.id
            continue
        end

        # Toroidal distance
        dx, dy, dist = MathUtils.toroidal_distance(
            sheep.position, other.position,
            params.world_size, params.world_size
        )

        # Separation: repel from nearby sheep
        if dist < params.separation_radius && dist > 1e-6
            repulsion_dir = [dx, dy] / dist
            sep -= repulsion_dir / dist  # Stronger when closer
            n_sep += 1
        end

        # Alignment: match velocity
        if dist < params.alignment_radius
            ali += other.velocity
            n_ali += 1
        end

        # Cohesion: move towards local center
        if dist < params.cohesion_radius
            coh_center += other.position
            n_coh += 1
        end
    end

    # Normalize
    if n_sep > 0
        sep /= n_sep
    end

    if n_ali > 0
        ali /= n_ali
    end

    if n_coh > 0
        coh_center /= n_coh
        # Vector towards cohesion center
        dx, dy, _ = MathUtils.toroidal_distance(
            sheep.position, coh_center,
            params.world_size, params.world_size
        )
        coh = [dx, dy]
    else
        coh = zeros(2)
    end

    return BOIDSForces(sep, ali, coh)
end

"""
Compute flee force from dogs with exponential decay.

F_flee = k_flee * exp(-d / r_fear) * normalize(direction_away_from_dog)

This creates a smooth, distance-dependent repulsion:
- At d=0: Maximum fear (k_flee)
- At d=r_fear: ~37% of max fear
- At d=3*r_fear: ~5% of max fear
"""
function compute_flee_force(
    sheep::Sheep,
    dog_positions::Vector{Vector{Float64}},
    params::SheepParams
)::Vector{Float64}

    flee = zeros(2)

    for dog_pos in dog_positions
        # Toroidal distance
        dx, dy, dist = MathUtils.toroidal_distance(
            sheep.position, dog_pos,
            params.world_size, params.world_size
        )

        if dist < params.flee_range && dist > 1e-6
            # Direction away from dog
            flee_dir = [dx, dy] / dist

            # Exponential decay
            flee_magnitude = params.k_flee * exp(-dist / params.r_fear)

            flee += flee_magnitude * flee_dir
        end
    end

    return flee
end

"""
Update sheep position and velocity.

Combines BOIDS forces, flee force, and environmental noise.
"""
function update_sheep!(
    sheep::Sheep,
    flock::Vector{Sheep},
    dog_positions::Vector{Vector{Float64}},
    params::SheepParams
)
    # 1. Compute BOIDS forces
    boids = compute_boids_forces(sheep, flock, params)

    # 2. Compute flee force from dogs
    flee = compute_flee_force(sheep, dog_positions, params)

    # 3. Combine forces with time-varying weights
    w = sheep.boids_weights
    total_force = w[1] * boids.separation +
                  w[2] * boids.alignment +
                  w[3] * boids.cohesion +
                  flee

    # 4. Add environmental noise
    noise = randn(2) * params.noise_strength
    total_force += noise

    # 5. Update velocity with acceleration limit
    desired_velocity = sheep.velocity + total_force * params.dt

    # Acceleration limiting
    accel = (desired_velocity - sheep.velocity) / params.dt
    if norm(accel) > params.max_acceleration
        accel = params.max_acceleration * normalize(accel)
    end

    sheep.velocity += accel * params.dt

    # Speed limiting
    if norm(sheep.velocity) > params.max_speed
        sheep.velocity = params.max_speed * normalize(sheep.velocity)
    end

    # 6. Update position
    sheep.position += sheep.velocity * params.dt

    # Toroidal wrap
    sheep.position = mod.(sheep.position, params.world_size)
end

"""
Create a flock of sheep with random initial positions.

# Arguments
- `n_sheep::Int`: Number of sheep
- `world_size::Float64`: World size (square world)
- `spawn_region::Tuple{Float64, Float64}`: (min, max) spawn coordinates
- `initial_weights::Vector{Float64}`: Initial BOIDS weights [sep, ali, coh]

# Returns
- `Vector{Sheep}`: Flock of sheep agents
"""
function create_sheep_flock(
    n_sheep::Int,
    world_size::Float64;
    spawn_region::Tuple{Float64, Float64} = (0.3, 0.7),
    initial_weights::Vector{Float64} = [1.5, 1.0, 1.0]
)::Vector{Sheep}

    flock = Sheep[]

    min_coord = world_size * spawn_region[1]
    max_coord = world_size * spawn_region[2]

    for i in 1:n_sheep
        x = min_coord + rand() * (max_coord - min_coord)
        y = min_coord + rand() * (max_coord - min_coord)

        # Random initial velocity
        vx = (rand() - 0.5) * 20.0
        vy = (rand() - 0.5) * 20.0

        push!(flock, Sheep(i, x, y, vx=vx, vy=vy, boids_weights=copy(initial_weights)))
    end

    return flock
end

"""
Adjust BOIDS weights temporally to test EPH adaptation.

Three phases:
1. Early (t < T/3): High cohesion (sheep cluster naturally)
2. Middle (T/3 ≤ t < 2T/3): Balanced
3. Late (t ≥ 2T/3): High separation (sheep scatter)

This tests whether EPH dog can adapt to changing sheep behavior.

# Arguments
- `flock::Vector{Sheep}`: Sheep flock
- `t::Float64`: Current simulation time
- `T_total::Float64`: Total simulation time

# Returns
- `Nothing` (modifies flock in-place)
"""
function adjust_boids_weights_temporal!(
    flock::Vector{Sheep},
    t::Float64,
    T_total::Float64
)
    # Determine current phase
    phase_duration = T_total / 3.0

    if t < phase_duration
        # Phase 1: High cohesion (sheep naturally cluster)
        w_sep, w_ali, w_coh = 1.0, 1.0, 2.5
    elseif t < 2 * phase_duration
        # Phase 2: Balanced
        w_sep, w_ali, w_coh = 1.5, 1.0, 1.0
    else
        # Phase 3: High separation (sheep scatter)
        w_sep, w_ali, w_coh = 3.0, 0.5, 0.5
    end

    # Update all sheep
    for sheep in flock
        sheep.boids_weights[1] = w_sep
        sheep.boids_weights[2] = w_ali
        sheep.boids_weights[3] = w_coh
    end

    nothing
end

"""
Compute center of mass of sheep flock.
"""
function compute_center_of_mass(flock::Vector{Sheep})::Vector{Float64}
    if isempty(flock)
        return [0.0, 0.0]
    end

    com = zeros(2)
    for sheep in flock
        com += sheep.position
    end

    return com / length(flock)
end

"""
Compute compactness metric (mean squared distance from COM).
"""
function compute_compactness(flock::Vector{Sheep})::Float64
    if length(flock) <= 1
        return 0.0
    end

    com = compute_center_of_mass(flock)

    C = 0.0
    for sheep in flock
        C += norm(sheep.position - com)^2
    end

    return C / length(flock)
end

end  # module SheepAgent
