# 視野角を考慮したHeading制御の再検討

## 重要な指摘

> "視野角が重要なファクターですので，heading 決定は重要です。"

これは**本質的な修正**が必要です。

### なぜHeadingが重要か

```
SPM = VAE_encoder(visual_input(position, heading, FoV))
```

- **Heading θ が視野の中心方向を決定**
- FoV（例：180°）内の障害物・エージェント情報がSPMに符号化
- Heading が変わる → 見える情報が変わる → SPMが変わる → 行動選択が変わる

**つまり**：Headingは知覚システムの入力であり、単なる「結果」ではない

---

## 修正された Formulation

### Option B' (修正版): Heading を制御可能にする

#### 状態空間
```
s = [x, y, vx, vy, θ, ω] ∈ ℝ⁶
```
- `(x, y)`: 位置
- `(vx, vy)`: 速度ベクトル
- `θ`: Heading角度（**視野方向を決定**）
- `ω`: 角速度

#### 制御入力
```
u = [Fx, Fy, τ] ∈ ℝ³
```
- `(Fx, Fy)`: 並進力（全方向）
- `τ`: トルク（**heading を能動的に制御**）

#### 運動方程式
```python
# 並進運動（全方向）
m·dvx/dt = Fx - cd·|v|·vx
m·dvy/dt = Fy - cd·|v|·vy

# 回転運動（独立制御）
I·dω/dt = τ - cr·ω
dθ/dt = ω
```

#### **重要な変更点**

以前の提案では：
- Heading は速度方向に「自動追従」（受動的）
- `dθ/dt = k_align·(atan2(vy, vx) - θ)`

**新しい提案**：
- Heading は τ で**能動的に制御**
- エージェントは移動方向と視線方向を独立に選択可能
- 例：後退しながら前を見る、横移動しながら別方向を見る

---

## EPH Action Candidate の再設計

### 3次元制御空間

```python
def generate_action_candidates_3d():
    """
    100候補: 5方向 × 4力 × 5トルク = 100
    または
    120候補: 6方向 × 4力 × 5トルク = 120
    """
    # 並進力の方向
    angles_F = [0, π/3, 2π/3, π, 4π/3, 5π/3]  # 6方向（60°刻み）
    magnitudes_F = [0, 50, 100, 150]  # 4段階

    # トルク
    torques = [-0.5, -0.25, 0, 0.25, 0.5]  # 5段階

    candidates = []
    for angle in angles_F:
        for F_mag in magnitudes_F:
            for tau in torques:
                Fx = F_mag * np.cos(angle)
                Fy = F_mag * np.sin(angle)
                candidates.append([Fx, Fy, tau])

    return np.array(candidates)  # Shape: (120, 3)
```

### EPH評価ループ（離散探索）

```python
def select_action_eph_with_fov(spm_current, s_current, vae, params):
    """視野角を考慮したEPH行動選択"""

    candidates = generate_action_candidates_3d()  # 120個

    F_min = float('inf')
    u_best = None

    for u in candidates:
        # 状態予測（RK4）
        s_pred = dynamics_rk4(s_current, u, params['dt'], params)

        # 予測されたheadingで視野を計算
        theta_pred = s_pred[4]

        # 視野情報からSPM生成（VAE encoder）
        # ★ここでheadingが重要！
        visual_input = render_fov(
            position=s_pred[0:2],
            heading=theta_pred,  # 視野中心方向
            fov_angle=params['fov'],  # 例：180°
            obstacles=params['obstacles'],
            agents=params['agents']
        )

        # VAEでSPM予測
        spm_pred = vae.encode(visual_input)

        # Goal Term（速度ベース）
        v_pred = s_pred[2:4]
        P_pred = np.dot(v_pred, params['d_goal'])
        Phi_goal = (P_pred - params['P_target'])**2 / (2 * params['sigma_P']**2)

        # Safety Term（予測SPMベース）
        Phi_safety = compute_safety_term(spm_pred, params['precision'])

        # Smoothness Term
        S = params['lambda_smooth'] * (np.sum(u[:2]**2) + params['w_tau'] * u[2]**2)

        # Total Free Energy
        F_val = Phi_goal + Phi_safety + S

        if F_val < F_min:
            F_min = F_val
            u_best = u

    return u_best  # ✅ 離散探索
```

---

## Heading制御の戦略的意味

### 例1: スクランブル交差点

**シナリオ**：東に向かって移動中、後方から接近する人を確認したい

```python
# 候補A: 前を見ながら東へ
u_A = [Fx=100, Fy=0, τ=0]
→ 前方の障害物は見える、後方は見えない

# 候補B: 振り返りながら東へ
u_B = [Fx=100, Fy=0, τ=0.5]  # 頭を回転
→ 後方のエージェントをSPMで観測可能
→ 衝突回避の精度向上
```

**EPHの評価**：
- 候補Aは前方のSafety高、後方のSafety低
- 候補Bは後方をカバー、total free energyで比較

### 例2: 狭い廊下

**シナリオ**：前進しながら、壁際の障害物を注視

```python
# 右の壁を見ながら前進
u = [Fx=100·cos(0), Fy=100·sin(0), τ=0.3]
→ 視野を少し右にずらして壁際を監視
```

### 例3: シープドッグ

**シナリオ**：羊群を押しながら、群れ全体を視野に収める

```python
# 北に押しながら、群れの中心を見る
u = [Fx=-50, Fy=100, τ=adjust_to_see_centroid]
→ 移動方向（北）と視線方向（群れ中心）が異なる
→ 群れ全体をSPMで把握
```

---

## 修正された物理パラメータ

```python
params = {
    # 並進
    'mass': 70.0,           # kg
    'drag_coeff': 0.5,      # N·s²/m²
    'F_max': 150.0,         # N

    # 回転
    'inertia': 2.0,         # kg·m²（人体の慣性モーメント）
    'rot_resistance': 0.5,  # N·m·s（回転抵抗）
    'tau_max': 1.0,         # N·m（最大トルク）

    # 視野
    'fov': 180.0,           # degree（人間の視野角）

    # 時間
    'dt': 0.01              # s
}
```

### 回転パラメータの根拠

人間の頭部回転：
- 慣性モーメント I ≈ 0.01~0.03 kg·m²（頭部のみ）
- しかしエージェント全体なら I ≈ 2.0 kg·m²（体幹含む）
- 最大角速度 ω_max ≈ 2π rad/s（1秒で1回転）
- 時定数 τ_rot = I/c_r ≈ 4秒（自然な回転速度）

---

## VAE Architecture への影響

### Encoder Input

```python
# 視野ベースの入力生成
def render_fov(position, heading, fov_angle, obstacles, agents):
    """
    Returns: (H, W, C) image tensor
    - Center: heading direction
    - Range: [heading - fov/2, heading + fov/2]
    """
    image = np.zeros((64, 64, 3))

    for obs in obstacles:
        angle_to_obs = atan2(obs.y - position[1], obs.x - position[0])
        relative_angle = angle_diff(angle_to_obs, heading)

        # FoV内かチェック
        if abs(relative_angle) < fov_angle / 2:
            # 画像内の座標に変換
            pixel_x = int((relative_angle / (fov_angle/2) + 1) * 32)
            distance = np.linalg.norm(obs.pos - position)
            pixel_y = int(32 / distance)

            # 描画
            image[pixel_y, pixel_x, :] = [1, 0, 0]  # 障害物は赤

    # 同様にagentsも描画
    return image
```

### VAE Prediction

```python
# EPH loop内
for u in candidates:
    # 1. 物理状態予測（dynamics）
    s_pred = dynamics_rk4(s_current, u, dt, params)

    # 2. 予測headingで視野生成
    visual_pred = render_fov(
        position=s_pred[0:2],
        heading=s_pred[4],  # ★予測されたheading
        fov_angle=180,
        obstacles=obstacles,
        agents=agents
    )

    # 3. VAE encoderでSPM生成
    spm_pred = vae.encode(visual_pred)

    # 4. Free Energy評価
    F_val = evaluate_free_energy(s_pred, spm_pred, u, ...)
```

---

## 制御空間の次元削減戦略

120候補（6方向 × 4力 × 5トルク）は計算可能ですが、さらに効率化したい場合：

### Strategy 1: 階層的探索

```python
# Phase 1: 粗い探索（30候補）
candidates_coarse = generate_candidates(n_angles=6, n_F=5, n_tau=1)  # τ=0のみ
u_coarse = argmin_free_energy(candidates_coarse)

# Phase 2: 周辺の細かい探索（27候補）
candidates_fine = generate_around(u_coarse, delta_angle=15°, delta_F=25, delta_tau=0.2)
u_fine = argmin_free_energy(candidates_fine)

return u_fine
```

### Strategy 2: Heading優先度ベース

```python
# 視覚的な不確実性が高い場合、headingのバリエーションを増やす
if haze_total > threshold:
    n_tau = 7  # トルク候補を増やす
else:
    n_tau = 3  # 移動に集中
```

---

## Option B' vs Option A の比較

| 側面 | Option A (元) | Option B (前提案) | **Option B' (修正)** |
|------|---------------|-------------------|----------------------|
| 状態 | [x,y,vx,vy,θ,ω] | [x,y,vx,vy,θ] | **[x,y,vx,vy,θ,ω]** |
| 制御 | [F,τ] (heading方向の力) | [Fx,Fy] (全方向) | **[Fx,Fy,τ]** ✅ |
| 並進 | heading依存 ❌ | 全方向 ✅ | **全方向** ✅ |
| Heading制御 | トルク τ ✅ | 自動追従（受動） ❌ | **トルク τ** ✅ |
| 視野制御 | 可能 ✅ | 不可 ❌ | **可能** ✅ |
| 候補数 | 100 (5×20) | 100 (20×5) | **120 (6×4×5)** |
| 計算コスト | 中 | 低 | **中** |
| 視野角要件 | 対応 ✅ | 非対応 ❌ | **対応** ✅ |
| **推奨度** | ⚠️ 横滑り問題 | ❌ FoV要件違反 | **✅ 最適** |

---

## 実装コード（完全版）

```python
def dynamics_rk4_full(state, u, dt, params):
    """
    視野角を考慮した完全な6D dynamics

    state: [x, y, vx, vy, theta, omega]
    u: [Fx, Fy, tau]
    """
    m = params['mass']
    I = params['inertia']
    cd = params['drag_coeff']
    cr = params['rot_resistance']

    def f(s, u):
        x, y, vx, vy, theta, omega = s
        Fx, Fy, tau = u

        v_norm = np.sqrt(vx**2 + vy**2)

        return np.array([
            vx,                           # dx/dt
            vy,                           # dy/dt
            Fx/m - cd/m * vx * v_norm,    # dvx/dt（全方向力）
            Fy/m - cd/m * vy * v_norm,    # dvy/dt
            omega,                        # dtheta/dt
            tau/I - cr/I * omega          # domega/dt
        ])

    # RK4 integration
    k1 = f(state, u)
    k2 = f(state + dt/2 * k1, u)
    k3 = f(state + dt/2 * k2, u)
    k4 = f(state + dt * k3, u)

    new_state = state + dt/6 * (k1 + 2*k2 + 2*k3 + k4)

    # Theta を [-π, π] に正規化
    new_state[4] = np.arctan2(np.sin(new_state[4]), np.cos(new_state[4]))

    return new_state
```

---

## まとめ

### 重要な変更

1. **Heading は能動的制御変数**
   - τ（トルク）で制御
   - 視野方向を戦略的に選択可能

2. **制御入力は3次元**
   - `u = [Fx, Fy, τ]`
   - 移動方向と視線方向を独立制御

3. **EPH は 120候補を離散評価**
   - 自動微分ではない ✅
   - 各候補で予測headingに基づくSPM生成

4. **視野角がSafety Termに直接影響**
   - Heading → FoV → SPM → Φ_safety
   - Headingの選択が衝突回避精度を左右

### 次のステップ

この Option B' で proposal を更新してよろしいでしょうか？

修正が必要な主要セクション：
- Section 2.2: State Space Definition
- Section 2.3: Dynamics (6D, not 5D)
- Section 3.2: Action Candidate Generation (120 candidates)
- Section 3.3: VAE Architecture (FoV-based encoder)

ご確認ください。
