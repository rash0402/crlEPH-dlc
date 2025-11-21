module Types

using LinearAlgebra

export Agent, Environment

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
    
    function Agent(id::Int, x::Float64, y::Float64; 
                   theta::Float64=0.0, radius::Float64=10.0, 
                   color::Tuple{Int, Int, Int}=(100, 150, 255))
        new(id, [x, y], [0.0, 0.0], theta, radius, 50.0, 20.0, color, nothing, nothing, nothing)
    end
end

mutable struct Environment
    width::Float64
    height::Float64
    agents::Vector{Agent}
    grid_size::Int
    haze_grid::Matrix{Float64}
    dt::Float64
    
    function Environment(width::Float64, height::Float64; grid_size::Int=20, dt::Float64=0.1)
        grid_w = ceil(Int, width / grid_size)
        grid_h = ceil(Int, height / grid_size)
        new(width, height, Agent[], grid_size, zeros(grid_w, grid_h), dt)
    end
end

end
