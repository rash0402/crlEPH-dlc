# GEMINI.md

This file provides context for Gemini Agent working on the EPH (Emergent Perceptual Haze) project.

## Project Identity
- **Name**: EPH (Emergent Perceptual Haze), formerly known as DIAL/HELM.
- **Version**: 5.5.0 (Pattern D Architecture)
- **Goal**: Implement bio-inspired uncertainty regulation (Haze) to solve "Freezing Robot Problem" in crowded navigation.

## Directory Structure (Canonical)

```
crlEPH-dlc/
├── src/                          # Julia Source Code
│   ├── action_vae.jl             # Pattern D VAE (Haze Estimation)
│   ├── controller.jl             # Active Inference Controller
│   ├── spm.jl                    # Saliency Polar Map Components
│   ├── dynamics.jl               # Physics Engine
│   ├── metrics.jl                # Evaluation Metrics (Freezing, etc.)
│   └── config.jl                 # Global Configuration
├── scripts/                      # Execution Scripts
│   ├── run_all.sh                # Main Launcher
│   ├── run_simulation.jl         # Simulation Entry Point
│   ├── train_action_vae.jl       # VAE Training Pipeline
│   ├── validate_haze.jl          # Haze Validation Pipeline
│   └── evaluate_metrics.jl       # Metrics Calculation
├── data/                         # Data Storage
│   ├── logs/                     # Simulation HDF5 Logs
│   └── vae_training/             # Training Datasets
├── models/                       # Model Artifacts
│   ├── action_vae_best.bson      # Current Best Model
│   └── checkpoints/              # Training Checkpoints
├── results/                      # Analysis Outputs
│   ├── haze_validation/          # Validation Reports & Plots
│   └── evaluation/               # Metrics Reports
└── viewer/                       # Python Visualization Tools
```

## Key Workflows

### 1. Simulation Loop
- `scripts/run_simulation.jl`:
  1. Initialize Agents & SPM
  2. Load VAE Model (`models/action_vae_best.bson`)
  3. Loop:
     - Generate SPM ($y_t$)
     - VAE Estimate Haze ($H = \text{Agg}(\sigma_z^2(y_t, u_{proposed}))$)
     - Modulate Precision ($\beta = \phi(H)$)
     - Optimize Action ($u_t = \arg\min F$)
     - Step Dynamics
     - Log Data

### 2. VAE Training Cycle
- `scripts/collect_diverse_vae_data.jl`: Generate dataset with exploration.
- `scripts/train_action_vae.jl`: Train Pattern D VAE.
  - Loss = Reconstruction + $\beta_{KL} \times$ KLD
  - $\beta_{KL} \approx 0.1 \sim 1.0$ (Critical for structured latent space)

### 3. Validation Cycle
- `scripts/validate_haze.jl`:
  - Counterfactual Analysis: Check if Haze varies with Action ($u$).
  - Correlation Analysis: Check if Haze predicts Prediction Error.

## Current State (Phase 1.5/2)
- **Status**: Pattern D Implemented. VAE Training in progress.
- **Next**: Implementing "Freezing Rate" metric in Phase 2.
