"""
EPH System Configuration
All constants and parameters for the simulation
"""

module Config

export SPMParams, WorldParams, AgentParams, ControlParams, CommParams
export DEFAULT_SPM, DEFAULT_WORLD, DEFAULT_AGENT, DEFAULT_CONTROL, DEFAULT_COMM

# ===== SPM Parameters =====
struct SPMParams
    n_rho::Int              # Radial resolution
    n_theta::Int            # Angular resolution
    fov_deg::Float64        # Field of view in degrees
    fov_rad::Float64        # Field of view in radians
    r_robot::Float64        # Robot body radius
    sensing_ratio::Float64  # Sensing distance ratio (D = ratio * r_total)
    sigma_spm::Float64      # Gaussian blur sigma for region projection
    beta_r_fixed::Float64   # Fixed beta for proximity softmin (M1 baseline)
    beta_nu_fixed::Float64  # Fixed beta for velocity softmax (M1 baseline)
    # Adaptive β(H) modulation parameters (M2)
    beta_r_min::Float64     # Minimum β_r (high uncertainty → smooth aggregation)
    beta_r_max::Float64     # Maximum β_r (low uncertainty → sharp aggregation)
    beta_nu_min::Float64    # Minimum β_ν (high uncertainty → smooth aggregation)
    beta_nu_max::Float64    # Maximum β_ν (low uncertainty → sharp aggregation)
end

function SPMParams(;
    n_rho=16,
    n_theta=16,
    fov_deg=210.0,
    r_robot=1.5,
    sensing_ratio=15.0,
    sigma_spm=0.25,
    beta_r_fixed=5.0,
    beta_nu_fixed=5.0,
    beta_r_min=1.0,      # Smooth aggregation when uncertain
    beta_r_max=10.0,     # Sharp aggregation when confident
    beta_nu_min=1.0,     # Smooth aggregation when uncertain
    beta_nu_max=10.0     # Sharp aggregation when confident
)
    SPMParams(
        n_rho,
        n_theta,
        fov_deg,
        deg2rad(fov_deg),
        r_robot,
        sensing_ratio,
        sigma_spm,
        beta_r_fixed,
        beta_nu_fixed,
        beta_r_min,
        beta_r_max,
        beta_nu_min,
        beta_nu_max
    )
end

# ===== Experiment Conditions (Ablation Study) =====
"""
Experiment conditions for ablation study (EPH Proposal 4.3)
- A1_BASELINE: Fixed β, no SPM, Cartesian (complete baseline)
- A2_SPM_ONLY: Fixed β, SPM, Polar (SPM contribution)
- A3_ADAPTIVE_BETA: Adaptive β(H), no SPM, Cartesian (β modulation contribution)
- A4_EPH: Adaptive β(H), SPM, Polar (full EPH - proposed method)
"""
@enum ExperimentCondition begin
    A1_BASELINE = 1
    A2_SPM_ONLY = 2
    A3_ADAPTIVE_BETA = 3
    A4_EPH = 4
end

# ===== World Parameters =====
struct WorldParams
    width::Float64          # Torus world width
    height::Float64         # Torus world height
    dt::Float64             # Time step
    max_steps::Int          # Maximum simulation steps
    obstacle_size::Float64  # Size of corner obstacles
    center_margin::Float64  # Margin from center for goal placement
end

function WorldParams(;
    width=100.0,
    height=100.0,
    dt=0.033,  # ~30Hz
    max_steps=3000,
    obstacle_size=15.0,
    center_margin=30.0
)
    WorldParams(width, height, dt, max_steps, obstacle_size, center_margin)
end

# ===== Agent Parameters =====
struct AgentParams
    mass::Float64           # Agent mass
    damping::Float64        # Damping coefficient
    r_agent::Float64        # Agent radius
    n_agents_per_group::Int # Number of agents per group (N/S/E/W)
    u_max::Float64          # Maximum control input magnitude
end

function AgentParams(;
    mass=1.0,
    damping=0.5,
    r_agent=1.5,
    n_agents_per_group=10,
    u_max=10.0
)
    AgentParams(mass, damping, r_agent, n_agents_per_group, u_max)
end

# ===== Control Parameters =====
struct ControlParams
    eta::Float64            # Learning rate for gradient descent
    sigma_safe::Float64     # Safety distance for saliency calculation
    T_th::Float64           # TTC threshold for risk calculation
    beta_ttc::Float64       # Sigmoid steepness for TTC
    epsilon::Float64        # Small value for numerical stability
    exploration_rate::Float64  # Probability of random action (0.0 = no exploration)
    exploration_noise::Float64 # Std of Gaussian noise added to actions
    experiment_condition::ExperimentCondition  # Ablation study condition
    use_vae::Bool          # Enable VAE for Haze computation
end

function ControlParams(;
    eta=1.0,
    sigma_safe=3.0,
    T_th=2.0,
    beta_ttc=2.0,
    epsilon=1e-6,
    exploration_rate=0.0,  # Default: no exploration
    exploration_noise=0.0,  # Default: no noise
    experiment_condition=A4_EPH,  # Default: full EPH
    use_vae=true  # Default: VAE enabled
)
    ControlParams(eta, sigma_safe, T_th, beta_ttc, epsilon, exploration_rate, exploration_noise, experiment_condition, use_vae)
end

# ===== Communication Parameters =====
struct CommParams
    zmq_endpoint::String    # ZMQ PUB endpoint
    global_topic::String    # Topic for global state
    detail_topic::String    # Topic for detail state
end

function CommParams(;
    zmq_endpoint="tcp://127.0.0.1:5555",
    global_topic="global",
    detail_topic="detail"
)
    CommParams(zmq_endpoint, global_topic, detail_topic)
end

# ===== Default Configuration =====
const DEFAULT_SPM = SPMParams(sensing_ratio=7.5)  # Halved from 15.0 to reduce sensing distance
const DEFAULT_WORLD = WorldParams()
const DEFAULT_AGENT = AgentParams()
const DEFAULT_CONTROL = ControlParams()
const DEFAULT_COMM = CommParams()

end # module
