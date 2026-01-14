# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EPH (Emergent Perceptual Haze) is a research implementation of the Free Energy Principle (FEP) for social robot navigation in crowded environments. The system uses Saliency Polar Maps (SPM) as bio-inspired perceptual representations and implements gradient-based control for collision avoidance.

## Architecture

**Julia Backend** (`src/`): Core simulation logic
- `config.jl` - System parameters
- `spm.jl` - Saliency Polar Map generation (12×12×3ch for v6.3)
- `dynamics.jl` - Agent physics with toroidal world boundary
- `controller.jl` - FEP-based controller + Random walk controller (v6.3)
- `scenarios.jl` - Scenario definitions (Scramble, Corridor, Random Obstacles)
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

## Development Status (v6.3 Current)

### Completed Milestones

- **v6.3 (Controller-Bias-Free Architecture)**: ✅ Unbiased VAE Training Data Collection
  - **Random Walk Controller**: Geometric collision avoidance without FEP bias
  - **3 Scenarios**: Scramble Crossing, Corridor, Random Obstacles
  - **Raw Trajectory Data**: Position, velocity, actions, heading saved in HDF5
  - **SPM Reconstruction**: On-the-fly generation from raw trajectories during training
  - **Data Efficiency**: 100x storage reduction (SPM reconstructed, not stored)

- **Random Obstacles Scenario**: ✅ Circular obstacles with reproducible generation
  - **Obstacle Generation**: 2-4m radius circles with safe zones
  - **Reproducibility**: Independent obstacle_seed parameter
  - **Integration**: Obstacles included in SPM for collision avoidance

- **Raw Trajectory Viewers**: ✅ Real-time visualization with SPM reconstruction
  - `viewer/raw_v63_viewer.py` - Main viewer with 3-channel SPM display
  - `viewer/spm_reconstructor.py` - Python SPM generator
  - **Features**: Global/local maps, obstacle visualization, agent selection

### Current Focus (v6.3 Phase)

- 🎯 **VAE Training**: Training on controller-bias-free dataset (9 files, 10MB)
- 🎯 **Ablation Study**: Comparing v6.2 (FEP-biased) vs v6.3 (unbiased) data
- 🎯 **Evaluation**: Collision rate, freezing rate, trajectory smoothness metrics

### Technical Specifications (v6.3)

- **Data Collection**: Random walk + geometric collision avoidance
- **SPM**: 12×12 grid, D_max=6.0m, sensing_ratio=6.0
- **Scenarios**:
  - Scramble: 40 agents, 2.5-3.4% collision rate
  - Corridor: 20 agents, 6.3-7.2% collision rate
  - Random Obstacles: 40 agents, 8.9-9.6% collision rate (507-575 obstacle points)
- **Data Structure**: HDF5 with `trajectory/`, `obstacles/`, `events/`, `metadata/`, `spm_params/`
- **Storage**: ~10MB for 9 datasets (3 scenarios × 3 seeds × 1500 steps)

For detailed research context, see `doc/v6.3_controller_bias_free_design.md`.
