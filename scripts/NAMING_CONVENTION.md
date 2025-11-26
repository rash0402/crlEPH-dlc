# Scripts Naming Convention

This document defines the naming convention for scripts in the `scripts/` directory.

## Prefix System

### `run-gui-*.sh` - GUI/Visualization Experiments
Scripts that launch graphical user interfaces or real-time visualizations.
- **Output**: Visual display (Pygame, Qt, etc.)
- **Interaction**: User can observe simulation in real-time
- **Use case**: Development, demonstration, debugging

**Examples**:
- `run-gui-foraging.sh` - Sparse foraging task with Pygame viewer
- `run-gui-coverage.sh` - Coverage experiment with Qt dashboard
- `run-gui-shepherding.sh` - Shepherding task with viewer
- `run-gui-dashboard.sh` - Dashboard GUI only (no simulation)

### `run-exp-*.sh` - Numerical Experiments (Headless)
Scripts that run experiments without GUI, producing JSON/CSV data output.
- **Output**: JSON files, CSV files, statistical results
- **Interaction**: Headless (no GUI), can run on servers
- **Use case**: Batch experiments, statistical analysis, paper results

**Examples**:
- `run-exp-fundamental.sh` - Fundamental theory validation experiments
- `run-exp-comparative.sh` - Comparative baseline experiments
- `run-exp-ablation.sh` - Ablation studies

### `run-*.sh` - General Runtime Scripts
Scripts that don't fit the above categories but run services or components.

**Examples**:
- `run-server-zmq.sh` - Start ZMQ server only
- `run-basic-validation.sh` - Validation test suite

### Other Prefixes

- `collect-*.sh` - Data collection scripts
  - Example: `collect-gru-training-data.sh`

- `setup-*.sh` - Environment setup scripts
  - Example: `setup-env.sh`

- `analyze-*.sh` - Post-experiment analysis scripts
  - Example: `analyze-results.sh`

## Terminology

### "fundamental" vs "foundation"

Use **"fundamental"** for experiments:
- `run-exp-fundamental.sh` ✓ (correct: "fundamental experiments")
- `run-exp-foundation.sh` ✗ (incorrect: "foundation" is a noun)

**Rationale**:
- "fundamental experiments" = 基礎実験 (academically correct)
- "foundation experiments" = 土台実験 (grammatically awkward)

## Directory Structure (Future)

If the number of scripts grows significantly, consider organizing by type:

```
scripts/
├── gui/                  # GUI experiments
│   ├── foraging.sh
│   ├── coverage.sh
│   └── shepherding.sh
├── experiments/          # Numerical experiments
│   ├── fundamental.sh
│   ├── comparative.sh
│   └── ablation.sh
├── utils/               # Utilities
│   ├── collect-data.sh
│   └── setup-env.sh
└── analysis/            # Analysis scripts
    └── visualize.sh
```

## Migration Guide

When renaming existing scripts:

1. Create symlink from old name to new name
2. Add deprecation warning in old script
3. Update all documentation
4. Remove old script after 2 weeks

Example:
```bash
# Create symlink for backward compatibility
ln -s run-gui-foraging.sh run_experiment.sh

# Add deprecation warning
echo "Warning: run_experiment.sh is deprecated. Use run-gui-foraging.sh" >&2
```

## Naming Checklist

Before creating a new script, ask:

- [ ] Does it launch a GUI? → `run-gui-*.sh`
- [ ] Does it produce numerical data? → `run-exp-*.sh`
- [ ] Does it collect data? → `collect-*.sh`
- [ ] Does it analyze results? → `analyze-*.sh`
- [ ] Does it set up environment? → `setup-*.sh`
- [ ] Does it run a service? → `run-*.sh`

## Examples in Context

```bash
# Run GUI experiments (development/demo)
./scripts/run-gui-foraging.sh
./scripts/run-gui-coverage.sh
./scripts/run-gui-shepherding.sh

# Run numerical experiments (research/papers)
./scripts/run-exp-fundamental.sh 1 --trials 20
./scripts/run-exp-fundamental.sh 2 --trials 10
./scripts/run-exp-fundamental.sh 3 --trials 15

# Collect training data
./scripts/collect-gru-training-data.sh

# Validate implementation
./scripts/run-basic-validation.sh all
```

## Summary

| Prefix | Purpose | Output | Interactive |
|--------|---------|--------|-------------|
| `run-gui-` | Visual experiments | Display | Yes |
| `run-exp-` | Numerical experiments | JSON/CSV | No |
| `collect-` | Data collection | Data files | No |
| `analyze-` | Post-analysis | Plots/Reports | Partial |
| `setup-` | Environment setup | - | No |
| `run-` | General services | Varies | Varies |
