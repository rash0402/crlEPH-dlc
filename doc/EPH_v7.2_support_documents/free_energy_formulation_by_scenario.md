# EPH v7.0: 各シナリオにおける自由エネルギーの具体的定義

**バージョン**: 7.2.0
**作成日**: 2026-01-14
**目的**: 3シナリオそれぞれにおける自由エネルギー $F(u)$ の具体的な定式化と計算手順を明記

---

## 目次

1. [理論的基盤](#理論的基盤)
2. [Scenario 1: Scramble Crossing](#scenario-1-scramble-crossing)
3. [Scenario 2: Narrow Corridor](#scenario-2-narrow-corridor)
4. [Scenario 3: Sheepdog Herding](#scenario-3-sheepdog-herding)
5. [実装上の注意事項](#実装上の注意事項)

---

## 自由エネルギーの理論的基礎

### Active Inference における自由エネルギー

**Variational Free Energy**:
$$
F = \mathbb{E}_{q(s)}[-\log p(o|s)] + D_{KL}[q(s) || p(s)]
$$

EPH では、これを以下の3項に分解：

$$
F(u) = \underbrace{\Phi_{\text{goal}}(u)}_{\text{Goal Term}} + \underbrace{\Phi_{\text{safety}}(u)}_{\text{Safety Term}} + \underbrace{S(u)}_{\text{Smoothness}}
$$

---

## Scenario 1: Scramble Crossing の自由エネルギー定義

### 目的
- 2次系動力学による創発度の評価
- Self-hazing の効果検証
- 1次系との比較

---

### 状態空間と制御入力

**状態**:
```
s = [x, y, vx, vy, θ] ∈ ℝ⁵
```

**制御入力**:
```
u = [Fx, Fy] ∈ ℝ²
```

**目標方向** (各エージェント固有):
```
d_goal ∈ {[1,0], [-1,0], [0,1], [0,-1]}  # East, West, North, South
```

---

### Free Energy の定義

$$
F(u; s_i, o_i, t) = \Phi_{\text{goal}}(u) + \Phi_{\text{safety}}(u) + S(u)
$$

---

### Term 1: Goal Term (進捗速度ベース)

**事前分布**:
$$
p(s_i|\mathbf{d}_{\text{goal},i}) \propto \exp\left(-\frac{(P_i - P_{\text{target}})^2}{2\sigma_P^2}\right)
$$

where:
- $P_i = \mathbf{v}_i \cdot \mathbf{d}_{\text{goal},i}$: 進捗速度
- $P_{\text{target}} = 1.0$ m/s: 目標進捗速度
- $\sigma_P = 0.5$ m/s: 許容幅

**Goal Term** (KL divergence の Gaussian 近似):
$$
\Phi_{\text{goal}}(u) = \frac{(P_{\text{pred}}(u) - P_{\text{target}})^2}{2\sigma_P^2}
$$

where:
- $P_{\text{pred}}(u) = \mathbf{v}_{\text{pred}}(u) \cdot \mathbf{d}_{\text{goal}}$: 予測進捗速度
- $\mathbf{d}_{\text{goal}}$: 固定目標方向ベクトル（初期パラメータ）
- $P_{\text{target}} = 1.0$ m/s
- $\sigma_P = 0.5$ m/s

---

## Scenario 1: Scramble Crossing

### 自由エネルギーの完全な定義

#### 状態とパラメータ

**エージェント $i$ の状態**:
```
s_i = [x_i, y_i, vx_i, vy_i, θ_i] ∈ ℝ⁵
```

**制御入力**:
```
u_i = [Fx_i, Fy_i] ∈ ℝ²
```

**目標方向** (初期パラメータ):
```python
# 各エージェントに固定方向ベクトルを割り当て
d_goal_i ∈ {[1,0], [-1,0], [0,1], [0,-1]}  # East, West, North, South
```

---

### 自由エネルギーの完全な定式化

#### 1. Goal Term (進捗速度ベース)

**事前分布**:
$$
p(s_i|\mathbf{d}_{\text{goal},i}) \propto \exp\left(-\frac{(P_i - P_{\text{target}})^2}{2\sigma_P^2}\right)
$$

where:
- $P_i = \mathbf{v}_i \cdot \mathbf{d}_{\text{goal},i}$: 進捗速度（ゴール方向への速度成分）
- $P_{\text{target}} = 1.0$ m/s: 目標進捗速度
- $\sigma_P = 0.5$ m/s: 許容幅

**Goal Term** (KL divergence近似):
$$
\Phi_{\text{goal}}(u) = \frac{(P_{\text{pred}}(u) - P_{\text{target}})^2}{2\sigma_P^2}
$$

where:
- $P_{\text{pred}}(u) = \mathbf{v}_{\text{pred}}(u) \cdot \mathbf{d}_{\text{goal}}$
- $\mathbf{v}_{\text{pred}}(u)$: VAEが予測する次時刻の速度
- $\mathbf{d}_{\text{goal}}$: 固定方向ベクトル

---

## 2. Narrow Corridor (狭い廊下)

### Goal Term (Scramble と同一)

**事前分布**:
$$
p(s_i|\mathbf{d}_{\text{goal},i}) \propto \exp\left(-\frac{(P_i - P_{\text{target}})^2}{2\sigma_P^2}\right)
$$

where:
- $P_i = \mathbf{v}_i \cdot \mathbf{d}_{\text{goal},i}$: 進捗速度
- $\mathbf{d}_{\text{goal},i}$: 固定方向ベクトル
  - 右側エージェント: $\mathbf{d}_{\text{goal}} = (1, 0)$ (East)
  - 左側エージェント: $\mathbf{d}_{\text{goal}} = (-1, 0)$ (West)
- $P_{\text{target}} = 1.0$ m/s
- $\sigma_P = 0.5$ m/s

**Goal Term**:
$$
\Phi_{\text{goal}}(u) = \frac{(P_{\text{pred}}(u) - P_{\text{target}})^2}{2\sigma_P^2}
$$

where:
$$
P_{\text{pred}}(u) = \mathbf{v}_{\text{pred}}(u) \cdot \mathbf{d}_{\text{goal}}
$$

**Safety Term** (Environmental Haze変調):
$$
\Phi_{\text{safety}}(u) = \sum_{\rho=1}^{16} \sum_{\theta=1}^{16} \Pi(\rho,\theta) \cdot \text{SPM}_{\text{pred}}(u; \rho,\theta)
$$

where:
$$
\Pi(\rho,\theta; \mathbf{x}) = \frac{1 + \gamma \cdot P_{\text{env}}(\mathbf{x})}{H_{\text{spatial}}(\rho) \cdot (1 + \beta(1-A)) + \epsilon}
$$

**Precision増大フィールド**:
$$
P_{\text{env}}(\mathbf{x}) = \begin{cases}
1.0 & \text{if } |y - y_{\text{wall}}| < 0.5 \quad \text{(壁近傍)} \\
0.0 & \text{otherwise} \quad \text{(中央)}
\end{cases}
$$

**パラメータ**:
- $\gamma = 2.0$: Precision増大係数
- $\beta = 1.0$: Self-hazing係数
- $\epsilon = 10^{-6}$: 数値安定化

**Smoothness Term**:
$$
S(u) = \frac{\|\mathbf{F}\|^2}{2\sigma_u^2}
$$
where $\sigma_u = 50$ N

**Total Free Energy**:
$$
F(u) = w_{\text{goal}} \cdot \Phi_{\text{goal}}(u) + w_{\text{safety}} \cdot \Phi_{\text{safety}}(u) + w_{\text{entropy}} \cdot S(u)
$$

**重み**:
- $w_{\text{goal}} = 1.0$
- $w_{\text{safety}} = 1.0$
- $w_{\text{entropy}} = 0.01$

---

### 2.3 Environmental Haze の効果

**壁近傍 (P_env=1.0)**:
$$
\Pi_{\text{wall}} = \frac{1 + 2.0}{H_{\text{spatial}}(\rho) + \epsilon} = 3 \cdot \Pi_{\text{baseline}}
$$

→ 壁近傍で Precision が **3倍** に増大

**中央 (P_env=0.0)**:
$$
\Pi_{\text{center}} = \frac{1}{H_{\text{spatial}}(\rho) + \epsilon} = \Pi_{\text{baseline}}
$$

→ 通常の Precision

**結果**:
- 壁近傍の障害物・壁への Safety Term の寄与が増大
- 壁からの予測的回避行動が促進
- 壁衝突率が大幅に減少 (67% reduction期待)

---

## Scenario 3: Sheepdog Herding

### 3.1 Dog Agent の自由エネルギー (EPH-driven)

**事前分布**:
$$
p(s_{\text{dog}}|\mathbf{d}_{\text{push}}) \propto \exp\left(-\frac{(P_{\text{dog}} - v_{\text{target}})^2}{2\sigma_v^2}\right)
$$

where:
- $P_{\text{dog}} = \mathbf{v}_{\text{dog}} \cdot \mathbf{d}_{\text{push}}$: 進捗速度
- $\mathbf{d}_{\text{push}} = [0, 1]$: 北方向（群れを押す方向）
- $v_{\text{target}} = 1.0$ m/s
- $\sigma_v = 0.5$ m/s

**Goal Term**:
$$
\Phi_{\text{goal}}^{\text{dog}}(u) = \frac{(P_{\text{dog,pred}}(u) - v_{\text{target}})^2}{2\sigma_v^2}
$$

where:
$$
P_{\text{dog,pred}}(u) = \mathbf{v}_{\text{dog,pred}}(u) \cdot \mathbf{d}_{\text{push}}
$$

**Safety Term**:
$$
\Phi_{\text{safety}}^{\text{dog}}(u) = \sum_{\rho,\theta} \Pi_{\text{dog}}(\rho,\theta) \cdot \text{SPM}_{\text{pred}}^{\text{dog}}(u; \rho,\theta)
$$

where:
- $\text{SPM}_{\text{pred}}^{\text{dog}}$: Dog の予測 SPM（Sheep の位置・密度を含む）
- $\Pi_{\text{dog}}(\rho,\theta)$: Dog の Precision map

**Smoothness Term**:
$$
S^{\text{dog}}(u) = \frac{\|\mathbf{F}_{\text{dog}}\|^2}{2\sigma_u^2}
$$

**Total Free Energy (Dog)**:
$$
F^{\text{dog}}(u) = \Phi_{\text{goal}}^{\text{dog}}(u) + \Phi_{\text{safety}}^{\text{dog}}(u) + S^{\text{dog}}(u)
$$

**重み** (Dog):
- $w_{\text{goal}} = 1.0$
- $w_{\text{safety}} = 1.0$
- $w_{\text{entropy}} = 0.01$

---

### 3.2 Sheep Agent の力学 (Boids-driven)

**Sheep は EPH ではなく Boids** で駆動されるため、自由エネルギーは定義されない。

**Boids 力の計算**:
$$
\mathbf{F}_{\text{sheep},i} = w_c \mathbf{F}_c + w_a \mathbf{F}_a + w_s \mathbf{F}_s + w_d \mathbf{F}_d
$$

where:

**Cohesion (凝集力)**:
$$
\mathbf{F}_c = w_c \cdot (\mathbf{c}_{\text{flock}} - \mathbf{x}_i)
$$
where $\mathbf{c}_{\text{flock}} = \frac{1}{N-1}\sum_{j \neq i} \mathbf{x}_j$ (群れ重心)

**Alignment (整列力)**:
$$
\mathbf{F}_a = w_a \cdot (\bar{\mathbf{v}}_{\text{neighbors}} - \mathbf{v}_i)
$$
where $\bar{\mathbf{v}}_{\text{neighbors}} = \frac{1}{|N_i|}\sum_{j \in N_i} \mathbf{v}_j$ (隣接個体の平均速度)

**Separation (分離力)**:
$$
\mathbf{F}_s = w_s \cdot \sum_{j \in N_i^{\text{close}}} \frac{\mathbf{x}_i - \mathbf{x}_j}{\|\mathbf{x}_i - \mathbf{x}_j\|^2}
$$
where $N_i^{\text{close}} = \{j : \|\mathbf{x}_i - \mathbf{x}_j\| < 1.0 \text{m}\}$

**Dog Avoidance (逃避力)**:
$$
\mathbf{F}_d = w_d \cdot \frac{\mathbf{x}_i - \mathbf{x}_{\text{dog}}}{\|\mathbf{x}_i - \mathbf{x}_{\text{dog}}\|^2} \quad \text{if } \|\mathbf{x}_i - \mathbf{x}_{\text{dog}}\| < 5.0 \text{m}
$$

**Boids パラメータ** (Baseline):
- $w_c = 0.5$ (凝集)
- $w_a = 0.3$ (整列)
- $w_s = 1.0$ (分離)
- $w_d = 2.0$ (Dog回避)

**Sheep の dynamics** (2次系):
$$
m_{\text{sheep}} \dot{\mathbf{v}}_i = \mathbf{F}_{\text{sheep},i} - c_d \|\mathbf{v}_i\| \mathbf{v}_i
$$

where $m_{\text{sheep}} = 50$ kg

---

### 3.3 Dog-Sheep Interaction の数理

#### Dog の SPM に含まれる情報

Dog の視野内に Sheep $j$ が存在する場合、SPM に以下が encode される:

**位置情報** (極座標):
$$
\rho_j = \log(\|\mathbf{x}_j - \mathbf{x}_{\text{dog}}\| + 1), \quad \theta_j = \text{atan2}(y_j - y_{\text{dog}}, x_j - x_{\text{dog}}) - \theta_{\text{dog}}
$$

**SPM値** (簡略化):
$$
\text{SPM}(\rho, \theta) = \sum_{j \in \text{visible}} \exp\left(-\frac{(\rho - \rho_j)^2 + (\theta - \theta_j)^2}{2\sigma_{\text{SPM}}^2}\right)
$$

where $\sigma_{\text{SPM}}$ は SPM の空間分解能

#### Sheep の反応予測

Dog が行動候補 $u$ を評価する際、VAE は以下を予測:

1. **Dog の次状態**: $s_{\text{dog,pred}}(u)$
2. **Dog の次SPM**: $\text{SPM}_{\text{dog,pred}}(u)$

VAE は学習により、以下を暗黙的に予測:
- Dog が接近 → Sheep が逃避 → SPM で Sheep の移動を観測
- Dog が離れる → Sheep が緩慢 → SPM で Sheep の停滞を観測

**重要**: Dog の Goal Term は **進捗速度のみ** に依存するため、Sheep の具体的な配置には非依存。Safety Term を通じて Sheep との相互作用を制御。

---

### 3.4 適応メカニズムの数理的説明

#### Sheep の Boids パラメータ変化

**Phase 1 → Phase 2** (凝集力低下: $w_c: 0.5 \to 0.2$):

Sheep の凝集力が低下すると:
$$
\mathbf{F}_c^{\text{new}} = 0.4 \cdot \mathbf{F}_c^{\text{old}}
$$

→ 群れがバラける

**Dog の SPM 変化**:
$$
\text{SPM}_{\text{dog}}^{\text{Phase 2}} : \text{Sheep が広範囲に分散}
$$

**Dog の Safety Term への影響**:
$$
\Phi_{\text{safety}}^{\text{dog}} = \sum_{\rho,\theta} \Pi(\rho,\theta) \cdot \text{SPM}_{\text{pred}}(\rho,\theta)
$$

分散した Sheep → SPM の広範囲にわたって値が増加 → Safety Term が増加

**Dog の適応行動**:
- Safety Term を低減するため、分散した Sheep に接近
- 端の Sheep を群れ中心に押し戻す
- 結果: 群れが再凝集

**適応時間**: $\Delta t_{\text{adapt}} < 5$ 秒（予測）

#### Phase 2 → Phase 3 (逃避力低下: $w_d: 2.0 \to 1.0$):

Sheep の Dog 回避力が低下:
$$
\mathbf{F}_d^{\text{new}} = 0.5 \cdot \mathbf{F}_d^{\text{old}}
$$

→ Sheep が Dog に接近しても逃げにくい

**Dog の SPM 変化**:
$$
\text{SPM}_{\text{dog}}^{\text{Phase 3}} : \text{Sheep との距離が減少}
$$

**Dog の Safety Term への影響**:
近距離の Sheep → SPM の近距離領域（小さい $\rho$）で値が増加

**Dog の適応行動**:
- Safety Term の増加を抑えるため、Sheep との距離を調整
- 距離を保ちながら圧力をかける
- Goal Term（進捗速度）は変わらないため、北進は継続

---

## 自由エネルギーの統一性と多様性

### 統一的な構造

全シナリオで共通の自由エネルギー形式:
$$
F(u) = w_{\text{goal}} \cdot \Phi_{\text{goal}}(u) + w_{\text{safety}} \cdot \Phi_{\text{safety}}(u) + w_{\text{entropy}} \cdot S(u)
$$

**Goal Term の統一形式**:
$$
\Phi_{\text{goal}}(u) = \frac{(P_{\text{pred}}(u) - P_{\text{target}})^2}{2\sigma_P^2}
$$
where $P_{\text{pred}}(u) = \mathbf{v}_{\text{pred}}(u) \cdot \mathbf{d}_{\text{goal}}$

**Safety Term の統一形式**:
$$
\Phi_{\text{safety}}(u) = \sum_{\rho,\theta} \Pi(\rho,\theta) \cdot \text{SPM}_{\text{pred}}(u; \rho,\theta)
$$

### シナリオごとの差異

| 項 | Scramble | Corridor | Sheepdog |
|----|----------|----------|----------|
| **d_goal** | 4方向 (E/W/N/S) | 2方向 (E/W) | 1方向 (N) |
| **P_target** | 1.0 m/s | 1.0 m/s | 1.0 m/s |
| **Π 変調** | なし (α=0) | 壁近傍 (γ=2.0) | なし |
| **Self-hazing β** | 0/1.0/2.0 (評価) | 1.0 (固定) | 1.0 (固定) |
| **エージェント** | 全て EPH | 全て EPH | Dog=EPH, Sheep=Boids |

---

## 実装上の注意点

### Precision の計算

**基本形**:
$$
\Pi(\rho,\theta; \mathbf{x}, t) = \frac{1}{H_{\text{total}}(\rho,\theta; \mathbf{x}, t) + \epsilon}
$$

**Total Haze**:
$$
H_{\text{total}} = H_{\text{spatial}}(\rho) \cdot (1 + \alpha \cdot H_{\text{env}}(\mathbf{x})) \cdot (1 + \beta \cdot (1 - A(t)))
$$

**Corridor での修正** (Precision増大):
$$
\Pi(\rho,\theta; \mathbf{x}) = \frac{1 + \gamma \cdot P_{\text{env}}(\mathbf{x})}{H_{\text{spatial}}(\rho) \cdot (1 + \beta(1-A)) + \epsilon}
$$

### 数値安定性

1. **ゼロ除算回避**: $\epsilon = 10^{-6}$
2. **角度正規化**: $\theta \in [-\pi, \pi]$ (atan2使用)
3. **速度閾値**: $\|\mathbf{v}\| > 0.1$ で heading 更新

### VAE 予測

**入力**:
- Current SPM: $\text{SPM}_t \in \mathbb{R}^{16 \times 16 \times 3}$
- Current state: $s_t = [x, y, v_x, v_y, \theta] \in \mathbb{R}^5$
- Action candidate: $u = [F_x, F_y] \in \mathbb{R}^2$

**出力**:
- Predicted state: $s_{t+1} = [x', y', v_x', v_y', \theta'] \in \mathbb{R}^5$
- Predicted SPM: $\text{SPM}_{t+1} \in \mathbb{R}^{16 \times 16 \times 3}$

---

## まとめ

### 自由エネルギーの設計原則

1. **理論的厳密性**: Active Inference (Friston 2010, 2015) に完全準拠
2. **進捗速度ベース Goal**: 座標ではなく方向で目標を表現
3. **Precision変調**: Environmental Haze と Self-hazing の統合
4. **離散探索**: 100候補の自由エネルギー評価 (自動微分ではない)

### シナリオ横断的な統一性

- **Goal Term**: 全シナリオで進捗速度ベース
- **Safety Term**: SPM + Precision の統一形式
- **Smoothness Term**: 制御力の2乗ペナルティ

### シナリオ固有の設計

- **Scramble**: Self-hazing の効果評価
- **Corridor**: Environmental Haze (Precision増大) の効果評価
- **Sheepdog**: 進捗速度ベース Goal の異種協調への適用

この設計により、EPH は **統一的な理論基盤** の下で **多様なシナリオ** に適用可能であることが示される。

---

**バージョン**: 7.2.0
**作成日**: 2026-01-14
**対応ファイル**:
- `proposal_v7.0_revised.md`
- `scenarios_detailed_description.md`
