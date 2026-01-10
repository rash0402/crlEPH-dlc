# EPH v5.6 Documentation

This directory contains core documentation for the EPH (Emergent Perceptual Haze) v5.6 project.

## Core Documents (v5.6)

### 1. Research Proposal
**File**: `proposal_v5.6.md` (52 KB)

Complete research proposal including:
- Theoretical background (Free Energy Principle, Active Inference)
- System architecture (VAE, SPM, Haze modulation)
- Implementation details (Pattern D, Surprise integration)
- Expected contributions and evaluation methodology

**Use for**: Paper writing, grant applications, theoretical reference

---

### 2. Theoretical Framework
**File**: `framework_v5.6.md` (14 KB)

Concise technical specification covering:
- Mathematical formulation of free energy with Surprise
- Haze separation concept (Design parameter vs. VAE output)
- Self-Hazing theory (Phase 6)
- Implementation guidelines

**Use for**: Quick reference, implementation guidance, algorithm design

---

### 3. Implementation Plan
**File**: `implementation_plan_v5.6.md` (51 KB)

Detailed phase-by-phase implementation guide:
- **Phase 0**: Specification & environment setup
- **Phase 1**: Data collection (50k+ samples)
- **Phase 2**: VAE training
- **Phase 3**: VAE validation (gate conditions)
- **Phase 4**: Control integration (Fixed Haze)
- **Phase 5**: Comparison experiments & Haze sensitivity analysis
- **Phase 6**: Self-Hazing (meta-learning)

Includes:
- Directory structure (data/, results/, models/)
- Success criteria for each phase
- Code snippets and example usage
- Expected outputs and deliverables

**Use for**: Development workflow, task tracking, quality gates

---

## Document Hierarchy

```
Research Context
    ↓
proposal_v5.6.md (Why & What) - 52 KB
    ↓
framework_v5.6.md (How - Theory) - 14 KB
    ↓
implementation_plan_v5.6.md (How - Practice) - 51 KB
    ↓
Actual Implementation (src/, scripts/)
```

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| **v5.6** | 2026-01-10 | ✅ Surprise integration, Haze separation, Dual scenarios |
| v5.5 | 2025-12 | Pattern D VAE (archived in `archive/v55_docs/`) |

## Key Concepts (v5.6)

### Free Energy with Surprise
```
F(u) = F_goal(u) + F_safety(u) + λ_s·S(u)

where S(u) = ||y[k] - VAE_recon(y[k], u)||²
```

### Haze Modes
1. **Fixed** (Phase 1-5): Haze = 0.5 (constant)
2. **Scheduled** (Extension): Haze = f(density, risk)
3. **Self-Adaptive** (Phase 6): Haze = π_haze(obs, task, σ_z²)

### Dual Scenarios
- **Scramble Crossing**: 4-group intersection (Freezing Rate metric)
- **Corridor**: Bidirectional narrow passage (Throughput metric)

## Archived Documents (v5.5)

Located in `archive/v55_docs/`:
- `EPH-proposal_all_v5.5.md` (68 KB) - v5.5 proposal
- `implementation_plan.md` (14 KB) - Old implementation plan
- `EPH_AI_DLC_Proposal.md` (12 KB) - Early draft proposal
- `phase2_5_evaluation_report.md` (4.4 KB) - Phase 2.5 evaluation

**Note**: These are preserved for reference but superseded by v5.6 documents.

## Quick Start

1. **Understanding the project**: Read `proposal_v5.6.md` (Section 1-2)
2. **Implementation overview**: Read `framework_v5.6.md`
3. **Start coding**: Follow `implementation_plan_v5.6.md` (Phase 0 → 1)

## Related Documentation

- **Codebase guide**: `CLAUDE.md` (project root)
- **Setup instructions**: `SETUP.md` (project root)
- **Cleanup summary**: `CLEANUP_SUMMARY.md` (project root)
- **Data structure**: `data/logs/README.md`, `results/README.md`

## Notes

📝 All documents use Markdown format with GitHub-flavored extensions
🔢 Mathematical equations use LaTeX syntax
📊 Includes code snippets in Julia
🎯 Follows academic paper structure (Introduction → Method → Evaluation)

---

**Last Updated**: 2026-01-10
**Version**: 5.6.0
**Status**: Ready for Phase 0-1 implementation
