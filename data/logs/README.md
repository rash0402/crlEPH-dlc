# EPH v5.6 Logs Directory

This directory contains simulation logs for EPH v5.6.

## Directory Structure

```
data/logs/
├── control_integration/       # Phase 4: Fixed Haze control integration
│   ├── scramble/              # Scramble Crossing scenario
│   └── corridor/              # Corridor scenario
├── comparison/                # Phase 5.1-5.4: Ablation & comparison
│   ├── scramble/
│   │   ├── A0_baseline/       # Standard FEP (no Surprise, no Haze)
│   │   ├── A1_haze_only/      # Haze modulation only
│   │   ├── A2_surprise_only/  # Surprise only (no Haze modulation)
│   │   └── A3_eph_v56/        # Full EPH v5.6 (Surprise + Haze)
│   └── corridor/
│       └── (same structure)
├── haze_sensitivity/          # Phase 5.5: Haze parametric study
│   ├── scramble/              # 5 Haze values × 4 densities × 5 seeds
│   └── corridor/
└── self_hazing/               # Phase 6: Self-Hazing meta-learning
    ├── scramble/
    └── corridor/
```

## Naming Convention

Simulation logs: `sim_{scenario}_{condition}_h{haze}_d{density}_s{seed}.h5`

Examples:
- `sim_scramble_A3_h0.5_d10_s1.h5` - EPH v5.6, Scramble, Haze=0.5, Density=10, Seed=1
- `sim_corridor_h0.7_d15_s3.h5` - Corridor, Haze=0.7, Density=15, Seed=3

## File Format

All logs are in HDF5 format containing:
- `/agents/{id}/positions` - Agent trajectories
- `/agents/{id}/velocities` - Agent velocities
- `/agents/{id}/spms` - Saliency Polar Maps (16×16×3)
- `/agents/{id}/actions` - Control inputs
- `/agents/{id}/haze` - Haze values (Phase 4+)
- `/agents/{id}/precision` - Precision β values
- `/agents/{id}/surprise` - Surprise values (Phase 4+)
- `/metadata` - Simulation parameters

## Version History

- **v5.6** (2026-01-10): Current version with Surprise integration and dual scenarios
- **v5.5** (archived in `archive/v55_logs/`): Pattern D VAE without Surprise separation

## Notes

⚠️ This directory is excluded from Git (see `.gitignore`)
📊 Analysis results are stored in `results/` directory
