"""
EnvironmentalHaze Module - Environmental Haze Sampling and Composition

Implements Phase 2 environmental haze functionality:
- Sampling haze_grid at agent's SPM bin locations
- Composing self-haze and environmental haze: H_total = H_self ⊕ H_env
- Lubricant/Repellent haze deposition mechanisms

Theory:
- Environmental haze H_env(x,y) is stored in haze_grid (world coordinates)
- Agents sample H_env at their SPM bin locations (agent-relative polar coordinates)
- Total haze: H_total(r,θ) = max(H_self(r,θ), H_env(x(r,θ), y(r,θ)))
"""
module EnvironmentalHaze

using ..Types
using ..MathUtils
using LinearAlgebra

export sample_environmental_haze, compose_haze, deposit_haze_trail

"""
    sample_environmental_haze(agent::Agent, env::Environment, Nr::Int, Nθ::Int, d_max::Float64) -> Matrix{Float64}

Sample environmental haze from haze_grid at locations corresponding to SPM bins.

# Arguments
- `agent::Agent`: Agent whose FOV we're sampling
- `env::Environment`: Environment containing haze_grid
- `Nr::Int`: Number of radial bins in SPM
- `Nθ::Int`: Number of angular bins in SPM
- `d_max::Float64`: Maximum perception range

# Returns
- `h_env::Matrix{Float64}`: Environmental haze matrix (Nr, Nθ) ∈ [0, 1]

# Algorithm
For each SPM bin (r, θ):
1. Convert bin to world coordinates (x, y) relative to agent
2. Sample haze_grid at (x, y) using bilinear interpolation
3. Return sampled haze value

# Notes
- Uses toroidal wrap-around for world boundaries
- Bilinear interpolation for smooth haze sampling
- Returns 0.0 if haze_grid is not initialized (backward compatibility)
"""
function sample_environmental_haze(agent::Agent, env::Environment,
                                    Nr::Int, Nθ::Int, d_max::Float64)::Matrix{Float64}
    # Initialize haze matrix
    h_env = zeros(Float64, Nr, Nθ)

    # Check if haze_grid is available
    if isnothing(env.haze_grid) || all(env.haze_grid .== 0.0)
        return h_env  # No environmental haze (Phase 1 compatibility)
    end

    grid_w, grid_h = size(env.haze_grid)

    # For each SPM bin, compute corresponding world position and sample haze
    for r_idx in 1:Nr
        for θ_idx in 1:Nθ
            # Compute radial distance for this bin
            # Bin 0 is personal space (0 to ps), bins 1+ are log-spaced
            if r_idx == 1
                # Personal space bin: use center
                r = agent.personal_space / 2.0
            else
                # Log-polar bins
                r_min = agent.personal_space
                r_max = d_max
                log_min = log(r_min + 1e-6)
                log_max = log(r_max)
                t = (r_idx - 1) / (Nr - 1)  # Normalized position in log space
                r = exp(log_min + t * (log_max - log_min))
            end

            # Compute angular direction (θ=0 is agent's forward direction)
            θ = ((θ_idx - 1) / Nθ) * 2π - π  # Range: [-π, π]

            # Convert to world coordinates
            global_θ = agent.orientation + θ
            dx = r * cos(global_θ)
            dy = r * sin(global_θ)

            world_x = agent.position[1] + dx
            world_y = agent.position[2] + dy

            # Apply toroidal wrap-around
            world_x = mod(world_x, env.width)
            world_y = mod(world_y, env.height)

            # Convert world coordinates to grid indices
            grid_x_cont = (world_x / env.width) * grid_w
            grid_y_cont = (world_y / env.height) * grid_h

            # Bilinear interpolation
            gx0 = floor(Int, grid_x_cont)
            gy0 = floor(Int, grid_y_cont)
            gx1 = (gx0 + 1) % grid_w
            gy1 = (gy0 + 1) % grid_h

            # Clamp to valid range [0, grid_w-1] and [0, grid_h-1]
            gx0 = clamp(gx0, 0, grid_w - 1) + 1  # +1 for Julia 1-indexing
            gy0 = clamp(gy0, 0, grid_h - 1) + 1
            gx1 = clamp(gx1, 0, grid_w - 1) + 1
            gy1 = clamp(gy1, 0, grid_h - 1) + 1

            # Interpolation weights
            wx = grid_x_cont - floor(grid_x_cont)
            wy = grid_y_cont - floor(grid_y_cont)

            # Bilinear interpolation
            h00 = env.haze_grid[gx0, gy0]
            h10 = env.haze_grid[gx1, gy0]
            h01 = env.haze_grid[gx0, gy1]
            h11 = env.haze_grid[gx1, gy1]

            h_interpolated = (1 - wx) * (1 - wy) * h00 +
                           wx * (1 - wy) * h10 +
                           (1 - wx) * wy * h01 +
                           wx * wy * h11

            h_env[r_idx, θ_idx] = clamp(h_interpolated, 0.0, 1.0)
        end
    end

    return h_env
end

"""
    compose_haze(h_self::Matrix{Float64}, h_env::Matrix{Float64}) -> Matrix{Float64}

Compose self-haze and environmental haze using max operator.

# Arguments
- `h_self::Matrix{Float64}`: Self-haze matrix (Nr, Nθ)
- `h_env::Matrix{Float64}`: Environmental haze matrix (Nr, Nθ)

# Returns
- `h_total::Matrix{Float64}`: Composed haze matrix (Nr, Nθ)

# Theory
Haze composition operator ⊕ is defined as element-wise maximum:
    H_total(r,θ) = max(H_self(r,θ), H_env(r,θ))

Interpretation:
- If either self-haze or environmental haze is high, total haze is high
- Self-haze: internal regulation (occupancy-based)
- Environmental haze: external guidance (stigmergic trails)
"""
function compose_haze(h_self::Matrix{Float64}, h_env::Matrix{Float64})::Matrix{Float64}
    if size(h_self) != size(h_env)
        error("Haze matrices must have same dimensions: $(size(h_self)) vs $(size(h_env))")
    end

    # Max operator: h_total = max(h_self, h_env)
    h_total = max.(h_self, h_env)

    return h_total
end

"""
    deposit_haze_trail!(env::Environment, agent::Agent, haze_type::Symbol, amount::Float64)

Deposit haze trail at agent's current position.

# Arguments
- `env::Environment`: Environment to modify
- `agent::Agent`: Agent depositing haze
- `haze_type::Symbol`: :lubricant (decrease haze) or :repellent (increase haze)
- `amount::Float64`: Magnitude of haze change

# Haze Types
- **Lubricant Haze** (:lubricant): Decreases haze → increases precision → guides followers
  - Example: Leader deposits lubricant trail for followers to track
  - Implementation: haze_grid[x,y] = max(0.0, current - amount)

- **Repellent Haze** (:repellent): Increases haze → decreases precision → promotes exploration
  - Example: Mark explored areas to encourage diversity
  - Implementation: haze_grid[x,y] = min(1.0, current + amount)

# Notes
- Haze is deposited in a small radius around agent (3x3 grid cells)
- Uses toroidal wrap-around for world boundaries
"""
function deposit_haze_trail!(env::Environment, agent::Agent,
                             haze_type::Symbol, amount::Float64)
    if isnothing(env.haze_grid)
        return  # No haze grid available
    end

    grid_w, grid_h = size(env.haze_grid)

    # Convert agent position to grid coordinates
    grid_x = floor(Int, (agent.position[1] / env.width) * grid_w)
    grid_y = floor(Int, (agent.position[2] / env.height) * grid_h)

    # Deposit haze in 3x3 neighborhood
    for dx in -1:1
        for dy in -1:1
            # Toroidal wrap-around
            gx = mod(grid_x + dx, grid_w) + 1  # +1 for Julia 1-indexing
            gy = mod(grid_y + dy, grid_h) + 1

            # Distance-based falloff
            dist_factor = 1.0 / (1.0 + sqrt(dx^2 + dy^2))
            effective_amount = amount * dist_factor

            # Update haze based on type
            if haze_type == :lubricant
                # Decrease haze (increase precision)
                env.haze_grid[gx, gy] = max(0.0, env.haze_grid[gx, gy] - effective_amount)
            elseif haze_type == :repellent
                # Increase haze (decrease precision)
                env.haze_grid[gx, gy] = min(1.0, env.haze_grid[gx, gy] + effective_amount)
            else
                error("Unknown haze type: $haze_type (use :lubricant or :repellent)")
            end
        end
    end
end

"""
    decay_haze_grid!(env::Environment, decay_rate::Float64)

Apply global decay to haze_grid.

# Arguments
- `env::Environment`: Environment to modify
- `decay_rate::Float64`: Decay factor ∈ (0, 1) (default: 0.99)

# Theory
Haze decays exponentially over time to prevent accumulation:
    H_env(t+1) = decay_rate · H_env(t)

Typical decay_rate: 0.99 (1% decay per timestep)
"""
function decay_haze_grid!(env::Environment, decay_rate::Float64=0.99)
    if !isnothing(env.haze_grid)
        env.haze_grid .*= decay_rate
    end
end

end  # module EnvironmentalHaze
