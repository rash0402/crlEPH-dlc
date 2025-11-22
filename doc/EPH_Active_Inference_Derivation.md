# EPH Active Inference Formulation: Complete Mathematical Derivation

**Document Type**: Technical Derivation
**Version**: 1.0
**Date**: 2025-11-22
**Author**: Hiroshi Igarashi (with AI-DLC Navigator assistance)
**Purpose**: Rigorous mathematical foundation for EPH based on Active Inference and Expected Free Energy

---

## 0. Executive Summary

This document provides the **complete mathematical derivation** of the Emergent Perceptual Haze (EPH) framework based on Active Inference theory. We establish:

1. **Expected Free Energy** $G(a)$ as the action selection criterion
2. **Self-hazing as belief entropy modulation** (not additive noise)
3. **Analytical gradient** $\nabla_a G$ for efficient implementation

**Key Result**: When other agents are not visible, self-hazing increases belief uncertainty, which drives **information-seeking exploration** through the epistemic value term in $G(a)$.

---

## 1. Active Inference Primer

### 1.1 Core Concepts

Active Inference is a normative framework where agents act to minimize **Expected Free Energy** over future trajectories.

#### Key Variables

| Symbol | Domain | Meaning |
|:---|:---|:---|
| $s_t$ | $\mathcal{S}$ | True environmental state (hidden) |
| $o_t$ | $\mathcal{O}$ | Observation (SPM in our case) |
| $a_t$ | $\mathcal{A}$ | Action (velocity command) |
| $q(s_t)$ | $\Delta(\mathcal{S})$ | Belief distribution over states |
| $p(o_t \| s_t)$ | - | Generative likelihood model |
| $p(s_{t+1} \| s_t, a_t)$ | - | Transition dynamics |

#### Free Energy Principle (FEP)

Agents minimize **Variational Free Energy** to infer hidden states:

$$
F[q] = \mathbb{E}_{q(s)}[\log q(s) - \log p(s, o)]
$$

This decomposes into:

$$
F[q] = \underbrace{D_{KL}[q(s) \| p(s|o)]}_{\text{Inference error}} + \underbrace{(-\log p(o))}_{\text{Surprise}}
$$

Minimizing $F$ is equivalent to accurate inference (posterior approximation) and unlikely observation avoidance.

---

## 2. Expected Free Energy (EFE)

### 2.1 Definition

For **action selection**, Active Inference uses **Expected Free Energy** $G(\pi)$ for policy $\pi = (a_t, a_{t+1}, \ldots)$:

$$
G(\pi) = \mathbb{E}_{q(o_\tau, s_\tau | \pi)} \left[ \log q(s_\tau | \pi) - \log p(o_\tau, s_\tau) \right]
$$

For a **single-step action** $a_t$, this simplifies to:

$$
G(a_t) = \mathbb{E}_{q(o_{t+1}, s_{t+1} | a_t)} \left[ \log q(s_{t+1} | a_t) - \log p(o_{t+1}, s_{t+1}) \right]
$$

### 2.2 Decomposition into Epistemic and Pragmatic Values

Using Bayes rule and rearranging:

$$
G(a_t) = \underbrace{\mathbb{E}_{q(s_{t+1}|a_t)}[D_{KL}[q(o_{t+1}|s_{t+1}) \| p(o_{t+1}|s_{t+1})]]}_{\text{Epistemic Value (Information Gain)}} - \underbrace{\mathbb{E}_{q(o_{t+1}, s_{t+1}|a_t)}[\log p(o_{t+1})]}_{\text{Pragmatic Value (Goal Achievement)}}
$$

**Simplified form** (assuming deterministic observation model):

$$
\boxed{
G(a) = \underbrace{H[q(s_{t+1}|a)]}_{\text{State Uncertainty}} - \underbrace{\mathbb{E}_{q(s_{t+1}|a)}[I(o_{t+1}; s_{t+1})]}_{\text{Expected Information Gain}} + \underbrace{D_{KL}[q(o_{t+1}|a) \| p^*(o)]}_{\text{Preference Mismatch}}
}
$$

Where:
- $H[q]$: Entropy (uncertainty)
- $I(o; s)$: Mutual information (information gain)
- $p^*(o)$: Prior preferences (desired observations)

### 2.3 Intuitive Interpretation

**Minimizing $G(a)$ balances two drives:**

1. **Epistemic Drive** (Exploration):
   - Minimize uncertainty $H[q(s|a)]$
   - Maximize information gain $I(o; s)$
   - **"Reduce what you don't know"**

2. **Pragmatic Drive** (Exploitation):
   - Minimize distance to preferred observations $p^*(o)$
   - **"Achieve your goals"**

---

## 3. EPH Formulation with Expected Free Energy

### 3.1 Mapping to SPM Framework

In EPH, we map Active Inference concepts to our SPM-based architecture:

| Active Inference | EPH Implementation |
|:---|:---|
| State $s_t$ | Other agents' positions/velocities (partially observed) |
| Observation $o_t$ | Saliency Polar Map $\text{SPM}_t \in \mathbb{R}^{3 \times N_r \times N_\theta}$ |
| Belief $q(s_t)$ | Implicit belief over obstacle configurations |
| Action $a_t$ | Velocity command $\mathbf{v}_t \in \mathbb{R}^2$ |
| Generative model $p(o|s)$ | SPM forward projection function |

### 3.2 EPH Expected Free Energy

We define the EPH action selection criterion:

$$
\boxed{
a_t^* = \arg\min_{a} G(a) = \arg\min_a \left[ \underbrace{F_{\text{percept}}(a, \mathcal{H}_t)}_{\text{Epistemic Term}} + \underbrace{\lambda \cdot M_{\text{meta}}(a)}_{\text{Pragmatic Term}} \right]
}
$$

Where:

#### Term 1: Epistemic Term (Surprise + Uncertainty)

$$
F_{\text{percept}}(a, \mathcal{H}) = \mathbb{E}_{q(s|o,a)}\left[ \| o_{\text{pred}}(s, a) - o_{\text{expected}} \|^2_{\Pi(\mathcal{H})} \right] + \beta \cdot H[q(s|o,a)]
$$

- $o_{\text{pred}}(s, a)$: Predicted SPM after taking action $a$
- $o_{\text{expected}}$: Expected SPM under current belief
- $\Pi(\mathcal{H})$: **Haze-modulated precision matrix**
- $H[q(s|o,a)]$: **Belief entropy** (epistemic uncertainty)

#### Term 2: Pragmatic Term (Goal Achievement / Collision Avoidance)

$$
M_{\text{meta}}(a) = \mathbb{E}_{q(s|a)}\left[ C_{\text{collision}}(s) + C_{\text{goal}}(s) \right]
$$

- $C_{\text{collision}}$: Cost of being close to obstacles
- $C_{\text{goal}}$: Cost of deviating from goal

---

## 4. Self-Hazing as Belief Entropy Modulation

### 4.1 The Key Insight

**Traditional View** (WRONG):
> "Self-hazing adds noise to observations: $o_{\text{noisy}} = o + \epsilon$"

**Active Inference View** (CORRECT):
> "Self-hazing increases the **belief entropy** $H[q(s)]$, reflecting epistemic uncertainty"

### 4.2 Mathematical Formulation

Define the **belief distribution** over hidden states (other agents' configurations):

$$
q(s | o, \mathcal{H}) = \frac{1}{Z} \exp\left( -\frac{1}{2} \| o - g(s) \|^2_{\Pi(\mathcal{H})} \right)
$$

Where:
- $g(s)$: Generative model (map states to SPM)
- $\Pi(\mathcal{H})$: Precision matrix modulated by haze

**Precision Matrix Modulation**:

$$
\Pi(r, \theta, c; \mathcal{H}) = \Pi_{\text{base}}(r, \theta, c) \cdot \underbrace{(1 - h(r, \theta, c))^\gamma}_{\text{Haze attenuation}}
$$

Where $h \in [0, 1]$ is the haze level, $\gamma \geq 1$ controls sensitivity.

### 4.3 Entropy Derivation

For Gaussian belief $q(s) = \mathcal{N}(s | \mu, \Sigma)$, the entropy is:

$$
H[q(s)] = \frac{1}{2} \log \det(2\pi e \Sigma)
$$

The covariance is related to precision via:

$$
\Sigma^{-1} = J^T \Pi J
$$

Where $J = \frac{\partial g(s)}{\partial s}$ is the Jacobian of the generative model.

**Key Result**:

$$
\boxed{
H[q(s|\mathcal{H})] = \frac{1}{2} \log \det(2\pi e (J^T \Pi(\mathcal{H}) J)^{-1})
}
$$

**When haze increases** ($h \to 1$):
- Precision decreases: $\Pi \to 0$
- Covariance increases: $\Sigma \to \infty$
- **Entropy increases**: $H[q] \to \infty$

**Physical Meaning**:
> "I can't see clearly (high haze) → I'm uncertain about where obstacles are (high entropy) → I should explore to reduce uncertainty"

---

## 5. Gradient Derivation: $\nabla_a G(a)$

### 5.1 Gradient of Epistemic Term

From Section 3.2, the epistemic term is:

$$
F_{\text{percept}}(a, \mathcal{H}) = \underbrace{\| o_{\text{pred}}(a) - o_{\text{expected}} \|^2_{\Pi(\mathcal{H})}}_{\text{Prediction Error}} + \beta \cdot H[q(s|a)]
$$

#### Part A: Prediction Error Gradient

$$
\frac{\partial}{\partial a} \| o_{\text{pred}}(a) - o_{\text{expected}} \|^2_{\Pi} = 2 (o_{\text{pred}} - o_{\text{expected}})^T \Pi \frac{\partial o_{\text{pred}}}{\partial a}
$$

Where $\frac{\partial o_{\text{pred}}}{\partial a}$ is computed via **automatic differentiation** (Zygote.jl).

For SPM, this involves:

$$
\frac{\partial \text{SPM}_{\text{pred}}}{\partial a} = \frac{\partial \text{SPM}_{\text{pred}}}{\partial x_{\text{rel}}} \cdot \frac{\partial x_{\text{rel}}}{\partial a}
$$

Where $x_{\text{rel}}$ is the relative position after taking action $a$.

#### Part B: Entropy Gradient

From the entropy formula:

$$
H[q] = -\frac{1}{2} \log \det(\Pi(\mathcal{H}))
$$

(Assuming $\mathcal{H}$ is action-dependent for self-hazing)

$$
\frac{\partial H}{\partial a} = -\frac{1}{2} \text{tr}\left( \Pi^{-1} \frac{\partial \Pi}{\partial a} \right)
$$

**For self-hazing** (haze depends on agent state):

$$
\frac{\partial \Pi}{\partial a} = \Pi_{\text{base}} \cdot \gamma (1-h)^{\gamma-1} \cdot \left(-\frac{\partial h}{\partial a}\right)
$$

Where $\frac{\partial h}{\partial a}$ depends on the self-hazing policy.

### 5.2 Gradient of Pragmatic Term

For collision avoidance:

$$
M_{\text{collision}}(a) = \sum_{r,\theta} w(r) \cdot \text{SPM}_{\text{pred}}[1, r, \theta; a]
$$

Where channel 1 is occupancy, $w(r)$ weights closer bins higher.

$$
\frac{\partial M_{\text{collision}}}{\partial a} = \sum_{r,\theta} w(r) \cdot \frac{\partial \text{SPM}_{\text{pred}}[1, r, \theta]}{\partial a}
$$

Again, computed via automatic differentiation.

### 5.3 Complete Gradient

$$
\boxed{
\nabla_a G(a) = 2 (o_{\text{pred}} - o_{\text{expected}})^T \Pi \frac{\partial o_{\text{pred}}}{\partial a} - \frac{\beta}{2} \text{tr}\left( \Pi^{-1} \frac{\partial \Pi}{\partial a} \right) + \lambda \nabla_a M_{\text{meta}}
}
$$

### 5.4 Gradient Descent Update

Action is updated via:

$$
a_{k+1} = a_k - \eta \nabla_a G(a_k)
$$

Where $\eta$ is the learning rate (step size).

---

## 6. Self-Hazing Policy: Continuous Entropy Modulation

### 6.1 Motivation

**Goal**: When no other agents are visible, increase belief entropy to drive exploration.

**Mechanism**: Adjust haze level $h$ based on the **information content** in the SPM.

### 6.2 Information-Based Haze Adjustment

Define the **total occupancy** in the SPM:

$$
\Omega(o_t) = \sum_{r,\theta} o_t[1, r, \theta]
$$

This measures "how much is visible."

**Self-haze function** (continuous, differentiable):

$$
\boxed{
h_{\text{self}}(t) = h_{\max} \cdot \sigma\left( -\alpha (\Omega(o_t) - \Omega_{\text{threshold}}) \right)
}
$$

Where:
- $\sigma(x) = \frac{1}{1 + e^{-x}}$: Sigmoid function
- $h_{\max}$: Maximum haze level
- $\alpha$: Sensitivity parameter
- $\Omega_{\text{threshold}}$: Occupancy threshold

**Behavior**:
- $\Omega \ll \Omega_{\text{threshold}}$ (few obstacles visible) → $h \to h_{\max}$ (high haze, high entropy)
- $\Omega \gg \Omega_{\text{threshold}}$ (many obstacles) → $h \to 0$ (low haze, low entropy)

### 6.3 Belief Entropy Dynamics

Combining the haze level with precision modulation:

$$
\Pi(r, \theta; h_{\text{self}}) = \Pi_{\text{base}}(r, \theta) \cdot (1 - h_{\text{self}}(t))^\gamma
$$

As $h_{\text{self}} \to 1$:

$$
\Pi \to 0 \implies \Sigma \to \infty \implies H[q(s)] \to \infty
$$

**Result**: Agent's belief becomes maximally uncertain → Epistemic value drives **information-seeking actions**.

---

## 7. Exploration Mechanism: From Entropy to Action

### 7.1 The Causal Chain

```
No visible agents
    ↓
Low occupancy Ω(o_t) < Ω_threshold
    ↓
Self-haze increases: h_self → h_max
    ↓
Precision decreases: Π → 0
    ↓
Belief entropy increases: H[q(s)] → ∞
    ↓
Epistemic term in G(a) increases
    ↓
Gradient ∇_a G points toward information-rich actions
    ↓
Agent moves to reduce uncertainty (exploration)
```

### 7.2 Mathematical Proof of Exploration Drive

**Claim**: High entropy $H[q]$ drives actions that maximize expected information gain.

**Proof Sketch**:

1. Expected Free Energy decomposes as:
   $$
   G(a) \approx H[q(s|a)] - I(o_{t+1}; s_{t+1}|a) + \text{pragmatic terms}
   $$

2. When $H[q]$ is high (due to self-haze), the agent seeks actions that:
   - Minimize future entropy: $H[q(s|a)] \to 0$
   - Maximize information gain: $I(o; s|a) \to \max$

3. **Information gain is maximized** by moving toward **uncertain regions** where observations will reduce belief entropy.

4. In practice, this manifests as:
   - Moving away from walls (boring, low information)
   - Moving toward open space (where other agents might appear)
   - Changing heading to scan different areas

**Conclusion**: Self-haze-driven entropy increase **naturally generates exploration behavior** without explicit random walk.

---

## 8. Comparison with Random Walk

### 8.1 Random Walk (Baseline)

**Mechanism**:
$$
a_t = a_{\text{nominal}} + \epsilon, \quad \epsilon \sim \mathcal{N}(0, \sigma^2 I)
$$

**Properties**:
- ❌ No information gain objective
- ❌ Uniform exploration (no bias toward uncertain regions)
- ❌ No adaptation to environment state

### 8.2 EPH Self-Hazing (Proposed)

**Mechanism**:
$$
a_t^* = \arg\min_a G(a; h_{\text{self}}(t))
$$

**Properties**:
- ✅ Information-seeking exploration (epistemic value)
- ✅ Adaptive: $h_{\text{self}}$ adjusts to visibility
- ✅ Proactive collision avoidance via prediction
- ✅ Theoretical grounding in Active Inference

### 8.3 Expected Performance Differences

| Metric | Random Walk | EPH Self-Haze |
|:---|:---|:---|
| Coverage Efficiency | Low (random) | High (information-driven) |
| Collision Rate | High (reactive) | Low (predictive) |
| Exploration Bias | None (uniform) | Information-rich regions |
| Theoretical Guarantee | None | Free Energy minimization |

---

## 9. Implementation Guide

### 9.1 Core Algorithm (Pseudocode)

```julia
function eph_action_selection(agent, spm_current, params)
    # Step 1: Compute self-haze level
    Ω = sum(spm_current[1, :, :])  # Total occupancy
    h_self = params.h_max * sigmoid(-params.α * (Ω - params.Ω_threshold))

    # Step 2: Compute precision matrix
    Π = compute_precision(spm_current, h_self, params)

    # Step 3: Predict SPM for candidate actions
    actions_candidate = generate_action_samples(agent, params)
    G_values = []

    for a in actions_candidate
        # Forward prediction
        spm_pred = predict_spm(agent, a, spm_current, params)

        # Epistemic term (prediction error + entropy)
        F_percept = prediction_error(spm_pred, spm_current, Π) +
                    params.β * belief_entropy(Π)

        # Pragmatic term (collision avoidance)
        M_collision = collision_cost(spm_pred, params)

        # Expected Free Energy
        G = F_percept + params.λ * M_collision
        push!(G_values, G)
    end

    # Step 4: Select action minimizing G
    a_star = actions_candidate[argmin(G_values)]

    return a_star
end
```

### 9.2 Gradient-Based Optimization (Efficient)

For continuous action spaces, use gradient descent:

```julia
function eph_gradient_descent(agent, spm_current, params)
    # Initialize action
    a = agent.velocity  # Current velocity as initial guess

    # Step 1: Compute self-haze
    h_self = compute_self_haze(spm_current, params)
    Π = compute_precision(spm_current, h_self, params)

    # Step 2: Gradient descent loop
    for iter in 1:params.max_iter
        # Forward pass with Zygote tracking
        G, grad = Zygote.gradient(a -> expected_free_energy(a, spm_current, Π, params), a)

        # Update action
        a = a - params.η * grad

        # Project to feasible set (e.g., max speed)
        a = project_action(a, params)
    end

    return a
end

function expected_free_energy(a, spm_current, Π, params)
    # Predict SPM
    spm_pred = predict_spm_differentiable(agent, a, spm_current)

    # Prediction error (weighted by precision)
    err = spm_pred - spm_current
    F_percept = sum(err .* Π .* err)  # Weighted squared error

    # Entropy term (simplified: -log det Π)
    H = -params.β * sum(log.(diag(Π) .+ 1e-8))

    # Collision cost
    M_collision = sum(params.w_collision .* spm_pred[1, :, :])

    # Total EFE
    return F_percept + H + params.λ * M_collision
end
```

### 9.3 Key Implementation Details

#### Precision Matrix Computation

```julia
function compute_precision(spm, h_self, params)
    Nr, Nθ = size(spm)[2:3]
    Π = zeros(Nr, Nθ)

    for r in 1:Nr, θ in 1:Nθ
        # Base precision (distance-dependent)
        Π_base = params.Π_max * exp(-params.decay_rate * r)

        # Haze modulation
        Π[r, θ] = Π_base * (1 - h_self)^params.γ
    end

    return Π
end
```

#### Belief Entropy (Simplified)

For implementation efficiency, approximate entropy as:

```julia
function belief_entropy(Π)
    # H ∝ -log det Π ≈ -sum(log(Π_ii))
    return -sum(log.(diag(Π) .+ 1e-8))
end
```

---

## 10. Theoretical Guarantees

### 10.1 Convergence of Gradient Descent

**Theorem 1** (Convergence to Local Minimum):

Under the following assumptions:
1. $G(a)$ is twice continuously differentiable
2. Learning rate $\eta < \frac{2}{\lambda_{\max}(\nabla^2 G)}$
3. Initial action $a_0$ is feasible

The gradient descent sequence $a_{k+1} = a_k - \eta \nabla G(a_k)$ converges to a local minimum $a^*$ such that $\nabla G(a^*) = 0$.

**Proof**: Standard result from convex optimization. See [Boyd & Vandenberghe, 2004].

### 10.2 Exploration Efficiency

**Theorem 2** (Information-Seeking Property):

For self-haze policy $h_{\text{self}}(\Omega)$ as defined in Section 6.2, when $\Omega < \Omega_{\text{threshold}}$:

$$
\arg\min_a G(a) \approx \arg\max_a I(o_{t+1}; s_{t+1} | a)
$$

**Proof Sketch**:
1. When $h_{\text{self}} \to h_{\max}$, precision $\Pi \to 0$
2. Prediction error term becomes negligible: $\| o_{\text{pred}} - o \|^2_\Pi \to 0$
3. Entropy term dominates: $H[q(s|a)]$ drives action selection
4. Minimizing $H[q(s|a)]$ is equivalent to maximizing expected information gain $I(o; s|a)$

---

## 11. Experimental Validation Plan

### 11.1 Phase 1: Single Agent Exploration

**Objective**: Verify that self-haze drives exploration in absence of other agents.

**Setup**:
- 1 agent in empty toroidal space (800×600)
- No environmental haze
- Self-haze enabled

**Metrics**:
- Coverage rate: $C(t) = |\{(x,y) : \text{visited at } t' \leq t\}| / |\text{total cells}|$
- Trajectory entropy: $H[\mathbf{p}_{\text{position}}]$
- Diffusion coefficient: $D = \lim_{t \to \infty} \langle r^2(t) \rangle / (4t)$

**Expected Result**:
- EPH explores more efficiently than random walk: $C_{\text{EPH}}(T) > C_{\text{RW}}(T)$
- EPH has directed exploration: $D_{\text{EPH}} > D_{\text{RW}}$ but with structured pattern

### 11.2 Phase 2: Multi-Agent Collision Avoidance

**Objective**: Compare EPH with baselines on collision avoidance.

**Conditions**:
- Random Walk, Potential Field, EPH (3 conditions)
- Agent density: [4, 8, 12] (3 levels)
- 30 trials per condition

**Metrics**:
- Collision rate: $N_{\text{collision}} / T$
- Time-to-collision (TTC) distribution
- Average minimum distance to others

**Hypothesis**: EPH achieves lower collision rate due to predictive (proactive) avoidance.

### 11.3 Phase 3: Parameter Sensitivity

**Factors**:
- $\alpha$ (sigmoid steepness): [0.1, 0.5, 1.0, 2.0]
- $\Omega_{\text{threshold}}$: [0.5, 1.0, 2.0, 5.0]
- $\beta$ (entropy weight): [0.0, 0.1, 0.5, 1.0]

**Analysis**: ANOVA to identify optimal parameter set.

---

## 12. Conclusion

We have provided a **rigorous mathematical foundation** for EPH based on Active Inference:

### Key Contributions

1. **Expected Free Energy Formulation**
   - $G(a) = F_{\text{percept}}(a, \mathcal{H}) + \lambda M_{\text{meta}}(a)$
   - Epistemic (exploration) + Pragmatic (goal achievement) balance

2. **Self-Hazing as Entropy Modulation**
   - Not additive noise, but precision matrix modulation
   - $h_{\text{self}}(\Omega) \to \Pi(\mathcal{H}) \to H[q(s)]$

3. **Analytical Gradient**
   - $\nabla_a G(a)$ derived for efficient optimization
   - Implementable via automatic differentiation (Zygote.jl)

4. **Exploration Mechanism**
   - High entropy → information-seeking actions
   - Theoretically grounded (Active Inference)
   - Distinct from random walk

### Next Steps

1. Implement in Julia (`src_julia/control/EPH.jl`)
2. Run Phase 1 experiments (single agent exploration)
3. Validate theoretical predictions empirically
4. Extend to multi-agent scenarios with environmental haze

---

## References

1. Friston, K., et al. (2015). "Active inference and epistemic value." *Cognitive Neuroscience*, 6(4), 187-214.
2. Parr, T., Pezzulo, G., & Friston, K. J. (2022). *Active Inference: The Free Energy Principle in Mind, Brain, and Behavior*. MIT Press.
3. Friston, K., et al. (2017). "Active inference: a process theory." *Neural Computation*, 29(1), 1-49.
4. Millidge, B., Tschantz, A., & Buckley, C. L. (2021). "Whence the expected free energy?" *Neural Computation*, 33(2), 447-482.
5. Da Costa, L., et al. (2020). "Active inference on discrete state-spaces: A synthesis." *Journal of Mathematical Psychology*, 99, 102447.

**End of Document**
