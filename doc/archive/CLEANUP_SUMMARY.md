# EPH v5.6 Directory Cleanup Summary

**Date**: 2026-01-10
**Action**: Restructured project directories for v5.6

## Changes Made

### 1. Logs Directory (data/logs/)
- ✅ **Archived** all v5.5 logs (~300 MB) to `archive/v55_logs/`
- ✅ **Created** new v5.6 structure:
  - `control_integration/{scramble,corridor}/` - Phase 4
  - `comparison/{scramble,corridor}/{A0-A3}/` - Phase 5.1-5.4
  - `haze_sensitivity/{scramble,corridor}/` - Phase 5.5
  - `self_hazing/{scramble,corridor}/` - Phase 6

### 2. Results Directory (results/)
- ✅ **Archived** old results to `archive/v55_results/`:
  - `comparison_challenging/`
  - `comparison_emergency/`
  - `evaluation/`
  - `haze_validation/`
- ✅ **Created** clean v5.6 structure:
  - `data_collection/` - Phase 1
  - `vae_training/` - Phase 2
  - `vae_validation/` - Phase 3
  - `control_integration/` - Phase 4
  - `comparison/` - Phase 5.1-5.4
  - `haze_sensitivity/` - Phase 5.5
  - `self_hazing/` - Phase 6

### 3. VAE Training Data (data/vae_training/)
- ✅ **Created** structure:
  - `raw/{scramble,corridor}/` - Individual simulation logs
  - `dataset_v56.h5` - Unified training dataset (to be generated)

### 4. Documentation
- ✅ **Added** READMEs:
  - `data/logs/README.md` - Log directory guide
  - `results/README.md` - Results directory guide
  - `archive/README.md` - Archive information
  - `archive/v55_logs/README.md` - v5.5 logs details

### 5. Git Configuration
- ✅ **Updated** `.gitignore`:
  - Excludes all logs: `data/logs/`, `data/vae_training/raw/`
  - Excludes models: `models/*.bson`
  - Excludes archives: `archive/v55_logs/`, `archive/v55_results/`
  - Keeps results: `results/` is Git-managed
- ✅ **Added** `.gitkeep` files for empty directory preservation

## Directory Size Summary

| Directory | Size | Git-Managed? |
|-----------|------|--------------|
| `data/logs/` | 0 (empty) | ❌ No (excluded) |
| `data/vae_training/` | 0 (empty) | ❌ No (excluded) |
| `results/` | ~1 MB | ✅ Yes |
| `archive/v55_logs/` | 304 MB | ❌ No (excluded) |
| `archive/v55_results/` | 1.2 MB | ❌ No (excluded) |

## Benefits

1. **Clean Slate**: v5.6 has dedicated, organized directories
2. **Clear Phases**: Each Phase (1-6) has explicit output locations
3. **Dual Scenarios**: Scramble Crossing and Corridor are separated
4. **Git Efficiency**: Only lightweight results are tracked
5. **Preserved History**: v5.5 data archived for reference

## Next Steps

Ready for Phase 0-1 implementation:
1. Implement `src/scenarios.jl` (Scramble/Corridor modules)
2. Create `scripts/collect_vae_data_v56.jl`
3. Run data collection → populate `data/vae_training/raw/`
4. Generate unified `dataset_v56.h5`

## Documentation References

- Implementation plan: `doc/implementation_plan_v5.6.md`
- Theoretical framework: `doc/framework_v5.6.md`
- Proposal: `doc/proposal_v5.6.md`
