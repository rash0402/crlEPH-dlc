# GRU Prediction Uncertainty Implementation

## Version Control

### Stable Version (Before Uncertainty)
- **Tag**: `v0.1.0-stable-before-uncertainty`
- **Date**: 2025-11-26
- **Commit**: `8b93511`

To revert to this version:
```bash
git checkout v0.1.0-stable-before-uncertainty
```

## Problem Statement

The current implementation uses a GRU predictor for SPM (Saliency Polar Map) prediction but does **not** explicitly quantify prediction uncertainty. This is problematic for Active Inference because:

1. **Expected Free Energy requires uncertainty**: G(a) should include prediction confidence
2. **Epistemic value underestimated**: Model uncertainty drives information-seeking behavior
3. **Over-confidence in novel situations**: GRU outputs deterministic predictions even in unexplored regions

### Current State (v0.1.0-stable)

**EPH.jl (lines 164-180):**
```julia
# Predict future SPM
spm_pred = SPMPredictor.predict_spm(predictor, agent, action, env, spm_params)

# Compute future entropy H[q(s_{t+1}|a)]
h_self_pred = SelfHaze.compute_self_haze(spm_pred, params)
Π_pred = SelfHaze.compute_precision_matrix(spm_pred, h_self_pred, params)
H_future = SelfHaze.compute_belief_entropy(Π_pred)

# Information Gain (spatial variance only, NOT prediction uncertainty)
I_gain = var(spm_pred[1, :, :])
```

**Issues:**
- `H_future`: Entropy from SPM spatial distribution, not prediction uncertainty
- `I_gain`: Variance within predicted SPM, not model confidence
- **Missing**: Epistemic uncertainty from GRU model

## Solution: Hybrid Uncertainty Estimation

### Approach 1: Hidden State Variance
**Theory**: GRU hidden state instability indicates prediction uncertainty

```julia
function compute_hidden_state_uncertainty(agent::Agent)::Float64
    if agent.hidden_state !== nothing
        h = agent.hidden_state
        # Variance of hidden state activations
        h_var = var(h)
        # Normalize to [0, 1] using sigmoid
        return 1.0 / (1.0 + exp(-h_var))
    else
        return 0.5  # Unknown state = moderate uncertainty
    end
end
```

**Advantages:**
- No model changes required
- Negligible computational cost
- GRU states naturally encode uncertainty

### Approach 2: Prediction Error History
**Theory**: Past prediction errors indicate current model reliability

```julia
# Added to Agent struct
mutable struct Agent
    # ... existing fields ...
    prediction_error_history::Vector{Float64}  # Recent N prediction errors
    prediction_uncertainty::Float64            # Current uncertainty estimate
end

function update_prediction_uncertainty!(agent::Agent, current_spm, predicted_spm)
    # Compute RMSE
    error = sqrt(mean((current_spm .- predicted_spm).^2))

    # Maintain sliding window (max 10 samples)
    push!(agent.prediction_error_history, error)
    if length(agent.prediction_error_history) > 10
        popfirst!(agent.prediction_error_history)
    end

    # Uncertainty = mean error + error volatility
    if length(agent.prediction_error_history) >= 3
        mean_error = mean(agent.prediction_error_history)
        std_error = std(agent.prediction_error_history)
        agent.prediction_uncertainty = mean_error + std_error
    else
        agent.prediction_uncertainty = 0.5
    end
end
```

**Advantages:**
- Reflects actual prediction performance
- No model structure changes
- Easy to interpret

### Hybrid Combination

```julia
function compute_hybrid_uncertainty(
    predictor::NeuralPredictor,
    agent::Agent,
    action::Vector{Float64},
    env::Environment,
    spm_params::SPMParams
)
    # Execute prediction
    spm_pred = predict_spm(predictor, agent, action, env, spm_params)

    # 1. Hidden state uncertainty (immediate)
    h_uncertainty = compute_hidden_state_uncertainty(agent)

    # 2. Historical uncertainty (long-term reliability)
    historical_uncertainty = agent.prediction_uncertainty

    # 3. Weighted combination
    # α = 0.3: prioritize historical stability
    α = 0.3
    total_uncertainty = α * h_uncertainty + (1 - α) * historical_uncertainty

    return spm_pred, total_uncertainty
end
```

## Integration with Expected Free Energy

### Modified EPH.jl

```julia
function expected_free_energy(action, agent, spm_tensor, env,
                               preferred_velocity, params, predictor, ...)
    # ... existing precision calculation ...

    # Predict with uncertainty
    spm_pred, pred_uncertainty = compute_hybrid_uncertainty(
        predictor, agent, action, env, spm_params
    )

    # Compute future belief entropy
    h_self_pred = SelfHaze.compute_self_haze(spm_pred, params)
    Π_pred = SelfHaze.compute_precision_matrix(spm_pred, h_self_pred, params)
    H_future = SelfHaze.compute_belief_entropy(Π_pred)

    # Adjust Information Gain with prediction uncertainty
    # High uncertainty = high information value
    I_gain_base = var(spm_pred[1, :, :])
    I_gain_adjusted = I_gain_base * (1.0 + pred_uncertainty)

    # Epistemic term: belief entropy + prediction uncertainty
    H_epistemic = H_future + params.γ_info * pred_uncertainty

    # Expected Free Energy
    G = F_percept + params.β * H_epistemic - params.γ_info * I_gain_adjusted + params.λ * M_pragmatic

    return G
end
```

### New EPHParams

```julia
Base.@kwdef mutable struct EPHParams
    # ... existing parameters ...

    # Prediction uncertainty parameters
    γ_info::Float64 = 0.5           # Information gain weight
    uncertainty_alpha::Float64 = 0.3  # Hidden state weight in hybrid
    uncertainty_window::Int = 10      # Prediction error history size
end
```

## Implementation Plan

### Phase 1: Agent Structure Extension
1. Add `prediction_error_history` and `prediction_uncertainty` to Agent struct
2. Initialize in Agent constructor
3. Update serialization if needed

### Phase 2: Uncertainty Computation
1. Implement `compute_hidden_state_uncertainty()`
2. Implement `update_prediction_uncertainty!()`
3. Implement `compute_hybrid_uncertainty()`
4. Add unit tests

### Phase 3: EPH Integration
1. Modify `expected_free_energy()` to use uncertainty
2. Adjust epistemic and information gain terms
3. Add uncertainty tracking to data collection

### Phase 4: Validation
1. Compare behavior with/without uncertainty
2. Verify exploration increases in novel regions
3. Measure prediction error correlation with uncertainty
4. Document performance impact

## Testing Strategy

### Unit Tests
```julia
@testset "Uncertainty Computation" begin
    # Test 1: Hidden state uncertainty
    agent = Agent(1, 100.0, 100.0)
    agent.hidden_state = randn(Float32, 32)
    u = compute_hidden_state_uncertainty(agent)
    @test 0.0 <= u <= 1.0

    # Test 2: Prediction error tracking
    for i in 1:15
        error = rand()
        update_prediction_uncertainty!(agent, zeros(3,6,6), ones(3,6,6))
    end
    @test length(agent.prediction_error_history) == 10
    @test agent.prediction_uncertainty > 0.0
end
```

### Integration Tests
```bash
# Run short simulation with uncertainty enabled
EPH_NON_INTERACTIVE=1 EPH_STEPS=100 ~/.juliaup/bin/julia --project=src_julia src_julia/main.jl

# Verify uncertainty values are logged
grep "prediction_uncertainty" data/logs/eph_experiment_*.jld2
```

### Behavioral Tests
- **Exploration increase**: Agents should explore more in novel regions
- **Prediction improvement**: Uncertainty should decrease with experience
- **Correlation check**: High uncertainty → high prediction error

## Rollback Procedure

If issues arise:

```bash
# 1. Check current commit
git log --oneline -1

# 2. Revert to stable version
git checkout v0.1.0-stable-before-uncertainty

# 3. Or cherry-pick specific fixes
git cherry-pick <commit-hash>

# 4. Force rebuild
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## References

### Theoretical Foundation
- **Active Inference**: Friston et al. (2017) "Active Inference: A Process Theory"
- **Epistemic Value**: Schwartenbeck et al. (2019) "Computational mechanisms of curiosity and goal-directed exploration"
- **Model Uncertainty**: Gal & Ghahramani (2016) "Dropout as a Bayesian Approximation"

### Related Work
- **Uncertainty in RL**: Pathak et al. (2017) "Curiosity-driven Exploration"
- **Prediction Error**: Rao & Ballard (1999) "Predictive coding in the visual cortex"

## Contact

For questions or issues related to this implementation:
- **Issue Tracker**: https://github.com/anthropics/claude-code/issues
- **Documentation**: See `CLAUDE.md` for general development guidelines
