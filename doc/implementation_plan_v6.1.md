# Implementation Plan v6.1: Bin 1-6 Haze=0 Fixed Strategy

**Date**: 2026-01-12
**Version**: 6.1
**Status**: Planning Phase

---

## Overview

v6.1 introduces a **Bin-Based Fixed Foveation** strategy to replace the Dual-Zone sigmoid approach. This change is grounded in neuroscience (Peripersonal Space), Active Inference (precision weighting), empirical research (pedestrian behavior), and control theory (gradient requirements).

### Key Changes

1. **Sensing Range**: `D_max = 7.5m → 8.0m` (2³, mathematical elegance + biological validity)
2. **Foveation Strategy**: Dual-Zone (sigmoid) → **Bin 1-6 Haze=0 Fixed** (step function)
   - **Bin 1-6** (0-2.18m): `Haze = 0.0` (β_max = 10.0, critical collision zone)
   - **Bin 7+** (2.18m+): `Haze = 0.5` (β ≈ 5.5, peripheral zone)

### Theoretical Justification

| Discipline | Key Evidence | Bin 1-6 Alignment |
|------------|--------------|-------------------|
| **Neuroscience** | Peripersonal Space (PPS) 0.5-2.0m | ✓ Bin 1-6 (2.18m) covers Extended PPS |
| **Active Inference** | Precision weighting for survival-critical predictions | ✓ High Π (Haze=0) required |
| **Empirical Research** | Avoidance initiation 2-3m (Moussaïd et al., 2011) | ✓ Bin 6 (2.18m) at lower bound |
| **Control Theory** | TTC 1s (predictive control) → 2.1m | ✓ Bin 6 covers TTC 1s |
| **Cognitive Science** | Dual-process (System 1 vs 2) | ✓ System 1 (0-2.18m) → High precision |

---

## Implementation Status

### ✅ Completed (2026-01-12)

1. **Core Implementation**
   - `src/config.jl`: `sensing_ratio = 8.0`, `FoveationParams` updated
   - `src/controller.jl`: `compute_precision_map()` simplified (step function)
   - `src/spm.jl`: ForwardDiff.Dual compatibility

2. **Visualization**
   - `tmp/visualize_bin16_haze0.jl`: 4 figures generated
   - Bin structure, Haze/β modulation, gradient strength, theoretical justification

3. **Git Commit**
   - Commit: `86c7577`
   - Message: "feat: Implement Bin 1-6 Haze=0 Fixed Strategy (v6.1)"
   - Pushed to `origin/main`

---

## Proposed Phased Approach

### Critical Question: VAE Retraining Required?

**Two-Phase Strategy**:

```
Phase 1: Test Bin 1-6 Haze=0 with Existing VAE (No retraining)
  ↓
  Evaluate collision avoidance performance
  ↓
Phase 2: VAE Retraining (If necessary)
```

**Rationale**:
1. **D_max change (7.5m → 8.0m)**: Only 7% difference, VAE may generalize
2. **Haze strategy change**: Affects β modulation (independent of VAE prediction)
3. **Primary effect**: Gradient strength for ∂Φ_safety/∂u (β-dependent, not VAE-dependent)

---

## Phase 1: Validation Without VAE Retraining

**Goal**: Verify that Bin 1-6 Haze=0 improves collision avoidance with existing VAE

### 1.1 Test Setup

**Scenario**: Unified obstacle test (scramble crossing)
- Script: `scripts/test_obstacles_unified.jl`
- Agents: 4 groups × 10 agents (N/S/E/W)
- Duration: 3000 steps (100 seconds @ 30Hz)

**Comparison Groups**:

| Group | D_max | Foveation Strategy | VAE Model |
|-------|-------|-------------------|-----------|
| **Baseline (v6.0)** | 7.5m | Dual-Zone (rho_index_ps=4) | Current (7.5m trained) |
| **v6.1 (Proposed)** | 8.0m | Bin 1-6 Haze=0 Fixed | Current (7.5m trained) |

**Hypothesis**:
- v6.1 will show **lower collision rate** despite VAE mismatch (D_max)
- Reason: Stronger ∂Φ_safety/∂u gradients in Bin 1-6

### 1.2 Evaluation Metrics

**Primary Metrics**:
1. **Collision Rate** (%)
   - Emergency stop activations / total steps
   - Lower is better

2. **Freezing Rate** (%)
   - Steps with |v| < 0.1 m/s / total steps
   - Lower is better (indicates smoother avoidance)

3. **Path Efficiency**
   - Actual path length / Optimal path length
   - Closer to 1.0 is better

**Secondary Metrics**:
4. **Gradient Magnitude** (∂Φ_safety/∂u)
   - Average gradient strength in critical situations
   - Higher is better (confirms theoretical prediction)

5. **VAE Prediction Error** (MSE)
   - Monitor if D_max mismatch causes issues
   - If error spikes, VAE retraining needed

### 1.3 Decision Criteria

**Proceed to Phase 2 (VAE Retraining) if**:
- ✅ Collision rate reduced by >10% (validates Bin 1-6 Haze=0)
- ⚠️ VAE prediction error is high (MSE > 2× baseline)

**Skip Phase 2 if**:
- ✅ Collision rate reduced AND VAE error acceptable
- Conclusion: Existing VAE generalizes well to D_max=8.0m

**Abort v6.1 if**:
- ❌ Collision rate NOT reduced (theory invalidated)

### 1.4 Timeline

- **Test Execution**: ~4 hours (multiple runs for statistical significance)
- **Analysis**: ~2 hours
- **Decision**: Same day

---

## Phase 2: VAE Retraining (Conditional)

**Trigger**: Phase 1 shows collision improvement BUT high VAE prediction error

### 2.1 Data Collection Requirements

**Dataset Specifications**:
- **SPM Configuration**: D_max = 8.0m, n_rho = 16, n_theta = 16
- **Haze Strategy**: Bin 1-6 Haze=0 Fixed (no variation)
- **Scenarios**: Same as v6.0 (scramble crossing, various densities)
- **Size**: 50,000 samples (y[k], u[k], y[k+1]) triplets

**Data Generation Script**: `scripts/create_dataset_v61.jl`

```julia
# Key parameters
spm_params = SPMParams(sensing_ratio=8.0)
foveation_params = FoveationParams(rho_index_critical=6, h_critical=0.0, h_peripheral=0.5)

# Fixed Haze (no agent-dependent variation)
function compute_haze_fixed(spm_config)
    n_rho, n_theta = spm_config.params.n_rho, spm_config.params.n_theta
    haze = zeros(Float64, n_rho, n_theta)
    haze[1:6, :] .= 0.0      # Bin 1-6: Critical
    haze[7:end, :] .= 0.5    # Bin 7+: Peripheral
    return haze
end
```

### 2.2 VAE Architecture

**No change from v6.0** (Pattern D: Action-Conditioned VAE)
- Encoder: `q(z | y[k], u[k])`
- Decoder: `p(y[k+1] | z, u[k])`
- Latent dim: 32

**Hyperparameters** (from v6.0 best config):
- β (KL weight): 0.5
- Learning rate: 1e-4
- Batch size: 128
- Epochs: 100

### 2.3 Training Pipeline

1. **Generate Dataset** (est. 6 hours)
   ```bash
   julia --project=. scripts/create_dataset_v61.jl
   ```

2. **Train VAE** (est. 4 hours on GPU)
   ```bash
   julia --project=. scripts/train_action_vae_v61.jl
   ```

3. **Validate** (est. 1 hour)
   - Reconstruction quality (MSE < 0.05)
   - Latent space structure (KL divergence)

4. **Integration Test** (est. 2 hours)
   - Repeat Phase 1 tests with new VAE
   - Verify collision rate improvement maintained

### 2.4 Timeline (if triggered)

- **Data Collection**: 6 hours
- **Training**: 4 hours
- **Validation**: 1 hour
- **Integration Test**: 2 hours
- **Total**: ~13 hours (2 days)

---

## Alternative: Skip VAE Retraining Entirely?

### Argument FOR Skipping

1. **Haze Effect is β-Mediated**
   - Bin 1-6 Haze=0 → β_max = 10.0 (sharp gradients)
   - This effect is **independent of VAE predictions**
   - VAE only affects Surprise term `S(u)`, not `Φ_safety(u)`

2. **D_max Change is Small**
   - 7.5m → 8.0m is only 7% difference
   - Bin structure changes, but relative proportions similar
   - VAE may generalize well (neural nets are robust)

3. **Time Efficiency**
   - Skip 13 hours of retraining
   - Proceed directly to main experiments

### Argument AGAINST Skipping

1. **Academic Rigor**
   - Reviewers may question VAE-SPM mismatch
   - "Why use VAE trained on wrong D_max?"

2. **Optimal Performance**
   - VAE trained on D_max=8.0m will be more accurate
   - Better Surprise estimates → better action selection

3. **Future-Proofing**
   - v6.1 VAE becomes the new baseline
   - Avoids confusion in future experiments

### Recommendation

**Start with Phase 1 (No VAE retraining)**:
- Quick validation of core hypothesis (Bin 1-6 Haze=0 improves collision avoidance)
- If successful AND VAE error acceptable → **Skip Phase 2**
- If successful BUT VAE error high → **Proceed to Phase 2**

This maximizes efficiency while maintaining rigor.

---

## Next Steps (Immediate)

### Step 1: Decide on Phased Approach

**User Decision Required**:
1. **Option A**: Two-Phase (Test first, retrain conditionally) — **Recommended**
2. **Option B**: Direct to VAE Retraining (more conservative)
3. **Option C**: Skip VAE entirely (most aggressive)

### Step 2: Prepare Test Script (Phase 1)

If Option A or C:
- Modify `scripts/test_obstacles_unified.jl` for v6.1 comparison
- Set up logging for all metrics (collision, freezing, gradient, VAE error)

If Option B:
- Prepare `scripts/create_dataset_v61.jl`
- Estimate computational resources (GPU availability)

### Step 3: Execute

Based on decision, execute appropriate pipeline.

---

## Open Questions

1. **VAE Generalization**: How robust is the current VAE to D_max change?
   - **Action**: Phase 1 will answer this empirically

2. **Computational Budget**: Do we have GPU access for VAE retraining?
   - **Action**: Check availability if Phase 2 needed

3. **Baseline Definition**: Should we compare against v5.5, v6.0, or both?
   - **Recommendation**: v6.0 only (most recent)

4. **Statistical Significance**: How many test runs needed?
   - **Recommendation**: 10 runs × 3000 steps = reliable statistics

---

## Success Criteria (Overall)

v6.1 is considered successful if:

1. ✅ **Collision rate reduced** by ≥10% vs v6.0
2. ✅ **Freezing rate reduced** by ≥10% vs v6.0
3. ✅ **Gradient magnitude increased** in Bin 1-6 (confirms theory)
4. ✅ **Path efficiency maintained** (≥95% of v6.0)
5. ✅ **Implementation simpler** than v6.0 (already achieved: step function vs sigmoid)

If criteria met → Proceed to paper writing with v6.1 as final system.

---

## Appendix: File Checklist

### Core Implementation (✅ Completed)
- [x] `src/config.jl` — Updated DEFAULT_SPM, FoveationParams
- [x] `src/controller.jl` — Updated compute_precision_map(), compute_action_v61()
- [x] `src/spm.jl` — ForwardDiff.Dual compatibility
- [x] `tmp/visualize_bin16_haze0.jl` — Visualization script

### Phase 1 (Pending User Decision)
- [ ] `scripts/test_obstacles_unified_v61.jl` — Modified test script
- [ ] `scripts/analyze_v61_results.jl` — Metrics analysis script

### Phase 2 (Conditional)
- [ ] `scripts/create_dataset_v61.jl` — Data generation (D_max=8.0m, Bin 1-6 Haze=0)
- [ ] `scripts/train_action_vae_v61.jl` — VAE training with new data
- [ ] `models/action_vae_v61_best.bson` — Trained model

### Documentation
- [x] `doc/implementation_plan_v6.1.md` — This document
- [ ] `doc/proposal_v6.1.md` — Update with empirical results (after Phase 1)
- [ ] `doc/FINAL_PAPER_REPORT.md` — Update with v6.1 final results

---

**End of Implementation Plan v6.1**
