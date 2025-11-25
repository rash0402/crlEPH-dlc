---
title: EPH Project Documentation Index
date: 2025-11-25
tags: [index, documentation, navigation]
---

# EPH Project Documentation Index

## 🎯 Quick Start

New to the project? Start here:
1. [[CLAUDE|Project Overview and Development Guide]]
2. [[PHASE_GUIDE|Implementation Phases]]
3. [[VALIDATION_PHILOSOPHY|Testing Philosophy]]

## 📚 Core Documentation

### Framework Design

- **[[technical_notes/HazeTensorControl|Haze Tensor Control]]** ⭐⭐ **NEW** - General framework for swarm behavioral guidance
  - **汎用アプローチ**: Exploration, Shepherding, Foraging, Pursuit-Evasion等に適用可能
  - 3つの制御パラダイム: Self-Hazing, Environmental Hazing, Engineered Hazing
  - タスク別応用テンプレートと設計原則

- **[[HAZE_TENSOR_DESIGN_GUIDELINES]]** ⭐ - Comprehensive design guidelines for spatial haze modulation
  - 9 experiments, 69 configurations tested
  - Recommended strategies (Tier S/A/B/C)
  - Trade-off analysis and implementation guide
  - **Compactness invariance の理論的解明**

- [[technical_notes/EmergentPerceptualHaze_EPH|Emergent Perceptual Haze (EPH)]] - Main framework proposal (汎用性強調)
- [[technical_notes/SaliencyPolarMap_SPM|Saliency Polar Map (SPM)]] - Perceptual representation

### Implementation Guides

- [[EPH_Implementation_Guide_Julia]] - Julia implementation details
- [[EPH_Active_Inference_Derivation]] - Mathematical derivation
- [[PHASE_GUIDE]] - Development phases
  - Phase 1: Scalar Self-Haze ✅
  - Phase 2: Environmental Haze ✅
  - Phase 3: Full Tensor Haze ✅
  - Phase 4: Shepherding Task (in progress)

### Testing & Validation

- [[VALIDATION_PHILOSOPHY]] - Testing methodology and workflow
- [[DIAGNOSTICS_GUIDE]] - Diagnostic tools and troubleshooting

## 🔬 Experimental Results

### Completed Studies

1. **Phase 3 Parameter Sensitivity** (2025-11)
   - Best: Ω_threshold_occ=0.12, weights=[1.0, 0.3, 0.3]
   - Coverage: 93.2%

2. **Directional Haze** (2025-11)
   - Result: All symmetric configurations failed
   - Insight: Spatial anisotropy harmful for exploration

3. **Localized Haze** (2025-11) ⭐
   - Best: Central-Mid High (3.0x)
   - Coverage: 92.2% (+3.0%)
   - First positive spatial haze result

4. **Distance-Selective Haze** (2025-11) ⭐⭐
   - Best: Mid-5.0x @500 steps
   - Coverage: 93.2% (+4.0%)
   - Matches Phase 2 performance

5. **Asymmetric Haze** (2025-11) ⭐
   - Best: Left-Half High (2.0x)
   - Coverage: 92.2% (+3.0%)
   - Left > Right (significance TBD)

6. **Combined Strategy** (2025-11) ⭐⭐⭐
   - Best: Near × Left-Half (3.0x × 2.0x)
   - Coverage: 92.2% (+3.0%)
   - Positive synergy confirmed

7. **Channel-Selective Haze** (2025-11) ⭐⭐
   - Best: Tangential-Only High
   - Coverage: 90.2% (+1.0%)
   - **Critical**: Radial-selective is unsafe (-6.0%, +46 collisions)

8. **Spatial Scan with Compactness** (2025-11-25) ⭐⭐⭐
   - 16 haze positions tested (4 radial × 4 angular)
   - Coverage: 96.9-99.6%, Collision: 1006-1414
   - **⚠️ Critical Finding**: Compactness invariant (0.000159-0.000167, <5% variation)
   - **Theoretical insight**: Repulsion-only systems cannot modulate aggregation via haze alone
   - **Implication**: Social Value (attraction) term required for shepherding applications

## 📋 Experimental Reports

Detailed analysis documents:

- **[[experimental_reports/haze_tensor_effect|Haze Tensor Spatial Modulation Report]]** ⭐⭐⭐ - Comprehensive spatial scan analysis
  - Experiment ID: `haze_spatial_scan_2025-11-25`
  - Compactness invariance proof (theoretical + experimental)
  - Design implications for swarm aggregation tasks
  - Future directions: Social Value integration, Hierarchical Active Inference

### Data Files

Located in `data/analysis/`:
- `haze_spatial_scan_2025-11-25_14-17-14.json` ⭐ **NEW** - Spatial scan with Compactness
- `combined_strategy_2025-11-25_*.json`
- `channel_selective_2025-11-25_*.json`
- `comprehensive_evaluation_2025-11-25_*.json`
- `distance_selective_haze_optimization_*.json`
- `asymmetric_haze_*.json`

## 🛠️ Development

### Project Structure

```
crlEPH-dlc/
├── src_julia/          # Main Julia implementation
│   ├── core/           # Agent, Environment, Types
│   ├── perception/     # SPM computation
│   ├── control/        # EPH controller, haze modules
│   ├── prediction/     # SPM predictor (Linear, GRU)
│   └── utils/          # Math utilities, data collection
├── gui/                # PySide6 dashboard
├── viewer.py           # Pygame visualization
├── scripts/            # Experiment scripts
└── doc/                # Documentation (you are here)
```

### Key Modules

**Julia Modules:**
- `Types.jl` - Data structures (Agent, Environment, EPHParams)
- `SPM.jl` - Saliency Polar Map computation
- `SelfHaze.jl` - Scalar haze computation
- `FullTensorHaze.jl` - 3D tensor haze (Phase 3)
- `EPH.jl` - Gradient-based controller
- `Simulation.jl` - Main simulation loop

**Control Modules:**
- `DirectionalHaze.jl` - Angular-selective haze
- `FullTensorHaze.jl` - Per-channel haze

## 📊 Research Context

### Active Inference Framework

Expected Free Energy (EFE) minimization:

$$G(a) = \mathbb{E}_{q(o|a)}[D_{KL}[q(s|o,a) || p(s)]] - H[q(o|a)]$$

Precision modulation via Haze:

$$\Pi(r,\theta; h) = \Pi_{\text{base}}(r,\theta) \cdot (1-h)^\gamma$$

### Performance Benchmarks

| Configuration | Coverage @500 | Coverage @1000 | Notes |
|---------------|---------------|----------------|-------|
| **Baseline** | 89.2% | 99.2% | Uniform haze |
| **Phase 2 (Env Haze)** | 93.2% | - | Best lubricant config |
| **Mid-Distance 5.0x** | 93.2% | ~99% | Matches Phase 2 |
| **Near×Left-Half** | 92.2% | - | Best combined |
| **Left-Half 2.0x** | 92.2% | - | Best asymmetric |

## 🔮 Future Directions

### Short-term
- [ ] Multi-seed robustness validation (seeds: 42, 123, 456, 789, 1024)
- [ ] Scalability testing (10, 20, 50 agents)
- [ ] Long-run validation (10,000 steps)

### Medium-term
- [ ] Adaptive haze (task-dependent switching)
- [ ] Complex environments (walls, dynamic obstacles)
- [ ] Task-specific optimization (shepherding, foraging)

### Long-term
- [ ] Meta-learning haze policy (RL-based)
- [ ] Multi-task generalization
- [ ] Theoretical analysis (convergence proofs)

## 📝 Notes

- **Legend**: ⭐ = Important finding, ✅ = Completed, 🔬 = Under investigation
- All experiments use: 5 agents, 400×400 toroidal world, Random seed 42
- Evaluation: Coverage, Novelty rate, Distance/Coverage, Control cost, Safety

## 🔗 External Links

- [Claude Code GitHub](https://github.com/anthropics/claude-code)
- [Active Inference Papers](https://www.fil.ion.ucl.ac.uk/~karl/The%20free-energy%20principle%20A%20unified%20brain%20theory.pdf)
- [Stigmergy Review](https://www.sciencedirect.com/science/article/pii/S0167739X14000685)

---

*Last Updated: 2025-11-25*
*Status: Active Development*
