# EPH v7.0: 3シナリオの詳細説明

**バージョン**: 7.2.0
**作成日**: 2026-01-14
**目的**: 各検証シナリオの環境設定、エージェント行動、期待される創発パターンを詳細に記述

---

## 概要

EPH v7.0 では、以下の3つの異質なシナリオで検証を行う：

1. **Scramble Crossing** (スクランブル交差点): 創発度の評価
2. **Narrow Corridor** (狭い廊下): Environmental Haze の効果検証
3. **Sheepdog Herding** (牧羊犬による群れ誘導): 異種エージェント協調

各シナリオは異なる課題を提起し、EPH の汎用性と転移学習能力を評価する。

---

## Scenario 1: Scramble Crossing (スクランブル交差点)

### 1.1 シナリオの背景と動機

**実世界での対応**:
- 渋谷スクランブル交差点
- 大型イベント会場の交差エリア
- 駅構内の交差通路

**課題**:
- 4方向から同時に進入するエージェント
- 衝突回避と効率的な通行の両立
- 中央での「デッドロック」回避

**EPH で検証したいこと**:
- 2次系動力学による **Lane Formation** の自然な創発
- Self-hazing による探索的行動の促進
- 1次系との創発度の定量的比較

---

### 1.2 環境設定

#### 空間構成
```
        North (5 agents)
             ↓
             ↓
West ← ← ← [中央] → → → East
(5 agents)  交差点  (5 agents)
             ↑
             ↑
        South (5 agents)
```

**詳細パラメータ**:
- **空間サイズ**: 10m × 10m の平面
- **中央交差点**: 半径 2m の円形領域
- **エージェント数**: N = 20 (各方向5エージェント)
- **初期配置**:
  - North側: (x ∈ [-1, 1], y = 5) にランダム配置
  - South側: (x ∈ [-1, 1], y = -5) にランダム配置
  - East側: (x = 5, y ∈ [-1, 1]) にランダム配置
  - West側: (x = -5, y ∈ [-1, 1]) にランダム配置
- **初期速度**: 全エージェント v = 0 (静止状態)

#### 目標方向の設定

各エージェントには固定方向ベクトル `d_goal` を割り当て：

```python
# North → South
d_goal_NS = np.array([0, -1])  # 南向き

# South → North
d_goal_SN = np.array([0, 1])   # 北向き

# East → West
d_goal_EW = np.array([-1, 0])  # 西向き

# West → East
d_goal_WE = np.array([1, 0])   # 東向き
```

**重要**: 目標は「座標」ではなく「方向」。エージェントは指定方向に進み続ける。

#### Environmental Haze の設定

**Baseline条件** (創発度評価用):
```python
H_env(x, y) = 0.0  # 全領域で均一（Environmental Hazeなし）
α = 0.0            # Environmental Haze係数なし
```

**理由**: Scramble は創発度のベースライン評価が目的。Environmental Haze の効果は Corridor で検証。

#### Haze パラメータ

| Condition | α | β | 説明 |
|-----------|---|---|------|
| **C1 (No Haze)** | 0.0 | 0.0 | 距離ベースHazeのみ（比較用） |
| **C2 (Self-hazing)** | 0.0 | 1.0 | Self-hazingあり |
| **C3 (Full Haze)** | 0.0 | 2.0 | Self-hazing強（探索促進） |

---

### 1.3 エージェントの行動

#### 初期状態 (t=0)

全エージェントは静止状態から、目標方向に向かって加速を開始：

```
t=0s:  全エージェント静止
       ↓
t=1s:  各方向から中央に向かって移動開始
       ↓
t=3s:  中央交差点で4方向のエージェントが交錯
       ↓
t=5-10s: Lane Formation が創発
       ↓
t=15s: ほぼ全エージェントが通過
```

#### 期待される行動パターン

**2次系 EPH (本研究)**:
1. **加速フェーズ** (0-2s):
   - 慣性により徐々に加速
   - Goal Term により目標方向への進捗を最大化

2. **交差フェーズ** (2-5s):
   - Safety Term により他エージェントを回避
   - 慣性により「曲がりにくい」→ 直進を維持

3. **Lane Formation 創発** (5-10s):
   - 同方向エージェントが自然に整列
   - 対向エージェントとは「レーン」を形成して分離
   - **物理制約から創発** (計算的最適化ではない)

4. **定常フェーズ** (10-15s):
   - Lane が安定して維持される
   - 滑らかな流れ (Flow Smoothness > 0.8)

**1次系ベースライン (比較用)**:
1. 瞬時に方向転換可能 → ジグザグな軌道
2. Lane Formation は弱い（最適化の結果に過ぎない）
3. Flow Smoothness 低 (≈ 0.65)

#### Self-hazing の効果

**C1 (β=0.0, Self-hazingなし)**:
- 予測失敗時も探索しない
- デッドロック発生頻度高
- 中央で「膠着状態」

**C2 (β=1.0)**:
- 予測失敗 → Haze増大 → 探索的行動
- デッドロック回避可能
- Path diversity 増加

**C3 (β=2.0)**:
- さらに探索的
- 多様な経路選択
- ただし効率は若干低下（探索コスト）

---

### 1.4 期待される創発パターン

#### Lane Formation (レーン形成)

**定義**:
同方向に移動するエージェントが自然に整列し、対向エージェントとは異なる「レーン」を形成する現象。

**創発メカニズム**:
```
慣性により直進を維持
    ↓
同方向エージェントと速度が近い
    ↓
Safety Term により一定距離を保つ
    ↓
結果: 自然な整列（Lane）
```

**定量評価**:
- **Lane幅の標準偏差**: σ_lane < 0.5m
- **Lane持続時間**: > 10秒
- **Lane内エージェント数**: > 3

#### Laminar Flow (層流)

**定義**:
各Laneが滑らかに流れる状態。エージェントの急激な方向転換がない。

**定量評価**:
- **Flow Smoothness**: $S = 1 - \frac{1}{N}\sum_i \|\Delta\theta_i\|_{\text{avg}} > 0.8$
- **速度の標準偏差**: σ_v < 0.3 m/s (Lane内)

#### Emergence Index (創発度)

**定義**:
集団レベルの秩序が、個体レベルの行動から予測できない程度。

**計算式**:
$$
\text{EI} = \frac{H_{\text{collective}} - \sum_i H_{\text{individual},i}}{H_{\text{collective}}}
$$

**期待値**:
- **2次系 EPH**: EI ≈ 0.6 ± 0.1
- **1次系**: EI ≈ 0.2 ± 0.1
- **統計的有意性**: p < 0.01 (t-test, n=30 runs)

---

### 1.5 評価指標

#### Primary Metric

1. **Emergence Index (EI)**: > 0.5
2. **Task Success Rate (TSR)**: > 0.85
   - 成功 = エージェントが交差点を通過し、10m移動

#### Secondary Metrics

1. **Flow Smoothness**: > 0.8
2. **Collision Rate**: < 0.05
3. **Lane Formation Stability**: > 10秒
4. **Average Speed**: > 0.8 m/s

#### 実験条件

- **試行回数**: 30 runs per condition
- **シミュレーション時間**: 20秒
- **比較対象**: 1次系 EPH, Social Force Model, Boids

---

## Scenario 2: Narrow Corridor (狭い廊下)

### 2.1 シナリオの背景と動機

**実世界での対応**:
- 駅構内の通路
- 病院・学校の廊下
- イベント会場の出入口

**課題**:
- 壁への衝突回避
- 対向流の効率的なすれ違い
- 狭い空間での Lane Formation

**EPH で検証したいこと**:
- **Environmental Haze** の効果実証
- 壁近傍での注意増大による衝突削減
- Scramble からの **転移学習性能**

---

### 2.2 環境設定

#### 空間構成

```
┌─────────────────────────────────┐ ← 上壁 (y=2.5)
│                                 │
│  ← ← ← ← ← ← ← ← ← ← ← ← ← ←  │ (Left agents, 7-8人)
│                                 │
│  → → → → → → → → → → → → → →  │ (Right agents, 7-8人)
│                                 │
└─────────────────────────────────┘ ← 下壁 (y=-2.5)
  x=-10              x=0          x=10
```

**詳細パラメータ**:
- **空間サイズ**: 20m × 5m
- **壁の位置**:
  - 上壁: y = 2.5
  - 下壁: y = -2.5
- **エージェント数**: N = 15
  - 右側 (East向き): 7人, 初期位置 x ∈ [-10, -8], y ∈ [-2, 2]
  - 左側 (West向き): 8人, 初期位置 x ∈ [8, 10], y ∈ [-2, 2]
- **初期速度**: v = 0.5 m/s (微速前進)

#### 目標方向の設定

```python
# 右側エージェント: 東向き
d_goal_right = np.array([1, 0])

# 左側エージェント: 西向き
d_goal_left = np.array([-1, 0])
```

#### Environmental Haze の設計

**核心アイデア**: 壁近傍で Haze を**低下**させ、Precision を**増大**させる。

```python
def H_env_corridor(x, y):
    """
    壁近傍で注意増大 (Haze低下)
    """
    wall_top = 2.5
    wall_bottom = -2.5
    wall_margin = 0.5  # 壁から0.5m以内

    if abs(y - wall_top) < wall_margin:
        return 0.2  # 上壁近傍: Haze低 → Precision高
    elif abs(y - wall_bottom) < wall_margin:
        return 0.2  # 下壁近傍: Haze低 → Precision高
    else:
        return 0.0  # 中央: 通常
```

**Precision への影響**:
```python
# 壁近傍 (H_env=0.2, α=2.0):
H_total = H_spatial · (1 + 2.0 × 0.2) · (1 + β(1-A))
        = H_spatial · 1.4 · (...)

Π = 1 / (H_total + ε)  # Haze増加 → Precision低下...待って！

# 実は逆！H_env=0.2 は「Haze基準値からの減少分」として設計
# 正しい解釈:
H_total = H_spatial · (1 - 0.2) · (1 + β(1-A))  # 壁近傍で Haze 減少
Π_wall > Π_center  # 壁近傍で Precision 増大
```

**修正された設計**:
Environmental Haze を「Precision増大フィールド」として再定義：

```python
# 壁近傍で Precision を直接増大
Π(x, y) = Π_base / (H_spatial(ρ) + ε) × (1 + γ · P_env(x, y))

where:
P_env(x, y) = 1.0  if |y - wall| < 0.5  (壁近傍)
            = 0.0  otherwise
γ = 2.0  # Precision増大係数
```

これにより：
- 壁近傍: Π = 3 × Π_base (3倍の注意)
- 中央: Π = Π_base (通常)

#### 実験条件

| Condition | P_env | γ | 説明 |
|-----------|-------|---|------|
| **C1 (Baseline)** | 0.0 (uniform) | 0.0 | Environmental効果なし |
| **C2 (Wall Precision)** | 1.0 (near walls) | 2.0 | 壁近傍で注意増大 |
| **C3 (Center Precision)** | 1.0 (center) | 2.0 | 中央で注意増大（対照実験） |

---

### 2.3 エージェントの行動

#### 期待される行動パターン

**C1 (Baseline, Environmental効果なし)**:
1. 壁近傍でも注意が低い
2. 壁衝突頻発 (CR ≈ 0.15)
3. Lane Formation 弱

**C2 (Wall Precision増大)**:
1. 壁近傍で Safety Term の重みが増加
2. 壁からの予測的回避
3. 壁衝突激減 (CR ≈ 0.05, **67% reduction**)
4. 中央に2つの Lane が形成

**C3 (Center Precision増大, 対照実験)**:
1. 中央で過度に慎重
2. 渋滞発生
3. 壁衝突は増加 (性能劣化の実証)

#### Lane Formation in Corridor

**2-Lane System**:
```
┌─────────────────────────────────┐
│          ↑ ↑ ↑ ↑ ↑ ↑           │ Lane 1 (West向き)
│                                 │
│          ↓ ↓ ↓ ↓ ↓ ↓           │ Lane 2 (East向き)
└─────────────────────────────────┘
```

**特徴**:
- 各Laneは壁から 0.5-1.0m の距離を保つ
- Lane間距離: 1.5-2.0m
- 対向エージェントとのすれ違いが滑らか

---

### 2.4 転移学習評価

#### プロトコル

1. **Phase 1: Scramble で学習**
   - VAE を Scramble シナリオのデータで学習
   - 学習データ: 1000 episodes, 10 agents per episode

2. **Phase 2: VAE 凍結**
   - VAE のパラメータを固定（再学習なし）
   - Precision modulator のみ更新可能

3. **Phase 3: Corridor で直接使用**
   - Environmental Haze のみ変更 (`P_env` を設定)
   - Goal Term は同一形式（進捗速度ベース）

#### Transfer Success Rate (TSR)

**定義**:
$$
\text{TSR}_{\text{transfer}} = \frac{\text{Task Success Rate}_{\text{transfer}}}{\text{Task Success Rate}_{\text{native}}}
$$

where:
- TSR_native: Corridor で学習したモデルの性能
- TSR_transfer: Scramble から転移したモデルの性能

**目標**: TSR_transfer > 0.8 (ネイティブの80%以上)

**期待値**: TSR_transfer ≈ 0.87

**解釈**:
- TSR > 0.8: 高い転移性能、汎用性あり
- TSR < 0.5: 転移失敗、シナリオ特化的

---

### 2.5 評価指標

#### Primary Metric

1. **Collision Reduction**: > 30%
   $$
   \text{CR}_{\text{reduction}} = \frac{\text{CR}_{\text{baseline}} - \text{CR}_{\text{wall precision}}}{\text{CR}_{\text{baseline}}} \times 100\%
   $$

2. **Transfer Success Rate**: > 0.8

#### Secondary Metrics

1. **Throughput**: エージェント数/分
2. **Flow Efficiency**: 平均速度 / 最大速度
3. **Wall Distance**: 壁からの平均距離 > 0.5m

---

## Scenario 3: Sheepdog Herding (牧羊犬による群れ誘導)

### 3.1 シナリオの背景と動機

**実世界での対応**:
- 牧羊犬による羊の誘導
- 群衆誘導（イベント会場、避難誘導）
- ドローンによる群れ制御

**課題**:
- 異種エージェントの協調（Dog vs. Sheep）
- Dog は Sheep の挙動を予測して行動
- Sheep の特性変化への適応

**EPH で検証したいこと**:
- **Heterogeneous Active Inference** の実証
- 進捗速度ベース Goal Term の有効性
- 明示的な再学習なしでの適応能力

---

### 3.2 環境設定

#### 空間構成

```
┌─────────────────────────────────┐
│                                 │
│         Target Zone (北側)       │
│           ⊙ (半径2m)            │
│                                 │
│                                 │
│       🐑 🐑 🐑                  │
│     🐑  🐑  🐑 🐑               │ Sheep群 (10頭)
│       🐑 🐑 🐑                  │
│                                 │
│                                 │
│                   🐕            │ Dog (1頭)
│                                 │
└─────────────────────────────────┘
     15m × 15m
```

**詳細パラメータ**:
- **空間サイズ**: 15m × 15m
- **Target Zone**: 中心 (0, 10), 半径 2m の円形領域
- **エージェント構成**:
  - Sheep: N_sheep = 10
  - Dog: N_dog = 1
- **Sheep 初期配置**: 中心 (0, 0) 付近にランダム分散 (半径3m内)
- **Dog 初期配置**: Sheep群の南側 (0, -5)
- **初期速度**: 全て v = 0

#### 目標の設定

**Dog の目標**:
```python
# 群れを北方向に押す
d_push = np.array([0, 1])  # 北向き

# Dog の Goal: 北方向への進捗速度を維持
P_dog_target = 1.0  # m/s
```

**重要**: Dog の目標は「群れの重心を Target Zone に入れる」ではなく、「北方向に進捗し続ける」。これにより：
- 群れの具体的な配置に依存しない
- SPM から観測される群れ情報で行動調整
- 適応的な herding が可能

**Sheep の目標**:
- Sheep は EPH ではなく **Boids** で駆動
- 目標なし（Dog から逃避するのみ）

---

### 3.3 エージェントの行動設計

#### 3.3.1 Dog Agent (EPH-driven)

**Goal Term** (進捗速度ベース):
```python
def dog_goal_term(v_dog, d_push):
    """
    Dog の Goal: 北方向への進捗速度を維持
    """
    P_dog = np.dot(v_dog, d_push)  # 進捗速度
    P_target = 1.0  # m/s
    sigma_P = 0.5  # m/s

    return (P_dog - P_target)**2 / (2 * sigma_P**2)
```

**Safety Term** (SPMベース):
```python
def dog_safety_term(spm_pred, precision_map):
    """
    Dog の Safety: 予測SPMに基づく安全性評価

    SPMには以下が含まれる:
    - Sheep の位置・密度
    - Sheep の移動方向
    - 群れの形状（広がり）
    """
    Phi_safety = 0
    for rho in range(16):
        for theta in range(16):
            Π = precision_map[rho, theta]
            Phi_safety += Π * spm_pred[rho, theta]

    return Phi_safety
```

**行動選択**:
Dog は100個の行動候補 `u = [Fx, Fy]` を評価し、自由エネルギーが最小となる行動を選択。

**Dog の戦略** (創発的に獲得):
1. Sheep群の南側に位置を保つ
2. Sheep が逃げる方向 = 北 → 目標方向と一致
3. 群れが広がりすぎたら、端の Sheep に接近
4. 群れ全体を「圧力」で押す感覚

#### 3.3.2 Sheep Agent (Boids-driven)

**Boids アルゴリズム**:
```python
class SheepAgent:
    def __init__(self, boids_params):
        self.w_cohesion = boids_params['w_cohesion']      # 群れの中心へ
        self.w_alignment = boids_params['w_alignment']     # 隣接個体の速度に整合
        self.w_separation = boids_params['w_separation']   # 近接個体から離反
        self.w_dog_avoidance = boids_params['w_dog_avoid'] # Dog から逃避

    def compute_force(self, other_sheep, dog_position):
        # 1. Cohesion: 群れ中心へ向かう
        centroid = np.mean([s.position for s in other_sheep], axis=0)
        F_cohesion = self.w_cohesion * (centroid - self.position)

        # 2. Alignment: 隣接個体の速度に整合
        neighbors = [s for s in other_sheep if distance(s, self) < 3.0]
        avg_velocity = np.mean([s.velocity for s in neighbors], axis=0)
        F_alignment = self.w_alignment * (avg_velocity - self.velocity)

        # 3. Separation: 近接個体から離反
        F_separation = np.zeros(2)
        for s in other_sheep:
            d = self.position - s.position
            dist = np.linalg.norm(d)
            if dist < 1.0:  # 1m以内
                F_separation += self.w_separation * d / (dist**2)

        # 4. Dog Avoidance: Dog から逃避
        d_dog = self.position - dog_position
        dist_dog = np.linalg.norm(d_dog)
        if dist_dog < 5.0:  # Dog が5m以内
            F_dog_avoid = self.w_dog_avoidance * d_dog / (dist_dog**2)
        else:
            F_dog_avoid = np.zeros(2)

        # Total force
        F_total = F_cohesion + F_alignment + F_separation + F_dog_avoid

        return F_total
```

**Boids パラメータ** (Baseline):
```python
boids_params_baseline = {
    'w_cohesion': 0.5,
    'w_alignment': 0.3,
    'w_separation': 1.0,
    'w_dog_avoidance': 2.0
}
```

#### 3.3.3 Dynamics

**Dog と Sheep の共通 dynamics** (2次系):
```python
# 並進
m·dvx/dt = Fx - cd·|v|·vx
m·dvy/dt = Fy - cd·|v|·vy

# Heading追従
dθ/dt = k_align · angle_diff(atan2(vy, vx), θ)
```

**パラメータ**:
- Dog: m=30kg (中型犬)
- Sheep: m=50kg (羊)

---

### 3.4 適応メカニズム

#### Sheep の特性変化

**実験**: Sheep の Boids パラメータを途中で変更

| Phase | Time | w_cohesion | w_dog_avoid | Sheep の挙動 |
|-------|------|------------|-------------|--------------|
| **Phase 1** | 0-20s | 0.5 | 2.0 | 通常の群れ行動 |
| **Phase 2** | 20-40s | **0.2** | 2.0 | 群れがバラバラに（凝集力低下） |
| **Phase 3** | 40-60s | 0.5 | **1.0** | Dog への恐怖減少（逃避力低下） |

#### Dog の適応

**Dog は再学習なし**で以下のように適応：

**Phase 1 → Phase 2** (群れがバラける):
```
Sheep の凝集力低下
    ↓
群れが広範囲に分散
    ↓
Dog の SPM に分散した Sheep が観測される
    ↓
Dog は Safety Term により、分散した Sheep に反応
    ↓
Dog は群れの「端」に接近して圧力をかける
    ↓
群れが再び凝集（Dog の圧力により）
```

**Phase 2 → Phase 3** (逃避力低下):
```
Sheep の Dog回避力低下
    ↓
Sheep が Dog に接近しても逃げない
    ↓
Dog の SPM で Sheep との距離が近いことを検知
    ↓
Dog は Safety Term により、Sheep に近づきすぎないよう調整
    ↓
Dog は距離を保ちながら押し続ける
```

**適応時間**: < 5秒（予測）

**メカニズムの本質**:
- Dog の Goal Term は「進捗速度」のみに依存（群れの配置に非依存）
- Safety Term が SPM を通じて群れ情報を取得
- 予測 SPM により、行動候補ごとに群れの反応を予測
- **結果**: 群れの特性が変化しても、適応的に herding 可能

---

### 3.5 期待される行動パターン

#### 3.5.1 初期フェーズ (0-10s)

**Dog**:
1. 南側から群れに接近
2. Sheep群 の南側に位置取り

**Sheep**:
1. Dog を検知 → 北方向に逃避
2. 群れ全体が北に移動開始

**創発パターン**:
- Sheep群 が自然に「群れ」として行動
- Dog の存在が「圧力」として機能

#### 3.5.2 誘導フェーズ (10-40s)

**Dog**:
1. 群れの南側を維持しながら北進
2. 群れが広がったら、端の Sheep に接近
3. Goal Term により、北方向への進捗を維持

**Sheep**:
1. Dog から逃避しつつ、群れの凝集を維持
2. Target Zone に徐々に接近

**創発パターン**:
- Dog と Sheep の「追跡-逃避」の動的平衡
- 群れ全体が北方向に「流れる」

#### 3.5.3 目標達成 (40-60s)

**成功条件**:
- 80%以上の Sheep が Target Zone 内 (半径2m以内)
- Dog は群れを Zone 内に維持

**Dog の行動**:
- Target Zone 周辺で Sheep を囲む
- Sheep が Zone から出ようとしたら押し戻す

---

### 3.6 評価指標

#### Primary Metric

**Herding Success Rate (HSR)**:
$$
\text{HSR} = \begin{cases}
1 & \text{if } \frac{N_{\text{in target}}}{N_{\text{sheep}}} > 0.8 \text{ within } T_{\max} \\
0 & \text{otherwise}
\end{cases}
$$

where:
- N_in_target: Target Zone内のSheep数
- T_max = 60秒

**目標**: HSR > 0.75 (30 episodes平均)

#### Secondary Metrics

1. **Herding Time**: 目標達成までの時間 (短いほど良い)
2. **Flock Cohesion**:
   $$
   \text{Cohesion} = 1 - \frac{\sigma_{\text{flock}}}{d_{\max}}
   $$
   where σ_flock は群れ内の位置分散

3. **Dog Efficiency**:
   $$
   \text{Efficiency} = \frac{\text{Flock displacement}}{\text{Dog displacement}}
   $$
   (Dog が少ない移動で群れを動かせるほど効率的)

4. **Adaptation Speed**: Boids パラメータ変更後、性能が回復するまでの時間

---

### 3.7 Heterogeneous Active Inference の検証

#### 検証仮説

**H1**: Dog の EPH は Sheep (Boids) と協調可能
- **検証**: HSR > 0.75

**H2**: Sheep の特性変化に適応可能（再学習なし）
- **検証**: Phase変更後、適応時間 < 5秒

**H3**: 進捗速度ベース Goal Term の有効性
- **検証**: 群れ配置が変化しても、Goal Term は安定

#### 比較ベースライン

1. **RL-based Dog** (PPO):
   - Sheep の Boids パラメータで学習
   - パラメータ変更時に再学習が必要

2. **Rule-based Dog**:
   - 「群れ重心に向かう」ヒューリスティック
   - 適応力なし

**期待**: EPH-Dog が両者を上回る

---

## 3シナリオの比較

| 側面 | Scramble | Corridor | Sheepdog |
|------|----------|----------|----------|
| **主要評価項目** | 創発度 (EI) | Environmental Haze効果 | 異種協調 |
| **エージェント数** | 20 (均質) | 15 (均質) | 11 (異種) |
| **Goal Term** | 進捗速度 | 進捗速度 | 進捗速度 |
| **H_env** | 均一 (0.0) | 壁近傍で変調 | （Optional） |
| **Self-hazing** | β変化で評価 | β=1.0固定 | β=1.0固定 |
| **期待される創発** | Lane Formation | 2-Lane System | 追跡-逃避平衡 |
| **転移学習** | 学習元 | 転移先 | - |
| **新規性** | 慣性誘導型創発 | 設計者制御Haze | Heterogeneous AI |

---

## まとめ

### 3シナリオの役割

1. **Scramble**: EPH の核心（慣性による創発）を実証
2. **Corridor**: Environmental Haze の設計者制御を実証
3. **Sheepdog**: 異種エージェント・適応能力を実証

### 統一性

- 全シナリオで **進捗速度ベース Goal Term** を使用
- VAE アーキテクチャは共通
- 物理ダイナミクス (Model A) は共通

### 多様性

- 環境構造が異なる（交差点 vs 廊下 vs 広場）
- Environmental Haze の設計が異なる
- エージェント構成が異なる（均質 vs 異種）

この統一性と多様性により、EPH の **汎用性** と **転移学習能力** を包括的に評価できる。

---

**バージョン**: 7.2.0
**作成日**: 2026-01-14
**対応 Proposal**: `proposal_v7.0_revised.md`
