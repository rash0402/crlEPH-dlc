# Agent Dynamics Formulation for EPH v7.0

## Your Concern

> "θ,ω がよくわかりません。入力司令 u を2次元ベクトルで指定するイメージでしたが，実際にはheading をどうするか悩んでいました。"

**Key Question**: How should we model agent dynamics to maintain EPH's discrete candidate evaluation while achieving realistic 2nd-order behavior?

---

## Three Candidate Approaches

### **Option A: Unicycle Model (Current Formulation)**

#### State Space
```
s = [x, y, vx, vy, θ, ω] ∈ ℝ⁶
```
- `(x, y)`: Position
- `(vx, vy)`: Velocity components
- `θ`: Heading angle (independent control variable)
- `ω`: Angular velocity

#### Control Input
```
u = [F, τ] ∈ ℝ²
```
- `F`: Forward force magnitude (in heading direction θ)
- `τ`: Torque (controls heading rotation)

#### Dynamics Equations
```python
# Translational dynamics
m·dvx/dt = F·cos(θ) - cd·|v|·vx
m·dvy/dt = F·sin(θ) - cd·|v|·vy

# Rotational dynamics
I·dω/dt = τ - cr·ω
dθ/dt = ω
```

#### **Problem**: Velocity Divergence
- Force applied in heading direction θ
- But velocity vector (vx, vy) can point in different direction
- **Physical inconsistency**: Agent can slide sideways like ice skating
- Example: θ=0° (heading East), but velocity=(0, 1) (moving North)

#### EPH Integration
- **Action candidates**: 100 pairs `{(F₀, τ₀), (F₁, τ₁), ..., (F₉₉, τ₉₉)}`
- **VAE prediction**: `(s_{t+1}, SPM_{t+1}) = VAE(SPM_t, [F_i, τ_i], s_t)`
- **Evaluation**: For each candidate, compute `F(u_i) = Φ_goal + Φ_safety + S`
- **Selection**: `u* = argmin F(u_i)` (discrete search, ✅ NOT differentiation)

#### **Verdict**: ❌ Physically unrealistic for pedestrian/robot agents

---

### **Option B: Omnidirectional Model with Heading Alignment**

#### State Space
```
s = [x, y, vx, vy, θ] ∈ ℝ⁵
```
- `(x, y)`: Position
- `(vx, vy)`: Velocity (primary state)
- `θ`: Heading angle (derived/aligned to velocity)

#### Control Input
```
u = [Fx, Fy] ∈ ℝ²
```
- `(Fx, Fy)`: Force vector in world frame (2D omnidirectional)

#### Dynamics Equations
```python
# Translational dynamics (2nd-order)
m·dvx/dt = Fx - cd·|v|·vx
m·dvy/dt = Fy - cd·|v|·vy

# Heading alignment (1st-order lag to velocity direction)
θ_target = atan2(vy, vx)
dθ/dt = k_align·angle_diff(θ_target, θ)
```

Where `k_align` is alignment speed (like your low-pass filter idea):
- High k_align → θ quickly follows velocity direction
- Low k_align → θ lags behind (like turning your body while moving)

#### **Advantages**
✅ **Physically consistent**: Heading naturally follows velocity direction
✅ **Simple control**: Direct force in desired direction
✅ **No sliding**: Velocity and heading automatically aligned
✅ **2nd-order**: Full inertial dynamics maintained

#### **Heading Determination** (Your Low-Pass Filter Idea)
```python
# Your original idea implemented:
v_angle = atan2(vy, vx)  # Instantaneous velocity angle
θ = low_pass_filter(v_angle, cutoff_freq=2.0 Hz)

# Equivalent to:
dθ/dt = k_align · (v_angle - θ)  # k_align = 2π·cutoff_freq
```

This is **excellent** for pedestrian-like agents:
- Gradual body rotation toward movement direction
- Natural lag when changing direction
- No instantaneous "snapping" to new heading

#### EPH Integration
```python
# Action candidates: 100 force vectors
angles = np.linspace(0, 2π, 20)  # 20 directions
magnitudes = [0.0, 0.5, 1.0, 1.5, 2.0]  # 5 magnitudes

for angle in angles:
    for F_mag in magnitudes:
        u = [F_mag*cos(angle), F_mag*sin(angle)]

        # VAE prediction
        s_next, spm_next = vae.predict(spm_current, u, s_current)

        # Free energy evaluation
        F_val = compute_free_energy(s_next, spm_next, u, ...)

        # Track minimum
        if F_val < F_min:
            u_best = u

return u_best  # ✅ Discrete evaluation, NOT differentiation
```

#### **Verdict**: ✅ **RECOMMENDED** - Best fit for EPH with pedestrian agents

---

### **Option C: Differential Drive Approximation**

#### State Space
```
s = [x, y, θ, v, ω] ∈ ℝ⁵
```
- `(x, y)`: Position
- `θ`: Heading
- `v`: Forward speed (scalar, always in heading direction)
- `ω`: Angular velocity

#### Control Input
```
u = [F, τ] ∈ ℝ²
```
- `F`: Forward force
- `τ`: Torque

#### Dynamics Equations
```python
# Forward dynamics
m·dv/dt = F - cd·v²

# Rotational dynamics
I·dω/dt = τ - cr·ω

# Kinematics (velocity always aligned with heading)
dx/dt = v·cos(θ)
dy/dt = v·sin(θ)
dθ/dt = ω
```

#### **Advantages**
✅ No velocity-heading divergence (enforced by design)
✅ Simpler state (5D vs 6D)
✅ Matches car-like or wheeled robots

#### **Disadvantages**
❌ Cannot move sideways or backwards easily
❌ Less realistic for pedestrians
❌ More constrained control

#### EPH Integration
Same as Option A (discrete candidates over F, τ)

#### **Verdict**: ⚠️ Good for robots, less suitable for pedestrian crowds

---

## Recommendation: Option B with Implementation Details

### Final State Space Definition
```
s = [x, y, vx, vy, θ] ∈ ℝ⁵
```

### Final Control Input
```
u = [Fx, Fy] ∈ ℝ²
```

### Complete Dynamics (RK4 Integration)
```python
def dynamics_rk4(state, u, dt, params):
    """
    state: [x, y, vx, vy, theta]
    u: [Fx, Fy]
    """
    m = params['mass']           # 70 kg (pedestrian)
    cd = params['drag_coeff']     # 0.5
    k_align = params['heading_align']  # 4.0 (τ = 0.25s)

    def f(s, u):
        x, y, vx, vy, theta = s
        Fx, Fy = u

        v_norm = np.sqrt(vx**2 + vy**2)

        # Target heading (velocity direction)
        if v_norm > 0.01:  # Threshold to avoid division by zero
            theta_target = np.arctan2(vy, vx)
        else:
            theta_target = theta  # Keep current heading if nearly stopped

        # Angle difference (handle wrap-around)
        dtheta = angle_diff(theta_target, theta)

        return np.array([
            vx,                                    # dx/dt
            vy,                                    # dy/dt
            Fx/m - cd/m * vx * v_norm,             # dvx/dt
            Fy/m - cd/m * vy * v_norm,             # dvy/dt
            k_align * dtheta                       # dtheta/dt
        ])

    # RK4 integration
    k1 = f(state, u)
    k2 = f(state + dt/2 * k1, u)
    k3 = f(state + dt/2 * k2, u)
    k4 = f(state + dt * k3, u)

    return state + dt/6 * (k1 + 2*k2 + 2*k3 + k4)

def angle_diff(target, current):
    """Compute shortest angular difference with wrap-around."""
    diff = target - current
    return np.arctan2(np.sin(diff), np.cos(diff))
```

### Physical Parameters
```python
params = {
    'mass': 70.0,           # kg (adult pedestrian)
    'drag_coeff': 0.5,      # Approximate air resistance
    'heading_align': 4.0,   # rad/s per radian error (τ ≈ 0.25s)
    'F_max': 150.0,         # N (reasonable walking force)
    'dt': 0.01              # s (10ms timestep)
}
```

### EPH Action Candidate Generation
```python
# 100 action candidates: 20 directions × 5 magnitudes
def generate_action_candidates(F_max=150.0, n_angles=20, n_magnitudes=5):
    angles = np.linspace(0, 2*np.pi, n_angles, endpoint=False)
    magnitudes = np.linspace(0, F_max, n_magnitudes)

    candidates = []
    for angle in angles:
        for F_mag in magnitudes:
            Fx = F_mag * np.cos(angle)
            Fy = F_mag * np.sin(angle)
            candidates.append([Fx, Fy])

    return np.array(candidates)  # Shape: (100, 2)
```

### EPH Evaluation Loop (Discrete, NOT Differentiation)
```python
def select_action_eph(spm_current, s_current, vae, params):
    """EPH action selection via discrete candidate evaluation."""

    # Generate candidates
    candidates = generate_action_candidates()

    F_min = float('inf')
    u_best = None

    for u in candidates:
        # VAE prediction (EPH core)
        s_pred, spm_pred = vae.predict(spm_current, u, s_current)

        # Goal term (progress-based)
        v_pred = s_pred[2:4]  # [vx, vy]
        P_pred = np.dot(v_pred, params['d_goal'])
        Phi_goal = (P_pred - params['P_target'])**2 / (2 * params['sigma_P']**2)

        # Safety term (haze-modulated SPM)
        Phi_safety = compute_safety_term(spm_pred, params['precision'])

        # Smoothness term
        S = params['lambda_smooth'] * np.sum(u**2)

        # Total free energy
        F_val = Phi_goal + Phi_safety + S

        # Track minimum
        if F_val < F_min:
            F_min = F_val
            u_best = u

    return u_best  # ✅ Selected via discrete search, NOT grad descent
```

---

## Why Option B is Best for EPH

### 1. **Physical Realism**
- No velocity-heading divergence
- Natural heading alignment (like humans turning their body)
- Smooth directional changes

### 2. **EPH Compatibility**
- ✅ Discrete action candidates (100 force vectors)
- ✅ VAE predicts (s_next, SPM_next) for each candidate
- ✅ Free energy evaluation per candidate
- ✅ Argmin selection (NOT automatic differentiation)

### 3. **Computational Efficiency**
- 5D state (vs 6D in Option A)
- No torque control complexity
- Simpler candidate space (2D force vs force+torque)

### 4. **Scenario Applicability**

#### Scramble Crossing
- Agents need omnidirectional movement
- Heading naturally follows walking direction
- ✅ Perfect fit

#### Narrow Corridor
- Forward/backward movement with gradual turns
- Heading lag prevents unrealistic instant rotation
- ✅ Excellent fit

#### Sheepdog
- Dog needs agile movement to herd sheep
- Omnidirectional force for rapid direction changes
- ✅ Ideal for herding behavior

---

## Integration with Progress-Based Goal Term

### Goal Term Formulation (Unchanged)
```
Φ_goal(u) = (P_pred - P_target)² / (2σ_P²)

where:
P_pred = v_pred · d_goal
v_pred = [vx_pred, vy_pred]  (predicted by VAE)
d_goal = [cos(θ_goal), sin(θ_goal)]  (fixed initial parameter)
```

### Heading Role in Goal Term
**Important**: θ (heading) does NOT appear in goal term!

- Goal term evaluates **velocity direction** vs goal direction
- Heading θ is purely for **visualization** and **spatial awareness** (SPM encoding)
- VAE predicts both velocity and heading, but only velocity affects goal achievement

This is **intentional**:
- Pedestrians can walk sideways while looking in different direction
- What matters: moving toward goal (velocity)
- Heading provides richer SPM information for collision avoidance

---

## Summary Table

| Aspect | Option A (Unicycle) | **Option B (Omnidirectional)** | Option C (Diff. Drive) |
|--------|---------------------|--------------------------------|------------------------|
| State dimension | 6D | **5D** | 5D |
| Control input | [F, τ] | **[Fx, Fy]** | [F, τ] |
| Velocity-heading consistency | ❌ Can diverge | **✅ Auto-aligned** | ✅ Enforced |
| Physical realism (pedestrian) | ❌ Sliding | **✅ Natural** | ⚠️ Too constrained |
| EPH discrete evaluation | ✅ | **✅** | ✅ |
| Omnidirectional movement | ⚠️ Limited | **✅ Full** | ❌ No |
| Heading lag (your idea) | N/A | **✅ Implemented** | N/A |
| Computational cost | Medium | **Low** | Medium |
| **Recommendation** | ❌ | **✅ BEST CHOICE** | ⚠️ |

---

## Your Low-Pass Filter Idea: Validated ✅

Your intuition was **exactly right**:

> "速度ベクトルの角度にローパスフィルターをかけて headingを特定する"

This is mathematically equivalent to:
```
dθ/dt = k_align · (atan2(vy, vx) - θ)
```

Where `k_align = 2π · f_cutoff` (cutoff frequency of low-pass filter).

**Recommended value**: k_align = 4.0 rad/s (cutoff ≈ 0.64 Hz, lag ≈ 0.25s)
- Fast enough: Heading updates within 0.5s when changing direction
- Smooth enough: No jittery rotation from velocity fluctuations

---

## Next Steps

1. **Update proposal_v7.0_revised.md** with Option B dynamics
2. **Implement RK4 integration** with heading alignment
3. **Test action candidate generation** (20 angles × 5 magnitudes)
4. **Verify EPH evaluation loop** maintains discrete selection

Should I proceed with updating the proposal document?
