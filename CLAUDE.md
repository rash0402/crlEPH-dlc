# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EPH (Emergent Perceptual Haze) is a research implementation of the Free Energy Principle (FEP) for social robot navigation in crowded environments. The system uses Saliency Polar Maps (SPM) as bio-inspired perceptual representations and implements gradient-based control for collision avoidance.

## Architecture

**Julia Backend** (`src/`): Core simulation logic
- `config.jl` - System parameters (SPM, world, agent, control, communication)
- `spm.jl` - Saliency Polar Map generation (16x16x3ch: Occupancy, Saliency, Risk)
- `dynamics.jl` - Agent physics with toroidal world boundary
- `controller.jl` - FEP-based controller with free energy minimization
- `communication.jl` - ZMQ PUB socket for real-time streaming
- `logger.jl` - HDF5 data logging

**Python Viewers** (`viewer/`): Real-time visualization
- `main_viewer.py` - 4-group scramble crossing display
- `detail_viewer.py` - SPM 3-channel visualization and metrics
- `zmq_client.py` - ZMQ SUB socket client

**Entry Point**: `scripts/run_simulation.jl` - includes modules and runs main loop

## Common Commands

### Install Dependencies
```bash
# Julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Python
~/local/venv/bin/pip install -r requirements.txt
```

### Run Simulation
```bash
# Recommended: Use launcher scripts in separate terminals
./scripts/start_backend.fish      # Terminal 1: Julia backend
./scripts/start_main_viewer.fish  # Terminal 2: Main viewer
./scripts/start_detail_viewer.fish # Terminal 3: Detail viewer (optional)

# Or all-in-one (macOS)
./scripts/start_all.fish

# Manual launch
julia --project=. scripts/run_simulation.jl
~/local/venv/bin/python viewer/main_viewer.py
```

### Port Management
```bash
lsof -i :5555                    # Check if ZMQ port in use
lsof -ti :5555 | xargs kill -9   # Kill process on port
```

## Key Concepts

- **SPM (Saliency Polar Map)**: Log-polar perceptual representation mimicking primate V1 cortex
- **Toroidal World**: Agents wrap at boundaries, distances computed with wrap-around
- **Ego-centric Frame**: SPM generated relative to agent's velocity direction
- **4-Group Scramble**: N/S/E/W groups crossing at center (standard test scenario)
- **ZMQ Streaming**: Julia publishes on `tcp://127.0.0.1:5555`, Python viewers subscribe

## Configuration

Parameters are defined as structs in `src/config.jl`:
- `SPMParams` - Resolution, FOV, sensing distance, beta parameters
- `WorldParams` - World size, timestep, max steps
- `AgentParams` - Mass, damping, radius, group size
- `ControlParams` - Learning rate, safety distance, TTC threshold
- `CommParams` - ZMQ endpoint and topic names

## Data Output

- Logs saved to `log/data_YYYYMMDD_HHMMSS.h5` (HDF5 format)
- Contains SPM tensors, actions, positions, velocities per timestep

## Development Status (v5.5 Aligned)

### Completed Milestones

- **M1-A (Julia Backend)**: ✅ 4-group scramble crossing simulator, SPM generation, ZMQ streaming
- **M1-B (Python Viewers)**: ✅ Main viewer (color-coded groups) and detail viewer (SPM/metrics)
- **M2 (World Model)**: ✅ Action-Conditioned VAE (Pattern B)
  - Encoder: Estimates latent distribution from y[k] only (u-independent)
  - Decoder: Predicts future SPM from (z, u) (u-conditioned)
  - Haze calculation: H[k] = (1/D) Σ σ²_z[k-1] (temporal delay avoids circular dependency)
- **M3 (Integration & Validation)**: ✅ Complete EPH controller with Haze-based β modulation
  - Freezing detection algorithm
  - Evaluation metrics (Success Rate, Collision Rate, Jerk, TTC)
  - Ablation study framework (A1-A4 conditions)
  - Statistical analysis (achieved: 36% Freezing reduction, 23% Jerk improvement)
  - **v5.5 Alignment**: Pattern B implementation, temporal Haze definition, Precision separation

### Current Focus (M4 - Planned)

- 🎯 Predictive collision avoidance: Expected Free Energy (EFE) minimization
- 🎯 Ch3-centric evaluation: Dynamic collision risk prediction (TTC-based)
- 🎯 Swarm extension: Emergent coordination via local Haze modulation

### Technical Specifications (v5.5)

**Pattern B Structure**:
- Causal flow: y[k] → σ²_z[k] → H[k+1] → β[k+1] → y[k+1]
- Gradient computation: Through decoder only (∂F/∂u), encoder fixed during u-optimization
- Precision separation: Inference (fixed) vs Perceptual Resolution β (adaptive)

For detailed research context, see `doc/EPH-proposal_all_v5.5.md` and `doc/EPH_AI_DLC_Proposal.md`.
