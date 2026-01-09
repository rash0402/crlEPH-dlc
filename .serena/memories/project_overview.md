# Project Overview (Updated 2026-01-09)

## Purpose
Research implementation of **Emergent Perceptual Haze (EPH)** v5.5 for social robot navigation in crowded environments. EPH uses adaptive perceptual resolution control based on Active Inference and Free Energy Principle (FEP) to suppress freezing behavior through uncertainty-driven precision modulation.

## Core Research Concepts

### 1. Saliency Polar Map (SPM)
- **Bio-inspired representation**: Log-polar coordinates mimicking primate V1 cortex
- **Resolution**: 16×16×3 channels
- **Channels**:
  1. Occupancy (density)
  2. Proximity Saliency (surface distance, adaptive β softmin)
  3. Dynamic Collision Risk (TTC-based, adaptive β softmax)
- **FOV**: 210° forward-facing
- **Adaptive Resolution**: β parameter modulated by Haze (β ∈ [0.1, 10.0])

### 2. Haze (Uncertainty-based Precision Modulation)
**v5.5 Pattern D Definition**:
- **Not environmental stigmergy**, but **action-dependent uncertainty estimate**
- **Counterfactual Haze**: H[k] = Agg(σ²_z(y[k], u[k]))
  - Encoder takes both current observation y[k] AND proposed action u[k]
  - High-risk actions → High latent variance → High Haze
  - Safe actions → Low latent variance → Low Haze
- **Causal Flow**: u[k] proposed → H(y[k], u[k]) estimated → β[k+1] modulated
- **Effect**: Risky action → High Haze → Low Precision → Conservative behavior

### 3. Action-Conditioned VAE (Pattern D)
```
Encoder: (y[k], u[k]) → q(z | y, u)     # Action-Dependent latent distribution
Decoder: (z, u[k]) → ŷ[k+1]              # Action-Conditioned future prediction
Haze: H[k] = (1/D) Σ σ²_z,d(y[k], u[k]) # Counterfactual uncertainty
```

**Key Innovation**: Encoder receives proposed action u[k], enabling "What if I take this action?" uncertainty estimation before execution.

### 4. EPH Control Loop
Agent selects action by minimizing expected free energy:
```
u*[k] = argmin_u E_q(z|y,u)[F(ŷ[k+1])]

F(ŷ) = ‖x[k+1] - x_g‖² + λ Σ φ(ŷ)
```
- Solved via gradient descent using ForwardDiff.jl
- Gradient flows through decoder only (encoder fixed during u-optimization)
- β modulation happens after u selection for next timestep

### 5. Freezing Suppression Mechanism
**Problem**: In crowded environments, robots often freeze due to over-conservative planning.

**EPH Solution**:
- High uncertainty → Low precision (β ↓) → Averaged perception → Smooth action
- Low uncertainty → High precision (β ↑) → Sharp perception → Precise avoidance
- **Result**: 36% Freezing reduction, 23% Jerk improvement (M3 validation)

## Current Implementation Status (v5.5)

### Completed Milestones

**M1 (Base Infrastructure)**: ✅ Complete
- Julia backend with toroidal world physics
- 4-group scramble crossing scenario (N/S/E/W flows)
- ZMQ streaming (Julia → Python) at 30-60 Hz
- Main viewer (color-coded groups) + Detail viewer (SPM/metrics)

**M2 (World Model)**: ✅ Complete
- Action-Conditioned VAE (Pattern D) implementation
- Encoder: (y, u) → q(z|y,u) with reparameterization trick
- Decoder: (z, u) → ŷ with action conditioning
- Training pipeline: Data collection → VAE training → Model checkpointing
- Haze calculation: Aggregation of latent variance σ²_z

**M3 (Integration & Validation)**: ✅ Complete
- Haze-based β modulation in SPM generation
- Freezing detection algorithm (velocity < threshold for N consecutive steps)
- Evaluation metrics: Success Rate, Collision Rate, Freezing Rate, Jerk, min TTC
- Ablation study framework (A1-A4 conditions)
- Statistical validation: 36% Freezing reduction, 23% Jerk improvement
- v5.5 Pattern D alignment confirmed

### Planned Milestones

**M4 (Advanced Features)**: 🔄 In Planning
- **Expected Free Energy (EFE)**: Predictive collision avoidance via future uncertainty minimization
- **Ch3-Centric Evaluation**: Dynamic collision risk (TTC) as primary decision factor
- **Swarm Extension**: Local Haze coordination for emergent collective behavior
  - Each agent estimates local Haze
  - Precision modulation creates adaptive cohesion/separation
  - Congestion/fragmentation suppression through emergent coordination

## Research Documentation

### Primary Documents
- **`doc/EPH-proposal_all_v5.5.md`**: Full research proposal (comprehensive, 1000+ lines)
- **`doc/EPH_AI_DLC_Proposal.md`**: Condensed proposal for quick reference
- **`CLAUDE.md`**: AI developer guide with v5.5 specifications

### Historical Documents
- **Previous versions** (v5.0-v5.4): Pattern B architectures (git history)
- **Pattern Evolution**:
  - Pattern A: Basic VAE (y → z → ŷ)
  - Pattern B: Action-Conditioned Decoder (y → z, (z,u) → ŷ) [EPH-proposal_all_v5.5.md discusses but not implemented]
  - Pattern D: Action-Dependent Encoder ((y,u) → z, (z,u) → ŷ) [Current implementation]

## Key Dependencies

### Julia Core
- **Flux.jl**: Neural network framework (VAE implementation)
- **Zygote.jl**: Automatic differentiation (VAE training)
- **ForwardDiff.jl**: Forward-mode AD (action gradient ∂F/∂u)
- **HDF5.jl**: Data logging and persistence
- **ZMQ.jl**: Inter-process communication (server)
- **MessagePack.jl**: Efficient binary serialization

### Python Visualization
- **pygame**: Real-time rendering (main viewer)
- **matplotlib**: SPM visualization (detail viewer)
- **zmq**: ZMQ client (SUB socket)
- **numpy**: Array operations
- **msgpack**: Message deserialization

## Running the Project

### Full Simulation (Recommended)
```bash
./scripts/run_all.sh
```
Starts Julia backend + Python viewers automatically.

### Individual Components
```bash
# Backend only
julia --project=. scripts/run_simulation.jl

# Viewers only (requires backend running)
~/local/venv/bin/python viewer/detail_viewer.py
~/local/venv/bin/python viewer/main_viewer.py
```

### VAE Training & Validation
```bash
# Collect training data
julia --project=. scripts/collect_diverse_vae_data.jl

# Train VAE
julia --project=. scripts/train_action_vae.jl

# Validate Haze
julia --project=. scripts/validate_haze.jl
```

### Evaluation
```bash
# Run metrics evaluation
julia --project=. scripts/evaluate_metrics.jl

# M4 validation
julia --project=. scripts/validate_m4.jl
```

## Research Context

### Theoretical Foundation
- **Free Energy Principle (Friston, 2010)**: Unified framework for perception and action
- **Active Inference**: Action selection via expected free energy minimization
- **Precision Weighting**: Uncertainty modulates perceptual sharpness (not just noise)

### Novel Contributions (v5.5)
1. **Counterfactual Haze**: Action-dependent uncertainty for proactive risk assessment
2. **Adaptive Perceptual Resolution**: β modulation as design principle for uncertainty handling
3. **Freezing Suppression**: Structural solution via precision control (not parameter tuning)
4. **Pattern D Architecture**: Encoder receives actions for "what-if" uncertainty estimation

### Academic Positioning
- **Problem**: Freezing Robot Problem in crowded navigation (Trautman et al., 2015)
- **Gap**: Existing methods lack explicit uncertainty-perception coupling
- **Solution**: EPH provides design principle for uncertainty-adaptive behavior
- **Validation**: 36% Freezing reduction in scramble crossing scenario

## Performance Characteristics

- **Simulation Speed**: ~60 Hz (16 agents, toroidal world)
- **VAE Inference**: ~10ms per forward pass (CPU, Apple Silicon M2)
- **Memory Usage**: ~500MB (simulation + VAE model)
- **Data Generation**: ~1GB/hour (HDF5 logs)
- **Training Time**: ~2 hours for 200 epochs (action VAE)

## Next Steps (M4 Focus)

1. **EFE Implementation**: Replace VFE with expected free energy for predictive control
2. **Ch3 Prioritization**: Shift from Ch2 (proximity) to Ch3 (dynamic risk) evaluation
3. **Swarm Experiments**: Multi-agent scenarios with local Haze coordination
4. **Paper Preparation**: Finalize experiments for academic submission
