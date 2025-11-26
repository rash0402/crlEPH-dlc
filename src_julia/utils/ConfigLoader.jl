module ConfigLoader

using YAML
using ..Types

export load_config, SimulationConfig

"""
Configuration structure for the entire simulation.
Loaded from YAML file.
"""
struct SimulationConfig
    # World configuration
    world_width::Float64
    world_height::Float64
    n_agents::Int

    # Agent configuration
    agent_radius::Float64
    max_speed::Float64
    personal_space::Float64

    # Coverage configuration
    grid_size::Int

    # EPH parameters (subset, full params in EPHParams)
    eph_params::Dict{String, Any}

    # Simulation parameters
    dt::Float64
    log_interval::Int
end

"""
    load_config(config_path::String) -> SimulationConfig

Load simulation configuration from YAML file.

# Arguments
- `config_path`: Path to YAML configuration file (default: "../config/simulation.yaml")

# Returns
- `SimulationConfig`: Parsed configuration structure
"""
function load_config(config_path::String="../config/simulation.yaml")::SimulationConfig
    # Resolve relative path from src_julia directory
    if !isabspath(config_path)
        config_path = joinpath(@__DIR__, "..", config_path)
    end

    if !isfile(config_path)
        @warn "Config file not found: $config_path. Using default values."
        return _default_config()
    end

    println("Loading configuration from: $config_path")
    config_dict = YAML.load_file(config_path)

    # Extract values with defaults
    world = get(config_dict, "world", Dict())
    agent = get(config_dict, "agent", Dict())
    coverage = get(config_dict, "coverage", Dict())
    eph = get(config_dict, "eph", Dict())
    simulation = get(config_dict, "simulation", Dict())

    SimulationConfig(
        # World
        get(world, "width", 300.0),
        get(world, "height", 300.0),
        get(world, "n_agents", 10),

        # Agent
        get(agent, "radius", 3.0),
        get(agent, "max_speed", 50.0),
        get(agent, "personal_space", 20.0),

        # Coverage
        get(coverage, "grid_size", 5),

        # EPH (stored as dict for flexibility)
        eph,

        # Simulation
        get(simulation, "dt", 0.1),
        get(simulation, "log_interval", 10)
    )
end

"""
    _default_config() -> SimulationConfig

Return default configuration when file is not found.
"""
function _default_config()::SimulationConfig
    SimulationConfig(
        300.0, 300.0, 10,  # world
        3.0, 50.0, 20.0,   # agent
        5,                  # coverage grid_size
        Dict{String, Any}(),  # eph_params (empty, use EPHParams defaults)
        0.1, 10             # simulation
    )
end

"""
    create_eph_params(config::SimulationConfig) -> EPHParams

Create EPHParams from configuration.

# Arguments
- `config`: SimulationConfig loaded from YAML

# Returns
- `EPHParams`: EPH parameters with values from config or defaults
"""
function create_eph_params(config::SimulationConfig)::Types.EPHParams
    eph = config.eph_params

    Types.EPHParams(
        # Self-hazing
        h_max = get(eph, "h_max", 0.8),
        α = get(eph, "alpha", 10.0),
        Ω_threshold = get(eph, "omega_threshold", 0.12),
        γ = get(eph, "gamma", 2.0),

        # EFE weights
        β = get(eph, "beta", 1.0),
        λ = get(eph, "lambda", 0.1),
        γ_info = get(eph, "gamma_info", 0.5),

        # Precision
        Π_max = get(eph, "pi_max", 1.0),
        decay_rate = get(eph, "decay_rate", 0.1),

        # Gradient descent
        max_iter = get(eph, "max_iter", 5),
        η = get(eph, "learning_rate", 0.1),

        # Physical
        max_speed = config.max_speed,
        max_accel = get(eph, "max_accel", 100.0),

        # FOV
        fov_angle = get(eph, "fov_angle", 210.0) * π / 180.0,
        fov_range = get(eph, "fov_range", 100.0),

        # Prediction
        prediction_dt = get(eph, "prediction_dt", 0.1),
        predictor_type = Symbol(get(eph, "predictor_type", "neural")),
        collect_data = get(eph, "collect_data", true),

        # Uncertainty
        uncertainty_alpha = get(eph, "uncertainty_alpha", 0.3),
        uncertainty_window = get(eph, "uncertainty_window", 10),
        uncertainty_enabled = get(eph, "uncertainty_enabled", true)
    )
end

end  # module ConfigLoader
