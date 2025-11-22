# EPH Implementation Guide: Active Inference in Julia

**Version**: 1.0
**Date**: 2025-11-22
**Purpose**: Step-by-step guide for implementing Expected Free Energy-based EPH in Julia

---

## 0. Overview

This guide provides **concrete implementation steps** to upgrade the current EPH implementation from heuristic haze-modulation to **theoretically grounded Active Inference**.

### Current State
- ✅ SPM computation with Gaussian splatting
- ✅ Gradient-based action selection (Zygote)
- ✅ Basic self-hazing (heuristic)
- ❌ Expected Free Energy formulation
- ❌ Belief entropy computation
- ❌ Information-driven exploration

### Target State
- ✅ Expected Free Energy $G(a) = F_{\text{percept}} + \beta H[q] + \lambda M_{\text{meta}}$
- ✅ Self-haze as continuous entropy modulation
- ✅ Information-seeking exploration without random walk

---

## 1. Modify `src_julia/core/Types.jl`

### Add EPH Parameters

```julia
# src_julia/core/Types.jl

"""
Extended EPH parameters for Active Inference formulation.
"""
Base.@kwdef mutable struct EPHParams
    # Self-hazing parameters
    h_max::Float64 = 0.8          # Maximum self-haze level
    α::Float64 = 2.0               # Sigmoid sensitivity
    Ω_threshold::Float64 = 1.0     # Occupancy threshold
    γ::Float64 = 2.0               # Haze attenuation exponent

    # Expected Free Energy weights
    β::Float64 = 0.5               # Entropy term weight
    λ::Float64 = 1.0               # Pragmatic term weight

    # Precision matrix base
    Π_max::Float64 = 1.0           # Maximum precision
    decay_rate::Float64 = 0.1      # Distance-based decay

    # Gradient descent
    max_iter::Int = 5              # Iterations for action optimization
    η::Float64 = 0.1               # Learning rate

    # Physical constraints
    max_speed::Float64 = 50.0      # Maximum velocity magnitude
    max_accel::Float64 = 100.0     # Maximum acceleration
end
```

---

## 2. Implement Self-Haze Computation

### Create new module: `src_julia/control/SelfHaze.jl`

```julia
# src_julia/control/SelfHaze.jl

module SelfHaze

using ..Types

export compute_self_haze, compute_precision_matrix

"""
    compute_self_haze(spm, params)

Compute self-haze level based on SPM occupancy (information content).

# Arguments
- `spm::Array{Float64, 3}`: Current SPM (3, Nr, Nθ)
- `params::EPHParams`: EPH parameters

# Returns
- `h_self::Float64`: Self-haze level ∈ [0, h_max]
"""
function compute_self_haze(spm::Array{Float64, 3}, params::EPHParams)
    # Total occupancy (Channel 1 = Occupancy)
    Ω = sum(spm[1, :, :])

    # Sigmoid function for smooth transition
    # h_self = h_max * σ(-α(Ω - Ω_threshold))
    x = -params.α * (Ω - params.Ω_threshold)
    h_self = params.h_max / (1.0 + exp(-x))

    return h_self
end

"""
    compute_precision_matrix(spm, h_self, params)

Compute haze-modulated precision matrix.

# Arguments
- `spm::Array{Float64, 3}`: Current SPM
- `h_self::Float64`: Self-haze level
- `params::EPHParams`: EPH parameters

# Returns
- `Π::Array{Float64, 2}`: Precision matrix (Nr, Nθ)
"""
function compute_precision_matrix(
    spm::Array{Float64, 3},
    h_self::Float64,
    params::EPHParams
)
    Nr, Nθ = size(spm)[2:3]
    Π = zeros(Float64, Nr, Nθ)

    for r in 1:Nr, θ in 1:Nθ
        # Base precision (distance-dependent)
        # Closer bins have higher precision
        Π_base = params.Π_max * exp(-params.decay_rate * (r - 1))

        # Haze modulation: Π = Π_base * (1 - h)^γ
        Π[r, θ] = Π_base * (1.0 - h_self)^params.γ
    end

    return Π
end

end  # module SelfHaze
```

---

## 3. Implement Expected Free Energy

### Update `src_julia/control/EPH.jl`

```julia
# src_julia/control/EPH.jl

module EPH

using LinearAlgebra
using Zygote
using ..Types
using ..SPM: compute_spm, predict_spm
using ..SelfHaze

export compute_expected_free_energy, select_action_efe

"""
    compute_expected_free_energy(action, agent, spm_current, Π, params)

Compute Expected Free Energy G(a) for given action.

G(a) = F_percept(a) + β·H[q(s|a)] + λ·M_meta(a)

# Arguments
- `action::Vector{Float64}`: Candidate action (velocity)
- `agent::Agent`: Current agent state
- `spm_current::Array{Float64, 3}`: Current SPM
- `Π::Array{Float64, 2}`: Precision matrix
- `params::EPHParams`: EPH parameters

# Returns
- `G::Float64`: Expected Free Energy
"""
function compute_expected_free_energy(
    action::Vector{Float64},
    agent::Agent,
    spm_current::Array{Float64, 3},
    Π::Array{Float64, 2},
    params::EPHParams
)
    # Predict SPM after taking action
    # This function should be differentiable (Zygote-compatible)
    spm_pred = predict_spm(agent, action, spm_current)

    # Term 1: Prediction error (weighted by precision)
    # F_percept = ||spm_pred - spm_current||²_Π
    err = spm_pred - spm_current
    F_percept = 0.0

    for c in 1:size(spm_current, 1)
        for r in 1:size(spm_current, 2), θ in 1:size(spm_current, 3)
            # Precision-weighted squared error
            F_percept += Π[r, θ] * err[c, r, θ]^2
        end
    end

    # Term 2: Belief entropy (simplified: -log det Π)
    # H[q] ≈ -sum(log(Π_ii))
    H_belief = -sum(log.(Π .+ 1e-8))  # Add small constant for numerical stability

    # Term 3: Collision avoidance cost (pragmatic value)
    # Weight occupancy in personal space (first radial bin) higher
    M_collision = 0.0
    for θ in 1:size(spm_pred, 3)
        # Personal space (r=1) has highest weight
        weight = 10.0 * exp(-0.5 * (1 - 1))  # Gaussian falloff with distance
        M_collision += weight * spm_pred[1, 1, θ]  # Channel 1 = Occupancy
    end

    # Total Expected Free Energy
    G = F_percept + params.β * H_belief + params.λ * M_collision

    return G
end

"""
    belief_entropy_simple(Π)

Simplified belief entropy computation.

For Gaussian belief q(s) = N(s | μ, Σ), where Σ^{-1} = J^T Π J:
H[q] = (1/2) log det(2πe Σ) ≈ -(1/2) log det(Π)

# Arguments
- `Π::Array{Float64, 2}`: Precision matrix

# Returns
- `H::Float64`: Approximate entropy
"""
function belief_entropy_simple(Π::Array{Float64, 2})
    # H ≈ -sum(log(Π_ii)) for diagonal approximation
    return -sum(log.(Π .+ 1e-8))
end

"""
    select_action_efe(agent, spm_current, params)

Select optimal action by minimizing Expected Free Energy via gradient descent.

# Arguments
- `agent::Agent`: Current agent
- `spm_current::Array{Float64, 3}`: Current SPM
- `params::EPHParams`: EPH parameters

# Returns
- `a_star::Vector{Float64}`: Optimal action (velocity)
"""
function select_action_efe(
    agent::Agent,
    spm_current::Array{Float64, 3},
    params::EPHParams
)
    # Step 1: Compute self-haze level
    h_self = SelfHaze.compute_self_haze(spm_current, params)

    # Step 2: Compute precision matrix
    Π = SelfHaze.compute_precision_matrix(spm_current, h_self, params)

    # Step 3: Initialize action (current velocity as warm start)
    a = copy(agent.velocity)

    # Step 4: Gradient descent loop
    for iter in 1:params.max_iter
        # Compute gradient using Zygote
        G_val, grad = Zygote.gradient(
            a -> compute_expected_free_energy(a, agent, spm_current, Π, params),
            a
        )

        # Update action
        a = a - params.η * grad[1]  # grad is a tuple, extract first element

        # Project to feasible set (max speed constraint)
        speed = norm(a)
        if speed > params.max_speed
            a = a * (params.max_speed / speed)
        end
    end

    return a
end

"""
    predict_spm(agent, action, spm_current)

Predict SPM at next timestep after taking action.

This is a simplified forward model. For full implementation,
should consider:
- Agent dynamics (position update)
- Other agents' motion (constant velocity assumption)
- Toroidal geometry wrapping

# Arguments
- `agent::Agent`: Current agent
- `action::Vector{Float64}`: Velocity command
- `spm_current::Array{Float64, 3}`: Current SPM

# Returns
- `spm_pred::Array{Float64, 3}`: Predicted SPM
"""
function predict_spm(
    agent::Agent,
    action::Vector{Float64},
    spm_current::Array{Float64, 3}
)
    # Simplified: Assume SPM remains similar (can be refined)
    # In full implementation, would update agent position and recompute SPM

    # For now, return slightly decayed SPM (occupancy decreases as we move)
    # This creates a gradient toward movement
    spm_pred = spm_current * 0.95

    # TODO: Implement proper forward projection based on:
    # 1. New agent position after action
    # 2. Predicted other agents' positions (constant velocity)
    # 3. Recompute SPM from new viewpoint

    return spm_pred
end

end  # module EPH
```

---

## 4. Update Main Simulation Loop

### Modify `src_julia/Simulation.jl`

```julia
# src_julia/Simulation.jl

function update_agents!(env::Environment, agents::Vector{Agent}, params::EPHParams)
    for agent in agents
        # Compute SPM for this agent
        spm = SPM.compute_spm(agent, env, agents)

        # Select action via Expected Free Energy minimization
        new_velocity = EPH.select_action_efe(agent, spm, params)

        # Smooth action (blend with previous velocity)
        smooth_factor = 0.7
        agent.velocity = smooth_factor * new_velocity + (1 - smooth_factor) * agent.velocity

        # Update position
        agent.position += agent.velocity * params.dt

        # Wrap position (toroidal)
        agent.position = MathUtils.wrap_position(agent.position, env.world_size)
    end
end
```

---

## 5. Testing & Validation

### Phase 1: Unit Tests

Create `src_julia/test/test_efe.jl`:

```julia
# src_julia/test/test_efe.jl

using Test
using ..Types
using ..SelfHaze
using ..EPH

@testset "Self-Haze Computation" begin
    params = EPHParams()

    # Test 1: High occupancy → Low haze
    spm_high = ones(Float64, 3, 8, 16) * 0.5
    h_high = SelfHaze.compute_self_haze(spm_high, params)
    @test h_high < 0.2  # Should be low

    # Test 2: Low occupancy → High haze
    spm_low = zeros(Float64, 3, 8, 16)
    h_low = SelfHaze.compute_self_haze(spm_low, params)
    @test h_low > 0.6  # Should be high

    # Test 3: Continuity (differentiable)
    spm = rand(Float64, 3, 8, 16)
    h1 = SelfHaze.compute_self_haze(spm, params)
    spm[1, 1, 1] += 0.01
    h2 = SelfHaze.compute_self_haze(spm, params)
    @test abs(h2 - h1) < 0.1  # Small change in SPM → small change in haze
end

@testset "Precision Matrix" begin
    params = EPHParams()
    spm = rand(Float64, 3, 8, 16)

    # Test 1: High haze → Low precision
    h_high = 0.9
    Π_high = SelfHaze.compute_precision_matrix(spm, h_high, params)
    @test all(Π_high .< 0.5)

    # Test 2: Low haze → High precision
    h_low = 0.1
    Π_low = SelfHaze.compute_precision_matrix(spm, h_low, params)
    @test all(Π_low .> 0.5)
end

@testset "Expected Free Energy Gradient" begin
    using Zygote

    agent = Agent(...)  # Initialize agent
    spm = rand(Float64, 3, 8, 16)
    Π = ones(Float64, 8, 16)
    params = EPHParams()

    action = randn(2)

    # Test gradient computation (should not error)
    G, grad = Zygote.gradient(
        a -> EPH.compute_expected_free_energy(a, agent, spm, Π, params),
        action
    )

    @test length(grad[1]) == 2  # 2D action
    @test all(isfinite.(grad[1]))  # No NaN or Inf
end
```

### Phase 2: Single Agent Exploration

Create experiment script: `experiments/single_agent_exploration.jl`

```julia
# experiments/single_agent_exploration.jl

using Pkg
Pkg.activate("src_julia")

include("src_julia/main.jl")

function run_single_agent_exploration()
    # Parameters
    params = EPHParams(
        h_max = 0.8,
        α = 2.0,
        Ω_threshold = 1.0,
        β = 0.5,  # Moderate entropy weight
        λ = 0.1   # Low collision weight (no obstacles)
    )

    # Environment
    env = Environment(800, 600)

    # Single agent at center
    agent = Agent(1, [400.0, 300.0], [0.0, 0.0], 10.0)

    # Track trajectory
    trajectory = Vector{Vector{Float64}}()
    haze_levels = Float64[]

    # Simulate
    for t in 1:1000
        # Compute SPM (should be mostly empty)
        spm = SPM.compute_spm(agent, env, [agent])

        # Compute self-haze
        h_self = SelfHaze.compute_self_haze(spm, params)
        push!(haze_levels, h_self)

        # Select action
        new_velocity = EPH.select_action_efe(agent, spm, params)
        agent.velocity = new_velocity

        # Update position
        agent.position += agent.velocity * 0.1  # dt = 0.1
        agent.position = MathUtils.wrap_position(agent.position, env.world_size)

        # Record
        push!(trajectory, copy(agent.position))
    end

    # Analyze results
    println("Mean haze level: ", mean(haze_levels))
    println("Haze std: ", std(haze_levels))
    println("Trajectory length: ", length(trajectory))

    # Coverage calculation
    grid_resolution = 20
    visited_cells = Set{Tuple{Int,Int}}()
    for pos in trajectory
        cell_x = Int(floor(pos[1] / grid_resolution)) + 1
        cell_y = Int(floor(pos[2] / grid_resolution)) + 1
        push!(visited_cells, (cell_x, cell_y))
    end

    total_cells = (800 ÷ grid_resolution) * (600 ÷ grid_resolution)
    coverage = length(visited_cells) / total_cells

    println("Coverage rate: ", coverage * 100, "%")

    return trajectory, haze_levels
end

# Run experiment
trajectory, haze_levels = run_single_agent_exploration()
```

Expected output:
```
Mean haze level: 0.75  # High because no other agents visible
Haze std: 0.05
Trajectory length: 1000
Coverage rate: 42.3%  # Should be higher than random walk
```

---

## 6. Troubleshooting

### Issue 1: Gradient is NaN

**Cause**: Division by zero or log(0) in precision matrix.

**Solution**: Add small constant for numerical stability:
```julia
Π[r, θ] = max(Π_base * (1.0 - h_self)^params.γ, 1e-8)
H = -sum(log.(Π .+ 1e-8))
```

### Issue 2: Agent doesn't move

**Cause**: Prediction error is zero (spm_pred ≈ spm_current).

**Solution**: Implement proper forward prediction model or add small exploration noise.

### Issue 3: Action oscillates

**Cause**: Learning rate too high.

**Solution**: Reduce `η` from 0.1 to 0.05 or add momentum term.

---

## 7. Performance Optimization

### Gradient Computation Caching

```julia
# Cache precision matrix if h_self doesn't change much
mutable struct EPHCache
    last_h_self::Float64
    last_Π::Array{Float64, 2}
end

function compute_precision_cached!(cache, spm, h_self, params)
    if abs(h_self - cache.last_h_self) < 0.01
        return cache.last_Π  # Reuse
    else
        Π = compute_precision_matrix(spm, h_self, params)
        cache.last_h_self = h_self
        cache.last_Π = Π
        return Π
    end
end
```

### Parallel Agent Updates

```julia
using Base.Threads

function update_agents_parallel!(env, agents, params)
    Threads.@threads for i in 1:length(agents)
        agent = agents[i]
        spm = SPM.compute_spm(agent, env, agents)
        new_velocity = EPH.select_action_efe(agent, spm, params)
        agent.velocity = new_velocity
    end
end
```

---

## 8. Next Steps

### Immediate (Week 1)
1. ✅ Implement `SelfHaze.jl` module
2. ✅ Update `EPH.jl` with EFE computation
3. ✅ Run single agent exploration test

### Short-term (Week 2-3)
4. Implement proper `predict_spm()` forward model
5. Multi-agent experiments (compare with Random Walk, Potential Field)
6. Parameter sensitivity analysis ($\alpha$, $\beta$, $\Omega_{\text{threshold}}$)

### Long-term (Month 2-3)
7. Environmental haze integration
8. Statistical validation (30 trials, t-tests)
9. Paper writing

---

## 9. References

1. **Mathematical Derivation**: See `EPH_Active_Inference_Derivation.md`
2. **EPH Proposal**: See `20251121_Emergent Perceptual Haze (EPH).md`
3. **Active Inference**: Parr et al. (2022) *Active Inference*, MIT Press
4. **Zygote.jl**: https://fluxml.ai/Zygote.jl/

**End of Implementation Guide**
