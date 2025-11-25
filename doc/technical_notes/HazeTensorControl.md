---
title: "Haze Tensor Control: A General Framework for Swarm Behavioral Guidance"
subtitle: "精度変調テンソルによる群行動制御の汎用理論"
type: Technical_Note
status: 🟢 Active
version: 1.0
date_created: 2025-11-25
date_modified: 2025-11-25
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Haze Tensor
  - Precision Modulation
  - Swarm Control
  - Active Inference
  - Behavioral Guidance
  - Stigmergy
---

# Haze Tensor Control: A General Framework for Swarm Behavioral Guidance

> [!ABSTRACT]
> **Purpose**: 本ドキュメントは、Haze Tensor を用いた群行動制御の汎用的理論フレームワークを提示する。EPHはShepherding専用ではなく、Exploration, Foraging, Pursuit-Evasion, Formation Control等、多様なタスクに適用可能な**汎用アプローチ**である。Hazeテンソルの空間的配置を操作することで、明示的な通信や中央制御なしに、群れの協調行動を誘導する原理を明らかにする。

## 0. Executive Summary

### 0.1 Core Concept

**Haze Tensor** $\mathcal{H}(r, \theta, c)$ は、エージェントの知覚空間（Saliency Polar Map）上で定義される **精度変調場（Precision Modulation Field）** である。Hazeは以下の3つの制御パラダイムで実現される：

1. **Self-Hazing** (自律的調整): エージェント内部状態に基づく動的調整
2. **Environmental Hazing** (Stigmergy): 環境に埋め込まれた制御信号
3. **Engineered Hazing** (外部制御): 設計者による明示的なHaze配置

これら3つのHazeソースを統合することで、**スケーラブルかつロバストな分散制御**が実現される。

### 0.2 Key Principles

#### Principle 1: Haze is a Modulator, Not a Generator
Hazeは**行動の根本的動機（引力・反発・目標）を生成しない**。既存の行動駆動力（Active InferenceのPragmatic/Epistemic terms）を**選択的に変調**する。

**Example**:
- 引力がない系: Haze操作 → 密集度変化なし ❌
- 引力がある系: Haze操作 → 引力の選択的抑制/強化 ✅

#### Principle 2: Spatial Selectivity is Essential
チャンネル次元（Occupancy, Radial, Tangential）の選択的Hazeは不十分。**空間次元（距離・角度）**での選択性が有効。

**Validated strategies**:
- Distance-selective (Mid-range haze) → +4% exploration efficiency
- Asymmetric angular haze → Limited robustness (seed-dependent)

#### Principle 3: Multi-Scale Control Hierarchy
Hazeは複数のスケールで機能：
- **Microscopic**: 個体の知覚バイアス（Self-Haze）
- **Mesoscopic**: 局所的な群れダイナミクス（Environmental Haze）
- **Macroscopic**: 群れ全体の創発パターン（Collective behavior）

---

## 1. Theoretical Foundation

### 1.1 Precision-Weighted Active Inference

Active Inferenceでは、エージェントは **Expected Free Energy (EFE)** を最小化：

$$
\boxed{G(a) = \mathbb{E}_{q(o|a)}[\ln q(s|o,a) - \ln p(s, o|\tilde{o})] - H[q(o|a)]}
$$

Simplified form (EPH implementation):

$$
G(a) = \underbrace{F_{percept}(a, \mathcal{H})}_{\text{Pragmatic}} + \underbrace{\beta \cdot H[q(s|a, \mathcal{H})]}_{\text{Epistemic}} + \underbrace{\lambda \cdot M_{meta}(a)}_{\text{Task-specific}}
$$

**Haze Tensor** $\mathcal{H}$ modulates **Precision Matrix** $\boldsymbol{\Pi}$:

$$
\Pi(r, \theta, c; \mathcal{H}) = \Pi_{base}(r, \theta, c) \cdot \underbrace{\exp(-\alpha \cdot h(r, \theta, c))}_{\text{Exponential decay}}
$$

where:
- $h \in [0, \infty)$: Haze value (higher → lower precision)
- $\alpha \geq 1$: Decay rate (controls haze sensitivity)
- $\Pi_{base}$: Base precision (distance-dependent, Gaussian-based)

**Key property**: Low precision → High covariance → High entropy → Exploration

### 1.2 Haze as Cognitive Filter

Hazeは **注意配分（Attention Allocation）** のメカニズムとして機能：

```
High Haze Region → Low Precision → Low Gradient Contribution
                  → "Ignore this direction"
                  → Reduce computational/behavioral cost

Low Haze Region → High Precision → High Gradient Contribution
                → "Focus on this direction"
                → Accurate collision avoidance
```

**Cognitive resource allocation**:
$$
\text{Effective compute} = \sum_{r,\theta} \Pi(r,\theta; \mathcal{H}) \cdot \text{ProcessingCost}(r,\theta)
$$

High haze → Reduce effective compute → Faster decision-making (at the cost of local accuracy)

### 1.3 Three Sources of Haze

#### 1.3.1 Self-Haze (Autonomic)

Computed from agent's own perceptual state (SPM):

$$
h_{self}(t) = h_{max} \cdot \sigma\left( -\alpha (\Omega(t) - \Omega_{threshold}) \right)
$$

where $\Omega(t) = \sum_{r,\theta} \text{SPM}[1, r, \theta]$ (total occupancy)

**Interpretation**:
- Low occupancy ($\Omega < \Omega_{threshold}$) → High self-haze → Exploration
- High occupancy ($\Omega > \Omega_{threshold}$) → Low self-haze → Exploitation

**Implementation**: `src_julia/control/SelfHaze.jl::compute_self_haze()`

#### 1.3.2 Environmental Haze (Stigmergy)

Embedded in 2D spatial grid $\mathcal{H}_{env}(x, y)$:

```julia
# Haze deposition by agent
function deposit_haze!(env, agent, haze_type, strength)
    if haze_type == :lubricant
        env.haze_grid[agent.position] -= strength  # Low haze → High precision
    elseif haze_type == :repellent
        env.haze_grid[agent.position] += strength  # High haze → Low precision
    end
end

# Haze decay over time
env.haze_grid .*= decay_rate  # e.g., 0.99
```

**Two types**:
- **Lubricant Haze** (Low haze): Increase precision → Encourage following
- **Repellent Haze** (High haze): Decrease precision → Discourage revisiting

**Analogy to pheromones**:
| Aspect | ACO Pheromone | EPH Haze |
|--------|---------------|----------|
| **Nature** | Positive value (reward) | Precision modulation (信頼度) |
| **Effect** | Attract agents | Bias attention |
| **Dynamics** | Reinforcement | Stigmergic information |
| **Interpretation** | "Good path" | "Reliable/Unreliable direction" |

#### 1.3.3 Engineered Haze (External Control)

Explicitly designed haze tensor for specific control objectives:

**Example: Distance-Selective Haze**
```julia
# Increase haze at mid-distance to suppress over-planning
mid_range = 3:max(3, Nr-2)
for r in mid_range
    for θ in 1:Nθ
        h_matrix[r, θ] *= 5.0  # Amplify haze
    end
end
```

**Effect**: Agents ignore mid-range obstacles → More direct paths → Better coverage

**Example: Asymmetric Angular Haze**
```julia
# Increase haze in left hemisphere
for θ_idx in 1:Nθ
    θ = compute_angle(θ_idx)
    if θ >= 0.0  # Left half
        h_matrix[:, θ_idx] *= 2.0
    end
end
```

**Effect** (context-dependent): Break symmetry → Consistent turn bias ⚠️ (Low robustness)

### 1.4 Haze Composition

Total haze at agent $i$ at position $(x, y)$:

$$
\mathcal{H}_{total}^{(i)}(r, \theta) = \max\left( h_{self}^{(i)}(r, \theta), \mathcal{H}_{env}(x + r\cos\theta, y + r\sin\theta), \mathcal{H}_{eng}(r, \theta) \right)
$$

**Composition operator**: $\max$ (pessimistic - highest uncertainty wins)

Alternative operators:
- $\text{mean}$: Average uncertainty
- $\text{product}$: Multiplicative composition (all sources must agree)

**Design choice**: $\max$ operator ensures **conservative behavior** (if any source indicates uncertainty, trust is reduced)

---

## 2. Task-Specific Applications

### 2.1 General Application Template

For任意のswarm taskに適用可能な汎用テンプレート：

#### Step 1: Identify Behavioral Drives
Determine task-specific Pragmatic Value $M_{meta}(a)$:

**Examples**:
- **Exploration**: $M_{meta} = (v - v_{target})^2$ (maintain speed)
- **Foraging**: $M_{meta} = ||\mathbf{p}_{agent} - \mathbf{p}_{resource}||^2$ (minimize distance to resource)
- **Shepherding**: $M_{meta} = ||\mathbf{p}_{dog} - \mathbf{p}_{sheep\_COM}||^2$ (Collecting phase)
- **Formation**: $M_{meta} = ||\mathbf{p}_{agent} - \mathbf{p}_{formation}||^2$ (maintain formation position)

#### Step 2: Design Haze Strategy
Choose haze modulation to enhance task performance:

**Exploration** → Mid-distance haze (suppress over-planning)
**Foraging** → High haze away from resource direction (focus attention forward)
**Shepherding** → Low haze toward sheep (maintain awareness)
**Formation** → High haze perpendicular to formation axis (ignore irrelevant directions)

#### Step 3: Validate Control Effect
Measure task-specific metrics:

| Task | Key Metrics |
|------|-------------|
| **Exploration** | Coverage rate, Time to 80%, Novelty rate |
| **Foraging** | Resource collection rate, Travel efficiency |
| **Shepherding** | Sheep compactness, Herding success rate, Time to goal |
| **Formation** | Formation error (MSE from desired positions), Stability |

### 2.2 Application 1: Exploration (✅ Validated)

**Objective**: Maximize coverage of unknown environment

**Behavioral drives**:
- $F_{percept}$: Collision avoidance (inherent)
- $\beta \cdot H[q]$: Epistemic exploration (inherent)
- $M_{meta}$: Speed maintenance (avoid停止)

**Haze strategy**: Distance-selective haze (Mid-range)

```julia
# Production configuration (from experimental validation)
mid_range = 3:max(3, Nr-2)
h_matrix[mid_range, :] *= 5.0
```

**Performance**:
- Coverage @500 steps: **93.2%** (+4.0% vs Baseline)
- Collision reduction: -2.7%
- Control cost: +82% (acceptable trade-off)

**Reference**: [Haze Tensor Effect Report](../experimental_reports/haze_tensor_effect.md#321-coverage-maximization)

### 2.3 Application 2: Shepherding (🔧 Proposed)

**Objective**: Guide sheep flock to target location

**Behavioral drives**:
- $F_{percept}$: Collision avoidance
- $M_{collect}$: Minimize distance to sheep COM (Collecting phase)
- $M_{drive}$: Minimize sheep COM to goal distance (Driving phase)
- $S_{social}$: Dog-dog coordination (maintain spacing)

**Haze strategy**: Context-aware modulation

##### Collecting Phase (Sheep dispersed)
```julia
# Low haze toward sheep → Maintain awareness
for θ_idx in 1:Nθ
    θ = angle_to_sheep_COM(agent, θ_idx)
    if abs(θ) < π/4  # Front cone toward sheep
        h_matrix[:, θ_idx] *= 0.5  # Decrease haze → Increase precision
    end
end
```

**Effect**: Dog focuses attention on sheep → Efficient approach

##### Driving Phase (Sheep compact)
```julia
# High haze behind sheep → Ignore rear obstacles
for θ_idx in 1:Nθ
    θ = angle_from_sheep_COM_to_goal(agent, θ_idx)
    if abs(θ) > 3π/4  # Rear cone
        h_matrix[:, θ_idx] *= 3.0  # Increase haze → Decrease precision
    end
end
```

**Effect**: Dog maintains pressure from behind without over-reacting

**Expected performance** (hypothesis):
- Sheep compactness: >10× baseline (with Social Value term)
- Time to goal: -20% vs Strömbom (2014)
- Robustness to sheep behavior changes: +30%

### 2.4 Application 3: Foraging (🔬 Speculative)

**Objective**: Collect resources from environment, return to nest

**Behavioral drives**:
- $M_{search}$: Exploration (when not carrying resource)
- $M_{collect}$: Minimize distance to resource (when resource detected)
- $M_{return}$: Minimize distance to nest (when carrying resource)

**Haze strategy**: Phase-dependent modulation

##### Search Phase
```julia
# Repellent haze at previously visited locations (Environmental Haze)
deposit_haze!(env, agent, :repellent, 0.5)
```

**Effect**: Avoid redundant search → Improve coverage

##### Return Phase
```julia
# Lubricant haze trail toward nest (Environmental Haze)
deposit_haze!(env, agent, :lubricant, 0.3)
```

**Effect**: Other agents follow trail → Collective path formation

**Expected emergent behavior**: Ant-like trail formation without explicit communication

### 2.5 Application 4: Pursuit-Evasion (🔬 Speculative)

**Objective**: Pursuer agents capture evader agents

**Behavioral drives** (Pursuer):
- $M_{pursuit}$: Minimize distance to nearest evader
- $F_{percept}$: Avoid collisions with teammates

**Haze strategy**: Forward-focused attention

```julia
# High haze in lateral and rear directions
for θ_idx in 1:Nθ
    θ = compute_angle(θ_idx)
    if abs(θ) > π/3  # Lateral/rear
        h_matrix[:, θ_idx] *= 4.0
    end
end
```

**Effect**: Pursuer focuses on forward direction → Faster reaction to evader movements

**Behavioral drives** (Evader):
- $M_{evade}$: Maximize distance from nearest pursuer
- $F_{percept}$: Avoid obstacles

**Haze strategy**: Rear-focused attention

```julia
# Low haze in rear direction (high precision on pursuers)
for θ_idx in 1:Nθ
    θ = compute_angle(θ_idx)
    if abs(θ - π) < π/4  # Rear cone
        h_matrix[:, θ_idx] *= 0.3  # Decrease haze
    end
end
```

**Effect**: Evader monitors pursuers precisely → Effective escape

---

## 3. 設計原則とガイドライン

### 3.1 Haze制御を使うべき場面

#### ✅ 適している状況

1. **注意配分が必要なタスク**
   - 複数の競合する目的（探索 vs 安全性）
   - 限られた計算資源
   - リアルタイム意思決定

2. **行動駆動力が明確に定義されている**
   - 明確なPragmatic Value項が存在
   - 望ましい行動がEFE最小化として表現可能

3. **空間構造が重要**
   - 異なる方向が異なる重要性を持つ
   - 距離依存的な情報価値

4. **分散制御が望ましい**
   - 中央制御器なし
   - 各エージェントが自律的に行動
   - 大規模群れへのスケーラビリティ（100+ agents）

#### ❌ 適していない状況

1. **既存の行動駆動力がない**
   - Hazeは動機を生成できず、変調のみ可能
   - 例: 引力項のない集約タスク → Haze無効

2. **全方向対称なタスク**
   - 利用可能な空間構造がない
   - 例: ランダムウォーク（hazeの効果なし）

3. **厳密な制御が必要**
   - Hazeは**ソフトガイダンス**であり、ハード制約ではない
   - 例: 精密な軌道追従（明示的制御を使用すべき）

### 3.2 Haze戦略選択マトリクス

| タスク特性 | 推奨Haze戦略 | 根拠 |
|-----------|------------|------|
| **探索主体** | Mid-distance haze (+) | 過剰計画の抑制 |
| **目標追従** | 目標方向のLow haze | 注意の集中 |
| **回避主体** | Near-distance haze (−) | 安全性維持 |
| **協調が必要** | Environmental haze (Stigmergy) | 間接的コミュニケーション |
| **多フェーズタスク** | Adaptive haze (時変) | 文脈に応じた変調 |
| **非対称環境** | Directional haze | 有利な方向へのバイアス |

**(+)**: Hazeを増加、**(−)**: Hazeを減少

### 3.3 よくある落とし穴

#### 落とし穴1: 過剰変調
**症状**: 極端なhaze値（>10×）→ 行動不安定化

**例**:
```julia
h_matrix[:, :] *= 100.0  # 極端すぎる！
```

**効果**: Precision → 0 → 信念エントロピー → ∞ → カオス的挙動

**解決策**: 穏やかなmultiplier（2-5×）、段階的な遷移

#### 落とし穴2: 安全性重要情報の無視
**症状**: Near-distanceの高haze → 衝突増加

**例**:
```julia
# 危険: Near-distanceのhaze増加
h_matrix[1:2, :] *= 5.0
```

**効果**: 衝突回避能力低下 → 安全性違反

**解決策**: Near-distance precisionは常に高く保つ（haze ≤ 1.0×）

#### 落とし穴3: ロバスト性検証なしの非対称Haze
**症状**: Left/Right非対称hazeがseed依存の性能を示す

**例**:
```julia
# Left半球のhaze増加
h_matrix[:, left_bins] *= 2.0
```

**効果**: カオス的感度 → 予測不能な性能（分散 ±6%）

**解決策**: ≥10 seedsで検証、可能な限り対称戦略を使用

#### 落とし穴4: 空間文脈なしのチャンネル選択的Haze
**症状**: 単一SPMチャンネルの変調 → 性能劣化

**例**:
```julia
# 無効: Radial velocityのみのhaze
spm_modulated[2, :, :] ./= 3.0  # Channel 2 = Radial
```

**効果**: 情報の不整合 → 衝突増加（+46 events）

**解決策**: Hazeを全チャンネルに一様適用、空間的に変調（r, θ）

### 3.4 検証チェックリスト

Haze戦略を展開する前に確認：

- [ ] **安全性**: Near-distance衝突が著しく増加しない（<10%）
- [ ] **ロバスト性**: Seed間の性能分散が許容範囲内（<20%）
- [ ] **タスク改善**: 目標指標がBaseline比≥3%改善
- [ ] **トレードオフ許容**: 制御コスト増加が性能向上で正当化される
- [ ] **理論的整合性**: Hazeが既存駆動力を変調し、新しい駆動力を生成しない
- [ ] **Multi-seed検証**: ≥5個のランダムseedでテスト
- [ ] **Ablation study**: Hazeの寄与を検証（あり/なし比較）

---

## 4. 実装アーキテクチャ

### 4.1 モジュール構造

```
src_julia/
├── control/
│   ├── EPH.jl                 # EFE最小化コントローラ
│   ├── SelfHaze.jl            # Self-haze計算
│   └── EnvironmentalHaze.jl   # (将来) Environmental haze管理
├── perception/
│   └── SPM.jl                 # Saliency Polar Map
└── utils/
    └── MathUtils.jl           # トーラス幾何
```

### 4.2 Haze計算パイプライン

```julia
# 1. Compute SPM
spm = SPM.compute_spm(agent, env, spm_params)

# 2. Compute Self-Haze
h_self = SelfHaze.compute_self_haze(spm, eph_params)
h_matrix_self = SelfHaze.compute_self_haze_matrix(spm, eph_params)

# 3. (Optional) Sample Environmental Haze
h_env = sample_environmental_haze(env.haze_grid, agent.position, agent.orientation)

# 4. (Optional) Apply Engineered Haze
h_matrix_eng = apply_engineered_haze(h_matrix_self, strategy)

# 5. Compose Haze
h_matrix_total = max.(h_matrix_self, h_env, h_matrix_eng)

# 6. Compute Precision
Π = SelfHaze.compute_precision_matrix(spm, h_matrix_total, eph_params)

# 7. Minimize EFE
action = EPH.decide_action(controller, agent, spm, env, preferred_velocity,
                           h_matrix_override=h_matrix_total)
```

### 4.3 拡張ポイント

#### 拡張1: カスタムHaze戦略
```julia
module CustomHazeStrategy

export apply_custom_haze!

function apply_custom_haze!(
    h_matrix::Matrix{Float64},
    agent::Agent,
    env::Environment,
    task_context::Dict
)::Matrix{Float64}
    # User-defined logic
    # Example: Task-phase-dependent modulation
    if task_context["phase"] == :collecting
        # Increase precision toward target
        ...
    elseif task_context["phase"] == :driving
        # Decrease precision behind
        ...
    end

    return h_matrix
end

end
```

#### 拡張2: 学習されたHazeポリシー
```julia
# Haze policy as neural network
struct LearnedHazePolicy
    network::Chain  # Flux.jl neural network
end

function (policy::LearnedHazePolicy)(spm::Array{Float64, 3}, agent_state::Vector{Float64})
    input = vcat(vec(spm), agent_state)
    h_matrix_flat = policy.network(input)
    h_matrix = reshape(h_matrix_flat, (Nr, Nθ))
    return h_matrix
end
```

Train via Reinforcement Learning:
```julia
# Reward = task_performance - λ * control_cost
reward = coverage_rate - 0.1 * sum(actions.^2)
```

---

## 5. 理論的性質

### 5.1 収束性と安定性

#### 命題1: EFE勾配流
穏やかな条件下（有界Haze、Lipschitz連続SPM）において、行動選択プロセス：

$$
a_{k+1} = a_k - \eta \nabla_a G(a_k; \mathcal{H})
$$

は $G(a; \mathcal{H})$ の局所最小に収束する。

**証明スケッチ**:
1. $G(a; \mathcal{H})$ は2回微分可能（Zygote自動微分）
2. 固定ステップサイズ $\eta$ の勾配降下は、強凸な $G$ に対して収束
3. Hazeは勾配の大きさを変調するが、基本的な景観構造は変えない

**含意**: Hazeは収束を不安定化せず、収束速度と局所最小の選択のみを変調する。

#### 命題2: Haze感度
最終行動のHaze摂動に対する感度は有界：

$$
\left\| \frac{\partial a^*}{\partial h(r,\theta)} \right\| \leq C \cdot \Pi_{base}(r,\theta) \cdot \alpha
$$

ここで $C$ はSPM大きさに依存する定数。

**含意**: Haze効果は局所化される—遠方のbinの摂動は最小限の影響しか与えない。

### 5.2 創発特性

#### 特性1: Environmental Hazeによる自己組織化

エージェントが環境Hazeを堆積させる場合：

$$
\frac{\partial \mathcal{H}_{env}(x,y)}{\partial t} = -\gamma \mathcal{H}_{env} + \sum_{i} \delta(\mathbf{p}_i - (x,y)) \cdot h_{deposit}
$$

これは**スティグマージーフィードバックループ**を生成：
- 交通量の多いエリア → 高Haze堆積 → 反発効果（$h_{deposit} > 0$ の場合）
- 交通量の少ないエリア → 低Haze → 引力効果（相対的）

**創発行動**: 明示的な協調なしで空間パターン（経路、縄張り）が形成

#### 特性2: 相転移
Haze変調された引力/反発力を持つマルチエージェントシステムにおいて：

$$
\text{Compactness}(\mathcal{H}) = f(\lambda_{attract}, \lambda_{repel}, \mathcal{H})
$$

は臨界Haze閾値で**分岐**を示す：
- Low haze: 密集的集約
- High haze: 分散的探索

**応用**: 動的相制御（例：Shepherding における Collecting ↔ Driving）

---

## 6. 関連アプローチとの比較

### 6.1 vs. Potential Fields (Khatib, 1986)

| 側面 | Potential Fields | EPH Haze |
|--------|------------------|----------|
| **制御パラダイム** | 明示的な力 | 暗黙的なprecision変調 |
| **局所最小** | トラップに陥りやすい | 認識的探索で脱出 |
| **スケーラビリティ** | O(N²) agent-agent | O(1) per agent (SPM-based) |
| **適応性** | 固定ポテンシャル | 動的Self-haze |
| **通信** | しばしば必要 | 不要（Stigmergyはオプション） |

**EPHの優位性**: 認識的探索によって局所最小を回避（高エントロピー → トラップからのランダムウォーク脱出）

### 6.2 vs. Ant Colony Optimization (Dorigo, 1992)

| 側面 | ACO | EPH Haze |
|--------|-----|----------|
| **シグナル** | Pheromone (価値) | Haze (precision) |
| **意味論** | "良い経路" | "信頼できる情報" |
| **強化** | 正のフィードバック | 文脈依存 |
| **表現** | スカラー値 | 空間テンソル (r, θ) |
| **理論** | ヒューリスティック | FEP/Active Inference |

**EPHの優位性**: 原理的な理論基盤（FEP）、より豊かな空間構造

### 6.3 vs. Flocking Models (Reynolds, 1987; Couzin, 2002)

| 側面 | Flocking | EPH |
|--------|----------|-----|
| **ルール** | 手作り（Separation, Alignment, Cohesion） | EFE最小化から創発 |
| **モジュール性** | 新しい行動には新しいルールを追加 | Pragmatic Value項を調整 |
| **注意機構** | 全ての隣接個体を等しく重み付け | Haze変調された注意 |
| **理論的基盤** | 運動学的 | Active Inference（ベイズ的） |

**EPHの優位性**: 統一フレームワーク（ルール増殖なし）、生物学的基盤

---

## 7. 今後の研究方向

### 7.1 適応的Hazeポリシー

**問い**: エージェントは最適なHaze戦略を学習できるか？

**アプローチ**: メタ強化学習

```python
# Meta-RL for haze policy
policy_network = HazePolicyNet(input_dim, output_dim)

for episode in episodes:
    task = sample_task()  # Exploration, Shepherding, Foraging, ...
    h_matrix = policy_network(spm, task_context)
    reward = task_performance(h_matrix)
    policy_network.update(reward)
```

**期待される成果**: 手作り戦略を上回るタスク特化型Hazeポリシー

### 7.2 マルチエージェントHaze交渉

**問い**: エージェントは協調のためにHaze設定を交渉できるか？

**シナリオ**: 複数の犬によるShepherding
- Dog A は羊方向に低Hazeを望む（羊に注目）
- Dog B は Dog A 方向に高Hazeを望む（衝突回避）

**アプローチ**: ゲーム理論的Haze最適化
$$
\mathcal{H}^* = \arg\min_{\mathcal{H}} \sum_{i} G_i(a_i; \mathcal{H}) + \lambda \cdot \text{Nash均衡コスト}
$$

### 7.3 階層的Haze制御

**問い**: 個体のHaze（ミクロ）と集団パターン（マクロ）はどう相互作用するか？

**アプローチ**: Haze動力学の平均場理論

$$
\frac{\partial \rho(\mathbf{x}, \mathcal{H}, t)}{\partial t} = -\nabla \cdot (\rho \mathbf{v}(\mathcal{H})) + D \nabla^2 \rho
$$

ここで $\rho$ はエージェント密度、$\mathbf{v}(\mathcal{H})$ はHaze依存速度場

**期待される知見**: 局所Hazeルールからグローバルパターン形成への条件

### 7.4 実世界ロボティクス検証

**問い**: EPH-Hazeはノイズのあるセンサーを持つ実機ロボットで機能するか？

**課題**:
- Lidar/カメラノイズ下でのSPM計算
- リアルタイム勾配計算（組み込みシステム）
- マルチロボット通信遅延

**テストベッド**: Turtlebot3 スワーム（5-10台）

---

## 8. 結論

### 8.1 貢献のまとめ

1. **汎用フレームワーク**: Haze Tensor Controlは**汎用的アプローチ**であり、Shepherdingに限定されない
2. **3つの制御パラダイム**: Self-Hazing、Environmental Hazing、Engineered Hazing
3. **設計原則**: Haze戦略選択のための検証済みガイドライン
4. **理論的基盤**: FEPに基づくprecision重み付きActive Inference
5. **拡張性**: カスタムHaze戦略のためのモジュラーアーキテクチャ

### 8.2 重要なポイント

#### 研究者向け
- **Hazeは変調器である**: 既存の駆動力を形成するが、それ自体を生成するものではない
- **空間選択性**: 距離と角度の次元が鍵
- **ロバスト性が重要**: 複数のシード（≥5）で検証すること
- **ネガティブな結果にも価値がある**: Compactness不変性実験は限界を明確化

#### 実務者向け
- **シンプルから始める**: まずSelf-Haze、次にEnvironmental、最後にEngineered
- **安全性を検証**: 近距離precisionは高く維持すること
- **タスク特化チューニング**: 万能なHaze設定は存在しない
- **トレードオフが存在**: 性能 vs 制御コスト vs ロバスト性

### 8.3 ビジョン

EPH Haze Tensor Controlの最終目標：

> **「知的に注意を配分し、動的環境に適応し、最小限の通信で自己組織化する群れ—全てが自由エネルギー原理に基づいて。」**

---

## 参考文献

### EPHフレームワーク
- [EmergentPerceptualHaze_EPH.md](./EmergentPerceptualHaze_EPH.md) - Core EPH theory
- [SaliencyPolarMap_SPM.md](./SaliencyPolarMap_SPM.md) - Perceptual representation
- [Haze Tensor Effect Report](../experimental_reports/haze_tensor_effect.md) - Spatial scan validation

### Active Inference文献
- Friston, K. J. (2010). The free-energy principle: a unified brain theory? *Nature Reviews Neuroscience*, 11(2), 127-138.
- Parr, T., & Friston, K. J. (2019). Generalised free energy and active inference. *Biological cybernetics*, 113(5-6), 495-513.

### 群知能文献
- Reynolds, C. W. (1987). Flocks, herds and schools: A distributed behavioral model. *ACM SIGGRAPH*, 21(4), 25-34.
- Dorigo, M., et al. (1996). Ant system: optimization by a colony of cooperating agents. *IEEE Transactions on Systems, Man, and Cybernetics*, Part B, 26(1), 29-41.
- Couzin, I. D., et al. (2002). Collective memory and spatial sorting in animal groups. *Journal of theoretical biology*, 218(1), 1-11.

---

**Document Status**: Active Development
**Version**: 1.0
**Last Updated**: 2025-11-25
**Author**: Hiroshi Igarashi (AI-DLC, Tokyo Denki University)
**License**: Internal research document
