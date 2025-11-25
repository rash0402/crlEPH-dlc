# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a research implementation of the "Emergent Perceptual Haze (EPH)" framework for swarm intelligence. EPH uses spatial precision modulation based on Active Inference and Free Energy Principle (FEP) to guide agent behavior in multi-agent environments.

**Core Concepts:**
- **Saliency Polar Map (SPM)**: Bio-inspired perceptual representation using log-polar coordinates
- **Haze**: Spatial precision modulation field that influences agent perception and behavior
- **Active Inference**: Agents minimize free energy through haze-modulated surprise minimization
- **Stigmergy**: Environmental coordination through deposited haze trails

## Architecture

The codebase has **dual implementations** (Python and Julia) with different purposes:

### Julia Implementation (Primary Simulation)
Located in `src_julia/`, this is the current active implementation optimized for performance.

**Module Structure:**
- `core/Types.jl` - Agent and Environment data structures
- `perception/SPM.jl` - Saliency Polar Map computation with Gaussian splatting
- `control/SelfHaze.jl` - Self-haze computation and precision modulation (Phase 1)
- `control/EnvironmentalHaze.jl` - Environmental haze sampling, composition, deposition (Phase 2)
- `control/FullTensorHaze.jl` - 3D tensor haze with per-channel control (Phase 3)
- `control/EPH.jl` - Gradient-based action selection using Zygote automatic differentiation
- `prediction/SPMPredictor.jl` - GRU neural network for SPM prediction
- `utils/MathUtils.jl` - Toroidal geometry utilities
- `utils/DataCollector.jl` - Training data collection for GRU
- `utils/ExperimentLogger.jl` - Diagnostic logging and analysis
- `Simulation.jl` - Main simulation loop and agent management
- `main.jl` - ZeroMQ server entry point

**Key Design Patterns:**
- Modules use `using ..Types` for sibling module access
- SPM uses soft-mapping with Gaussian kernels for differentiability
- EPH controller uses gradient descent on a dual-objective cost function: `F_percept + λ * M_meta`
- Toroidal (wrap-around) world geometry throughout

### Python Implementation (Legacy/Experimentation)
Located in `src/`, used for prototyping and analysis.

**Structure:**
- `core/` - simulator, environment, agent
- `perception/spm.py` - SPM tensor generation
- `control/eph.py` and `eph_gradient.py` - Control implementations
- `utils/` - math utilities, visualization tools

### Visualization
- `viewer.py` - Real-time Pygame-based visualization that connects to Julia server via ZeroMQ
- Renders agents, FOV sectors, and haze grid overlay

## Common Development Commands

### Running the Full Simulation
```bash
./scripts/run_experiment.sh
```
This script:
1. Starts the Julia EPH server on port 5555 (ZeroMQ PUB socket)
2. Starts the Python viewer (ZeroMQ SUB socket)
3. Handles cleanup on Ctrl+C

**Prerequisites:**
- Julia installed via juliaup (`~/.juliaup/bin/julia`)
- Python virtual environment at `~/local/venv/`
- Port 5555 available

### Julia Development

**Running directly:**
```bash
cd src_julia
julia main.jl
```

**Installing/updating dependencies:**
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

**Dependencies** (from Project.toml):
- ZMQ - Inter-process communication
- Zygote - Automatic differentiation for gradient-based control
- JSON - Message serialization
- LinearAlgebra, Random, Statistics - Standard libraries

### Python Development

**Running viewer standalone** (requires Julia server running):
```bash
export PYTHONPATH=.
python viewer.py
```

**Running experiments:**
```bash
python scramble_with_spm.py
python narrow_corridor_visual.py
```

**Dependencies** (requirements.txt):
```
numpy
pygame
zmq
```

## Key Implementation Details

### SPM (Saliency Polar Map)
- **Shape**: `(3, Nr, Ntheta)` where channels are [Occupancy, Radial Velocity, Tangential Velocity]
- **Coordinate mapping**: Personal space defines inner zone (bin 0), outer zones use log-polar mapping
- **Gaussian splatting**: Objects contribute to multiple bins via soft-mapping for differentiability
- **Precision matrix**: Sigmoid function modulates attention based on distance vs personal_space

### EPH Controller (Julia)
- **Cost function**: `J(a) = F_percept(a, Haze) + M_meta(a)`
  - `F_percept`: Haze-modulated collision avoidance cost
  - `M_meta`: Goal-seeking or exploration maintenance cost
- **Optimization**: Gradient descent via Zygote.gradient with 5 iterations
- **Haze modulation**: High haze reduces effective precision → reduces collision avoidance → "lubricant" effect
- **Action smoothing**: 70% new action + 30% previous velocity for continuity

### SPM Predictor

**Default**: GRU Neural Predictor (`:neural`)
- **Model**: Trained GRU with hidden size 128
- **Performance**: MSE ~0.28 (80x better than Linear)
- **Location**: `data/models/predictor_model.jld2`
- **Training**: 75 episodes (15 agents × 5 files), Train Loss=0.041, Test Loss=0.044

**Linear Predictor (`:linear`)**:
- **Purpose**: Initial training data generation ONLY
- **Usage**: `src_julia/collect_training_data.jl` uses Linear to avoid GRU inference overhead
- **Performance**: MSE ~22.2 (baseline)
- **Note**: Not recommended for actual simulation (use GRU instead)

**Predictor Policy** (established 2025-11-24):
- ✅ **Phase 1-4 Simulations**: Use GRU predictor (default)
- ✅ **Data Collection for GRU Training**: Use Linear predictor (efficiency)
- ⚠️ **Never use Linear for evaluation**: GRU provides 80x better prediction accuracy

### Haze Mechanics

#### Phase 1: Self-Haze (Scalar)
- **Formula**: `h_self(Ω) = h_max · σ(-α(Ω - Ω_threshold))` where `σ(x) = 1/(1 + exp(-x))`
- **Parameters** (optimized 2025-11-24):
  - `h_max = 0.8`: Maximum self-haze level
  - `α = 10.0`: Sigmoid sensitivity
  - **`Ω_threshold = 0.12`**: Occupancy threshold (**optimized for 50:50 state distribution**)
  - `γ = 2.0`: Haze attenuation exponent
- **Cognitive States**:
  - **Isolated** (h > 0.5): Low occupancy → High haze → Low precision → **Exploration mode**
  - **Grouped** (h ≤ 0.5): High occupancy → Low haze → High precision → **Collision avoidance mode**
- **State Transitions**: Expected ~0.13-0.17 transitions per timestep with Ω_threshold=0.12
- **Effect**: `Π(r,θ; h) = Π_base(r,θ) · (1-h)^γ` - High haze reduces precision, enabling exploration

#### Phase 2: Environmental Haze (Spatial + Stigmergy) - **Integrated 2025-11-24**
- **Implementation**: `control/EnvironmentalHaze.jl` - Fully integrated in `Simulation.jl`
- **Spatial Self-Haze**: `h_self_matrix(r,θ)` computed per SPM bin instead of scalar
  - Formula: `h_self(r,θ) = h_max · σ(-α(Ω(r,θ) - Ω_threshold))`
  - Enables directional precision modulation
- **Environmental Haze**: 2D grid (`haze_grid`) for stigmergic communication
  - Agents sample `h_env` at SPM bin locations using bilinear interpolation
  - Haze composition: `H_total(r,θ) = max(H_self(r,θ), H_env(r,θ))`
- **Haze Deposition**: Agents deposit trails at their positions each timestep
  - **Lubricant** (`:lubricant`): Decreases haze → increases precision → guides followers
  - **Repellent** (`:repellent`): Increases haze → decreases precision → promotes exploration
  - Default: Repellent with amount=0.2, deposited in 3×3 neighborhood
- **Haze Decay**: Global decay factor 0.99 (1% per timestep) prevents accumulation
- **Parameters** (EPHParams) - **Optimized 2025-11-24**:
  - `enable_env_haze::Bool = false` - Phase 2 activation flag
  - `haze_deposit_amount::Float64 = 0.3` - Deposition magnitude (**optimized: 0.3**)
  - `haze_decay_rate::Float64 = 0.97` - Temporal forgetting rate (**optimized: 0.97 = 3%/step**)
  - `haze_deposit_type::Symbol = :lubricant` - **Lubricant (RECOMMENDED)** or Repellent
- **Parameter Sensitivity Analysis** (24 experiments, 500 steps, 5 agents):
  - **Best Configuration**: Lubricant, deposit=0.3, decay=0.97
  - ✓ Coverage: **93.2%** (Phase 1: 89.2%, **+4.0% improvement**)
  - ✓ Lubricant haze outperforms Repellent haze
  - ✓ Optimal deposit amount: 0.3 (higher deposition = better coordination)
  - ✓ Optimal decay rate: 0.97 (faster decay = fresher trails)
- **Lubricant vs Repellent Comparison**:
  - **Lubricant**: Decreases haze → increases precision → improves exploration
  - **Repellent**: Increases haze → decreases precision → reduces coverage
  - Lubricant achieves higher maximum coverage (93.2% vs 92.5%)

#### Phase 3: Full Tensor Haze (Per-Channel Control) - **Integrated 2025-11-24**
- **Implementation**: `control/FullTensorHaze.jl` - Fully integrated in `Simulation.jl`
- **3D Haze Tensor**: `H(c, r, θ)` where c ∈ {occupancy, radial_vel, tangential_vel}
  - Per-channel haze computation: `h_c(r,θ) = h_max_c · σ(-α_c(Ω_c - Ω_threshold_c))`
  - Enables selective attention and cognitive biases
- **Per-Channel Precision**: `Π(c, r, θ) = Π_base · (1 - h(c,r,θ))^γ`
  - Different precision for each SPM channel
  - Channel masking for selective attention (e.g., "see obstacles but ignore them")
- **Weighted Precision Collapse**: 3D tensor → 2D for compatibility with current EPH controller
  - `Π(r,θ) = Σ_c w_c · Π(c,r,θ) / Σ_c w_c`
  - Allows gradual integration without EPH controller rewrite
- **Parameters** (EPHParams):
  - `enable_full_tensor::Bool = false` - Phase 3 activation flag
  - `channel_weights::Vector{Float64} = [1.0, 0.5, 0.5]` - Per-channel importance [occ, rad, tan]
  - `channel_mask::Vector{Float64} = [1.0, 1.0, 1.0]` - Selective attention mask
  - Per-channel thresholds: `Ω_threshold_occ`, `Ω_threshold_rad`, `Ω_threshold_tan`
  - Per-channel sensitivity: `α_occ`, `α_rad`, `α_tan`
  - Per-channel max haze: `h_max_occ`, `h_max_rad`, `h_max_tan`
- **Initial Comparison Results** (200 steps, 5 agents):
  - Phase 1 (Baseline): Coverage 52.2%, Self-Haze 0.555
  - Phase 2 (Optimized): Coverage 42.8% (-9.5%), Self-Haze 0.557
  - Phase 3 (Full Tensor): Coverage 40.0% (-12.2%), Self-Haze 0.061
  - **Note**: Lower coverage in Phase 3 suggests parameter tuning needed
  - Very low self-haze (0.061) indicates aggressive per-channel thresholds
- **Future Enhancements**:
  - Enhance EPH controller to use full 3D precision tensor (no collapse)
  - Per-channel Expected Free Energy computation
  - Channel-specific exploratory behaviors

### Communication Protocol (Julia ↔ Python)
**ZeroMQ PUB-SUB pattern**

Message format (JSON):
```json
{
  "frame": int,
  "agents": [
    {
      "id": int,
      "x": float, "y": float,
      "vx": float, "vy": float,
      "radius": float,
      "color": [r, g, b],
      "orientation": float,
      "has_goal": bool
    }
  ],
  "haze_grid": [[float]]
}
```

## Research Context

This implementation corresponds to the research proposals in `doc/`:
- **20251121_Emergent Perceptual Haze (EPH).md** - Main EPH framework proposal
- **20251120_Saliency Polar Map (SPM).md** - SPM perceptual representation proposal

The current simulation demonstrates:
- **Scenario**: Sparse Foraging Task with 10 agents in 400×400 toroidal world (displayed as 800×800)
- **Goal**: Verify Active Inference hypothesis - gradient-only collision avoidance with self-hazing
- **Key Features**:
  - Pure gradient descent on Expected Free Energy (no repulsion forces)
  - Self-haze transitions: Isolated (red FOV) ↔ With neighbors (blue FOV)
  - Gradient visualization (red arrow shows -∇G direction)
  - Real-time plots (EFE, self-haze, gradient norm, SPM heatmaps)

## Task Tracking and Workflow

### Current Task Documentation
**IMPORTANT**: Always maintain `CURRENT_TASK.md` in the project root to track ongoing work.

**Purpose:**
- Document the current task being worked on
- Track progress and blockers
- Provide context for resuming work after interruptions
- Enable better collaboration and handoffs

**When to Update:**
1. **Starting a new task**: Document objectives, approach, and expected outcomes
2. **Making progress**: Update completed steps and next actions
3. **Encountering blockers**: Document issues and potential solutions
4. **Completing tasks**: Mark as complete and create new task entry if needed
5. **Before switching tasks**: Ensure current state is documented

**Workflow Integration:**
```
1. Read CURRENT_TASK.md to understand current work
   ↓
2. Work on the task (code, test, document)
   ↓
3. Update CURRENT_TASK.md with progress
   ↓
4. Run validation if code changed
   ./scripts/run_basic_validation.sh all
   ↓
5. Commit changes (including CURRENT_TASK.md updates)
   ↓
6. If task complete: Update CURRENT_TASK.md status to COMPLETED
```

**File Location:** `CURRENT_TASK.md` (project root)

**Template Structure:** See `CURRENT_TASK.md` for the standard template.

### Validation Workflow
**CRITICAL**: Before any Git commit, run validation tests:

```bash
./scripts/run_basic_validation.sh all
```

All tests must PASS before committing code changes. See `doc/VALIDATION_PHILOSOPHY.md` for detailed explanation.

## Development Notes

### Coordinate Systems
- **World**: Cartesian (x, y) with toroidal wrap-around
- **Agent-relative**: Polar (r, θ) where θ=0 is agent's forward direction
- **SPM**: Log-polar bins with personal_space as inner zone boundary

### Index Conventions
- **Julia**: 1-based indexing (bin 1 = first radial bin)
- **Python**: 0-based indexing
- Conversion handled in `_add_to_tensor!` via `+1` offsets

### Debugging Utilities
Several debug scripts exist in root:
- `debug_gradient.py` - Test gradient flow through EPH controller
- `debug_collision.py` - Verify collision detection
- `debug_inside_obstacle.py` - Check SPM occupancy mapping
- `visualize_spm.py` - Visualize SPM tensor structure

### Git Status Note
The codebase is actively under development. Current modified files include simulation parameters and viewer enhancements.

## Documentation

### Comprehensive Guides

**📘 [Haze Tensor Design Guidelines](doc/HAZE_TENSOR_DESIGN_GUIDELINES.md)** ⭐ **NEW**
- **Purpose**: Comprehensive design guidelines for spatial haze modulation strategies
- **Content**:
  - 7 independent experiments (44 configurations, 22,000 simulation steps)
  - Recommended strategies with tier classification (S/A/B/C)
  - Trade-off analysis (exploration efficiency ↔ control cost ↔ safety)
  - Production-ready configurations
- **Key Findings**:
  - Distance-Selective (Mid-range) + Angular (Left-Half): Best combined strategy (92.2% coverage)
  - Tangential velocity precision reduction: Safe and effective (+1.0%)
  - Radial velocity precision reduction: Unsafe and ineffective (-6.0%, +46 collisions)
  - Channel-selective haze insufficient; spatial modulation essential
- **When to Use**: Designing haze strategies for exploration, understanding trade-offs

**📚 [Documentation Index](doc/INDEX.md)**
- Central navigation hub for all project documentation
- Quick start guides, experimental results catalog
- Links to all technical notes and implementation guides

### Technical References

**Framework & Theory:**
- `doc/technical_notes/EmergentPerceptualHaze_EPH.md` - Main EPH framework proposal
- `doc/technical_notes/SaliencyPolarMap_SPM.md` - SPM perceptual representation
- `doc/EPH_Active_Inference_Derivation.md` - Mathematical derivations

**Implementation:**
- `doc/EPH_Implementation_Guide_Julia.md` - Julia-specific implementation details
- `doc/PHASE_GUIDE.md` - Development phases and milestones
- `doc/VALIDATION_PHILOSOPHY.md` - Testing methodology and validation workflow
- `doc/DIAGNOSTICS_GUIDE.md` - Troubleshooting and diagnostic tools

### Research Context

The project validates the EPH framework through systematic experiments:

**Completed Studies (2025-11):**
1. Phase 3 Full Tensor Haze: Channel weight optimization
2. Directional Haze: Symmetric angular modulation (failed)
3. Localized Haze: Specific bin modulation (Central-Mid succeeded, +3.0%)
4. Distance-Selective: Radial range modulation (Mid-5.0x best, +4.0%)
5. Asymmetric Haze: Left-Right asymmetry (Left-Half succeeded, +3.0%)
6. Combined Strategy: Distance × Angular integration (Near×Left best, +3.0%)
7. Channel-Selective: Per-channel modulation (Tangential-only safe, +1.0%)

**Performance Benchmarks:**
- Baseline (uniform haze): 89.2% coverage @500 steps
- Best spatial haze: 92.2% coverage @500 steps (+3.0%, statistically significant)
- Phase 2 environmental haze: 93.2% coverage @500 steps (reference)

All documentation follows Obsidian conventions (YAML frontmatter, WikiLinks, Mermaid diagrams) for seamless integration into research notes.
