# Implementation Plan v7.2: Model A (Simple 5D Dynamics)

本ドキュメントは、EPH v7.2 (Model A) の実装計画を定義します。
Model A は、状態空間を 5D に簡略化し、Heading が速度方向に自動追従するモデルです。
ベースとなる既存実装: v6.3 (Controller Bias Free)

---

## 1. 概要と目的

### 目的
- EPH のコア理論である "Haze-dependent Perception-Action Loop" を生物学的に妥当かつシンプルな系で検証する。
- 3つのシナリオ (Scramble, Corridor, Sheepdog) において統一的な理論枠組み (Progress Velocity-based Goal Term) を適用する。

### v7.2 の主要な変更点
1.  **5D 状態空間**: `s = [x, y, vx, vy, θ]` (角速度 `ω` 削除)。
2.  **全方向力制御**: `u = [Fx, Fy]` (Heading独立のトルク制御ではない)。
3.  **Heading 追従**: `dθ/dt = k_align * (θ_target - θ)`。
4.  **進捗速度ベース Goal**: `d_goal` (方向ベクトル) に基づく評価。

---

## 2. 変更が必要なファイル一覧

### Core System
- `src/dynamics.jl`: 5D RK4動力学の実装、Structure更新。
- `src/action_vae.jl`: VAE入力次元の確認・調整。
- `src/controller.jl`: EPHコントローラの更新（100候補生成、新Goal項）。
- `src/spm.jl`: (変更なし見込みだが確認)

### Data & Training
- `scripts/create_dataset_v72_scramble.jl`: データ収集（Scramble）。
- `scripts/create_dataset_v72_corridor.jl`: データ収集（Corridor）。
- `scripts/create_dataset_v72_random_obstacles.jl`: データ収集（Random）。
- `scripts/train_action_vae.jl`: 学習スクリプト更新。

### Simulation
- `scripts/run_simulation_eph.jl`: メインループ更新。

---

## 3. 実装ステップ詳細

### Phase 1: Core Dynamics & Data Collection (1-2日)

動力学モデルを刷新し、新しいデータを収集できるようにします。

#### 1.1 `src/dynamics.jl` の更新
- **Agent Struct**: `acc`, `ω` を整理。`d_goal` をベクトル型に統一。
- **Trajectory Logging**: 5D 状態保存に対応。
- **RK4 Logic** (提案書2.1.3節に準拠):
  ```julia
  # v7.2 Dynamics (2次系動力学)
  # 並進運動: Newton's 2nd law
  dvx/dt = (Fx - cd * v_norm * vx) / m
  dvy/dt = (Fy - cd * v_norm * vy) / m
  
  # Heading追従: 速度方向への1次遅れ
  θ_target = atan2(vy, vx)  # 速度ベクトルの方向
  dθ/dt = k_align * angle_diff(θ_target, θ)
  
  # 位置更新
  dx/dt = vx
  dy/dt = vy
  ```
  
- **Physical Parameters** (提案書2.1.3節):
  ```julia
  m = 1.0 kg              # Mass (基礎エージェント)
  c_d = 1.0 N·s²/m²       # Drag coefficient
  k_align = 5.0 rad/s     # Heading alignment gain
  F_max = 15.0 N          # Maximum force
  dt = 0.01 s             # Timestep
  ```

#### 1.2 データ収集スクリプトの更新 (`scripts/create_dataset_v72_*.jl`)

**重要**: データ収集時には**SPMは計算・保存しない**。生の軌道データのみを記録する（v6.2のRaw Trajectory Data Architectureを継承）。

- **記録するデータ**:
  - **エージェント状態**: 位置 `pos [T, N, 2]`, 速度 `vel [T, N, 2]`, 方向 `heading [T, N]`
  - **制御入力**: `u [T, N, 2]` (Fx, Fy)
  - **環境情報**: 障害物位置 `obstacles/data [M, 2]`
  - **メタデータ**: シナリオ名、エージェント数、ステップ数、dt、衝突率など
  - **SPMパラメータ**: SPM再生成用の設定（n_bins, n_angles, D_max, h_critical, h_peripheral等）

- **Action Sampling**: データ収集時はランダムウォークまたは幾何学的衝突回避を使用（Controller-Bias-Free）。
  - 100候補 (20 angles × 5 magnitudes) の探索空間をカバーするデータを収集。
  - Angles: [0°, 18°, 36°, ..., 342°] (20方向)
  - Magnitudes: [0, 3.75, 7.5, 11.25, 15.0] N (5段階、F_max=15.0Nに基づく)

- **HDF5 Format** (v6.2継承):
  ```
  trajectory/
    pos [T, N, 2]       # Position (x, y)
    vel [T, N, 2]       # Velocity (vx, vy)
    u [T, N, 2]         # Control input (Fx, Fy)
    heading [T, N]      # Heading angle θ
  
  obstacles/
    data [M, 2]         # Obstacle positions (x, y)
  
  metadata/
    scenario            # "scramble", "corridor", or "sheepdog"
    n_agents, n_steps, dt, collision_rate, ...
  
  spm_params/          # For SPM reconstruction
    n_bins, n_angles, D_max, h_critical, h_peripheral, ...
  ```

- **シナリオ別エージェント数** (提案書4.1節):
  - Scramble: N = 20 (各方向5エージェント)
  - Corridor: N = 15 (各7-8エージェント)
  - Sheepdog: N_f = 10 (Flock) + N_s = 1 (Shepherd)

- **SPM再生成**: VAE学習時（Phase 2）に、`trajectory_loader.jl`を使用して生データからSPMを再生成する。

#### 1.3 データ収集の実行
- **3つのシナリオでそれぞれデータログを収集**:
  - Scramble: 20ファイル程度収集し、分布を確認
  - Corridor: 20ファイル程度収集
  - Sheepdog: 20ファイル程度収集
- **確認事項**: HDF5ファイルにSPMが含まれていないこと、生データ（pos, vel, heading, u）と環境情報（obstacles）が正しく記録されていることを確認。

### Phase 2: VAE Training (1日)

収集したデータを用いて Pattern D VAE を学習させます。

#### 2.1 `src/action_vae.jl` の確認・微修正
- **VAEアーキテクチャ**:
  - **Encoder入力**: `SPM_t` ∈ ℝ^(12×12×3) (現在のSPM 3ch)
  - **Encoder出力**: `z_t` ∈ ℝ^32 (潜在変数)
  - **Decoder入力**: `(z_t, u, s_t)` where:
    - `z_t` ∈ ℝ^32 (潜在変数)
    - `u` ∈ ℝ^2 (行動: Fx, Fy)
    - `s_t` ∈ ℝ^5 (現在状態: x, y, vx, vy, θ)
  - **Decoder出力**: `SPM_{t+1}` ∈ ℝ^(12×12×3) (次SPM 3chのみ)
- Pattern D (Action-Conditioned) のアーキテクチャは維持。
- **重要**: VAEは状態（s_{t+1}）を予測しない。次状態は動力学モデル（RK4）で計算する。

#### 2.2 学習実行 (`scripts/train_action_vae.jl`)
- Loss の収束を確認。
- `models/action_vae_v72_best.bson` として保存。

### Phase 3: EPH Controller & Simulation (2-3日)

学習済みモデルを用いてコントローラを実装し、シミュレーションを行います。

#### 3.1 `src/controller.jl` の更新
- **Action Candidates** (提案書Algorithm 1, Line 1に準拠):
  - `utils` 関数として実装（極座標生成）
  - 20 angles × 5 magnitudes = 100候補
  - angles: [0°, 18°, 36°, ..., 342°]
  - magnitudes: [0, 3.75, 7.5, 11.25, 15.0] N (F_max=15.0Nに基づく)
  
- **VAE予測**:
  - 入力:
    - `o_t` ∈ ℝ^(12×12×3): 現在のSPM (3ch)
    - `U_candidates`: 行動候補リスト (100個)
    - `s_t` ∈ ℝ^5: 現在状態 (x, y, vx, vy, θ)
  - 処理: `VAE.predict_batch(o_t, U_candidates, s_t)` で全候補を並列予測
    - Encoder: `SPM_t → z_t`
    - Decoder: `(z_t, u, s_t) → SPM_{t+1}` for each u
  - 出力: `SPM_next[]`
    - `SPM_next[u]` ∈ ℝ^(12×12×3): 次SPM (3ch)
  
- **次状態の計算**:
  - VAEは状態を予測しない。次状態は動力学モデル（RK4）で計算する。
  - `s_{t+1} = dynamics_rk4(s_t, u, dt, params)` for each u

- **Free Energy計算** (提案書2.2.2節、3.3節に準拠):
  ```julia
  # 各行動候補 u について評価
  for each u in U_candidates:
      # 次状態の計算（動力学モデル）
      s_next = dynamics_rk4(s_t, u, dt, params)  # (x', y', vx', vy', θ')
      
      # Goal Term (進捗速度ベース)
      v_pred = s_next[3:4]  # (vx', vy')
      P_pred = v_pred · d_goal    # 進捗速度
      P_target = 1.0 m/s          # 目標進捗速度
      σ_P = 0.5 m/s               # 許容幅
      Phi_goal = (P_pred - P_target)^2 / (2 * σ_P^2)
      
      # Safety Term (Haze変調SPM)
      Phi_safety = Σ_{ρ,θ} Π(ρ,θ) · SPM_next[u](ρ,θ)
      # SPM_pred includes ch2 (proximity saliency) and ch3 (collision risk)
      
      # Smoothness Term
      S = ||u||² / (2 * σ_u²)  # where σ_u is action variance parameter
      
      # Total Free Energy
      F[u] = w_goal * Phi_goal + w_safety * Phi_safety + w_entropy * S
      # where w_goal = 1.0, w_safety = 0.5, w_entropy = 0.1 (提案書2.3.5節)
  end
  
  # Action Selection
  u* = argmin_u F[u]  # 離散探索 (NOT 自動微分)
  ```

- **Haze Modulator** (提案書Algorithm 1, Line 4-10、2.3.4節に準拠):
  ```julia
  # Haze計算 (Algorithm 1, Line 4-6)
  H_env = GetEnvironmentalHaze(s_t.position)  # 環境Haze [0, 1]
  # Scramble: H_env = 0.0 (均一、提案書4.2.1節)
  # Corridor: H_env = 0.2 (壁近傍) / 0.0 (中央、提案書4.3.1節)
  # Sheepdog: Shepherd指定 (Optional、提案書4.4.1節)
  
  A = exp(-λ * ||SPM_obs - SPM_pred_previous||₂)  # 予測精度 [0, 1]
  # where λ = 0.5 (予測誤差感度、提案書2.3.3節)
  
  # 各行動候補評価ループ内で (Algorithm 1, Line 9-10)
  for each u in U_candidates:
      # Spatial Haze (距離ベース基底)
      H_spatial(ρ) = ...  # Bin 1-6: 0.0 (Critical Zone), Bin 7+: 0.5 (Peripheral Zone)
      
      # Total Haze (乗法版、提案書2.3.4節推奨、Algorithm 1, Line 9)
      H_total = H_spatial * (1 + α * H_env) * (1 + β * (1 - A))
      
      # Precision変換 (Algorithm 1, Line 10)
      Π = 1.0 / (H_total + ε)  # where ε = 0.01 (数値安定化)
  end
  
  # パラメータ (提案書2.3.9節)
  α = 1.0    # Environmental Haze coupling (default)
  β = 1.0    # Self-hazing strength (default, range: [0, 5])
  λ = 0.5    # Prediction error sensitivity (default)
  ```

#### 3.2 シナリオ統合 (`scripts/run_simulation_eph.jl`)
- Scramble: Self-hazing の検証。
- Corridor: Environmental Haze (壁際のPrecision) の検証。
- Sheepdog: Dog Agent の実装（異種エージェント対応）。

---

## 4. 検証計画

### 4.1 Unit Tests
- [ ] **Dynamics**: 直進、旋回時のHeading追従が `k_align=5.0` で期待通りか。
- [ ] **Goal Term**: ゴール方向に向かうアクションが最小コストになるか。
- [ ] **Haze計算**: Total Haze = H_spatial · (1 + α·H_env) · (1 + β·(1-A)) が正しく計算されるか。
- [ ] **Precision変換**: Π = 1 / (H_total + ε) が正しく計算されるか。

### 4.2 Integration Tests
- [ ] **Data Viewer**: 新しいデータ形式を `scripts/view_v72_data.sh` で表示できるか。
- [ ] **Short Simulation**: 100ステップ程度でエラー落ちしないか。

### 4.3 Evaluation Metrics (提案書4.1節に準拠)
- **創発度**: Emergence Index (EI) > 0.5 (2次系)
  - Flow Smoothness: S > 0.8
  - Lane Formation Stability: 持続時間 > 10秒
- **環境適応性**: Task Success Rate (TSR) > 0.85 (各シナリオ)
- **転移学習性能**: Transfer Success Rate (TSR) > 0.8 (Scramble→Corridor)
- **Haze制御効果**: 
  - Corridor: Collision reduction > 30% (Environmental Haze)
  - Scramble: Path diversity ∝ β (Self-hazing)
- **Safety**: 衝突率 (Collision Rate) < 0.05

---

## 5. 作業順序

1. `src/dynamics.jl` の改修。
2. `scripts/create_dataset_v72.jl` の整備とテスト収集。
3. `view_v72_data.sh` でデータ確認。
4. VAE学習。
5. `src/controller.jl` 実装とシミュレーション実行。
