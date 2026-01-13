---
title: "EPH v6.2 Implementation Specification"
type: Implementation_Guide
status: "🟢 Active"
version: 6.2.0
date_created: "2026-01-13"
date_modified: "2026-01-13"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
related_docs:
  - proposal_v6.2.md
  - CLAUDE.md
tags:
  - Implementation/Specification
  - Topic/FEP
  - Status/Active
---

# EPH v6.2 実装仕様書

> [!IMPORTANT] 実装の核心
>
> **v6.2の3つの柱**：
> 1. **Precision-Weighted Safety**：Φ_safetyとSの両方にΠ(ρ)を適用
> 2. **Sigmoid Blending**：ステップ関数をC∞-smooth遷移に改善（数学的厳密性・神経科学的妥当性）
> 3. **Raw Trajectory Data Architecture**：生データ保存でストレージ100倍削減

---

## 目次

1. [アーキテクチャ概要](#1-アーキテクチャ概要)
2. [主要コンポーネント](#2-主要コンポーネント)
3. [Haze/Precision適用の正しい方法](#3-hazeprecision適用の正しい方法)
4. [VAE学習パイプライン](#4-vae学習パイプライン)
5. [推論時Controller動作](#5-推論時controller動作)
6. [データフロー](#6-データフロー)
7. [実装上の注意点](#7-実装上の注意点)
8. [既知の問題と将来課題](#8-既知の問題と将来課題)

---

## 1. アーキテクチャ概要

### 1.1 システム構成

```
[データ収集フェーズ]
  Simulation → Raw Trajectories (pos, vel, u, heading)
              ↓
  [HDF5保存] 16.8MB/sim（100倍圧縮）

[VAE学習フェーズ]
  Raw Data → SPM Reconstruction (Haze=0) → VAE Training
            ↓
  Pattern D VAE Model

[推論フェーズ（Controller）]
  Environment → SPM Generation (Haze=0)
              ↓
  Precision Map (Haze→Π変換) → Φ_safety(u;Π) + S(u;Π)
              ↓
  Free Energy F(u) → Action u*
```

### 1.2 ディレクトリ構成

```
crlEPH-dlc/
├── src/
│   ├── config.jl              # システムパラメータ
│   ├── spm.jl                 # SPM生成（★要確認：β変調）
│   ├── controller.jl          # v6.1/v6.2 Controller
│   ├── action_vae.jl          # Pattern D VAE
│   ├── trajectory_loader.jl   # ★v6.2: Raw data → SPM
│   └── scenarios.jl           # シナリオ設定
├── scripts/
│   ├── create_dataset_v62_raw.jl   # ★v6.2: Raw data収集
│   ├── train_action_vae_v62.jl     # ★v6.2: VAE訓練
│   └── run_simulation_eph.jl       # 推論実行
├── data/
│   └── vae_training/
│       └── raw_v62/           # ★v6.2: 80 files, 139.4MB
├── models/
│   ├── action_vae_v61_best.bson    # v6.1モデル
│   └── action_vae_v62_best.bson    # ★v6.2モデル（訓練中）
└── doc/
    ├── proposal_v6.2.md       # 研究提案書
    └── implementation_v6.2.md # 本ドキュメント
```

---

## 2. 主要コンポーネント

### 2.1 SPM生成 (src/spm.jl)

**関数シグネチャ**:
```julia
function generate_spm_3ch(
    config::SPMConfig,
    agents_rel_pos::Vector{<:AbstractVector},
    agents_rel_vel::Vector{<:AbstractVector},
    r_agent::Real,
    precision::Real = 1.0  # ⚠️ デフォルト値
) → Array{T, 3}  # [n_rho, n_theta, 3]
```

**仕様**:
- Log-polar座標系（16 rho bins × 16 theta bins）
- D_max = 8.0m
- 3チャンネル：
  - Ch1: Occupancy（存在確率）
  - Ch2: Proximity Saliency（接近度）
  - Ch3: Collision Risk（衝突リスク）

**⚠️ 実装上の問題**:
```julia
# 現在の実装 (spm.jl:105-113)
precision_clamped = clamp(precision, 0.01, 100.0)
beta_r = params.beta_r_min + (params.beta_r_max - params.beta_r_min) * precision_clamped
beta_nu = params.beta_nu_min + (params.beta_nu_max - params.beta_nu_min) * precision_clamped
```

**問題点**: precisionによってβが変調され、SPM生成方法自体が変化する

**v6.2プロポーザルの意図**:
- Precision-Weighted SafetyはSPM生成を変えるのではない
- 生成されたSPMに対する**重み付け**を変える

**推奨対応**:
- Option A: precision引数を削除、固定β値を使用（beta_r_fixed=5.0, beta_nu_fixed=5.0）
- Option B: precision引数を保持するが、β変調を無効化

---

### 2.2 Precision Map計算 (src/controller.jl)

**関数シグネチャ** (v6.2 Sigmoid Blending):
```julia
function compute_precision_map(
    spm_config::SPMConfig,
    rho_index_critical::Int = 6,    # Critical zone center: Bin 6
    h_critical::Float64 = 0.0,      # Haze=0.0
    h_peripheral::Float64 = 0.5,    # Haze=0.5
    tau::Float64 = 1.0              # ★v6.2: Sigmoid transition smoothness
) → Array{Float64, 2}  # [n_rho, n_theta]
```

**v6.2 実装** (Sigmoid Blending):
```julia
for i in 1:n_rho
    # Sigmoid blending: Haze(ρ) = h_crit + (h_peri - h_crit) · σ((ρ - ρ_crit) / τ)
    rho_crit = rho_index_critical + 0.5  # Transition center at bin boundary
    sigmoid_val = 1.0 / (1.0 + exp(-(i - rho_crit) / tau))
    haze = h_critical + (h_peripheral - h_critical) * sigmoid_val

    precision = 1.0 / (haze + 1e-6)  # ε=1e-6

    for j in 1:n_theta
        precision_map[i, j] = precision
    end
end
```

**v6.2の改善点**:
1. **数学的厳密性**: C∞-smooth → ForwardDiff.jl安定性向上
2. **神経科学的妥当性**: 連続的PPS境界（指数減衰）と整合
3. **制御安定性**: Gain Scheduling滑らかさ条件を満たす

**出力例** (τ=1.0):
```
Bin 1:   Π ≈ 491.1  (Far Critical, Haze≈0.002)
Bin 6:   Π ≈ 5.30   (Critical boundary, Haze≈0.189)
Bin 7:   Π ≈ 3.21   (Peripheral boundary, Haze≈0.311)
Bin 16:  Π ≈ 2.00   (Far Peripheral, Haze≈0.500)
```

**Step Function比較** (旧v6.1):
```julia
# v6.1 (Step Function - DEPRECATED)
haze = (i <= rho_index_critical) ? h_critical : h_peripheral
# 問題: Bin 6→7で不連続ジャンプ (Π: 100.0 → 2.0)
```

---

### 2.3 Controller v6.1 (src/controller.jl)

**関数シグネチャ**:
```julia
function compute_free_energy_v61(
    agent::Agent,
    spm_current::Array{Float64, 3},
    u::AbstractVector,
    other_agents::Vector{Agent},
    action_vae,
    spm_config::SPMConfig,
    world_params::WorldParams,
    d_pref::Vector{Float64},
    precision::Float64,  # ⚠️ 単一値（未使用推奨）
    k_2::Float64,
    k_3::Float64,
    precision_map::Array{Float64, 2}  # ★v6.1: Precision Map
) → Float64
```

**実装の核心**:

#### (1) Φ_goal: 目標到達項
```julia
pos_next, vel_next = Dynamics.predict_state(agent, u, AgentParams(), world_params)
Φ_goal = -dot(vel_next, d_pref)
```

#### (2) Φ_safety: Precision-Weighted Safety（★v6.2）
```julia
# SPM予測生成（ForwardDiff.Dual対応）
spm_pred = SPM.generate_spm_3ch(
    spm_config, agents_rel_pos, agents_rel_vel,
    AgentParams().r_agent,
    precision  # ⚠️ この引数は削除推奨
)

ch2_pred = spm_pred[:, :, 2]
ch3_pred = spm_pred[:, :, 3]

# ★v6.2: Precision-Weighted Safety
Φ_safety = sum(precision_map .* (k_2 .* ch2_pred .+ k_3 .* ch3_pred))
```

**重要**: `precision_map`で空間的重み付け（Critical Zoneで増幅）

#### (3) S(u): Precision-Weighted Surprise（v6.1継承）
```julia
# VAE予測（Float32変換、非微分）
spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))
u_input = Float32.(reshape(u_val, 2, 1))

μ_z, logσ_z = ActionVAEModel.encode(action_vae, spm_input, u_input)
z = μ_z
spm_vae_pred = ActionVAEModel.decode_with_u(action_vae, z, u_input)

# Precision-Weighted MSE
S = 0.0
for c in 1:3, j in 1:n_theta, i in 1:n_rho
    error_sq = (spm_pred_batch[i,j,c,1] - spm_vae_pred[i,j,c,1])^2
    S += precision_map[i,j] * error_sq
end
S = S * 0.5
```

#### (4) Total Free Energy
```julia
F = Φ_goal + Φ_safety + Float64(S)
```

---

### 2.4 Action-Conditioned VAE (src/action_vae.jl)

**Pattern D アーキテクチャ**:
```
Encoder:  (y[k], u[k]) → q(z|y,u) → μ_z, σ_z
Decoder:  (z, u[k]) → p(y[k+1]|z,u) → ŷ[k+1]
```

**ネットワーク構成**:
```julia
# Encoder
Conv(16×16×3 → 8×8×32) → Conv(8×8×32 → 4×4×64) → Flatten(1024)
Concat[1024 + 2(action)] → Dense(512) → μ_z(32), logσ_z(32)

# Decoder
Concat[32(z) + 2(action)] → Dense(512) → Dense(1024)
Reshape(4×4×64) → ConvTranspose(8×8×32) → ConvTranspose(16×16×3)
```

**損失関数**:
```julia
L = Reconstruction Loss + β * KL Divergence

Reconstruction Loss = MSE(y[k+1], ŷ[k+1])
KL Divergence = -0.5 * Σ(1 + logσ_z² - μ_z² - σ_z²)
```

---

## 3. Haze/Precision適用の正しい方法

### 3.1 ✅ 正しい設計（v6.2プロポーザル準拠）

#### フェーズ1: VAE学習

```julia
# データ収集時（エージェント制御）
# create_dataset_v62_raw.jl
const V62_FOV_PARAMS = FoveationParams(
    rho_index_critical=6,
    h_critical=0.0,
    h_peripheral=0.0  # ★エージェント制御用（VAE学習には無関係）
)

# VAE学習時（SPM再生成）
# trajectory_loader.jl:129
spm_t = reconstruct_spm_at_timestep(
    pos[t, :, :], vel[t, :, :], obstacles, agent_idx, spm_config, r_agent
)
# ↓ 内部でgenerate_spm_3ch呼び出し（precision引数なし → デフォルト1.0）

# VAE訓練
VAE.train(y[k]=spm_t, u[k], y[k+1]=spm_t1)
```

**✅ 正しい理由**:
- VAEは**真の状態遷移（Haze=0）**を学習
- 高精度な予測モデルを獲得

#### フェーズ2: 推論時（Controller）

```julia
# SPM生成: Haze=0で生成（真の状態）
spm_current = generate_spm_3ch(config, pos, vel, r_agent)
spm_pred = generate_spm_3ch(config, pos_next, vel_next, r_agent)
# ★ precision引数を渡さない（デフォルト1.0 = Haze=0）

# VAE予測: 真の状態を予測
spm_vae_pred = VAE.predict(spm_current, u)

# Precision Map計算: Hazeから重み付けを計算
precision_map = compute_precision_map(
    config,
    rho_index_critical=6,
    h_critical=0.0,
    h_peripheral=0.5  # ★ Hazeを推論時に適用
)

# Φ_safety: Precision-Weighted Safety
Φ_safety = Σ precision_map[i,j] * [k_2*ch2_pred[i,j] + k_3*ch3_pred[i,j]]

# S(u): Precision-Weighted Surprise
S = Σ precision_map[i,j] * (spm_pred[i,j,c] - spm_vae_pred[i,j,c])^2

# Total Free Energy
F = Φ_goal + Φ_safety + S
```

**✅ 正しい理由**:
- SPMは常にHaze=0で生成（真の状態）
- Hazeは**重み付けとして**のみ機能
- Critical Zone: 同じSPMでも寄与100倍
- Peripheral Zone: 同じSPMでも寄与2倍

---

### 3.2 ❌ 誤った理解（訂正済み）

**誤解1**: VAE学習時にh_peripheral=0.5を適用すべき
→ ❌ **間違い**。VAEはHaze=0で学習すべき

**誤解2**: SPM生成にprecision引数を渡してβ変調すべき
→ ❌ **間違い**。プロポーザルではprecision引数なし

**誤解3**: データ収集時のh_peripheral設定がVAE学習に影響する
→ ❌ **間違い**。Raw Dataから再生成するため無関係

---

## 4. VAE学習パイプライン

### 4.1 データ収集 (scripts/create_dataset_v62_raw.jl)

**実行コマンド**:
```bash
julia --project=. scripts/create_dataset_v62_raw.jl --scenario both --steps 3000
```

**出力**:
```
data/vae_training/raw_v62/
  ├── v62_scramble_d5_s1_YYYYMMDD_HHMMSS.h5
  ├── v62_corridor_w30_d10_s1_YYYYMMDD_HHMMSS.h5
  └── ... (80 files total, ~139.4 MB)
```

**HDF5構造**:
```
/trajectory
  ├── pos [T, N, 2]       # Position trajectories
  ├── vel [T, N, 2]       # Velocity trajectories
  ├── u [T, N, 2]         # Control input trajectories
  └── heading [T, N]      # Heading angle trajectories

/obstacles
  └── data [M, 2]         # Obstacle positions (x, y)

/metadata
  ├── collision_rate
  ├── freezing_rate
  └── ...

/spm_params              # ★v6.2: SPM再生成用
  ├── n_rho = 16
  ├── n_theta = 16
  ├── sensing_ratio
  ├── rho_index_critical = 6
  ├── h_critical = 0.0
  └── h_peripheral = 0.0  # データ収集時の設定（VAE学習には無関係）
```

---

### 4.2 VAE訓練 (scripts/train_action_vae_v62.jl)

**実行コマンド**:
```bash
# テスト（20ファイル）
julia --project=. scripts/train_action_vae_v62.jl

# 本番（80ファイル）- MAX_FILES=nothingに変更後
julia --project=. scripts/train_action_vae_v62.jl
```

**設定**:
```julia
# Data loading parameters
const STRIDE = 5              # Sample every 5 timesteps
const AGENT_SUBSAMPLE = nothing  # Use all agents
const MAX_FILES = 20          # Testing: 20, Production: nothing

# Training parameters
const LATENT_DIM = 32
const BETA = 0.5              # KL weight
const LEARNING_RATE = 0.0001
const BATCH_SIZE = 128
const EPOCHS = 100
```

**データフロー**:
```
1. load_trajectories_batch() → Raw Data読み込み
2. extract_vae_training_pairs() → SPM再生成（Haze=0）
3. Train/Val/Test分割（80/10/10%）
4. Batch作成
5. VAE訓練（Flux.jl + Adam）
6. Best model保存（models/action_vae_v62_best.bson）
```

**期待される出力**:
```
Epoch   1/100 | Train Loss: 0.0368 (Recon: 0.0348, KL: 0.0042) | Val Loss: 0.0225
Epoch   2/100 | Train Loss: 0.0223 (Recon: 0.0223, KL: 0.0001) | Val Loss: 0.0222
...
Epoch  50/100 | Train Loss: 0.0220 (Recon: 0.0220, KL: 0.0000) | Val Loss: 0.0220
✅ Best model saved: models/action_vae_v62_best.bson
```

---

## 5. 推論時Controller動作

### 5.1 エントリーポイント (scripts/run_simulation_eph.jl)

**実行コマンド**:
```bash
julia --project=. scripts/run_simulation_eph.jl
```

**シナリオ選択**:
```julia
scenario = initialize_scenario(
    "scramble";  # or "corridor"
    n_agents_per_group=25,
    world_size=(30.0, 30.0),
    seed=1
)
```

---

### 5.2 制御ループ

```julia
# Initialization
action_vae = load_vae_model("models/action_vae_v62_best.bson")
precision_map = compute_precision_map(spm_config, 6, 0.0, 0.5)

for t in 1:max_steps
    for agent in agents
        # 1. SPM生成（Haze=0）
        spm_current = generate_spm_from_agent(agent, other_agents, obstacles)

        # 2. 行動選択（ForwardDiff.jl自動微分）
        u = compute_action_v61(
            agent, spm_current, other_agents, action_vae,
            control_params, agent_params, world_params,
            spm_config, d_pref, precision=1.0, k_2, k_3;
            rho_index_critical=6,
            h_critical=0.0,
            h_peripheral=0.5
        )

        # 3. 状態更新
        agent = update_agent_state(agent, u, dt)
    end

    # 4. ログ記録
    log_step(logger, agents, t)
end
```

---

### 5.3 行動選択詳細 (compute_action_v61)

**勾配降下法**:
```julia
u = zeros(2)  # 初期化

for iter in 1:n_iters
    # Free energy計算
    F_of_u(u_vec) = compute_free_energy_v61(
        agent, spm_current, u_vec, other_agents,
        action_vae, spm_config, world_params,
        d_pref, precision=1.0, k_2, k_3, precision_map
    )

    # 勾配計算（ForwardDiff.jl）
    grad_F = ForwardDiff.gradient(F_of_u, u)

    # 更新
    u = u - learning_rate .* grad_F
    u = clamp.(u, -u_max, u_max)
end

return u
```

---

## 6. データフロー

### 6.1 全体フロー

```
[Phase 1: Data Collection]
Simulation (v6.1 Controller) → Raw Trajectories
  ├── pos [T, N, 2]
  ├── vel [T, N, 2]
  ├── u [T, N, 2]
  └── heading [T, N]
     ↓
  HDF5 (16.8MB/sim, 80 files, 139.4MB total)

[Phase 2: VAE Training]
Raw Data → SPM Reconstruction (Haze=0)
  ├── y[k] = reconstruct_spm(pos[t], vel[t])
  ├── u[k] = u[t]
  └── y[k+1] = reconstruct_spm(pos[t+1], vel[t+1])
     ↓
  VAE Training (Pattern D)
     ↓
  Trained Model (action_vae_v62_best.bson, 1.4MB)

[Phase 3: Inference]
Environment State → SPM (Haze=0)
     ↓
  Precision Map (h_critical=0.0, h_peripheral=0.5)
     ↓
  Free Energy F(u) = Φ_goal + Φ_safety(u;Π) + S(u;Π)
     ↓
  Action u* = argmin F(u)
```

---

### 6.2 メモリフロー（VAE訓練時）

```
[20ファイルテスト]
20 files × 12,000 samples/file = 240,000 samples
240,000 × 16×16×3×4bytes = 737 MB (SPM data)
+ u, y[k+1] → ~858 MB total

[80ファイル本番]
80 files × 12,000 samples/file = 960,000 samples
960,000 × 16×16×3×4bytes = 2.95 GB (SPM data)
→ メモリ効率化必須（batch processing + GC）
```

---

## 7. 実装上の注意点

### 7.1 ForwardDiff.jl対応

**重要**: SPM生成はDual数対応必須

```julia
# ❌ 間違い
agents_rel_pos = Vector{Vector{Float64}}()

# ✅ 正しい
T = eltype(pos_next)  # Dual or Float64
agents_rel_pos = Vector{Vector{T}}()
```

**VAE呼び出しはFloat32変換**:
```julia
# VAE operations are non-differentiable
u_val = [ForwardDiff.value(u[1]), ForwardDiff.value(u[2])]
spm_input = Float32.(reshape(spm_current, 16, 16, 3, 1))
```

---

### 7.2 メモリ管理

**VAE訓練時のGC強制実行**:
```julia
if i % 10 == 0
    GC.gc()
    println("    [Memory: $(round(Sys.free_memory()/1e9, digits=2)) GB free]")
end
```

**バッチサイズ調整**:
- CPU: BATCH_SIZE=128
- GPU: BATCH_SIZE=256 or 512

---

### 7.3 HDF5データアクセス

**圧縮レベル**:
```julia
h5open(filepath, "w") do file
    traj_group["pos", compress=4] = pos  # Level 4 compression
end
```

**読み込み順序**:
```julia
# ファイルリストをソート（再現性確保）
files = sort(filter(f -> occursin(r"v62_.*\.h5$", f), readdir(directory, join=true)))
```

---

## 8. 既知の問題と将来課題

### 8.1 既知の問題

#### 問題1: spm.jlのprecision引数によるβ変調

**現状**:
```julia
# spm.jl:105-113
beta_r = params.beta_r_min + (params.beta_r_max - params.beta_r_min) * precision
beta_nu = params.beta_nu_min + (params.beta_nu_max - params.beta_nu_min) * precision
```

**問題点**:
- precisionによってSPM生成方法が変化
- v6.2プロポーザルの「重み付けのみ」と矛盾

**対応案**:
- Option A: 固定β値使用（beta_r_fixed=5.0, beta_nu_fixed=5.0）
- Option B: precision引数削除

**影響範囲**:
- src/spm.jl
- src/controller.jl (generate_spm_3ch呼び出し箇所)

---

#### 問題2: controller.jlのprecision引数（単一値）

**現状**:
```julia
# controller.jl:705
spm_pred = SPM.generate_spm_3ch(..., precision)
```

**問題点**:
- precision（単一値）とprecision_map（配列）の二重管理
- プロポーザルではprecision引数なし

**対応案**:
- precision引数を削除、常に1.0で生成

**影響範囲**:
- src/controller.jl:705, 710

---

### 8.2 将来課題

#### 課題1: 80ファイル本番訓練

**現状**: 20ファイルテスト完了
**次**: MAX_FILES=nothingに変更し80ファイル訓練

**予想実行時間**: 約12時間（CPU）

---

#### 課題2: Ablation Study

**比較条件**:
1. v6.1 Baseline: S(u;Π)のみPrecision重み付け
2. v6.2 Full: Φ_safety(u;Π) + S(u;Π)の両方
3. Ablation A: Φ_safety(u;Π)のみ
4. Ablation B: S(u;Π)のみ
5. Ablation C: 両方にΠなし（v6.0相当）

**実装**: 各条件用のcontroller関数を作成

---

#### 課題3: SPM構造柔軟性検証

**目的**: Raw Data Architectureの利点確認

**実験**:
1. 同一データからD_max=6m, 8m, 10mでSPM再生成
2. 各設定でVAE訓練
3. 性能比較（Reconstruction Loss）

---

#### 課題4: GPU対応

**現状**: CPU only（CUDA not available）
**次**: Metal.jl（Mac）またはCUDA.jl（Linux/Windows）対応

**期待効果**: 訓練時間10倍高速化

---

## 9. クイックリファレンス

### 9.1 主要関数一覧

| 関数名 | ファイル | 用途 |
|--------|---------|------|
| `generate_spm_3ch` | spm.jl:92 | SPM生成（ForwardDiff対応） |
| `compute_precision_map` | controller.jl:605 | Haze→Π変換 |
| `compute_free_energy_v61` | controller.jl:667 | v6.1 Free Energy |
| `compute_action_v61` | controller.jl:789 | v6.1 行動選択 |
| `reconstruct_spm_at_timestep` | trajectory_loader.jl:95 | Raw data→SPM |
| `extract_vae_training_pairs` | trajectory_loader.jl:155 | VAE訓練データ抽出 |
| `load_trajectories_batch` | trajectory_loader.jl:331 | メモリ効率的読み込み |

---

### 9.2 設定パラメータ

**SPM設定**:
```julia
n_rho = 16              # Log-polar rho bins
n_theta = 16            # Angular bins
D_max = 8.0             # Maximum sensing distance [m]
sensing_ratio = 15.0    # D_max / r_min
sigma_spm = 0.5         # Gaussian blur width
```

**Critical Zone設定**:
```julia
rho_index_critical = 6  # Bin 1-6: Critical Zone (0-2.18m)
h_critical = 0.0        # Critical Zone Haze
h_peripheral = 0.5      # Peripheral Zone Haze
```

**VAE設定**:
```julia
LATENT_DIM = 32         # Latent space dimension
BETA = 0.5              # KL weight
LEARNING_RATE = 0.0001  # Adam learning rate
BATCH_SIZE = 128        # Batch size
EPOCHS = 100            # Training epochs
```

**Controller設定**:
```julia
k_2 = 1.0               # Proximity saliency weight
k_3 = 1.0               # Collision risk weight
n_iters = 10            # Gradient descent iterations
learning_rate = 0.1     # Action update rate
```

---

## 10. まとめ

### 10.1 v6.2実装の核心

**Precision-Weighted Safety**:
- ✅ SPM生成はHaze=0（真の状態）
- ✅ Precision MapはHazeから計算
- ✅ ΦとSの両方に重み付け適用

**Raw Trajectory Data Architecture**:
- ✅ 生データのみ保存（100倍圧縮）
- ✅ VAE学習時にSPM再生成（Haze=0）
- ✅ 柔軟性とストレージ効率の両立

---

### 10.2 実装チェックリスト

**データ収集**:
- [x] create_dataset_v62_raw.jl実装
- [x] 80シミュレーション実行完了（139.4MB）
- [x] HDF5構造確認（pos, vel, u, heading, obstacles, spm_params）

**VAE訓練**:
- [x] trajectory_loader.jl実装（SPM再生成）
- [x] train_action_vae_v62.jl実装
- [x] 20ファイルテスト実行中
- [ ] 80ファイル本番訓練

**Controller**:
- [x] compute_precision_map実装
- [x] Precision-Weighted Safety実装（Φ_safety）
- [x] Precision-Weighted Surprise実装（S）
- [x] Sigmoid Blending実装（v6.2改善、2026-01-13）
- [x] tau parameter追加（τ=1.0デフォルト）
- [ ] spm.jl precision引数問題の解決
- [ ] controller.jl precision引数の整理

**検証**:
- [ ] Ablation Study実装
- [ ] v6.1 vs v6.2性能比較
- [ ] Raw Data柔軟性検証（D_max変更）
- [ ] 創発的社会行動の観測

---

### 10.3 次のステップ

1. ✅ **Sigmoid Blending実装完了**（2026-01-13）
2. **現VAE訓練完了待ち**（20ファイル、残り~8時間）
3. **80ファイル本番訓練実行**（MAX_FILES=nothing、Sigmoid版）
4. **Step vs Sigmoid実験比較**（τ=0.5, 1.0, 2.0、後回し）
5. **Active Inference理論拡張の形式的証明**（論文執筆時）
6. **Ablation Study実装**
7. **論文執筆開始**

---

## 変更履歴

### v6.2.0 (2026-01-13)

**Major Improvements**:
- ✅ **Sigmoid Blending実装**: ステップ関数からC∞-smooth遷移へ改善
  - `compute_precision_map`にtauパラメータ追加（デフォルト1.0）
  - 数学的厳密性（ForwardDiff.jl安定性向上）
  - 神経科学的妥当性（連続的PPS境界）
  - 制御安定性（Gain Scheduling滑らかさ条件）

**Theoretical Foundation**:
- 🔬 **Active Inference拡張**: Π(ρ)の理論的正当化を準備中
- 📄 **12専門家レビュー**: review_v6.2_multi_persona.md完成

**Implementation**:
- `src/controller.jl::compute_precision_map`: Sigmoid blending実装
- `src/controller.jl::compute_action_v61`: tauパラメータ追加
- `scripts/test_sigmoid_blending.jl`: 検証スクリプト追加

**Documentation**:
- `doc/implementation_v6.2.md`: Sigmoid blending反映
- `results/vae_tuning/review_v6.2_multi_persona.md`: 学術的レビュー

**Next Steps**:
- VAE訓練完了待ち（20ファイル、~8時間）
- 80ファイル本番訓練（Sigmoid版）
- Active Inference理論拡張の形式的証明

---

**バージョン**: 6.2.0
**最終更新**: 2026-01-13
**関連ドキュメント**: proposal_v6.2.md, CLAUDE.md, review_v6.2_multi_persona.md
**メンテナ**: Hiroshi Igarashi
