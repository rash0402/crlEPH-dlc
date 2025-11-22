# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a research implementation of the "Emergent Perceptual Haze (EPH)" framework for swarm intelligence. EPH uses spatial precision modulation based on Active Inference and Free Energy Principle (FEP) to guide agent behavior in multi-agent environments.

**Core Concepts:**
- **Saliency Polar Map (SPM)**: Bio-inspired perceptual representation using log-polar coordinates
- **Haze**: Spatial precision modulation field that influences agent perception and behavior
- **Active Inference**: Agents minimize free energy through haze-modulated surprise minimization
- **Stigmergy**: Environmental coordination through deposited haze trails

## Architecture

The codebase has **dual implementations** (Python and Julia) with different purposes:

### Julia Implementation (Primary Simulation)
Located in `src_julia/`, this is the current active implementation optimized for performance.

**Module Structure:**
- `core/Types.jl` - Agent and Environment data structures
- `perception/SPM.jl` - Saliency Polar Map computation with Gaussian splatting
- `control/EPH.jl` - Gradient-based action selection using Zygote automatic differentiation
- `utils/MathUtils.jl` - Toroidal geometry utilities
- `Simulation.jl` - Main simulation loop and agent management
- `main.jl` - ZeroMQ server entry point

**Key Design Patterns:**
- Modules use `using ..Types` for sibling module access
- SPM uses soft-mapping with Gaussian kernels for differentiability
- EPH controller uses gradient descent on a dual-objective cost function: `F_percept + λ * M_meta`
- Toroidal (wrap-around) world geometry throughout

### Python Implementation (Legacy/Experimentation)
Located in `src/`, used for prototyping and analysis.

**Structure:**
- `core/` - simulator, environment, agent
- `perception/spm.py` - SPM tensor generation
- `control/eph.py` and `eph_gradient.py` - Control implementations
- `utils/` - math utilities, visualization tools

### Visualization
- `viewer.py` - Real-time Pygame-based visualization that connects to Julia server via ZeroMQ
- Renders agents, FOV sectors, and haze grid overlay

## Common Development Commands

### Running the Full Simulation
```bash
./scripts/run_experiment.sh
```
This script:
1. Starts the Julia EPH server on port 5555 (ZeroMQ PUB socket)
2. Starts the Python viewer (ZeroMQ SUB socket)
3. Handles cleanup on Ctrl+C

**Prerequisites:**
- Julia installed via juliaup (`~/.juliaup/bin/julia`)
- Python virtual environment at `~/local/venv/`
- Port 5555 available

### Julia Development

**Running directly:**
```bash
cd src_julia
julia main.jl
```

**Installing/updating dependencies:**
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

**Dependencies** (from Project.toml):
- ZMQ - Inter-process communication
- Zygote - Automatic differentiation for gradient-based control
- JSON - Message serialization
- LinearAlgebra, Random, Statistics - Standard libraries

### Python Development

**Running viewer standalone** (requires Julia server running):
```bash
export PYTHONPATH=.
python viewer.py
```

**Running experiments:**
```bash
python scramble_with_spm.py
python narrow_corridor_visual.py
```

**Dependencies** (requirements.txt):
```
numpy
pygame
zmq
```

## Key Implementation Details

### SPM (Saliency Polar Map)
- **Shape**: `(3, Nr, Ntheta)` where channels are [Occupancy, Radial Velocity, Tangential Velocity]
- **Coordinate mapping**: Personal space defines inner zone (bin 0), outer zones use log-polar mapping
- **Gaussian splatting**: Objects contribute to multiple bins via soft-mapping for differentiability
- **Precision matrix**: Sigmoid function modulates attention based on distance vs personal_space

### EPH Controller (Julia)
- **Cost function**: `J(a) = F_percept(a, Haze) + M_meta(a)`
  - `F_percept`: Haze-modulated collision avoidance cost
  - `M_meta`: Goal-seeking or exploration maintenance cost
- **Optimization**: Gradient descent via Zygote.gradient with 5 iterations
- **Haze modulation**: High haze reduces effective precision → reduces collision avoidance → "lubricant" effect
- **Action smoothing**: 70% new action + 30% previous velocity for continuity

### Haze Mechanics
- **Environmental haze**: 2D grid (`haze_grid`) updated each timestep
  - Agents deposit haze at their position (value += 0.2, capped at 1.0)
  - Decays globally by 0.99 each timestep
- **Haze effects in cost function**:
  - Adds noise to SPM: `spm_noisy = spm + haze * 0.05`
  - Reduces effective precision: `uncertainty_factor = 1.0 - haze * 0.8`
  - Net effect: Agents ignore obstacles more in high-haze areas

### Communication Protocol (Julia ↔ Python)
**ZeroMQ PUB-SUB pattern**

Message format (JSON):
```json
{
  "frame": int,
  "agents": [
    {
      "id": int,
      "x": float, "y": float,
      "vx": float, "vy": float,
      "radius": float,
      "color": [r, g, b],
      "orientation": float,
      "has_goal": bool
    }
  ],
  "haze_grid": [[float]]
}
```

## Research Context

This implementation corresponds to the research proposals in `doc/`:
- **20251121_Emergent Perceptual Haze (EPH).md** - Main EPH framework proposal
- **20251120_Saliency Polar Map (SPM).md** - SPM perceptual representation proposal

The current simulation demonstrates:
- **Scenario**: Scramble crossing with 12 agents (random walk, no goals)
- **Goal**: Observe emergent coordination via haze stigmergy
- **Comparison baseline**: Traditional random walk vs EPH with haze-guided behavior

## Development Notes

### Coordinate Systems
- **World**: Cartesian (x, y) with toroidal wrap-around
- **Agent-relative**: Polar (r, θ) where θ=0 is agent's forward direction
- **SPM**: Log-polar bins with personal_space as inner zone boundary

### Index Conventions
- **Julia**: 1-based indexing (bin 1 = first radial bin)
- **Python**: 0-based indexing
- Conversion handled in `_add_to_tensor!` via `+1` offsets

### Debugging Utilities
Several debug scripts exist in root:
- `debug_gradient.py` - Test gradient flow through EPH controller
- `debug_collision.py` - Verify collision detection
- `debug_inside_obstacle.py` - Check SPM occupancy mapping
- `visualize_spm.py` - Visualize SPM tensor structure

### Git Status Note
The codebase is actively under development. Current modified files include simulation parameters and viewer enhancements.
