# Models Directory

All model files (`*.bson`) are git-ignored for repository size optimization.

---

## Reproducing VAE Models

### Train VAE Model (v5.6)

```bash
julia --project=. scripts/train_vae_v56.jl
```

**Expected Output**: `models/action_vae_v56_best.bson`

**Training Time**: ~2 hours on M1 Mac

**Requirements**:
- Training data must be generated first using `scripts/create_dataset_v56.jl`
- Or use pre-generated data in `data/vae_training/exploratory/` (if available)

---

## Model Architecture

**Type**: Action-Conditioned VAE (Pattern D)

**Encoder**: (SPM, action) → latent distribution q(z|y, u)

**Decoder**: (z, action) → reconstructed SPM

**Input**:
- SPM: 16×16×3 (Occupancy, Proximity Saliency, Collision Risk)
- Action: 2D velocity vector

**Output**:
- Reconstructed SPM: 16×16×3

**Training Strategy (v5.6.1)**:
- Training data: Haze=0 (maximum resolution)
- Runtime: Variable Haze ∈ [0.0, 1.0]
- Ensures monotonic S(u) coupling with Haze via information degradation

---

## Hyperparameter Tuning

Best configuration (from `scripts/tune_vae_v56.jl`):
- β (KL weight): 0.1
- Latent dim: 16
- Learning rate: 0.001
- Batch size: 32
- Epochs: 200

See `results/vae_tuning/` for detailed tuning logs.

---

## Validation

Run validation:
```bash
julia --project=. scripts/validate_vae_v56.jl
```

Expected metrics:
- Reconstruction MSE: < 0.01
- Latent KL divergence: ~1.5

See `results/vae_validation/` for validation reports.

---

## Directory Structure

```
models/
├── README.md (this file)
├── .gitkeep (preserves directory in git)
└── *.bson (git-ignored, generated locally)
```

**Note**: All `.bson` files are excluded from git. Researchers must train models locally or obtain from published archives.
