# EPH v5.5 Archive

This directory contains archived data from EPH v5.5 experiments.

## Contents

### v55_logs/ (~300 MB)
- Simulation logs (HDF5 format)
- Batch experiments for Scramble Crossing and Corridor scenarios
- Comparison experiments (Challenging, Emergency scenarios)

### v55_results/
- Analysis reports and figures from v5.5 experiments
- Comparison results: `comparison_challenging/`, `comparison_emergency/`
- Evaluation results: `evaluation/`
- Haze validation results: `haze_validation/`

## Why Archived?

EPH v5.5 had architectural limitations:
1. **Pattern混在**: Pattern B and D were mixed in implementation
2. **No Surprise separation**: Surprise was not explicitly integrated into free energy
3. **Haze = σ_z²**: Haze was automatically calculated from VAE variance (not a design parameter)

EPH v5.6 addresses these issues with:
- ✅ Clean Pattern D architecture
- ✅ Explicit Surprise term: `F = F_goal + F_safety + λ_s·Surprise`
- ✅ Haze as design parameter (Fixed → Scheduled → Self-Adaptive)
- ✅ Dual scenario support (Scramble Crossing + Corridor)

## Access Policy

These archives are preserved for reference only and should **not** be used for v5.6 analysis or publications.

For new experiments, use:
- `data/logs/` - v5.6 simulation logs
- `results/` - v5.6 analysis results

## Archive Date

2026-01-10

## Total Size

Approximately 300 MB (logs) + analysis results
