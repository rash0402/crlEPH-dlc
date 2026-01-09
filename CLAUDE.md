# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EPH (Emergent Perceptual Haze) is a research implementation of the Free Energy Principle (FEP) for social robot navigation in crowded environments. The system uses Saliency Polar Maps (SPM) as bio-inspired perceptual representations and implements gradient-based control for collision avoidance.

## Architecture

**Julia Backend** (`src/`): Core simulation logic
- `config.jl` - System parameters
- `spm.jl` - Saliency Polar Map generation (16x16x3ch)
- `dynamics.jl` - Agent physics with toroidal world boundary
- `controller.jl` - FEP-based controller with free energy minimization
- `action_vae.jl` - Action-Dependent VAE (Pattern D) for Haze estimation
- `communication.jl` - ZMQ PUB socket for real-time streaming
- `logger.jl` - HDF5 data logging
- `metrics.jl` - Evaluation metrics (Freezing, etc.)

**Python Viewers** (`viewer/`): Real-time visualization
- `main_viewer.py` - 4-group scramble crossing display
- `detail_viewer.py` - SPM 3-channel visualization and metrics
- `zmq_client.py` - ZMQ SUB socket client

**Entry Point**: `scripts/run_all.sh` (Mac/Linux)

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
# Recommended: Start everything (Sim + Viewers)
./scripts/run_all.sh

# Or Manual launch
julia --project=. scripts/run_simulation.jl
~/local/venv/bin/python viewer/detail_viewer.py
```

### Haze Validation
```bash
julia --project=. scripts/validate_haze.jl
```

## Data Output

- **Simulation Logs**: `data/logs/eph_sim_YYYYMMDD_HHMMSS.h5`
- **VAE Training Data**: `data/vae_training/`
- **Trained Models**: `models/action_vae_best.bson`
- **Validation Results**: `results/haze_validation/`

## Development Status (v5.5 Aligned)

### Completed Milestones

- **M1-3 (Base v5.5)**: ✅ Pattern D VAE Architecture & Haze Logic
  - **Encoder**: $(y[k], u[k]) \to q(z|y, u)$ (Action-Dependent)
  - **Decoder**: $(z, u[k]) \to \hat{y}[k+1]$ (Action-Conditioned)
  - **Haze**: $H[k] = \text{Agg}(\sigma_z^2(y[k], u[k]))$ (Counterfactual Haze)
  - **Validation**: Haze correlates with risk of action

### Current Focus (Phase 1.5/2)

- 🎯 **VAE Training**: Optimizing Pattern D model ($\beta=0.1 \sim 1.0$)
- 🎯 **Evaluation**: Implementing Freezing Rate metric in `scripts/evaluate_metrics.jl`
- 🎯 **Documentation**: Defining v5.5 specifications

### Technical Specifications (v5.5 Pattern D)

- **Causal Flow**: $u_k$ Proposed $\to H(y_k, u_k)$ Estimated $\to \beta_{k+1}$ Modulated
- **Advantage**: "Risky Action" $\to$ High Haze $\to$ Low Precision $\to$ Conservative Behavior
- **Data Structure**: HDF5 logs contain `spm`, `actions`, `haze`, `precision`

For detailed research context, see `doc/EPH-proposal_all_v5.5.md`.
