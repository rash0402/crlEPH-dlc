# Heading と Gaze（視線）の分離モデル

## 問題の本質

> "この場合，headingは 本体の速度方向とは独立に視線を変化させることになる？？"

そうです。しかしこれは**不自然**です。

### 人間の実際の行動

1. **体の向き（Heading θ_body）**: 通常は移動方向に追従
2. **視線方向（Gaze θ_gaze）**: 首を回して周囲を確認

例：
- 前進しながら**首だけ**右に回して確認 ✅ 自然
- 体は北向きのまま東に移動 ❌ 不自然（横歩き？）

---

## 提案：3つのモデル比較

### **Model A: Body Heading のみ（視線 = 体の向き）**

#### 状態空間
```
s = [x, y, vx, vy, θ] ∈ ℝ⁵
```
- θ: Body heading（体の向き = 視線方向）

#### 制御入力
```
u = [Fx, Fy] ∈ ℝ²
```

#### Heading決定
```python
# 速度方向にローパスフィルター追従
θ_target = atan2(vy, vx)
dθ/dt = k_align · (θ_target - θ)
```

#### 視野
```python
FoV_center = θ  # 体の向き = 視野中心
FoV_range = [θ - 90°, θ + 90°]  # 180°視野
```

#### **問題点**
- ❌ 視線制御が不可能
- ❌ 「後ろを見ながら前進」ができない

---

### **Model B: Body + Gaze 分離（2階層制御）**

#### 状態空間
```
s = [x, y, vx, vy, θ_body, ω_body, θ_gaze, ω_gaze] ∈ ℝ⁸
```
- θ_body: 体の向き（移動方向に追従）
- θ_gaze: 視線方向（能動制御）

#### 制御入力
```
u = [Fx, Fy, τ_gaze] ∈ ℝ³
```
- (Fx, Fy): 全方向力
- τ_gaze: 首の回転トルク（視線制御）

#### Dynamics
```python
# 並進（全方向）
m·dvx/dt = Fx - cd·|v|·vx
m·dvy/dt = Fy - cd·|v|·vy

# Body heading（速度方向に追従）
θ_body_target = atan2(vy, vx)
dθ_body/dt = k_align · (θ_body_target - θ_body)

# Gaze（独立制御）
I_neck·dω_gaze/dt = τ_gaze - c_neck·ω_gaze
dθ_gaze/dt = ω_gaze

# 制約：首の可動範囲
θ_gaze ∈ [θ_body - 90°, θ_body + 90°]  # 左右90°まで
```

#### 視野
```python
FoV_center = θ_gaze  # 視線方向が視野中心
FoV_range = [θ_gaze - 90°, θ_gaze + 90°]
```

#### EPH Action Candidates
```python
# 120候補: 6方向 × 4力 × 5視線トルク
for angle_F in [0°, 60°, 120°, 180°, 240°, 300°]:
    for F_mag in [0, 50, 100, 150]:
        for tau_gaze in [-0.5, -0.25, 0, 0.25, 0.5]:
            u = [F_mag*cos(angle_F), F_mag*sin(angle_F), tau_gaze]
            # 評価...
```

#### **利点**
- ✅ 視線制御が可能
- ✅ 物理的に自然（体は移動方向、首だけ回す）
- ✅ 「振り返りながら前進」が可能

#### **欠点**
- ⚠️ 状態が8次元（複雑）
- ⚠️ VAEが8D状態を学習する必要

---

### **Model C: Simplified Gaze（離散的な視線選択）**

#### 状態空間
```
s = [x, y, vx, vy, θ_body] ∈ ℝ⁵
```

#### 制御入力
```
u = [Fx, Fy, gaze_mode] ∈ ℝ² × {0,1,2,3,4}
```
- (Fx, Fy): 全方向力
- gaze_mode: 視線モード
  - 0: 前方（θ_body + 0°）
  - 1: 右前（θ_body + 45°）
  - 2: 右（θ_body + 90°）
  - 3: 左前（θ_body - 45°）
  - 4: 左（θ_body - 90°）

#### Dynamics
```python
# 並進
m·dvx/dt = Fx - cd·|v|·vx
m·dvy/dt = Fy - cd·|v|·vy

# Body heading（速度追従）
θ_body_target = atan2(vy, vx)
dθ_body/dt = k_align · (θ_body_target - θ_body)

# Gaze（離散的）
gaze_offset = {0: 0°, 1: 45°, 2: 90°, 3: -45°, 4: -90°}
θ_gaze = θ_body + gaze_offset[gaze_mode]
```

#### 視野
```python
FoV_center = θ_gaze
FoV_range = [θ_gaze - 90°, θ_gaze + 90°]
```

#### EPH Action Candidates
```python
# 120候補: 6方向 × 4力 × 5視線モード
for angle_F in [0°, 60°, 120°, 180°, 240°, 300°]:
    for F_mag in [0, 50, 100, 150]:
        for gaze_mode in [0, 1, 2, 3, 4]:
            u = [F_mag*cos(angle_F), F_mag*sin(angle_F), gaze_mode]

            # Body heading予測
            s_pred = dynamics_rk4(s, u[:2], dt)
            θ_body_pred = s_pred[4]

            # Gaze direction
            θ_gaze_pred = θ_body_pred + gaze_offset[gaze_mode]

            # 視野生成
            visual = render_fov(s_pred[0:2], θ_gaze_pred, fov=180°)
            spm_pred = vae.encode(visual)

            # 評価...
```

#### **利点**
- ✅ 視線制御が可能
- ✅ 状態は5次元（シンプル）
- ✅ 物理的に自然
- ✅ 実装が簡単

#### **欠点**
- ⚠️ 視線方向が離散的（連続ではない）
- ただし実用上は十分？

---

## 3モデルの比較表

| 側面 | Model A (Body のみ) | Model B (連続 Gaze) | **Model C (離散 Gaze)** |
|------|---------------------|---------------------|-------------------------|
| 状態次元 | 5D | 8D | **5D** |
| 制御次元 | 2D | 3D (連続) | **2D + 離散** |
| 視線制御 | ❌ 不可 | ✅ 連続 | **✅ 離散** |
| 物理的自然さ | ✅ | ✅ | **✅** |
| Body-速度整合 | ✅ 追従 | ✅ 追従 | **✅ 追従** |
| 実装複雑さ | 低 | 高 | **中** |
| VAE学習 | 易 | 難（8D） | **易（5D）** |
| 候補数 | 100 | 120 | **120** |
| **推奨度** | ❌ | ⚠️ | **✅** |

---

## 推奨：Model C（離散Gaze）

### 理由

1. **視野制御が可能**
   - 5つのgaze modeで周囲を確認
   - 「前進しながら右確認」が可能

2. **物理的に自然**
   - Body heading は移動方向に追従
   - Gaze は body からの相対角度
   - 人間の首の動きに対応

3. **実装がシンプル**
   - 5D状態空間（VAE学習が容易）
   - Gaze mode は離散変数
   - RK4は2D力のみ（連続）

4. **EPH前提を堅持**
   - 120個の離散候補
   - 各候補で視野を生成 → SPM予測
   - Free energy評価 → argmin選択
   - ✅ 自動微分ではない

### 視線モードの設計

```python
GAZE_MODES = {
    'FORWARD': 0,      # θ_body + 0°   (前方)
    'RIGHT_FRONT': 1,  # θ_body + 45°  (右前)
    'RIGHT': 2,        # θ_body + 90°  (右)
    'LEFT_FRONT': 3,   # θ_body - 45°  (左前)
    'LEFT': 4,         # θ_body - 90°  (左)
}
```

必要に応じて7モードに拡張：
```python
GAZE_MODES_EXTENDED = {
    'FORWARD': 0,       # 0°
    'RIGHT_30': 1,      # +30°
    'RIGHT_60': 2,      # +60°
    'RIGHT_90': 3,      # +90°
    'LEFT_30': 4,       # -30°
    'LEFT_60': 5,       # -60°
    'LEFT_90': 6,       # -90°
}
```

---

## 実装例：Model C

### Complete Dynamics

```python
def dynamics_with_gaze(state, u, dt, params):
    """
    state: [x, y, vx, vy, theta_body]
    u: [Fx, Fy, gaze_mode]

    Returns: (new_state, theta_gaze)
    """
    # 並進 dynamics（RK4）
    state_new = dynamics_rk4_translation(state, u[:2], dt, params)

    # Body heading（速度追従）
    vx, vy = state_new[2:4]
    v_norm = np.sqrt(vx**2 + vy**2)

    if v_norm > 0.1:  # 移動中
        theta_body_target = np.arctan2(vy, vx)
        theta_body = state[4]
        dtheta = angle_diff(theta_body_target, theta_body)
        state_new[4] = theta_body + params['k_align'] * dtheta * dt
    # else: 停止中は heading 維持

    # Gaze direction
    gaze_offset = params['gaze_offsets'][int(u[2])]
    theta_gaze = state_new[4] + gaze_offset

    return state_new, theta_gaze


def select_action_eph_with_discrete_gaze(spm_current, s_current, vae, params):
    """EPH行動選択（離散Gaze付き）"""

    # 120候補生成
    angles = np.linspace(0, 2*np.pi, 6, endpoint=False)
    forces = [0, 50, 100, 150]
    gaze_modes = [0, 1, 2, 3, 4]

    F_min = float('inf')
    u_best = None

    for angle in angles:
        for F_mag in forces:
            for gaze_mode in gaze_modes:
                Fx = F_mag * np.cos(angle)
                Fy = F_mag * np.sin(angle)
                u = np.array([Fx, Fy, gaze_mode])

                # 状態 + gaze 予測
                s_pred, theta_gaze_pred = dynamics_with_gaze(
                    s_current, u, params['dt'], params
                )

                # 視野生成（gaze中心）
                visual = render_fov(
                    position=s_pred[0:2],
                    heading=theta_gaze_pred,  # ★視線方向
                    fov=180.0,
                    obstacles=params['obstacles'],
                    agents=params['agents']
                )

                # SPM予測
                spm_pred = vae.encode(visual)

                # Goal Term
                v_pred = s_pred[2:4]
                P_pred = np.dot(v_pred, params['d_goal'])
                Phi_goal = (P_pred - params['P_target'])**2 / (2 * params['sigma_P']**2)

                # Safety Term
                Phi_safety = compute_safety_term(spm_pred, params['precision'])

                # Smoothness
                S = params['lambda_smooth'] * (Fx**2 + Fy**2)

                # Total
                F_val = Phi_goal + Phi_safety + S

                if F_val < F_min:
                    F_min = F_val
                    u_best = u

    return u_best  # ✅ 離散探索
```

### Parameters

```python
params = {
    # 並進
    'mass': 70.0,
    'drag_coeff': 0.5,
    'F_max': 150.0,

    # Heading追従
    'k_align': 4.0,  # rad/s per radian error

    # Gaze modes
    'gaze_offsets': [0, π/4, π/2, -π/4, -π/2],  # [0°, 45°, 90°, -45°, -90°]

    # 視野
    'fov': 180.0,  # degrees

    # 時間
    'dt': 0.01
}
```

---

## シナリオでの動作例

### スクランブル交差点

```python
# 状況：東に向かって移動、後方から接近する人
s = [x, y, vx=1.0, vy=0, θ_body=0°]

# 候補1: 前を見ながら東へ
u1 = [100, 0, gaze_mode=0]  # FORWARD
→ θ_gaze = 0° (前方のみ見える)

# 候補2: 右を確認しながら東へ
u2 = [100, 0, gaze_mode=2]  # RIGHT
→ θ_gaze = 90° (右側を確認)

# EPHが評価
# 右から接近者 → u2 の Φ_safety が低い → u2 選択
```

### シープドッグ

```python
# 状況：北に押す、群れは北東にいる
s = [x, y, vx=0, vy=1.0, θ_body=90°]  # 北向き

# 候補：北に進みながら右前（群れ）を見る
u = [0, 100, gaze_mode=1]  # RIGHT_FRONT
→ θ_body = 90° (北)
→ θ_gaze = 90° + 45° = 135° (北東方向を注視)
→ 群れ全体をSPMで把握
```

---

## Model B（連続Gaze）との比較

### Model B の利点
- 視線方向が連続（任意の角度）
- より柔軟

### Model B の問題
- 8D状態空間 → VAE学習が困難
- 連続τ_gazeの離散化が必要
- 複雑

### Model C の利点
- 5D状態空間 → VAE学習が容易
- 実用上5方向で十分？
- 実装がシンプル

---

## 結論：推奨 Model C

### 状態空間
```
s = [x, y, vx, vy, θ_body] ∈ ℝ⁵
```

### 制御入力
```
u = [Fx, Fy, gaze_mode] ∈ ℝ² × {0,1,2,3,4}
```

### 重要な特徴
1. **Body heading**: 速度方向にローパスフィルター追従
2. **Gaze direction**: Body + 相対角度（離散5方向）
3. **視野中心**: Gaze direction
4. **EPH**: 120候補の離散評価

この方針で proposal を更新してよろしいでしょうか？

それとも Model B（連続Gaze、8D状態）の方が良いでしょうか？
