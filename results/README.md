# EPH Results Directory

Analysis results (reports, figures, statistics) organized by version.

---

## Directory Structure

```
results/
├── README.md (this file)
├── v62/                    # v6.2 experiments
│   ├── vae_tuning/         # Training logs and hyperparameter tuning
│   └── vae_vis/            # VAE prediction visualizations
└── v72/                    # v7.2 experiments (current)
    ├── vae_tuning/         # Training logs (when available)
    └── vae_vis/            # VAE visualizations (when available)
```

---

## File Types

- **Markdown (*.md)**: Analysis reports, summaries
- **PNG (*.png)**: Figures, plots, visualizations
- **CSV (*.csv)**: Raw statistics, experimental results
- **HDF5 (*.h5)**: Training checkpoints and logs

---

## Version Organization

Results are organized by version to enable:
- Easy comparison between approaches (v6.2 vs v7.2)
- Clear tracking of experimental evolution
- Reproducibility via version-specific configurations

### v6.2 Results
- VAE training with FEP-biased data
- 16×16 SPM grid
- Velocity-based dynamics

### v7.2 Results (Current)
- VAE training with controller-bias-free data
- 12×12 SPM grid
- 5D state space (x, y, vx, vy, θ)
- Circular obstacle representation
- 3 scenarios: Scramble, Corridor, Random Obstacles

---

## Usage

These files are Git-managed (small file sizes).

Results should be:
- Referenced in papers and presentations
- Self-contained with embedded figures
- Versioned for reproducibility

Raw simulation data is in `data/logs/` (git-ignored).

---

## Current Status (v7.2 Phase 2)

**Completed**:
- ✅ Phase 1: Controller-bias-free data collection (9 files, 25MB, 450k samples)

**In Progress**:
- 🎯 Phase 2: VAE Training
- 🎯 Phase 3: Haze Effect Evaluation

---

**Note**: Results directories are created automatically when running training/evaluation scripts.
