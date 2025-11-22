# crlEPH-dlc: Emergent Perceptual Haze (EPH) Framework

[![Julia](https://img.shields.io/badge/Julia-1.9%2B-9558B2?logo=julia)](https://julialang.org/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python)](https://www.python.org/)
[![PyQt5](https://img.shields.io/badge/PyQt5-5.15%2B-41CD52?logo=qt)](https://www.riverbankcomputing.com/software/pyqt/)
[![License](https://img.shields.io/badge/License-Research-blue.svg)]()

A research implementation of the **Emergent Perceptual Haze (EPH)** framework for swarm intelligence, combining **Active Inference** and **Free Energy Principle** with bio-inspired perception for gradient-based multi-agent coordination.

## 🎯 Overview

EPH enables multi-agent coordination through **self-hazing** - a precision modulation mechanism where agents dynamically adjust their perceptual uncertainty based on local occupancy. This creates emergent exploration-exploitation behavior without explicit communication.

### Core Concepts

- **Active Inference**: Agents minimize Expected Free Energy (EFE) through gradient descent
- **Self-Hazing**: Belief entropy modulation based on SPM occupancy (`h_self(Ω)`)
- **Prediction-Based Surprise**: Temporal surprise from prediction errors (Active Inference Phase 1)
- **Saliency Polar Map (SPM)**: Bio-inspired log-polar visual representation (V1 cortex)
- **Gradient-Based Control**: Pure gradient descent on EFE - **no force fields or repulsion**

### Key Innovation

**Collision avoidance emerges purely from gradients** - no repulsion forces, no collision detection:
```julia
# Only gradient descent on Expected Free Energy
grad = ∇_a G(a) where G(a) = F_percept + β·H[q(s|a)] + λ·M_meta + γ_info·I
action ← action - η·grad
```

**Surprise-driven exploration**: Prediction errors drive epistemic behavior
```julia
Surprise = Σ_{r,θ} Π[r,θ] · (SPM_observed - SPM_predicted)² · dist_weight
High surprise → Information gain → Exploration
```

High occupancy → Low self-haze → High precision → Strong collision avoidance
Low occupancy → High self-haze → Low precision → Exploratory behavior

## 🚀 Quick Start

### Prerequisites

- **Julia 1.9+** (via [juliaup](https://github.com/JuliaLang/juliaup))
- **Python 3.8+** with **PyQt5** (for visualization)
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

# Install Python dependencies (PyQt5 viewer)
pip install -r requirements.txt
```

### Run Simulation

```bash
# Full simulation with PyQt5 dashboard
./scripts/run_experiment.sh

# Julia server only (headless)
cd src_julia && julia --project=. main.jl

# Python viewer only (requires server running)
python viewer.py
```

Press `Ctrl+C` to stop. The script automatically cleans up ZeroMQ ports.

## 📊 PyQt5 Dashboard Visualization

The integrated PyQt5 viewer displays:

### Left Panel: Simulation View
- **Agents**: Red (tracked Agent 1), Blue (others)
- **FOV Sectors**: Semi-transparent field of view
- **Gradient Arrow (Red)**: Shows `-∇G` descent direction
  - Longer arrow = stronger gradient
  - Points away from obstacles
- **Frame & Coverage**: Real-time metrics

### Right Panel: Real-Time Plots

**Top Row (3 plots)**:
1. **Expected Free Energy (EFE)** - Total cost function
2. **Belief Entropy** - Combined spatial + temporal uncertainty
3. **Surprise (F_percept)** - Prediction error magnitude

**Middle Row (2 plots)**:
4. **Gradient Norm** - Proves gradient-based control
5. **Self-Haze** - Precision modulation level

**Bottom Row (3 plots)**:
6-8. **SPM Heatmaps** - Occupancy, Radial Velocity, Tangential Velocity

## 📁 Project Structure

```
crlEPH-dlc/
├── README.md                     # This file
├── CLAUDE.md                     # Developer onboarding guide
├── requirements.txt              # Python dependencies (PyQt5 viewer)
│
├── src_julia/                    # Julia implementation (main)
│   ├── main.jl                   # ZeroMQ server entry point
│   ├── Simulation.jl             # Main simulation loop
│   ├── Project.toml              # Julia dependencies
│   ├── core/
│   │   └── Types.jl              # Agent, Environment, EPHParams
│   ├── perception/
│   │   └── SPM.jl                # Saliency Polar Map computation
│   ├── prediction/
│   │   └── SPMPredictor.jl       # SPM prediction (Phase 1)
│   ├── control/
│   │   ├── SelfHaze.jl           # Self-haze & precision computation
│   │   └── EPH.jl                # Gradient-based EFE minimization
│   └── utils/
│       └── MathUtils.jl          # Toroidal geometry utilities
│
├── viewer.py                     # PyQt5 integrated dashboard
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
Julia Server (port 5555)  ──ZeroMQ PUB/SUB──>  PyQt5 Viewer
     ↓                                              ↓
  Simulation                                   Integrated Dashboard
  SPM Computation                              - Simulation rendering
  SPM Prediction (Phase 1)                     - Real-time plots
  Surprise Calculation                         - SPM heatmaps
  Self-Haze Calculation                        - Gradient visualization
  EFE Gradient Descent
```

### Active Inference Pipeline (Phase 1)

```julia
# 1. Perception: Compute SPM
spm = compute_spm(agent, env, params)

# 2. Prediction: Estimate next SPM (Phase 1)
spm_predicted = predict_spm(agent.previous_spm, agent.velocity, params)

# 3. Surprise: Prediction error
surprise = Σ Π[r,θ] · (spm - spm_predicted)² · dist_weight

# 4. Self-Hazing: Compute belief entropy
h_self = compute_self_haze(spm, params)  # Sigmoid based on occupancy
Π = compute_precision_matrix(spm, h_self, params)

# Spatial entropy (uncertainty over space)
H_spatial = compute_belief_entropy(Π)

# Temporal entropy (prediction error variance)
H_temporal = log(var(spm - spm_predicted) + ε)

# Combined belief entropy
H_belief = H_spatial + H_temporal

# 5. Action Selection: Minimize Expected Free Energy
G(a) = F_percept(a, Π) + β·H_belief + λ·M_meta(a) + γ_info·Surprise
grad = Zygote.gradient(a -> G(a), action)
action ← action - η·grad  # Pure gradient descent

# 6. Physics: Integrate velocity
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

**Surprise Calculation (Phase 1)**:
```julia
prediction_error = spm_current - spm_previous
surprise = Σ_{r,θ} Π[r,θ] · (w_occ·error_occ² + w_rad·error_rad² + w_tan·error_tan²) · dist_weight
```

**Current Parameters** (tuned for 300×300 world, 10 agents):
- `α = 10.0` (sensitivity, was 2.0)
- `Ω_threshold = 0.05` (realistic occupancy range 0.0-0.15)
- `β = 1.0` (entropy weight, was 0.5)
- `γ = 2.0` (haze attenuation exponent)
- `γ_info = 0.5` (information gain weight, **new in Phase 1**)
- `personal_space = 30.0` (collision buffer, was 20.0)
- `FOV = 210° × 100px`

## 📊 Current Scenario

**Sparse Foraging Task (Phase 1: Prediction-Based Surprise)**
- **10 agents** in **300×300 toroidal world** (smaller for frequent interactions)
- **No explicit goals** - pure epistemic foraging
- **Hypothesis Testing**: Agents transition between:
  1. **Isolated (high self-haze)** → Exploration (high entropy)
  2. **Encountering neighbors** → Surprise spike → Information-seeking
  3. **Predictable environment (low self-haze)** → Exploitation (collision avoidance)

**Phase 1 Features**:
- ✅ Linear SPM prediction (velocity-based extrapolation)
- ✅ Multi-channel surprise (occupancy + radial + tangential velocity)
- ✅ Temporal belief entropy (prediction error variance)
- ✅ Information gain term in EFE

**Observation**: High surprise when agents suddenly appear in FOV → Active exploration

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
- **PyQt5 Integration**: Use Qt signal/slot for safe cross-thread updates

See `CLAUDE.md` for comprehensive development guidelines.

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)**: Developer guide (architecture, commands, conventions)
- **[doc/EPH_Active_Inference_Derivation.md](doc/EPH_Active_Inference_Derivation.md)**: Mathematical derivation
- **[doc/EPH_Implementation_Guide_Julia.md](doc/EPH_Implementation_Guide_Julia.md)**: Implementation details
- **[doc/](doc/)**: Research proposals and technical specifications

## 🔬 Research Status

**Current Phase**: Active Inference Phase 1 - Prediction & Surprise

**Completed**:
- ✅ Julia-based simulation core
- ✅ SPM with Gaussian splatting (differentiable)
- ✅ **Active Inference formulation** (Expected Free Energy)
- ✅ **Self-hazing mechanism** (belief entropy modulation)
- ✅ **Gradient-based action selection** (Zygote AD)
- ✅ **Phase 1: Prediction-based surprise**
  - Linear SPM predictor
  - Multi-channel surprise calculation
  - Temporal belief entropy
  - Information gain term in EFE
- ✅ **PyQt5 integrated dashboard**
  - Unified simulation + plots window
  - Surprise plot
  - Gradient visualization
  - SPM heatmaps
- ✅ ZeroMQ communication protocol

**Key Verification**:
- ✅ **Pure gradient-based collision avoidance** (no repulsion forces)
- ✅ Gradient values visualized on screen: Red arrow shows `-∇G`
- ✅ Self-haze transitions: Isolated ↔ With neighbors
- ✅ **Surprise spikes on unpredicted encounters**
- ✅ Parameter tuning: 50% self-haze change on encounter (was 3.3%)

**Next Steps**:
- **Phase 2**: GRU-based SPM predictor (learned temporal dynamics)
- **Phase 3**: Goal inference from predicted SPM
- Baseline comparisons (Random Walk, Potential Field, ACO)
- Statistical validation (coverage efficiency, interaction rates, surprise correlation)
- Scalability testing (agent count, world size)
- Mathematical analysis (convergence proofs, stability)

## 🎓 Theoretical Foundation

**Active Inference (Phase 1)**: Agents minimize Expected Free Energy with information gain
```
G(a) = F_percept(a) + β·H[q(s|a)] + λ·M_meta(a) + γ_info·I[a]

Where:
- F_percept = Perceptual surprise (prediction error)
- H[q(s|a)] = Belief entropy (spatial + temporal)
- M_meta = Pragmatic value (goal seeking)
- I[a] = Information gain (epistemic value)
```

**Surprise (Prediction Error)**:
```
F_percept = Σ_{r,θ,c} Π[r,θ] · w[c] · (SPM_obs[c,r,θ] - SPM_pred[c,r,θ])² · dist_decay(r)

Where c ∈ {occupancy, radial_vel, tangential_vel}
```

**Self-Hazing Hypothesis**:
```
Low occupancy Ω → High self-haze h → Low precision Π
→ High covariance Σ = Π^(-1) → High spatial entropy H_spatial
→ Epistemic term dominates → Exploration emerges
```

**Temporal Uncertainty (Phase 1)**:
```
Prediction error variance → Temporal entropy H_temporal
High H_temporal → Unpredictable environment → Information-seeking behavior
```

**Gradient Flow**:
```
∂G/∂a = ∂F_percept/∂a + β·∂H/∂a + λ·∂M_meta/∂a + γ_info·∂I/∂a

Where F_percept penalizes moving towards occupied bins AND prediction errors:
F_percept = Σ_{r,θ} [occupancy[r,θ] · precision[r,θ] · alignment(a,θ) · dist_decay(r)
             + surprise[r,θ]]
```

## 🤝 Contributing

This is a research project. For contributions:
1. Read `CLAUDE.md` for code conventions
2. Ensure Zygote-compatible code (test with `gradient()`)
3. Test with PyQt5 viewer: `./scripts/run_experiment.sh`
4. Use conventional commit messages (see `CLAUDE.md`)

## 📝 License

Research prototype. License TBD.

## 🔗 Related Work

- **Active Inference**: Friston et al. (2010-2023)
- **Free Energy Principle**: Friston (2010)
- **Predictive Coding**: Rao & Ballard (1999)
- **Log-Polar Mapping**: Schwartz (1977), Traver & Bernardino (2010)
- **Stigmergy**: Grassé (1959), Theraulaz & Bonabeau (1999)
- **Gradient-Based Swarms**: Olfati-Saber & Murray (2004), Reynolds (1987)

## 📧 Contact

For questions about this implementation, see `CLAUDE.md` or open an issue.

---

**Note**: This project transitioned from Python to Julia (2025-11-22), implemented Active Inference formulation (2025-11-22), and added prediction-based surprise (Phase 1, 2025-11-22). Legacy Python code is archived in `archive/python_legacy/`.

**Citation**: If you use this code in your research, please cite:
```bibtex
@misc{crleph2025,
  title={crlEPH-dlc: Gradient-Based Emergent Perceptual Haze with Prediction-Based Surprise},
  author={[Your Name]},
  year={2025},
  publisher={GitHub},
  journal={Active Inference Framework for Swarm Coordination},
  url={[repository-url]}
}
```
