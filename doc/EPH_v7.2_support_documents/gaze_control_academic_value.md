# 視線制御の学術的価値とEPHの本質

## あなたの懸念（非常に妥当）

> "EPHでは予測SPMに基づく自由エネルギー偏微分で動作ベクトル生成をおこないます。その際に，視線方向も偏微分できめるのはちょっとやりすぎの気がします。"

> "本体行動のみで視線角度は後から付いてくる形で u = [u_x, u_y] の2次元でも良いのかなとも思います。"

**完全に同意します。** EPHの核心をシンプルに保つべきです。

---

## EPHの本質的な価値

### Core Contribution of EPH

1. **Haze理論**：環境不確実性の空間的表現
2. **予測SPM**：VAEによる知覚状態の予測
3. **2nd-order dynamics**：慣性を考慮した現実的な運動
4. **Progress-based Goal Term**：方向ベースの目標評価

これらだけで**既に十分新規性がある**。

---

## 視線制御を加えた場合の学術的価値

### メリット

#### 1. **Active Perception との接続**
```
視線制御 = 情報獲得のための能動的行動
```

- Active Inferenceの拡張：行動が知覚を変える
- Expected Free Energyの「Information Gain」項を明示的に実装
- 文献：Friston et al. (2015) "Active inference and epistemic value"

#### 2. **Human-like Behavior の再現**
- 歩行者は「振り返り確認」を行う
- 視線行動のモデル化 → より現実的なシミュレーション
- 文献：Kitazawa & Fujiyama (2010) "Pedestrian gaze behavior"

#### 3. **Novel Research Question**
```
Q: 視線制御をHaze理論とどう統合するか？

A: 高Haze領域を積極的に注視する戦略が創発するか？
```

これは**新しい問い**であり、論文の独自性を高める。

### デメリット

#### 1. **複雑性の増加**
- 状態8D（または離散gaze追加）
- VAE学習の困難さ増加
- 実装・デバッグの負担

#### 2. **EPH本質からの逸脱**
- EPHの核心は「Haze + 2nd-order + VAE予測」
- 視線制御は「周辺的な拡張」に過ぎない
- 本質をぼやかすリスク

#### 3. **評価の複雑化**
- ベースラインとの比較が難しい
- 「視線制御の効果」と「Haze理論の効果」の分離が困難

---

## 推奨：シンプルな Model A（視線 = 体の向き）

### 理由

#### 1. **EPHの核心に集中**
```
EPH = Haze Theory + VAE Prediction + 2nd-order Dynamics
```
これだけで Nature Communications に十分な新規性。

#### 2. **実装・評価が明確**
- 5D状態空間：シンプル
- VAE学習：容易
- ベースライン比較：公平

#### 3. **段階的な研究展開**
- **v7.0**: 視線 = 体の向き（シンプル版）
- **v8.0**: 視線制御を追加（拡張版、将来の研究）

---

## Model A（推奨版）の完全仕様

### 状態空間
```
s = [x, y, vx, vy, θ] ∈ ℝ⁵
```
- `(x, y)`: 位置
- `(vx, vy)`: 速度
- `θ`: Body heading = Gaze direction

### 制御入力
```
u = [Fx, Fy] ∈ ℝ²
```
全方向の力ベクトル（あなたの元々のイメージ通り）

### Dynamics
```python
def dynamics_rk4(state, u, dt, params):
    """
    state: [x, y, vx, vy, theta]
    u: [Fx, Fy]
    """
    m = params['mass']           # 70 kg
    cd = params['drag_coeff']     # 0.5
    k_align = params['k_align']   # 4.0 rad/s

    def f(s, u):
        x, y, vx, vy, theta = s
        Fx, Fy = u

        v_norm = np.sqrt(vx**2 + vy**2)

        # 目標heading（速度方向）
        if v_norm > 0.1:
            theta_target = np.arctan2(vy, vx)
            dtheta = angle_diff(theta_target, theta)
        else:
            dtheta = 0  # 停止中は回転しない

        return np.array([
            vx,                           # dx/dt
            vy,                           # dy/dt
            Fx/m - cd/m * vx * v_norm,    # dvx/dt
            Fy/m - cd/m * vy * v_norm,    # dvy/dt
            k_align * dtheta              # dtheta/dt
        ])

    # RK4 integration
    k1 = f(state, u)
    k2 = f(state + dt/2 * k1, u)
    k3 = f(state + dt/2 * k2, u)
    k4 = f(state + dt * k3, u)

    new_state = state + dt/6 * (k1 + 2*k2 + 2*k3 + k4)

    # Normalize theta to [-π, π]
    new_state[4] = np.arctan2(np.sin(new_state[4]), np.cos(new_state[4]))

    return new_state
```

### 視野生成
```python
def render_fov(position, heading, fov_angle, obstacles, agents):
    """
    heading = 視野中心方向
    fov_angle = 180° (人間の視野)

    Returns: (64, 64, 3) RGB image
    """
    image = np.zeros((64, 64, 3))

    for obs in obstacles:
        # 障害物への相対角度
        angle_to_obs = np.arctan2(obs.y - position[1], obs.x - position[0])
        relative_angle = angle_diff(angle_to_obs, heading)

        # FoV内かチェック
        if abs(relative_angle) <= fov_angle / 2:
            # 距離
            distance = np.linalg.norm(obs.pos - position)

            # 画像座標に変換
            # 中心が heading、左右に ±90°
            pixel_x = int((relative_angle / (fov_angle/2) + 1) * 32)  # [0, 64]
            pixel_y = int(32 / max(distance, 0.5))  # 近いほど下

            if 0 <= pixel_x < 64 and 0 <= pixel_y < 64:
                image[pixel_y, pixel_x, :] = [1, 0, 0]  # 赤

    # 同様に他エージェントを描画（青）
    for agent in agents:
        angle_to_agent = np.arctan2(agent.y - position[1], agent.x - position[0])
        relative_angle = angle_diff(angle_to_agent, heading)

        if abs(relative_angle) <= fov_angle / 2:
            distance = np.linalg.norm(agent.pos - position)
            pixel_x = int((relative_angle / (fov_angle/2) + 1) * 32)
            pixel_y = int(32 / max(distance, 0.5))

            if 0 <= pixel_x < 64 and 0 <= pixel_y < 64:
                image[pixel_y, pixel_x, :] = [0, 0, 1]  # 青

    return image
```

### EPH行動選択
```python
def select_action_eph(spm_current, s_current, vae, params):
    """
    EPHの本質：予測SPMに基づく離散候補評価

    u = [Fx, Fy] の2次元制御
    """
    # 100候補：20方向 × 5力
    angles = np.linspace(0, 2*np.pi, 20, endpoint=False)
    forces = [0, 37.5, 75, 112.5, 150]  # N

    F_min = float('inf')
    u_best = None

    for angle in angles:
        for F_mag in forces:
            u = np.array([F_mag * np.cos(angle), F_mag * np.sin(angle)])

            # 1. 状態予測（dynamics）
            s_pred = dynamics_rk4(s_current, u, params['dt'], params)

            # 2. 予測headingで視野生成
            heading_pred = s_pred[4]
            visual_pred = render_fov(
                position=s_pred[0:2],
                heading=heading_pred,
                fov_angle=180.0,
                obstacles=params['obstacles'],
                agents=params['agents']
            )

            # 3. VAEでSPM予測
            spm_pred = vae.encode(visual_pred)

            # 4. Goal Term（進捗ベース）
            v_pred = s_pred[2:4]
            P_pred = np.dot(v_pred, params['d_goal'])
            Phi_goal = (P_pred - params['P_target'])**2 / (2 * params['sigma_P']**2)

            # 5. Safety Term（Haze変調）
            Phi_safety = 0
            for i, spm_val in enumerate(spm_pred):
                precision = 1.0 / (params['haze_map'][i] + 1e-6)
                Phi_safety += precision * spm_val

            # 6. Smoothness Term
            S = params['lambda_smooth'] * np.sum(u**2)

            # 7. Total Free Energy
            F_val = Phi_goal + Phi_safety + S

            if F_val < F_min:
                F_min = F_val
                u_best = u

    return u_best  # ✅ 離散候補から選択
```

---

## この formulation の学術的強み

### 1. **シンプルで明確**
- EPHの核心（Haze + VAE + 2nd-order）に集中
- 評価・再現が容易

### 2. **視野は heading に依存**
```
heading → 視野 → SPM → 行動
```
- Heading の選択が間接的に視野を制御
- これは**暗黙的な視線制御**

### 3. **Active Inferenceと整合**
- 行動 u が状態 s を変える
- 状態 s が観測 o（視野）を変える
- 観測 o が次の行動を決める
- **Perception-Action Loop** が完結

### 4. **拡張性**
- 将来、視線制御を追加可能
- まずは基礎版（v7.0）を確立

---

## 視線制御の将来的な追加（v8.0以降）

もし視線制御を追加するなら：

### Option 1: Epistemic Value の追加
```python
# Expected Free Energy に情報獲得項を追加
G(u) = Risk(u) + Ambiguity(u) - Information_Gain(u)

# Information Gain = 高Haze領域を見ることの価値
IG(u, gaze) = Σ Haze(region) · visibility(region, gaze)
```

### Option 2: 2段階最適化
```python
# Phase 1: 移動方向を決定
u_move = argmin_u F(u)  # 100候補

# Phase 2: 最適視線を選択
gaze_best = argmin_gaze IG(u_move, gaze)  # 5候補
```

これなら：
- Phase 1で EPH本来の行動選択
- Phase 2で 視線の追加最適化
- EPHの本質を保ちつつ拡張

---

## まとめ：推奨方針

### **EPH v7.0: Model A（シンプル版）**

```
状態: s = [x, y, vx, vy, θ] ∈ ℝ⁵
制御: u = [Fx, Fy] ∈ ℝ²
視野: heading = θ（速度方向に追従）
候補: 100個（20方向 × 5力）
```

#### 理由
1. ✅ EPHの本質に集中（Haze理論が主役）
2. ✅ 実装・評価がシンプル
3. ✅ Nature Communications に十分な新規性
4. ✅ あなたの元々の直感と一致
5. ✅ 段階的な研究展開が可能

#### 学術的価値
- **Core**: Haze理論 + VAE予測 + 2nd-order + Progress-based Goal
- **十分な新規性**: 既存手法にない4つの要素
- **明確な評価**: 3シナリオで有効性検証

### **EPH v8.0以降: 視線制御の追加（将来）**
- Active Perception の明示的モデル化
- Information Gain の実装
- より人間らしい行動の再現

---

## 結論

**あなたの判断が正しいです。**

> "本体行動のみで視線角度は後から付いてくる形で u = [u_x, u_y] の2次元でも良い"

**賛成します。** この方針で proposal を更新しましょう。

視線制御は：
- 学術的に「面白い拡張」ではある
- しかしEPH v7.0の本質ではない
- 将来研究として残す

この **Model A（u = [Fx, Fy]、θ は速度追従）** で進めてよろしいでしょうか？
