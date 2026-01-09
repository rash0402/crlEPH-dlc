# Project Structure and Architecture (Updated 2026-01-09)

## Overview
EPH (Emergent Perceptual Haze) v5.5 is a Julia-based implementation of Active Inference with Action-Conditioned VAE (Pattern D) for social robot navigation. The system achieves 36% Freezing reduction through adaptive perceptual resolution control.

## Current Implementation Status
- **Version**: v5.5 (Pattern D)
- **Milestones**: M1-M3 completed, M4 planned
- **Architecture**: Action-Dependent VAE with Counterfactual Haze

## Directory Structure

```
crlEPH-dlc/
├── src/                        # Julia core implementation
│   ├── config.jl              # System parameters (SPM, World, Agent, Control)
│   ├── spm.jl                 # Saliency Polar Map (16x16x3ch, adaptive β)
│   ├── action_vae.jl          # Pattern D: Encoder(y,u)→z, Decoder(z,u)→ŷ
│   ├── controller.jl          # EPH controller with Haze-based β modulation
│   ├── dynamics.jl            # Agent physics (toroidal world)
│   ├── communication.jl       # ZMQ PUB socket (port 5555)
│   ├── logger.jl              # HDF5 data logging
│   ├── metrics.jl             # Evaluation metrics (Freezing, Jerk, TTC)
│   ├── prediction.jl          # VAE-based future SPM prediction
│   ├── data_loader.jl         # Training data management
│   ├── vae.jl                 # Legacy VAE (deprecated)
│   └── autoencoder.jl         # Autoencoder utilities
│
├── scripts/                    # Execution scripts
│   ├── run_simulation.jl      # Main simulation entry point
│   ├── run_all.sh             # Launcher (Julia backend + Python viewers)
│   ├── train_action_vae.jl    # VAE training script
│   ├── validate_haze.jl       # Haze validation experiments
│   ├── validate_m4.jl         # M4 milestone validation
│   ├── evaluate_metrics.jl    # Metrics evaluation pipeline
│   └── collect_diverse_vae_data.jl  # Training data collection
│
├── viewer/                     # Python visualization (ZMQ clients)
│   ├── main_viewer.py         # 4-group scramble crossing display
│   ├── detail_viewer.py       # SPM 3-channel + metrics visualization
│   └── zmq_client.py          # ZMQ SUB socket client
│
├── doc/                        # Research documentation
│   ├── EPH-proposal_all_v5.5.md    # Full research proposal (v5.5)
│   ├── EPH_AI_DLC_Proposal.md      # Condensed proposal
│   └── Dockerfile             # Docker build specification
│
├── data/                       # Data directories
│   ├── logs/                  # Simulation HDF5 logs
│   └── vae_training/          # VAE training datasets
│
├── models/                     # Trained models
│   └── checkpoints/           # VAE checkpoints (.bson files)
│
├── results/                    # Experimental results
│   ├── haze_validation/       # Haze validation outputs
│   └── evaluation/            # Metrics evaluation results
│
├── CLAUDE.md                   # AI developer guide (v5.5 aligned)
├── README.md                   # Project overview
├── Project.toml                # Julia dependencies
└── requirements.txt            # Python dependencies
```

## Architecture Components

### 1. Julia Backend (`src/`)

**Pattern D VAE Architecture** (`action_vae.jl`):
```julia
Encoder: (y[k], u[k]) → q(z | y, u)     # Action-Dependent
Decoder: (z, u[k]) → ŷ[k+1]              # Action-Conditioned
Haze: H[k] = Agg(σ²_z(y[k], u[k]))      # Counterfactual Haze
```

**SPM Generation** (`spm.jl`):
- Resolution: 16×16×3 (Occupancy, Saliency, Risk)
- FOV: 210° (log-polar coordinates)
- Adaptive β modulation: β[k] = f(H[k])

**EPH Controller** (`controller.jl`):
- Method: Active Inference with gradient descent
- Free Energy: F = ‖x[k+1] - x_g‖² + λΣφ(ŷ)
- Optimization: ForwardDiff for ∂F/∂u

**Dynamics** (`dynamics.jl`):
- 2nd-order system: M·ẍ + D·ẋ = u
- Toroidal world: wrap-around boundaries
- 4-group scramble crossing scenario

### 2. Python Viewers (`viewer/`)

**Main Viewer** (`main_viewer.py`):
- 4-group color-coded visualization
- Real-time agent tracking
- ZMQ SUB subscriber (port 5555)

**Detail Viewer** (`detail_viewer.py`):
- SPM 3-channel display
- Haze/Precision time series
- Metrics overlay

### 3. Scripts Pipeline (`scripts/`)

**Training Pipeline**:
1. `collect_diverse_vae_data.jl` → VAE training data
2. `train_action_vae.jl` → Train Pattern D model
3. `validate_haze.jl` → Validate Haze correlation

**Evaluation Pipeline**:
1. `run_simulation.jl` → Generate logs
2. `evaluate_metrics.jl` → Compute metrics (Freezing, Jerk, TTC)
3. `validate_m4.jl` → M4 milestone validation

## Key Design Patterns

### Pattern D Causal Flow
```
u[k] proposed → H(y[k], u[k]) estimated → β[k+1] modulated
```

**Advantage**: "Risky action" → High Haze → Low Precision → Conservative behavior

### Differentiability
- All functions in SPM → Controller chain support ForwardDiff
- Gaussian splatting enables differentiable SPM projection
- Toroidal distance calculations preserve gradients

### Communication Protocol
- **Julia PUB**: Broadcasts state at 30-60 Hz (ZMQ)
- **Python SUB**: Receives and renders in real-time
- **Data format**: MessagePack for efficiency

## Data Structures

### HDF5 Logs (`data/logs/`)
```
/data/
  ├── spm       [16, 16, 3, T]  Float32
  ├── actions   [2, T]          Float32
  ├── positions [N, 2, T]       Float32
  ├── velocities [N, 2, T]      Float32
  ├── haze      [T]             Float32
  └── precision [T]             Float32
```

### VAE Training Data (`data/vae_training/`)
```
spm_current_*.csv   # y[k]
spm_next_*.csv      # y[k+1]
actions_*.csv       # u[k]
```

## Development Milestones

### Completed (M1-M3)
- ✅ M1: Base simulation + viewers
- ✅ M2: Pattern D VAE implementation
- ✅ M3: Integration & validation (36% Freezing reduction)

### Planned (M4)
- 🎯 Expected Free Energy (EFE) minimization
- 🎯 Ch3-centric evaluation (TTC-based risk)
- 🎯 Swarm extension (local Haze coordination)

## Configuration Management

**Julia Parameters** (`src/config.jl`):
```julia
SPMParams(n_rho=16, n_theta=16, fov_rad=210°, ...)
WorldParams(world_size=200.0, dt=0.1, ...)
AgentParams(mass=1.0, radius=1.5, ...)
ControlParams(lr=0.5, beta_min=0.1, beta_max=10.0, ...)
```

**Runtime Modification**: Parameters can be overridden via command-line args

## Performance Characteristics

- **Simulation Speed**: ~60 Hz (16 agents, toroidal world)
- **VAE Inference**: ~10ms per forward pass (CPU)
- **Memory Usage**: ~500MB (simulation + VAE)
- **Data Logging**: ~1GB/hour (HDF5 compressed)

## Version Control Notes

**Git LFS** (if enabled):
- `*.bson` (VAE models)
- `*.h5` (large HDF5 logs)

**Ignored Files** (`.gitignore`):
- `data/logs/`
- `results/*/`
- `Manifest.toml` (Julia lock file)
- `__pycache__/`

## Migration from Legacy Structure

Previous structure (`src_julia/`) has been consolidated into `src/`. Legacy Python prototype under `src/` (if present) is deprecated. Current active development uses Julia exclusively for computation, Python only for visualization.

## References

- Research Proposal: `doc/EPH-proposal_all_v5.5.md`
- Developer Guide: `CLAUDE.md`
- Setup Instructions: `SETUP.md`
