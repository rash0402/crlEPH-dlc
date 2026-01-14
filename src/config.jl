"""
EPH System Configuration
All constants and parameters for the simulation
"""

module Config

export SPMParams, WorldParams, AgentParams, ControlParams, CommParams, FoveationParams
export DEFAULT_SPM, DEFAULT_WORLD, DEFAULT_AGENT, DEFAULT_CONTROL, DEFAULT_COMM, DEFAULT_FOVEATION

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
    beta_r_min=0.5,      # v6.1: Blur時の低解像度
    beta_r_max=10.0,     # v6.1: Clear時の高解像度（5.0 → 10.0に変更）
    beta_nu_min=0.5,     # v6.1: Blur時の低解像度
    beta_nu_max=10.0     # v6.1: Clear時の高解像度（5.0 → 10.0に変更）
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
"""
Agent physical parameters (v7.2: Pedestrian model)

Physical changes from v6.x:
- mass: 1.0 kg → 70.0 kg (adult pedestrian)
- damping: 0.5 N/s → 0.5 N·s²/m² (quadratic drag coefficient)
- u_max: 10.0 N → 150.0 N (walking force)
- k_align: NEW - 4.0 rad/s (heading alignment gain)
"""
struct AgentParams
    mass::Float64           # Agent mass [kg]
    damping::Float64        # Drag coefficient [N·s²/m²] (v7.2: quadratic drag)
    r_agent::Float64        # Agent radius [m]
    n_agents_per_group::Int # Number of agents per group (N/S/E/W)
    u_max::Float64          # Maximum control force magnitude [N]
    k_align::Float64        # Heading alignment gain [rad/s] (v7.2: NEW)
    # Emergency avoidance parameters (v6.3 data collection only)
    k_emergency::Float64          # Emergency repulsion strength
    emergency_threshold_obs::Float64   # Distance threshold for obstacle avoidance
    emergency_threshold_agent::Float64 # Distance threshold for agent avoidance
    enable_emergency::Bool        # Enable/disable emergency avoidance
end

function AgentParams(;
    mass=70.0,              # v7.2: Adult pedestrian mass (was 1.0 kg)
    damping=0.5,            # v7.2: Quadratic drag coefficient [N·s²/m²]
    r_agent=0.5,            # Agent radius (human shoulder width ~0.5m)
    n_agents_per_group=10,
    u_max=150.0,            # v7.2: Walking force (was 10.0 N)
    k_align=4.0,            # v7.2: Heading alignment gain [rad/s] (τ ≈ 0.25s)
    k_emergency=20.0,       # v6.3 data collection parameter
    emergency_threshold_obs=0.3,
    emergency_threshold_agent=1.1,
    enable_emergency=true
)
    AgentParams(mass, damping, r_agent, n_agents_per_group, u_max, k_align,
                k_emergency, emergency_threshold_obs, emergency_threshold_agent, enable_emergency)
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
    use_predictive_control::Bool  # Enable M4 predictive collision avoidance
    # v6.0/v6.1 Free Energy weights
    k_2::Float64           # Weight for Ch2 (Proximity Saliency)
    k_3::Float64           # Weight for Ch3 (Collision Risk)
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
    use_vae=true,  # Default: VAE enabled
    use_predictive_control=false,  # Default: reactive control (M3 baseline)
    k_2=100.0,    # v6.1 推奨値: Proximity Gain
    k_3=1000.0    # v6.1 推奨値: Collision Gain
)
    ControlParams(eta, sigma_safe, T_th, beta_ttc, epsilon, exploration_rate, exploration_noise, experiment_condition, use_vae, use_predictive_control, k_2, k_3)
end

# ===== Foveation Parameters (v6.1) =====
"""
Parameters for Bin-Based Fixed Foveation strategy (v6.1)

Bin-Based step function (replaces sigmoid Dual-Zone):
  - Bin 1-6 (0-2.18m @ D_max=8m): Haze=0.0 (Critical collision zone)
  - Bin 7+ (2.18m+): Haze=0.5 (Peripheral zone)

Theoretical justification:
  1. Neuroscience: Peripersonal Space (PPS) 0.5-2.0m + margin → Bin 1-6
  2. Active Inference: High precision for survival-critical predictions
  3. Empirical: Avoidance initiation 2-3m (Moussaïd et al., 2011)
  4. Control: TTC 1s (predictive control) → 2.1m → Bin 6

Note: For n_rho=16, sensing_ratio=8.0:
  - rho_index_critical=6 → 0-2.18m (recommended, covers PPS + predictive control)
  - rho_index_critical=7 → 0-2.48m (more conservative, TTC 1.4s)
"""
struct FoveationParams
    rho_index_critical::Int  # Bin index threshold (Bin 1-rho_index_critical: Haze=0)
    h_critical::Float64      # Haze in Critical Zone (typically 0.0)
    h_peripheral::Float64    # Haze in Peripheral Zone (typically 0.5)
end

function FoveationParams(;
    rho_index_critical=6,    # v6.1: Bin 1-6 Haze=0 (0-2.18m @ D_max=8m)
    h_critical=0.0,          # Critical Zone: Maximum Precision (β=β_max)
    h_peripheral=0.5         # Peripheral Zone: Medium Precision (β≈β_mid)
)
    FoveationParams(rho_index_critical, h_critical, h_peripheral)
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
const DEFAULT_SPM = SPMParams(
    n_rho=12,
    n_theta=12,
    sensing_ratio=3.0  # v6.3: Human-like cognitive range (D_max=6.0m), optimized resolution
)
const DEFAULT_WORLD = WorldParams()
const DEFAULT_AGENT = AgentParams()
const DEFAULT_CONTROL = ControlParams()
const DEFAULT_COMM = CommParams()
const DEFAULT_FOVEATION = FoveationParams()  # v6.1 Dual-Zone defaults

end # module
