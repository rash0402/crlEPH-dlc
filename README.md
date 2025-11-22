# crlEPH-dlc: Emergent Perceptual Haze (EPH) Framework

[![Julia](https://img.shields.io/badge/Julia-1.9%2B-9558B2?logo=julia)](https://julialang.org/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python)](https://www.python.org/)
[![License](https://img.shields.io/badge/License-Research-blue.svg)]()

A research implementation of the **Emergent Perceptual Haze (EPH)** framework for swarm intelligence, combining Active Inference and Free Energy Principle with bio-inspired perception.

## 🎯 Overview

EPH enables multi-agent coordination through **spatial precision modulation** without explicit communication. Agents perceive their environment via a Saliency Polar Map (SPM) and adjust their behavior based on environmental "haze" fields that act as stigmergic signals.

### Core Concepts

- **Saliency Polar Map (SPM)**: Bio-inspired log-polar visual representation mimicking primate V1 cortex
- **Haze**: Precision modulation field that influences agent perception (not additive noise)
- **Active Inference**: Gradient-based action selection minimizing free energy
- **Stigmergy**: Environmental coordination through deposited haze trails

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
│   │   └── Types.jl              # Agent, Environment structs
│   ├── perception/
│   │   └── SPM.jl                # Saliency Polar Map computation
│   ├── control/
│   │   └── EPH.jl                # Gradient-based EPH controller
│   └── utils/
│       └── MathUtils.jl          # Toroidal geometry utilities
│
├── viewer.py                     # Python/Pygame visualization client
│
├── scripts/
│   ├── run_experiment.sh         # Launch server + viewer
│   ├── run_server.sh             # Julia server only
│   ├── run_viewer.sh             # Python viewer only
│   └── setup_env.sh              # Environment setup helper
│
├── doc/
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
  SPM Computation                              Agent/Haze Display
  EPH Controller
```

### Julia Implementation Highlights

- **Differentiable pipeline**: SPM → EPH → Action selection supports Zygote.jl gradients
- **Toroidal geometry**: World wraps at boundaries for infinite space simulation
- **Soft-mapping**: Gaussian kernels enable smooth, differentiable spatial binning
- **Performance**: 10-100× faster than Python for large-scale swarms

### SPM Tensor Structure

Shape: `(3, Nr, Nθ)` where:
- **Channel 1**: Occupancy (0.0 = free, 1.0 = obstacle)
- **Channel 2**: Radial velocity (+ approaching, - receding)
- **Channel 3**: Tangential velocity (+ left-to-right, - right-to-left)

Bins use log-polar spacing with personal space as inner zone.

## 📊 Current Scenario

**Scramble Crossing Simulation**
- 12 agents with random walk behavior
- Toroidal world (800×600 pixels)
- Agents deposit haze trails (stigmergy)
- Goal: Observe emergent coordination patterns

## 🛠️ Development

### Key Commands

```bash
# Julia REPL testing
cd src_julia && julia --project=.

# Check type stability (performance)
julia> using Zygote
julia> @code_warntype my_function(args)

# Test gradient flow
julia> gradient(a -> cost_function(a), action)

# Check port availability
lsof -i :5555
```

### Design Constraints

- **Differentiability**: All perception/control functions must support Zygote AD
- **Toroidal distances**: Always use `wrapped_distance()`, never naive Euclidean
- **Immutable operations**: No in-place array modifications in gradient paths

See `CLAUDE.md` for comprehensive development guidelines.

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)**: Developer guide (architecture, commands, conventions)
- **[doc/](doc/)**: Research proposals and technical specifications
- **[.serena/memories/](serena/memories/)**: MCP server context (auto-maintained)

## 🔬 Research Status

**Current Phase**: Prototype implementation

**Completed**:
- ✅ Julia-based simulation core
- ✅ SPM with Gaussian splatting
- ✅ Gradient-based EPH controller (Zygote)
- ✅ ZeroMQ communication protocol
- ✅ Real-time Pygame visualization

**Priority Improvements** (from AI-DLC Expert Review):
- **P0**: Baseline comparisons (Potential Field, ACO), statistical validation
- **P1**: Acceleration limits, convergence criteria, resolution sensitivity
- **P2**: Mathematical proofs, failure mode analysis

See `doc/` for detailed research proposals and expert feedback.

## 🤝 Contributing

This is a research project. For contributions:
1. Read `CLAUDE.md` for code conventions
2. Ensure Zygote-compatible code (test with `gradient()`)
3. Use conventional commit messages (see `CLAUDE.md`)
4. Update `.serena/memories/` if architecture changes

## 📝 License

Research prototype. License TBD.

## 🔗 Related Work

- **Active Inference**: Friston et al. (2010-2023)
- **Free Energy Principle**: Friston (2010)
- **Log-Polar Mapping**: Schwartz (1977), Traver & Bernardino (2010)
- **Stigmergy**: Grassé (1959), Theraulaz & Bonabeau (1999)

## 📧 Contact

For questions about this implementation, see `CLAUDE.md` or open an issue.

---

**Note**: This project transitioned from Python to Julia (2025-11-22). Legacy Python code is archived in `archive/python_legacy/` for reference.
