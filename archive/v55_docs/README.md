# EPH v5.5 Archived Documentation

This directory contains documentation from EPH v5.5 (December 2025).

## Contents

### 1. EPH-proposal_all_v5.5.md (68 KB)
Original research proposal for v5.5, including:
- Pattern D VAE architecture
- Haze = Agg(σ_z²) formulation (automatic calculation)
- No explicit Surprise term
- Single scenario (Scramble Crossing)

### 2. implementation_plan.md (14 KB)
Initial implementation plan with:
- Phase 0-2 structure
- Pattern B/D混在 architecture (architectural confusion)
- Limited evaluation metrics

### 3. EPH_AI_DLC_Proposal.md (12 KB)
Early draft proposal exploring:
- AI-DLC (Dynamic Learning Controller) concept
- FEP/HRI integration ideas
- Initial adaptive control proposals

### 4. phase2_5_evaluation_report.md (4.4 KB)
Phase 2.5 evaluation results:
- Corridor scenario testing
- Collision detection evaluation
- Baseline comparison metrics

## Why Archived?

EPH v5.5 had the following limitations addressed in v5.6:

| Aspect | v5.5 | v5.6 (Current) |
|--------|------|----------------|
| **Architecture** | Pattern B/D混在 | Clean Pattern D |
| **Surprise** | Not integrated | Explicit term: `F = F_goal + F_safety + λ_s·S` |
| **Haze** | Auto-calculated (σ_z²) | Design parameter (Fixed/Scheduled/Self) |
| **Scenarios** | Scramble only | Dual (Scramble + Corridor) |
| **VAE Role** | Prediction only | Prediction + Surprise |

## Access Policy

These documents are preserved for:
- Historical reference
- Tracking theoretical evolution
- Understanding design decisions

**Do not use for**:
- Current implementation (use v5.6 docs)
- Paper writing (cite v5.6)
- Code development (follow implementation_plan_v56.md)

## Migration to v5.6

Key changes made:
1. ✅ Separated Surprise from Haze (two-layer control)
2. ✅ Haze as explicit design parameter
3. ✅ Dual scenario support (Scramble + Corridor)
4. ✅ Phase 5.5 Haze sensitivity analysis added
5. ✅ Clear Phase 0-6 pipeline

## Related Archives

- **Logs**: `archive/v55_logs/` (~304 MB)
- **Results**: `archive/v55_results/` (~1.2 MB)

---

**Archived Date**: 2026-01-10
**Reason**: Superseded by v5.6 with cleaner architecture
**Current Docs**: See `doc/` for v5.6 documentation
