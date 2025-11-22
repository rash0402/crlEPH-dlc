# crlEPH-dlc: Emergent Perceptual Haze (EPH) Framework

[![Julia](https://img.shields.io/badge/Julia-1.9%2B-9558B2?logo=julia)](https://julialang.org/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python)](https://www.python.org/)
[![License](https://img.shields.io/badge/License-Research-blue.svg)]()

A research implementation of the **Emergent Perceptual Haze (EPH)** framework for swarm intelligence, combining **Active Inference** and **Free Energy Principle** with bio-inspired perception for gradient-based multi-agent coordination.

## 🎯 Overview

EPH enables multi-agent coordination through **self-hazing** - a precision modulation mechanism where agents dynamically adjust their perceptual uncertainty based on local occupancy. This creates emergent exploration-exploitation behavior without explicit communication.

### Core Concepts

- **Active Inference**: Agents minimize Expected Free Energy (EFE) through gradient descent
- **Self-Hazing**: Belief entropy modulation based on SPM occupancy (`h_self(Ω)`)
- **Saliency Polar Map (SPM)**: Bio-inspired log-polar visual representation (V1 cortex)
- **Gradient-Based Control**: Pure gradient descent on EFE - **no force fields or repulsion**
- **Stigmergy**: Environmental coordination through precision modulation

### Key Innovation

**Collision avoidance emerges purely from gradients** - no repulsion forces, no collision detection:
```julia
# Only gradient descent on Expected Free Energy
grad = ∇_a G(a) where G(a) = F_percept + β·H[q(s|a)] + λ·M_meta
action ← action - η·grad
```

High occupancy → Low self-haze → High precision → Strong collision avoidance
Low occupancy → High self-haze → Low precision → Exploratory behavior

## 🚀 Quick Start

### Prerequisites

- **Julia 1.9+** (via [juliaup](https://github.com/JuliaLang/juliaup))
- **Python 3.8+** (for visualization only)
- **ZeroMQ** (bundled with Julia/Python packages)

### Installation

```bash
# Clone repository
git clone <repository-url>
cd crlEPH-dlc

# Install Julia dependencies
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd ..

# Install Python dependencies (for viewer)
pip install -r requirements.txt
```

### Run Simulation

```bash
# Full simulation with visualization
./scripts/run_experiment.sh

# Julia server only (headless)
cd src_julia && julia --project=. main.jl

# Python viewer only (requires server running)
export PYTHONPATH=.
python viewer.py
```

Press `Ctrl+C` to stop. The script automatically cleans up ZeroMQ ports.

## 📊 Visualization

The viewer displays:

### Pygame Window (800×800)
- **Agents**: Red (tracked Agent 1), Blue (others)
- **FOV Sectors**: Color indicates self-haze
  - Red/Pink = High self-haze (isolated, exploration mode)
  - Blue/Cyan = Low self-haze (with neighbors, exploitation mode)
- **Red Arrow**: Gradient vector `-∇G` showing descent direction
- **Numbers**: Visible neighbor count
- **On-screen metrics**: Gradient values `∇G=[x, y]`, norm

### Matplotlib Windows

**Time Series (4 subplots)**:
1. Expected Free Energy (EFE)
2. Self-Haze & Belief Entropy
3. **Gradient Norm** `||∇G||` - proves gradient-based control
4. Visibility & Speed

**SPM Heatmaps (3 channels)**:
- Occupancy channel (log-polar bins)
- Radial velocity
- Tangential velocity

## 📁 Project Structure

```
crlEPH-dlc/
├── README.md                     # This file
├── CLAUDE.md                     # Developer onboarding guide
├── requirements.txt              # Python dependencies (viewer)
│
├── src_julia/                    # Julia implementation (main)
│   ├── main.jl                   # ZeroMQ server entry point
│   ├── Simulation.jl             # Main simulation loop
│   ├── Project.toml              # Julia dependencies
│   ├── core/
│   │   └── Types.jl              # Agent, Environment, EPHParams
│   ├── perception/
│   │   └── SPM.jl                # Saliency Polar Map computation
│   ├── control/
│   │   ├── SelfHaze.jl           # Self-haze & precision computation
│   │   └── EPH.jl                # Gradient-based EFE minimization
│   └── utils/
│       └── MathUtils.jl          # Toroidal geometry utilities
│
├── viewer.py                     # Python/Pygame visualization client
│
├── scripts/
│   └── run_experiment.sh         # Launch server + viewer
│
├── doc/
│   ├── EPH_Active_Inference_Derivation.md      # Mathematical derivation
│   ├── EPH_Implementation_Guide_Julia.md       # Implementation guide
│   ├── 20251121_Emergent Perceptual Haze (EPH).md
│   └── 20251120_Saliency Polar Map (SPM).md
│
└── archive/
    └── python_legacy/            # Original Python implementation (archived)
```

## 🧪 Architecture

### Communication Flow

```
Julia Server (port 5555)  ──ZeroMQ PUB/SUB──>  Python Viewer
     ↓                                              ↓
  Simulation                                   Pygame Rendering
  SPM Computation                              Matplotlib Plots
  Self-Haze Calculation                        SPM Heatmaps
  EFE Gradient Descent                         Gradient Visualization
```

### Active Inference Pipeline

```julia
# 1. Perception: Compute SPM
spm = compute_spm(agent, env, params)

# 2. Self-Hazing: Compute belief entropy
h_self = compute_self_haze(spm, params)  # Sigmoid based on occupancy
Π = compute_precision_matrix(spm, h_self, params)
H_belief = compute_belief_entropy(Π)

# 3. Action Selection: Minimize Expected Free Energy
G(a) = F_percept(a, Π) + β·H_belief + λ·M_meta(a)
grad = Zygote.gradient(a -> G(a), action)
action ← action - η·grad  # Pure gradient descent

# 4. Physics: Integrate velocity
position += velocity * dt
```

### Key Implementation Details

**SPM Tensor**: `(3, Nr, Nθ)` where:
- Channel 1: Occupancy (Gaussian splatting for differentiability)
- Channel 2: Radial velocity
- Channel 3: Tangential velocity

**Self-Haze Function**:
```julia
Ω = mean(spm[1, :, :])  # Average occupancy
h_self = h_max · sigmoid(-α(Ω - Ω_threshold))
```

**Precision Modulation**:
```julia
Π[r,θ] = Π_base[r,θ] · (1 - h_self)^γ
```

**Current Parameters** (tuned for 400×400 world, 10 agents):
- `α = 10.0` (sensitivity, was 2.0)
- `Ω_threshold = 0.05` (realistic occupancy range 0.0-0.15)
- `β = 1.0` (entropy weight, was 0.5)
- `γ = 2.0` (haze attenuation exponent)
- `FOV = 210° × 100px`

## 📊 Current Scenario

**Sparse Foraging Task**
- **10 agents** in **400×400 toroidal world** (displayed as 800×800)
- **No explicit goals** - pure epistemic foraging
- **Hypothesis Testing**: Agents transition between:
  1. **Isolated (high self-haze)** → Exploration (high entropy)
  2. **Encountering neighbors (low self-haze)** → Exploitation (collision avoidance)
  3. **Separating** → Back to exploration

**Observation**: Coverage ~50% at frame 100 with emergent coordination

## 🛠️ Development

### Key Commands

```bash
# Julia REPL testing
cd src_julia && julia --project=.

# Check gradient flow
julia> using Zygote
julia> gradient(a -> expected_free_energy(a, agent, spm, nothing, params), action)

# Type stability (performance)
julia> @code_warntype decide_action(controller, agent, spm, nothing)

# Check ZeroMQ port
lsof -i :5555
```

### Design Constraints

- **Differentiability**: All functions in EFE path must support Zygote AD
  - No in-place mutations (`.=`)
  - Use array comprehensions instead of loops with mutations
- **Toroidal distances**: Always use `toroidal_distance()`, never naive Euclidean
- **Coordinate systems**:
  - World: Cartesian (x, y) with wrap-around
  - Agent-relative: Polar (r, θ) where θ=0 is forward
  - SPM: Log-polar bins

See `CLAUDE.md` for comprehensive development guidelines.

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)**: Developer guide (architecture, commands, conventions)
- **[doc/EPH_Active_Inference_Derivation.md](doc/EPH_Active_Inference_Derivation.md)**: Mathematical derivation
- **[doc/EPH_Implementation_Guide_Julia.md](doc/EPH_Implementation_Guide_Julia.md)**: Implementation details
- **[doc/](doc/)**: Research proposals and technical specifications

## 🔬 Research Status

**Current Phase**: Active Inference implementation with gradient visualization

**Completed**:
- ✅ Julia-based simulation core
- ✅ SPM with Gaussian splatting (differentiable)
- ✅ **Active Inference formulation** (Expected Free Energy)
- ✅ **Self-hazing mechanism** (belief entropy modulation)
- ✅ **Gradient-based action selection** (Zygote AD)
- ✅ **Gradient visualization** (red arrow on screen)
- ✅ ZeroMQ communication protocol
- ✅ Real-time Pygame + Matplotlib visualization
- ✅ SPM heatmap visualization

**Key Verification**:
- ✅ **Pure gradient-based collision avoidance** (no repulsion forces)
- ✅ Gradient values displayed on screen: `∇G=[x, y]`
- ✅ Self-haze transitions: Red FOV (isolated) ↔ Blue FOV (with neighbors)
- ✅ Parameter tuning: 50% self-haze change on encounter (was 3.3%)

**Next Steps**:
- Baseline comparisons (Random Walk, Potential Field, ACO)
- Statistical validation (coverage efficiency, interaction rates)
- Scalability testing (agent count, world size)
- Mathematical analysis (convergence proofs, stability)

## 🎓 Theoretical Foundation

**Active Inference**: Agents act to minimize Expected Free Energy
```
G(a) = E_q[log q(s|a) - log p(o,s)] + KL[q(s|a)||q(s)]
     = F_percept(a) + β·H[q(s|a)] + λ·M_meta(a)
```

**Self-Hazing Hypothesis**:
```
Low occupancy Ω → High self-haze h → Low precision Π
→ High covariance Σ = Π^(-1) → High entropy H[q]
→ Epistemic term dominates → Exploration emerges
```

**Gradient Flow**:
```
∂G/∂a = ∂F_percept/∂a + β·∂H/∂a + λ·∂M_meta/∂a

Where F_percept penalizes moving towards occupied bins:
F_percept = Σ_{r,θ} occupancy[r,θ] · precision[r,θ] · alignment(a,θ) · dist_decay(r)
```

## 🤝 Contributing

This is a research project. For contributions:
1. Read `CLAUDE.md` for code conventions
2. Ensure Zygote-compatible code (test with `gradient()`)
3. Run `./scripts/run_experiment.sh` to verify changes
4. Use conventional commit messages (see `CLAUDE.md`)

## 📝 License

Research prototype. License TBD.

## 🔗 Related Work

- **Active Inference**: Friston et al. (2010-2023)
- **Free Energy Principle**: Friston (2010)
- **Log-Polar Mapping**: Schwartz (1977), Traver & Bernardino (2010)
- **Stigmergy**: Grassé (1959), Theraulaz & Bonabeau (1999)
- **Gradient-Based Swarms**: Olfati-Saber & Murray (2004), Reynolds (1987)

## 📧 Contact

For questions about this implementation, see `CLAUDE.md` or open an issue.

---

**Note**: This project transitioned from Python to Julia (2025-11-22) and implemented Active Inference formulation (2025-11-22). Legacy Python code is archived in `archive/python_legacy/`.

**Citation**: If you use this code in your research, please cite:
```
@misc{crleph2025,
  title={crlEPH-dlc: Gradient-Based Emergent Perceptual Haze for Swarm Coordination},
  author={[Your Name]},
  year={2025},
  publisher={GitHub},
  url={[repository-url]}
}
```
