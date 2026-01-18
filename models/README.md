# Models Directory

All model files (`*.bson`) are git-ignored for repository size optimization.

---

## Current Version: v7.2

**Action-Conditioned VAE** for 5D state space with heading alignment.

### Train VAE Model

```bash
# Using generic entry point (recommended)
julia --project=. scripts/train_vae.jl

# Or version-specific script
julia --project=. scripts/v72/train_vae.jl
```

**Expected Output**: `models/action_vae_v72_best.bson`

**Training Requirements**:
- Training data: `data/vae_training/raw_v72/` (9 files, 25MB)
- 3 scenarios: Scramble, Corridor, Random Obstacles
- 450,000 samples total

---

## Model Architecture

**Type**: Action-Conditioned VAE (Pattern D)

**Encoder**: q(z | y[t], u[t])
- Input: SPM (12×12×3) + Action (2D force)
- Output: Latent distribution (μ, σ)

**Decoder**: p(y[t+1] | z, u[t])
- Input: Latent z + Action (2D force)
- Output: Predicted SPM (12×12×3)

**SPM Channels**:
1. Occupancy (Gray colormap)
2. Proximity Saliency (Hot colormap)
3. Collision Risk (Reds colormap)

**SPM Specifications**:
- Grid: 12×12 bins (n_rho=12, n_theta=12)
- Sensing range: 6.0m (sensing_ratio=3.0)
- FOV: 210°

---

## Training Configuration (v7.2)

Best hyperparameters:
- Latent dim: 32
- β (KL weight): 0.1
- Learning rate: 0.001
- Batch size: 64
- Epochs: 50
- Training stride: 5 steps

Training data collection:
- Random walk controller (bias-free)
- Geometric collision avoidance
- 3 scenarios for generalization

---

## Validation

Run validation and visualization:

```bash
# Visualize VAE predictions
julia --project=. scripts/utils/visualize_vae.jl
```

Output: `results/v72/vae_vis/vae_pred_sample_*.png`

Expected metrics:
- Reconstruction MSE: < 0.01
- Latent KL divergence: ~1.5

---

## Version History

- **v7.2** (2026-01-18): 5D state space, circular obstacles, controller-bias-free data
- **v6.3** (2026-01-14): Raw trajectory storage with SPM reconstruction
- **v6.2** (2026-01-13): Action-conditioned VAE baseline
- **v5.6** (2026-01-10): Surprise integration

---

## Directory Structure

```
models/
├── README.md (this file)
├── .gitkeep
└── *.bson (git-ignored, train locally)
```

**Note**: Researchers must train models locally. Pre-trained models may be available in published archives.
