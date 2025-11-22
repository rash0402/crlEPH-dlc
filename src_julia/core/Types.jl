module Types

using LinearAlgebra

export Agent, Environment, EPHParams

mutable struct Agent
    id::Int
    position::Vector{Float64}
    velocity::Vector{Float64}
    orientation::Float64
    radius::Float64
    max_speed::Float64
    personal_space::Float64
    color::Tuple{Int, Int, Int}
    goal::Union{Vector{Float64}, Nothing}

    # SPM state (stored for visualization/debugging)
    current_spm::Union{Array{Float64, 3}, Nothing}
    current_precision::Union{Matrix{Float64}, Nothing}

    # Active Inference state
    self_haze::Float64  # Current self-haze level
    visible_agents::Vector{Int}  # IDs of currently visible agents

    function Agent(id::Int, x::Float64, y::Float64;
                   theta::Float64=0.0, radius::Float64=10.0,
                   color::Tuple{Int, Int, Int}=(100, 150, 255))
        # Initialize with high self-haze (isolated state)
        # Will be updated to actual value in first step
        initial_self_haze = 0.7  # Corresponds to isolated state (low occupancy)
        new(id, [x, y], [0.0, 0.0], theta, radius, 50.0, 20.0, color, nothing,
            nothing, nothing, initial_self_haze, Int[])
    end
end

mutable struct Environment
    width::Float64
    height::Float64
    agents::Vector{Agent}
    grid_size::Int
    haze_grid::Matrix{Float64}
    dt::Float64

    # Experimental tracking
    coverage_map::Matrix{Bool}  # Coverage tracking
    frame_count::Int

    function Environment(width::Float64, height::Float64; grid_size::Int=20, dt::Float64=0.1)
        grid_w = ceil(Int, width / grid_size)
        grid_h = ceil(Int, height / grid_size)
        coverage_map = falses(grid_w, grid_h)
        new(width, height, Agent[], grid_size, zeros(grid_w, grid_h), dt, coverage_map, 0)
    end
end

"""
EPH Parameters for Active Inference formulation.
"""
Base.@kwdef mutable struct EPHParams
    # Self-hazing parameters
    h_max::Float64 = 0.8          # Maximum self-haze level
    α::Float64 = 2.0               # Sigmoid sensitivity
    Ω_threshold::Float64 = 1.0     # Occupancy threshold
    γ::Float64 = 2.0               # Haze attenuation exponent

    # Expected Free Energy weights
    β::Float64 = 0.5               # Entropy term weight
    λ::Float64 = 0.1               # Pragmatic term weight (low for exploration)

    # Precision matrix base
    Π_max::Float64 = 1.0           # Maximum precision
    decay_rate::Float64 = 0.1      # Distance-based decay

    # Gradient descent
    max_iter::Int = 5              # Iterations for action optimization
    η::Float64 = 0.1               # Learning rate

    # Physical constraints
    max_speed::Float64 = 50.0      # Maximum velocity magnitude
    max_accel::Float64 = 100.0     # Maximum acceleration

    # FOV parameters
    fov_angle::Float64 = 120.0 * π / 180.0  # 120 degrees in radians
    fov_range::Float64 = 100.0     # Perception range
end

end
