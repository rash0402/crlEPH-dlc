# Project Overview (Updated 2025-11-22)

## Purpose
Research implementation of **Emergent Perceptual Haze (EPH)** framework for swarm intelligence. EPH uses spatial precision modulation based on Active Inference and Free Energy Principle (FEP) to guide agent behavior in multi-agent environments without explicit communication.

## Core Research Concepts

### 1. Saliency Polar Map (SPM)
- Bio-inspired perceptual representation using log-polar coordinates
- Mimics primate V1 cortex retinotopic mapping
- Shape: `(3, Nr, Ntheta)` - channels for [Occupancy, Radial Velocity, Tangential Velocity]
- Reduces computational complexity from O(L²) to O(Nr × Ntheta) ≈ O(1)

### 2. Haze (Spatial Precision Modulation)
- Not additive noise, but **precision matrix modulation** in FEP framework
- Environmental haze: 2D grid deposited by agents (stigmergy)
- Self-hazing: Internal state-based uncertainty regulation
- Effect: High haze → Low precision → Reduced collision avoidance ("lubricant effect")

### 3. EPH Control Loop
Agent decides action by minimizing dual-objective cost:
```
J(a) = F_percept(a, Haze) + λ * M_meta(a)
```
- F_percept: Haze-modulated collision avoidance cost
- M_meta: Goal-seeking or exploration maintenance cost
- Solved via gradient descent using automatic differentiation (Zygote.jl)

### 4. Stigmergy
Environmental coordination through haze trails:
- Lubricant Haze: Reduces avoidance in traveled paths → smooth following
- Repellent Haze: Increases exploration in visited areas → distributed search

## Current Implementation Status

### Julia Implementation (Primary)
Located in `src_julia/`:
- **Core**: Agent/Environment data structures (Types.jl)
- **Perception**: SPM computation with Gaussian splatting (SPM.jl)
- **Control**: Gradient-based EPH controller (EPH.jl)
- **Simulation**: Main loop, toroidal geometry (Simulation.jl)
- **Server**: ZeroMQ PUB socket on port 5555 (main.jl)

### Python Implementation (Visualization Only)
- **Viewer**: Pygame-based real-time visualization (viewer.py)
- **Legacy**: Prototype code in `src/` (being phased out)

### Research Documentation
- `doc/20251121_Emergent Perceptual Haze (EPH).md` - Main proposal
- `doc/20251120_Saliency Polar Map (SPM).md` - SPM framework
- `CLAUDE.md` - Developer onboarding guide

## AI-DLC Expert Review Summary (2025-11-22)

11 expert personas evaluated the project. Key findings:

### ✅ Strengths
1. **Biological plausibility**: SPM + Personal Space + FEP integration is theoretically robust
2. **Working prototype**: Julia + ZeroMQ + visualization confirmed operational
3. **Documentation**: CLAUDE.md facilitates onboarding

### 🚩 Critical Gaps
1. **Baseline comparison**: No quantitative comparison with Potential Field, ACO, etc.
2. **Statistical validation**: Lacks 30-trial experiments with t-tests, effect sizes
3. **Mathematical rigor**: Parameter choices appear arbitrary, convergence not proven

### 🎯 Priority Improvements (see priority_improvements.md)
- **P0** (Paper submission essential): Baseline experiments, statistical tests, parameter justification
- **P1** (Implementation quality): Acceleration limits, convergence criteria, resolution sensitivity
- **P2** (Academic rigor): Convergence proofs, failure mode analysis

## Key Dependencies

### Julia (Main)
- Zygote: Automatic differentiation for gradient-based control
- ZMQ: Inter-process communication (server)
- JSON: Message serialization
- LinearAlgebra, Random, Statistics: Standard libraries

### Python (Viewer)
- pygame: Real-time visualization
- zmq: Inter-process communication (client)
- numpy: Numerical operations

## Running the Project

**Full simulation**:
```bash
./scripts/run_experiment.sh
```
This starts Julia server (port 5555) + Python viewer simultaneously.

**Julia development**:
```bash
cd src_julia
julia main.jl
```

**Python viewer standalone** (requires Julia server running):
```bash
export PYTHONPATH=.
python viewer.py
```

## Research Context
This implementation corresponds to academic proposals aiming for:
- Novel integration of FEP + stigmergy in swarm control
- Computational efficiency for large-scale multi-agent systems
- Bio-inspired alternative to traditional potential fields
