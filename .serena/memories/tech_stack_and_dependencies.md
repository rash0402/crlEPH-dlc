# Tech Stack and Dependencies (Updated 2026-01-09)

## Primary Language: Julia 1.10+

### Julia Runtime
- **Installation**: Via `juliaup` package manager (recommended)
- **Version**: Julia 1.10 or later (Apple Silicon M2 optimized)
- **Project activation**: `julia --project=.` in repository root
- **Package environment**: `Project.toml` + `Manifest.toml` (Manifest.toml gitignored)

### Julia Dependencies (Project.toml)

**Neural Networks & Differentiation:**
- **Flux** (`587475ba-b771-5e3f-ad9e-33799f191a9c`) - Neural network framework for VAE implementation
- **Zygote** (`e88e6eb3-aa80-5325-afca-941959d7151f`) - Reverse-mode AD for VAE training (∂Loss/∂θ)
- **ForwardDiff** (`f6369f11-7733-5829-9624-2563aa707210`) - Forward-mode AD for action gradient (∂F/∂u)

**Communication & Serialization:**
- **ZMQ** (`c2297ded-f4af-51ae-bb23-16f91089e4e1`) - ZeroMQ for inter-process communication (Julia PUB → Python SUB)
- **MsgPack** (`99f44e22-a591-53d1-9472-aa23ef4bd671`) - Efficient binary serialization for ZMQ messages

**Data Management:**
- **HDF5** (`f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f`) - High-performance data logging (simulation logs, VAE training data)
- **FileIO** - Unified file I/O interface
- **BSON** (`fbb218c0-5317-5bc6-957e-2ee96dd4b1f0`) - Julia object serialization (VAE model checkpoints)

**Standard Libraries:**
- **LinearAlgebra** - Matrix operations for SPM, dynamics, control
- **Random** - Random number generation for initialization, sampling
- **Statistics** - Statistical utilities for data analysis
- **Distributions** - Probability distributions (Gaussian for VAE reparameterization)

### Installation
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
This reads `Project.toml` and installs all dependencies into project-local environment.

### Development Tools
```bash
# Julia REPL (interactive testing)
julia --project=.

# Run script
julia --project=. scripts/run_simulation.jl

# Add new package
julia --project=. -e 'using Pkg; Pkg.add("PackageName")'

# Update all packages
julia --project=. -e 'using Pkg; Pkg.update()'
```

## Secondary Language: Python 3.10+

### Python Runtime
- **Virtual environment**: `~/local/venv/` (project-specific isolation)
- **Activation**: `source ~/local/venv/bin/activate`
- **Purpose**: **Visualization only** (no computation)
- **Architecture**: Separate processes communicate via ZMQ

### Python Dependencies (requirements.txt)

**Visualization (Production):**
- **pygame** ≥2.5.0 - Real-time rendering for main viewer
  - Agent circles, FOV sectors, color-coded groups
  - Smooth 60 FPS visualization
- **matplotlib** ≥3.7.0 - SPM channel visualization (detail viewer)
  - 3-channel heatmaps (Occupancy, Saliency, Risk)
  - Time-series plots (Haze, Precision, Jerk)
- **numpy** ≥1.24.0 - Array operations for rendering

**Communication:**
- **pyzmq** ≥25.0.0 - ZeroMQ client (SUB socket)
- **msgpack** ≥1.0.0 - Binary message deserialization

**Optional (Analysis):**
- **h5py** - Read HDF5 logs for offline analysis
- **pandas** - DataFrame for metrics aggregation
- **seaborn** - Statistical visualization

### Installation
```bash
pip install -r requirements.txt
```

## Communication Protocol

### ZeroMQ Architecture
- **Pattern**: PUB-SUB (one-to-many broadcast)
- **Julia Side**: PUB socket on `tcp://127.0.0.1:5555`
- **Python Side**: SUB socket subscribing to all topics
- **Frequency**: 30-60 Hz (real-time streaming)

### Message Format (MessagePack)

**Global Topic** (`"global"`):
```python
{
  "step": int,                    # Simulation timestep
  "agents": [                     # All agents in world
    {
      "id": int,
      "x": float, "y": float,     # Position
      "vx": float, "vy": float,   # Velocity
      "group": int,               # Group ID (0-3: N/S/E/W)
      "radius": float
    }, ...
  ]
}
```

**Detail Topic** (`"detail"`):
```python
{
  "step": int,
  "agent_id": int,                # Focused agent
  "spm": [[[float]]] ,            # 16x16x3 SPM tensor
  "haze": float,                  # Current Haze value
  "precision": float,             # Current Precision (1/H or β)
  "action": [float, float],       # Selected action [ux, uy]
  "free_energy": float            # VFE value
}
```

### Port Usage
- **5555**: Julia ZMQ PUB socket (simulation server)
- No conflicts with system services (user-space port)

## Build & Deployment

### Docker Support
- **Dockerfile**: Located in `doc/Dockerfile`
- **Base Image**: Ubuntu 22.04
- **Purpose**: Reproducible environment for experiments
- **Status**: Available but not primary development method

### Native Development (Recommended)
- **macOS**: Primary platform (Darwin 25.2.0, Apple Silicon M2)
- **Linux**: Expected to work (not regularly tested)
- **Windows**: May require ZMQ configuration (WSL2 recommended)

## Data Formats

### HDF5 Logs (`data/logs/eph_sim_*.h5`)
```
/data/
  ├── spm        [16, 16, 3, T] Float32   # SPM time series
  ├── actions    [2, T]         Float32   # Control inputs
  ├── positions  [N, 2, T]      Float32   # Agent positions
  ├── velocities [N, 2, T]      Float32   # Agent velocities
  ├── haze       [T]            Float32   # Haze values
  └── precision  [T]            Float32   # Precision values
```

### VAE Model Checkpoints (`models/*.bson`)
- **Format**: BSON (Julia native serialization)
- **Contents**: Flux model state dict (encoder + decoder parameters)
- **Naming**: `action_vae_epoch_N.bson`, `action_vae_best.bson`
- **Size**: ~5-10 MB per checkpoint

### Training Data (`data/vae_training/`)
- **CSV format**: Comma-separated values
- **Files**:
  - `spm_current_*.csv`: Current SPM (16×16×3 flattened)
  - `spm_next_*.csv`: Next SPM (16×16×3 flattened)
  - `actions_*.csv`: Actions (2D vectors)

## Dependency Management Philosophy

1. **Minimal Core Dependencies**: Only essential packages (Flux, Zygote, ForwardDiff, ZMQ, HDF5)
2. **Separation of Concerns**: Julia for computation, Python for visualization only
3. **Reproducible Builds**: Lock files (Manifest.toml) for exact version control
4. **Virtual Environments**: Isolated Python packages (~/local/venv/)
5. **No Git LFS**: Binary files (.bson, .h5) gitignored, regenerate from scripts

## Performance Considerations

### Julia Compilation
- **First run**: ~30s JIT compilation overhead
- **Subsequent runs**: Pre-compiled, near-instant startup
- **Type stability**: All hot paths use concrete types for performance

### Memory Management
- **Julia GC**: Automatic garbage collection (generational)
- **HDF5 Chunking**: Efficient incremental writes (~1GB/hour)
- **VAE Inference**: Minimal allocation (~10ms per forward pass)

### Parallel Computing (Future)
- **Multi-threading**: Julia natively supports `Threads.@threads`
- **GPU**: Flux supports CUDA.jl for GPU acceleration (not currently used)
- **Distributed**: Multi-node experiments possible via `Distributed.jl`

## Version Compatibility

### Julia Package Versions (Project.toml)
```toml
Flux = "0.14"
Zygote = "0.6"
ForwardDiff = "0.10"
HDF5 = "0.17"
ZMQ = "1.2"
MsgPack = "1.2"
BSON = "0.3"
```

### Python Package Versions (requirements.txt)
```
pygame>=2.5.0
matplotlib>=3.7.0
numpy>=1.24.0
pyzmq>=25.0.0
msgpack>=1.0.0
```

## Troubleshooting

### Common Issues

**Julia Package Installation Fails:**
```bash
# Clear package cache and reinstall
rm -rf ~/.julia/compiled
julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
```

**ZMQ Port Already in Use:**
```bash
# Kill process on port 5555
lsof -ti :5555 | xargs kill -9
```

**Python Virtual Environment Issues:**
```bash
# Recreate venv
rm -rf ~/local/venv
python3 -m venv ~/local/venv
source ~/local/venv/bin/activate
pip install -r requirements.txt
```

**VAE Model Load Error:**
```bash
# Retrain VAE from scratch
julia --project=. scripts/train_action_vae.jl
```

## Security & Privacy

- **No external network access**: All communication is localhost-only
- **No telemetry**: No data sent to external servers
- **Reproducible experiments**: All random seeds configurable via `Random.seed!()`
