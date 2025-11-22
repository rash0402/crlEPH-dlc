# Project Structure and Architecture (Updated 2025-11-22)

## Overview
The project transitioned from Python prototype to Julia-based production implementation for performance optimization. Python code remains for visualization only.

## Primary Julia Implementation (`src_julia/`)

### Module Hierarchy
```
src_julia/
├── main.jl                 # ZeroMQ server entry point (port 5555)
├── Simulation.jl           # Main simulation loop, agent management
├── core/
│   └── Types.jl           # Agent, Environment, and parameter structs
├── perception/
│   └── SPM.jl             # Saliency Polar Map with Gaussian splatting
├── control/
│   └── EPH.jl             # Gradient-based EPH controller (Zygote)
└── utils/
    └── MathUtils.jl       # Toroidal geometry, distance calculations
```

### Key Design Patterns
- **Module imports**: Sibling modules accessed via `using ..Types` (parent-relative)
- **Differentiability**: All functions in SPM/EPH chain support Zygote AD
- **Toroidal geometry**: World wraps at boundaries, distances computed with wrap-around
- **Soft-mapping**: Gaussian kernels enable differentiable object-to-bin mapping in SPM

### Julia Package Structure
- `Project.toml`: Julia 1.9+ dependencies (ZMQ, Zygote, JSON, LinearAlgebra, etc.)
- `Manifest.toml`: Locked dependency versions (gitignored)
- Activated via `cd src_julia && julia --project=.`

## Python Visualization (`viewer.py`)
- **Location**: Root directory
- **Purpose**: Real-time Pygame visualization via ZeroMQ SUB socket
- **Communication**: Subscribes to `tcp://localhost:5555` from Julia server
- **Rendering**: Agent circles, FOV sectors, haze grid overlay

## Legacy Python Prototype (`src/`)
**Status**: Being phased out. Original Python implementation for reference.

Structure:
- `src/core/` - simulator, environment, agent (legacy)
- `src/perception/spm.py` - NumPy-based SPM (non-differentiable)
- `src/control/eph.py`, `eph_gradient.py` - Python control implementations
- `src/utils/` - math utilities, visualization tools

**Note**: Active development has moved to Julia. Python code under `src/` is for historical reference and comparative experiments only.

## Configuration & Scripts
- **`scripts/run_experiment.sh`**: Primary launcher (Julia server + Python viewer)
- **`config/`**: Legacy YAML configs (Python-based, not used by Julia)
- **`doc/`**: Research proposals and technical specifications
  - `20251121_Emergent Perceptual Haze (EPH).md`
  - `20251120_Saliency Polar Map (SPM).md`
  - `CLAUDE.md` - Developer onboarding guide

## Outputs & Transient Data
- **`log/`**: Simulation logs (create if needed)
- **`tmp/`**: Temporary outputs, debug artifacts
- **`.serena/`**: Serena MCP server cache and memories
- **`.git/`**: Version control

## Architecture Principles
1. **Separation of concerns**: Simulation (Julia) decoupled from visualization (Python) via ZeroMQ
2. **Differentiable pipeline**: SPM → EPH controller → action selection all support gradient flow
3. **Bio-inspired design**: Log-polar SPM mimics primate V1, toroidal geometry simplifies boundary conditions
4. **Performance-first**: Julia chosen for 10-100x speedup over Python for large-scale swarms
