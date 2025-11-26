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
    previous_spm::Union{Array{Float64, 3}, Nothing}  # For prediction-based surprise
    last_action::Union{Vector{Float64}, Nothing}     # For data collection (Phase 2)
    hidden_state::Union{Vector{Float32}, Nothing}    # For GRU state (Phase 3)

    # Active Inference state
    self_haze::Float64  # Current self-haze level
    visible_agents::Vector{Int}  # IDs of currently visible agents
    current_gradient::Union{Vector{Float64}, Nothing}  # EFE gradient for visualization
    current_efe::Float64  # Current Expected Free Energy value
    belief_entropy::Float64  # Current belief entropy H[q(s|a)]

    # Prediction uncertainty tracking (Phase 2.5)
    prediction_error_history::Vector{Float64}  # Sliding window of recent prediction errors
    prediction_uncertainty::Float64  # Current prediction uncertainty estimate [0, 1]

    function Agent(id::Int, x::Float64, y::Float64;
                   theta::Float64=0.0, radius::Float64=2.0,
                   color::Tuple{Int, Int, Int}=(100, 150, 255))
        # Initialize with high self-haze (isolated state)
        # Will be updated to actual value in first step
        initial_self_haze = 0.7  # Corresponds to isolated state (low occupancy)
        new(id, [x, y], [0.0, 0.0], theta, radius, 50.0, 20.0, color, nothing,
            nothing, nothing, nothing, nothing, nothing, initial_self_haze, Int[], nothing, 0.0, 0.0,
            Float64[], 0.5)  # Initialize with empty history and moderate uncertainty
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
    coverage_map::Matrix{Int}  # Visit count tracking (0 = unvisited, N = visited N times)
    frame_count::Int

    # Scenario-specific fields (optional, nothing for exploration)
    scenario_type::Symbol  # :exploration or :shepherding
    target_position::Union{Vector{Float64}, Nothing}  # Target for shepherding
    sheep_agents::Union{Vector{Agent}, Nothing}  # Separate sheep agents for shepherding

    function Environment(width::Float64, height::Float64;
                        grid_size::Int=20, dt::Float64=0.1, scenario_type::Symbol=:exploration)
        grid_w = ceil(Int, width / grid_size)
        grid_h = ceil(Int, height / grid_size)
        coverage_map = zeros(Int, grid_w, grid_h)  # Changed to Int for visit counting
        new(width, height, Agent[], grid_size, zeros(grid_w, grid_h), dt, coverage_map, 0,
            scenario_type, nothing, nothing)
    end
end

"""
EPH Parameters for Active Inference formulation.
"""
Base.@kwdef mutable struct EPHParams
    # Self-hazing parameters
    h_max::Float64 = 0.8          # Maximum self-haze level
    α::Float64 = 10.0              # Sigmoid sensitivity (higher = more responsive)
    Ω_threshold::Float64 = 0.12    # Occupancy threshold (optimized for 50:50 state distribution)
    γ::Float64 = 2.0               # Haze attenuation exponent

    # Expected Free Energy weights
    β::Float64 = 1.0               # Entropy term weight (epistemic value)
    λ::Float64 = 0.1               # Pragmatic term weight (low for exploration)
    γ_info::Float64 = 0.5          # Information gain weight (new for Phase 1)

    # Prediction uncertainty parameters (Phase 2.5)
    uncertainty_alpha::Float64 = 0.3    # Hidden state weight in hybrid uncertainty (0-1)
    uncertainty_window::Int = 10        # Prediction error history window size
    uncertainty_enabled::Bool = true    # Enable prediction uncertainty estimation

    # Precision matrix base
    Π_max::Float64 = 1.0           # Maximum precision
    decay_rate::Float64 = 0.1      # Distance-based decay

    # Gradient descent
    max_iter::Int = 5              # Iterations for action optimization
    η::Float64 = 0.1               # Learning rate

    # Physical constraints
    max_speed::Float64 = 50.0      # Maximum velocity magnitude
    max_accel::Float64 = 100.0     # Maximum acceleration
    
    # Prediction parameters (Phase 1, 2, 3)
    prediction_dt::Float64 = 0.1   # Prediction time horizon (seconds)
    predictor_type::Symbol = :neural  # :neural (GRU, default) or :linear (data collection only)
    collect_data::Bool = false     # Enable data collection for GRU training
    
    # Online learning parameters (Phase 5)
    enable_online_learning::Bool = false  # Enable real-time GRU updates
    online_lr_base::Float64 = 0.0001      # Base learning rate for online updates
    online_lr_min_agents::Int = 2         # Minimum visible agents for full learning rate
    online_update_interval::Int = 10      # Update model every N steps

    # Environmental Haze parameters (Phase 2) - Optimized 2025-11-24
    enable_env_haze::Bool = false         # Enable environmental haze (stigmergy)
    haze_deposit_amount::Float64 = 0.3    # Haze deposition magnitude per step (optimized: 0.3)
    haze_decay_rate::Float64 = 0.97       # Global haze decay factor (optimized: 0.97 = 3% decay/step)
    haze_deposit_type::Symbol = :lubricant # :lubricant (decrease haze, RECOMMENDED) or :repellent (increase haze)

    # Full Tensor Haze parameters (Phase 3)
    enable_full_tensor::Bool = false      # Enable Phase 3 full tensor haze
    channel_weights::Vector{Float64} = [1.0, 0.5, 0.5]  # Per-channel haze weights [occ, rad, tan]
    channel_mask::Vector{Float64} = [1.0, 1.0, 1.0]     # Selective attention mask [occ, rad, tan]
    # Per-channel thresholds (Ω_threshold for each channel)
    Ω_threshold_occ::Float64 = 0.05       # Occupancy threshold
    Ω_threshold_rad::Float64 = 0.03       # Radial velocity threshold
    Ω_threshold_tan::Float64 = 0.03       # Tangential velocity threshold
    # Per-channel sigmoid sensitivity
    α_occ::Float64 = 10.0                 # Occupancy sensitivity
    α_rad::Float64 = 8.0                  # Radial velocity sensitivity
    α_tan::Float64 = 8.0                  # Tangential velocity sensitivity
    # Per-channel maximum haze
    h_max_occ::Float64 = 0.8              # Max haze for occupancy
    h_max_rad::Float64 = 0.6              # Max haze for radial velocity
    h_max_tan::Float64 = 0.6              # Max haze for tangential velocity

    # FOV parameters
    fov_angle::Float64 = 120.0 * π / 180.0  # 120 degrees in radians
    fov_range::Float64 = 100.0     # Perception range
end

end
