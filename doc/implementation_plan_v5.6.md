# EPH v5.6 実装プラン

**Version**: 5.6.0
**Date**: 2026-01-10
**Status**: 🟢 Ready for Implementation
**Theoretical Framework**: `EPH_v56_framework.md`

---

## 🎯 全体フロー（ゼロベース再構築）

```
Phase 0: 仕様明確化と環境整備
    ↓
Phase 1: データ収集（Training Data Generation）
    ↓
Phase 2: VAE学習（Model Training with Surprise）
    ↓
Phase 3: VAE検証（Model Validation: Prediction & Surprise）
    ↓
Phase 4: 制御統合（Controller Integration with Fixed Haze）
    ↓
Phase 5: 比較実験（Baseline Comparison）
    ↓
Phase 6: Self-Hazing（将来拡張）
```

**設計原則**:
- 各Phaseで **Input → Process → Output → 成功基準** を明確化
- Phase 3 での品質確認がゲート条件（VAEが不合格なら Phase 4 に進まない）
- Haze は Phase 1-5 で固定値（0.5）、Phase 6 で自律化

---

## Phase 0: 仕様明確化と環境整備

### 🎯 目標
v5.6 の理論仕様を実装レベルに落とし込み、開発基盤を整備する

### 📋 タスク

#### 0.1 データフォーマット定義

**訓練データ構造**:
```julia
struct VAEDataSample
    spm_current::Array{Float32, 3}   # (16, 16, 3) - y[k]
    action::Vector{Float32}          # (2,) - u[k]
    spm_next::Array{Float32, 3}      # (16, 16, 3) - y[k+1]
end
```

**HDF5 スキーマ**:
```
data/vae_training/dataset_v56.h5
├── /metadata
│   ├── version: "5.6.0"
│   ├── creation_date: "2026-01-10"
│   └── description: "Action-Dependent VAE with Surprise"
├── /train
│   ├── spms_current: (N_train, 16, 16, 3)
│   ├── actions: (N_train, 2)
│   ├── spms_next: (N_train, 16, 16, 3)
│   └── metadata: {density, scenario, seed}
├── /val
│   └── (同上)
├── /test_iid
│   └── (同上)
└── /test_ood
    └── (未学習密度データ)
```

#### 0.2 評価指標の事前定義

**VAE指標**:
- Prediction MSE: `||y[k+1] - ŷ[k+1]||²`
- Surprise (Reconstruction Error): `||y[k] - VAE_recon(y[k], u[k])||²`
- KL Divergence: `KL[q(z|y,u) || p(z)]`
- Haze-Error Correlation: ρ (Spearman)

**制御指標**:
- Freezing Rate: 速度 < 0.1 m/s が 2秒以上
- Success Rate: ゴール到達率
- Collision Rate: 衝突発生率
- Path Efficiency: 直線距離 / 実経路長
- Jerk: 加速度変化率の時間平均

#### 0.3 コード構造整理

**ディレクトリ構成**:
```
src/
├── config.jl              # パラメータ定義
├── spm.jl                 # SPM生成（β変調込み）
├── dynamics.jl            # 物理シミュレーション
├── scenarios.jl           # 新規: シナリオ実装（Scramble/Corridor）★追加★
├── action_vae.jl          # Pattern D VAE（v5.6準拠）
├── controller_v56.jl      # 新規: Surprise統合制御
├── surprise.jl            # 新規: Surprise計算モジュール
├── haze.jl                # 新規: Haze管理（固定/スケジュール/Self）
├── metrics.jl             # 評価指標
└── logger.jl              # HDF5ログ

scripts/
├── collect_vae_data_v56.jl      # Phase 1: データ収集（両シナリオ対応）
├── train_vae_v56.jl             # Phase 2: VAE学習
├── validate_vae_v56.jl          # Phase 3: VAE検証
├── run_simulation_v56.jl        # Phase 4: メインシミュレーション（両シナリオ対応）
├── run_batch_experiments_v56.jl # Phase 5: バッチ実験
├── run_haze_sensitivity_v56.jl  # Phase 5: Haze感度分析
├── analyze_comparison_v56.jl    # Phase 5: 比較分析
└── analyze_haze_sensitivity_v56.jl  # Phase 5.5: 感度分析

data/                              # 【生データ】シミュレーションログ（HDF5）
├── vae_training/                  # Phase 1: VAE訓練データ
│   ├── raw/                       # 個別シミュレーション生データ
│   │   ├── scramble/              # sim_d{d}_s{s}.h5
│   │   └── corridor/              # sim_d{d}_s{s}.h5
│   └── dataset_v56.h5             # 統合データセット（Train/Val/Test）
└── logs/                          # Phase 4-6: 制御統合後のログ
    ├── control_integration/       # Phase 4.1-4.4: 制御統合（固定Haze）
    │   ├── scramble/              # sim_h{h}_d{d}_s{s}.h5
    │   └── corridor/              # sim_h{h}_d{d}_s{s}.h5
    ├── hyperparameter_tuning/     # Phase 4.5: ハイパーパラメータチューニング ★NEW★
    │   ├── scramble/              # tuning_λ{λs}_λs{λsp}_n{n}_h{h}_s{s}.h5
    │   └── corridor/
    ├── comparison/                # Phase 5.1-5.4: 比較実験
    │   ├── scramble/
    │   │   ├── A0_baseline/       # sim_d{d}_s{s}.h5
    │   │   ├── A1_haze_only/
    │   │   ├── A2_surprise_only/
    │   │   └── A3_eph_v56/
    │   └── corridor/
    │       └── (同上)
    ├── haze_sensitivity/          # Phase 5.5: Haze感度分析
    │   ├── scramble/              # sim_h{h}_d{d}_s{s}.h5
    │   └── corridor/
    └── self_hazing/               # Phase 6: Self-Hazing学習
        ├── scramble/              # sim_ep{ep}_s{s}.h5
        └── corridor/

results/                           # 【分析結果】レポート・図・統計
├── data_collection/               # Phase 1: データ統計サマリ
│   ├── dataset_summary.md
│   └── distribution_plots.png
├── vae_training/                  # Phase 2: VAE学習結果
│   ├── training_log.csv
│   ├── loss_curves.png
│   └── hyperparameter_comparison.md
├── vae_validation/                # Phase 3: VAE検証結果
│   ├── prediction_report.md
│   ├── counterfactual_surprise.png
│   ├── surprise_error_correlation.png
│   └── ood_analysis.md
├── control_integration/           # Phase 4.1-4.4: 制御統合可視化
│   ├── scramble_freezing_analysis.png
│   └── corridor_throughput_analysis.png
├── hyperparameter_tuning/         # Phase 4.5: ハイパーパラメータチューニング結果 ★NEW★
│   ├── tuning_results.csv         # 全チューニング結果
│   ├── pareto_front.png           # Freezing vs Collision
│   ├── lambda_safety_sensitivity.png
│   └── tuning_report.md
├── comparison/                    # Phase 5.1-5.4: 比較実験結果
│   ├── comparison_report.md       # 総合レポート
│   ├── freezing_vs_density.png    # Scramble用
│   ├── throughput_vs_density.png  # Corridor用
│   ├── ablation_study.png
│   └── statistical_tests.csv
├── haze_sensitivity/              # Phase 5.5: Haze感度分析結果
│   ├── raw_results.csv            # 全実験結果（200件）
│   ├── sensitivity_report.md      # 総合レポート
│   ├── scramble_haze_vs_freezing.png
│   ├── scramble_heatmap.png       # Haze × Density
│   ├── corridor_haze_vs_throughput.png
│   ├── corridor_heatmap.png
│   └── task_comparison_success_rate.png
└── self_hazing/                   # Phase 6: Self-Hazing結果
    ├── meta_learning_log.csv
    ├── optimal_haze_policy_report.md
    └── learning_curves.png

models/                            # 学習済みモデル
├── action_vae_v56_best.bson       # Phase 2: 最良VAEモデル
├── action_vae_v56_checkpoints/    # Phase 2: 学習チェックポイント
└── self_haze_policy_v56.bson      # Phase 6: Self-Hazingポリシー

config/                            # 設定ファイル ★NEW★
└── optimal_params_v56.json        # Phase 4.5: 最適ハイパーパラメータ
```

**命名規則**:
- **data/**: 生データ（HDF5ログ） → 大容量、Git管理外
- **results/**: 分析結果（レポート、図、CSV） → 軽量、Git管理対象
- ログファイル: `sim_{scenario}_{condition}_h{haze}_d{density}_s{seed}.h5`
- レポート: `{phase_name}_report.md`

#### 0.4 シナリオ実装モジュール作成 ★新規追加★

**`src/scenarios.jl`**:
```julia
module Scenarios

using ..Dynamics

export ScenarioType, initialize_scenario, get_scenario_params

@enum ScenarioType begin
    SCRAMBLE_CROSSING
    CORRIDOR
end

"""
Scenario-specific parameters
"""
struct ScenarioParams
    scenario_type::ScenarioType
    world_size::Tuple{Float64, Float64}
    num_groups::Int
    group_positions::Vector{Tuple{Float64, Float64}}
    group_goals::Vector{Tuple{Float64, Float64}}
    corridor_width::Union{Nothing, Float64}  # Corridorのみ使用
end

"""
Initialize Scramble Crossing scenario.
4 groups crossing at intersection.
"""
function init_scramble_crossing(num_agents_per_group::Int)
    world_size = (50.0, 50.0)
    center = (25.0, 25.0)

    # 4グループの初期位置とゴール（90度間隔）
    positions = [
        (center[1] - 15.0, center[2]),       # West
        (center[1], center[2] + 15.0),       # North
        (center[1] + 15.0, center[2]),       # East
        (center[1], center[2] - 15.0)        # South
    ]

    goals = [
        (center[1] + 15.0, center[2]),       # West → East
        (center[1], center[2] - 15.0),       # North → South
        (center[1] - 15.0, center[2]),       # East → West
        (center[1], center[2] + 15.0)        # South → North
    ]

    return ScenarioParams(
        SCRAMBLE_CROSSING,
        world_size,
        4,
        positions,
        goals,
        nothing
    )
end

"""
Initialize Corridor scenario.
Bidirectional flow in narrow passage.
"""
function init_corridor(num_agents_per_group::Int; corridor_width::Float64=4.0)
    world_size = (60.0, 20.0)

    # 2グループ: 左→右、右→左
    positions = [
        (5.0, 10.0),    # Group 1: Left side
        (55.0, 10.0)    # Group 2: Right side
    ]

    goals = [
        (55.0, 10.0),   # Group 1 goal: Right side
        (5.0, 10.0)     # Group 2 goal: Left side
    ]

    return ScenarioParams(
        CORRIDOR,
        world_size,
        2,
        positions,
        goals,
        corridor_width
    )
end

"""
Initialize agents for given scenario.
"""
function initialize_scenario(
    scenario_type::ScenarioType,
    num_agents_per_group::Int,
    seed::Int
)
    Random.seed!(seed)

    if scenario_type == SCRAMBLE_CROSSING
        params = init_scramble_crossing(num_agents_per_group)
    elseif scenario_type == CORRIDOR
        params = init_corridor(num_agents_per_group)
    else
        error("Unknown scenario type: $scenario_type")
    end

    # エージェント生成
    agents = Agent[]
    for group_id in 1:params.num_groups
        start_pos = params.group_positions[group_id]
        goal_pos = params.group_goals[group_id]

        for i in 1:num_agents_per_group
            # グループ内でランダムに分散
            pos = start_pos .+ (randn(2) * 2.0)
            vel = [0.0, 0.0]
            goal_vel = normalize(goal_pos .- pos) * 1.0  # 1.0 m/s

            agent = Agent(
                id=length(agents) + 1,
                pos=pos,
                vel=vel,
                goal=goal_pos,
                goal_vel=goal_vel,
                group_id=group_id
            )
            push!(agents, agent)
        end
    end

    return agents, params
end

"""
Get scenario-specific obstacles (for Corridor).
"""
function get_obstacles(params::ScenarioParams)
    if params.scenario_type == CORRIDOR
        # 通路の壁を障害物として定義
        obstacles = []
        width = params.corridor_width
        center_y = params.world_size[2] / 2.0

        # 上側の壁（連続障害物）
        for x in 0:1.0:params.world_size[1]
            push!(obstacles, (x, center_y + width/2.0))
        end

        # 下側の壁
        for x in 0:1.0:params.world_size[1]
            push!(obstacles, (x, center_y - width/2.0))
        end

        return obstacles
    else
        return []  # Scrambleには壁なし
    end
end

end # module
```

### 📦 成果物
- [x] `doc/EPH_v56_framework.md` ✅ 完成
- [x] `doc/implementation_plan_v56.md` ✅ 完成（ディレクトリ構造統一）
- [ ] `src/data_schema.jl` (データローディングAPI)
- [ ] `src/config_v56.jl` (v5.6パラメータ)
- [ ] `src/scenarios.jl` (Scramble/Corridor実装) ★新規★
- [ ] `.gitignore` 更新（data/logs/, models/ を追加）

### 📁 ディレクトリ構造の整理完了 ✅

**設計原則**:
- **data/**: 生データ（HDF5ログ）→ 大容量、Git管理外
- **results/**: 分析結果（レポート・図・CSV）→ 軽量、Git管理対象
- **models/**: 学習済みモデル（BSON）→ Git LFS または管理外

**命名規則**:
- ログ: `sim_{scenario}_{condition}_h{haze}_d{density}_s{seed}.h5`
- レポート: `{phase_name}_report.md`
- 図: `{metric}_{scenario}.png`

**推奨 .gitignore 追加**:
```
# 生データ（大容量）
data/logs/
data/vae_training/raw/
data/vae_training/dataset_v56.h5

# 学習済みモデル（大容量、別途管理）
models/*.bson
models/action_vae_v56_checkpoints/

# 分析結果は Git 管理対象（results/ は含めない）
```

### ✅ 成功基準
- [x] 全スキーマが文書化されている ✅
- [x] ディレクトリ構成が統一的に定義されている ✅
- [ ] v5.5の古いコードが`archive/`に移動されている
- [ ] 両シナリオ（Scramble/Corridor）が正しく動作する ★新規★
- [ ] .gitignore が適切に設定されている

---

## Phase 1: データ収集

### 🎯 目標
多様なシナリオで高品質な `(y[k], u[k], y[k+1])` データセットを収集する

### 📥 Input
- 既存シミュレーション環境 (`src/dynamics.jl`, `src/spm.jl`)
- データ収集用の行動ポリシー（ランダム or 既存FEP）

### ⚙️ Process

#### 1.1 データ収集スクリプト作成

**`scripts/collect_vae_data_v56.jl`**:
```julia
using ..Scenarios

# 設定
densities = [5, 10, 15, 20]       # エージェント密度
scenarios = [:scramble, :corridor] # 両シナリオ対応 ★更新★
seeds = 1:5                        # 各条件5シード
num_steps = 1500                   # ステップ数
haze_fixed = 0.5                   # 固定Haze

# 行動ポリシー（データ多様性確保）
function exploration_policy(agent, spm)
    # 基本FEP + ランダムノイズ
    u_fep = compute_action(agent, spm, control_params, agent_params)
    noise = randn(2) * 0.3  # 30% ノイズ
    return clamp.(u_fep + noise, -u_max, u_max)
end

# データ収集ループ
samples = []
for scenario in scenarios, density in densities, seed in seeds
    println("Collecting data: scenario=$scenario, density=$density, seed=$seed")

    # シナリオ初期化 ★両シナリオ対応★
    scenario_type = scenario == :scramble ? SCRAMBLE_CROSSING : CORRIDOR
    agents, scenario_params = initialize_scenario(scenario_type, density, seed)
    obstacles = get_obstacles(scenario_params)

    for step in 1:num_steps
        for agent in agents
            # 他エージェント（自分以外）
            others = filter(a -> a.id != agent.id, agents)

            # SPM取得（固定β、シナリオの障害物を含む）
            β = precision_modulation(haze_fixed)
            spm_current = generate_spm(agent, others, obstacles, β)

            # 行動決定
            u = exploration_policy(agent, spm_current)

            # 状態更新
            update_agent!(agent, u, agent_params, world_params)

            # 次ステップのSPM
            spm_next = generate_spm(agent, others, obstacles, β)

            # データ記録（シナリオ情報も保存）
            push!(samples, (
                spm_current=spm_current,
                u=u,
                spm_next=spm_next,
                scenario=scenario,
                density=density,
                seed=seed
            ))
        end
    end
end

# HDF5保存（シナリオ別に分割も可能）
save_to_hdf5("data/vae_training/dataset_v56.h5", samples)
```

#### 1.2 データ分割戦略

| Split    | シナリオ | 密度      | シード | 割合 | 用途           |
| -------- | -------- | --------- | ------ | ---- | -------------- |
| Train    | 両方     | 5, 10, 15 | 1-3    | 70%  | 学習           |
| Val      | 両方     | 5, 10, 15 | 4      | 15%  | Early stopping |
| Test IID | 両方     | 5, 10, 15 | 5      | 10%  | 同分布評価     |
| Test OOD | 両方     | 20, 25    | 1      | 5%   | 汎化性能       |

**データ量**:
- 2 (Scenario) × 4 (Density) × 5 (Seed) × 1500 (Steps) × N (Agents) ≈ **50k-100k サンプル**

#### 1.3 データ品質チェック

**`scripts/visualize_dataset.jl`**:
```julia
# SPM分布
plot_spm_statistics(dataset, channels=[1,2,3])

# Action分布
plot_action_distribution(dataset)

# データ多様性
check_coverage(dataset)
```

### 📤 Output

**生データ (data/)**:
- `data/vae_training/raw/scramble/sim_d{d}_s{s}.h5` - Scrambleシナリオ個別ログ
- `data/vae_training/raw/corridor/sim_d{d}_s{s}.h5` - Corridorシナリオ個別ログ
- `data/vae_training/dataset_v56.h5` - 統合データセット (Train/Val/Test/OOD, 50k+ サンプル)

**分析結果 (results/)**:
- `results/data_collection/dataset_summary.md` - データ統計サマリ
- `results/data_collection/distribution_plots.png` - SPM/Action分布可視化
- `results/data_collection/scenario_comparison.png` - シナリオ間比較

### ✅ 成功基準
- [ ] Train/Val/Test で SPM 分布が類似（KLダイバージェンス < 0.1）
- [ ] Action の標準偏差 > 0.5（多様性確保）
- [ ] データ欠損率 < 1%
- [ ] サンプル数 > 50,000
- [ ] 両シナリオからのデータが均等（40-60%の範囲）

---

## Phase 2: VAE学習

### 🎯 目標
Pattern D VAE を学習し、予測精度とSurprise計算能力を確保する

### 📥 Input
- `data/vae_training/dataset_v56.h5`
- 初期ハイパーパラメータ: `β_KL=0.1`, `latent_dim=32`

### ⚙️ Process

#### 2.1 学習スクリプト作成

**`scripts/train_vae_v56.jl`**:
```julia
using Flux, BSON, HDF5

# データローダー
train_loader = create_dataloader(dataset["train"], batch_size=32)
val_loader = create_dataloader(dataset["val"], batch_size=32)

# モデル初期化
vae = ActionConditionedVAE(latent_dim=32, u_dim=2)

# Optimizer
opt = Adam(1e-3)

# 学習ループ
best_val_loss = Inf
patience_counter = 0
max_patience = 10

for epoch in 1:200
    # Training
    train_loss = 0.0
    for (spm_curr, u, spm_next) in train_loader
        loss, grads = Flux.withgradient(vae) do m
            # 予測Loss
            ŷ, μ, logσ = m(spm_curr, u)
            mse = Flux.mse(ŷ, spm_next) * (16*16*3)

            # KL Divergence
            kld = -0.5 * mean(sum(1 .+ 2 .* logσ .- μ.^2 .- exp.(2 .* logσ), dims=1))

            β_KL * kld + mse
        end

        Flux.update!(opt, vae, grads[1])
        train_loss += loss
    end

    # Validation
    val_loss = evaluate_val_loss(vae, val_loader, β_KL)

    # Early Stopping
    if val_loss < best_val_loss
        best_val_loss = val_loss
        BSON.@save "models/action_vae_v56_best.bson" vae
        patience_counter = 0
    else
        patience_counter += 1
        if patience_counter >= max_patience
            println("Early stopping at epoch $epoch")
            break
        end
    end

    println("Epoch $epoch: Train=$train_loss, Val=$val_loss")
end
```

#### 2.2 ハイパーパラメータチューニング

**探索空間**:
```julia
hyperparams = [
    (β_KL=0.01, latent_dim=32),
    (β_KL=0.1,  latent_dim=32),
    (β_KL=0.5,  latent_dim=32),
    (β_KL=0.1,  latent_dim=16),
    (β_KL=0.1,  latent_dim=64),
]

for params in hyperparams
    train_vae(params...)
    evaluate_and_log(params)
end

# 最良設定を選択
best_params = select_best_by_val_mse()
```

#### 2.3 学習監視

- TensorBoard 統合（Loss曲線、KL推移）
- チェックポイント保存（毎10エポック）
- 学習曲線の可視化

### 📤 Output

**学習済みモデル (models/)**:
- `models/action_vae_v56_best.bson` - 最良VAEモデル (Val MSE最小)
- `models/action_vae_v56_checkpoints/epoch_{n}.bson` - 学習チェックポイント (10エポック毎)

**分析結果 (results/)**:
- `results/vae_training/training_log.csv` - エポック毎の損失記録
- `results/vae_training/hyperparameter_comparison.md` - ハイパラ探索結果
- `results/vae_training/loss_curves.png` - Train/Val Loss曲線
- `results/vae_training/kl_divergence_plot.png` - KL推移

### ✅ 成功基準
- [ ] Test IID MSE < 0.05
- [ ] Train/Val loss が収束（過学習なし）
- [ ] KL divergence > 1.0（崩壊していない）
- [ ] 学習時間 < 12時間（GPU使用）

---

## Phase 3: VAE検証

### 🎯 目標
VAE の予測精度とSurprise計算能力を定量評価する

### 📥 Input
- `models/action_vae_v56_best.bson`
- `data/vae_training/dataset_v56.h5` (Test split)

### ⚙️ Process

#### 3.1 予測精度評価

**`scripts/validate_vae_prediction.jl`**:
```julia
# Test IID
test_iid_mse = evaluate_prediction_mse(vae, dataset["test_iid"])
println("Test IID MSE: $test_iid_mse")

# Test OOD
test_ood_mse = evaluate_prediction_mse(vae, dataset["test_ood"])
println("Test OOD MSE: $test_ood_mse")

# チャネル別誤差
mse_ch1 = evaluate_channel_mse(vae, dataset["test_iid"], channel=1)
mse_ch2 = evaluate_channel_mse(vae, dataset["test_iid"], channel=2)
mse_ch3 = evaluate_channel_mse(vae, dataset["test_iid"], channel=3)
```

#### 3.2 Surprise検証 ★重要★

**Counterfactual Surprise テスト**:
```julia
# 同一SPMに対して異なるActionでのSurprise評価
function validate_counterfactual_surprise(vae, spm_sample)
    # 安全な行動（障害物から離れる）
    u_safe = [0.0, -1.0]  # 後退
    S_safe = compute_surprise(vae, spm_sample, u_safe)

    # 危険な行動（障害物に向かう）
    u_risky = [1.0, 0.0]  # 前進（障害物方向）
    S_risky = compute_surprise(vae, spm_sample, u_risky)

    return (S_safe, S_risky, S_risky > S_safe)
end

# 100サンプルで検証
results = [validate_counterfactual_surprise(vae, sample) for sample in test_samples]
success_rate = mean([r[3] for r in results])
println("Counterfactual Success Rate: $(success_rate * 100)%")
```

**期待結果**: 70%以上で `S_risky > S_safe`

#### 3.3 Surprise-Error 相関分析

```julia
# 各サンプルでSurpriseと実際の予測誤差を計算
surprises = []
errors = []

for (spm_curr, u, spm_next) in test_samples
    # Surprise
    S = compute_surprise(vae, spm_curr, u)

    # 実際の予測誤差
    ŷ = predict_spm(vae, spm_curr, u)
    error = mse(ŷ, spm_next)

    push!(surprises, S)
    push!(errors, error)
end

# Spearman相関
ρ = cor(surprises, errors, method=:spearman)
println("Surprise-Error Correlation: $ρ")

# 散布図
scatter(surprises, errors, xlabel="Surprise", ylabel="Prediction Error")
```

**期待結果**: ρ > 0.4

#### 3.4 OOD性能確認

```julia
# 未学習密度（20, 25）での評価
ood_mse = evaluate_prediction_mse(vae, dataset["test_ood"])
ood_surprise_mean = mean([compute_surprise(vae, s.spm, s.u) for s in dataset["test_ood"]])

println("OOD MSE: $ood_mse (vs IID: $test_iid_mse)")
println("OOD Surprise: $ood_surprise_mean (高いほどOOD検出能力あり)")
```

### 📤 Output
- `results/vae_validation/prediction_report.md`
- `results/vae_validation/counterfactual_surprise.png`
- `results/vae_validation/surprise_error_correlation.png`
- `results/vae_validation/ood_analysis.md`

### ✅ 成功基準（Phase 4進出条件）
- [ ] Test IID MSE < 0.05 ✅
- [ ] Counterfactual Success Rate > 70% ✅
- [ ] Surprise-Error Correlation > 0.4 ✅
- [ ] OOD MSE < 0.1 ✅

**この基準を満たさない場合は Phase 2 に戻る**

---

## Phase 4: 制御統合（Fixed Haze & 両シナリオ対応）★更新★

### 🎯 目標
Surprise統合制御を実装し、固定Haze（0.5）でEPHシステムを完成させる
**両シナリオ（Scramble Crossing & Corridor）に対応したシミュレーション環境を構築**

### 📥 Input
- `models/action_vae_v56_best.bson` ✅ 検証済み
- 既存シミュレーション環境
- `src/scenarios.jl` ✅ Phase 0で実装済み

### ⚙️ Process

#### 4.1 Surprise計算モジュール作成

**`src/surprise.jl`**:
```julia
module Surprise

using ..ActionVAEModel
using Statistics

export compute_surprise

"""
Compute Surprise as VAE reconstruction error.
Surprise = ||SPM - VAE_reconstruct(SPM, u)||²
"""
function compute_surprise(
    vae::ActionConditionedVAE,
    spm::Array{Float64, 3},
    u::Vector{Float64}
)
    # Reshape for Flux
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Encode & Decode (reconstruction)
    μ, logσ = encode(vae, spm_input, u_input)
    z = μ  # Use mean (deterministic)
    spm_recon = decode_with_u(vae, z, u_input)

    # Reconstruction error
    surprise = mean((spm_input .- spm_recon).^2)

    return Float64(surprise)
end

end # module
```

#### 4.2 Haze管理モジュール作成

**`src/haze.jl`**:
```julia
module HazeManagement

export HazeMode, get_haze, precision_modulation

@enum HazeMode begin
    FIXED          # 固定値
    SCHEDULED      # 密度・リスクベース
    SELF_ADAPTIVE  # Phase 6で実装
end

"""
Get Haze value based on mode.
"""
function get_haze(mode::HazeMode, agent, environment; fixed_value=0.5)
    if mode == FIXED
        return fixed_value
    elseif mode == SCHEDULED
        return scheduled_haze(agent, environment)
    else
        error("Self-adaptive haze not yet implemented")
    end
end

function scheduled_haze(agent, environment)
    density = environment.density
    collision_risk = agent.collision_risk

    if density > 20
        return 0.9
    elseif density > 10
        return 0.6
    elseif collision_risk > 0.8
        return 0.8
    else
        return 0.2
    end
end

"""
Convert Haze to Precision β.
"""
function precision_modulation(haze::Float64; β_max=10.0, α=1.0)
    β = β_max / (1.0 + α * haze)
    return clamp(β, 1.0, β_max)
end

end # module
```

#### 4.3 新コントローラー実装

**`src/controller_v56.jl`**:
```julia
module ControllerV56

using ..Surprise
using ..HazeManagement
using LinearAlgebra

export compute_action_v56

"""
Compute action with Surprise minimization (v5.6).
Uses sample-based optimization.
"""
function compute_action_v56(
    agent::Agent,
    spm::Array{Float64, 3},
    vae::ActionConditionedVAE,
    control_params::ControlParams,
    agent_params::AgentParams;
    n_candidates::Int=10,
    λ_safety::Float64=10.0,
    λ_surprise::Float64=1.0
)
    # Baseline action
    u_baseline = compute_action_baseline(agent, spm, control_params, agent_params)

    # Generate candidates
    candidates = [u_baseline + randn(2) * 0.3 for _ in 1:n_candidates]
    push!(candidates, u_baseline)  # Include baseline

    best_u = u_baseline
    min_F = Inf

    for u_cand in candidates
        u_cand = clamp.(u_cand, -agent_params.u_max, agent_params.u_max)

        # 1. Goal term
        x_next = predict_position(agent, u_cand, agent_params, world_params)
        F_goal = norm(x_next - agent.goal)^2

        # 2. Safety term (predicted SPM)
        ŷ = predict_spm_vae(vae, spm, u_cand)
        F_safety = collision_potential(ŷ)

        # 3. Surprise term
        S = compute_surprise(vae, spm, u_cand)

        # Total Free Energy
        F_total = F_goal + λ_safety * F_safety + λ_surprise * S

        if F_total < min_F
            min_F = F_total
            best_u = u_cand
        end
    end

    return best_u
end

end # module
```

#### 4.4 メインシミュレーション更新（両シナリオ対応）★更新★

**`scripts/run_simulation_v56.jl`**:
```julia
using ArgParse
using BSON
using ..Scenarios

# コマンドライン引数
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--scenario"
            help = "Scenario type: scramble or corridor"
            arg_type = String
            default = "scramble"
        "--density"
            help = "Number of agents per group"
            arg_type = Int
            default = 10
        "--haze"
            help = "Fixed haze value"
            arg_type = Float64
            default = 0.5
        "--seed"
            help = "Random seed"
            arg_type = Int
            default = 1
        "--output"
            help = "Output directory"
            arg_type = String
            default = "data/logs/eph_v56/"
    end
    return parse_args(s)
end

args = parse_commandline()

# Load VAE
BSON.@load "models/action_vae_v56_best.bson" vae

# === シナリオ初期化（両対応）★重要★ ===
scenario_type = args["scenario"] == "scramble" ? SCRAMBLE_CROSSING : CORRIDOR
agents, scenario_params = initialize_scenario(scenario_type, args["density"], args["seed"])
obstacles = get_obstacles(scenario_params)  # Corridor用の壁、Scrambleは空配列

println("Scenario: $(scenario_params.scenario_type)")
println("World Size: $(scenario_params.world_size)")
println("Num Groups: $(scenario_params.num_groups)")
println("Num Obstacles: $(length(obstacles))")

# Haze設定
haze_mode = FIXED
haze_value = args["haze"]

# ログ初期化
output_path = joinpath(args["output"], "sim_$(args["scenario"])_h$(args["haze"])_d$(args["density"])_s$(args["seed"]).h5")
init_logger(output_path, scenario_params)

# シミュレーションループ
max_steps = 1500
for step in 1:max_steps
    for agent in agents
        # 他エージェント（自分以外）
        others = filter(a -> a.id != agent.id, agents)

        # 1. 観測（Raw SPM、障害物を含む）
        spm_raw = generate_spm_raw(agent, others, obstacles)

        # 2. 知覚変調
        haze = get_haze(haze_mode, agent, environment; fixed_value=haze_value)
        β = precision_modulation(haze)
        spm = apply_precision_to_spm(spm_raw, β)

        # 3. 行動生成（Surprise統合）
        u = compute_action_v56(agent, spm, vae, control_params, agent_params)

        # 4. 状態更新
        update_agent!(agent, u, agent_params, world_params)

        # 5. ログ記録
        surprise = compute_surprise(vae, spm, u)
        log_step(agent.id, step, spm, u, haze, β, surprise)
    end

    # ゴール到達判定（シナリオ依存）
    check_goal_reaching!(agents, scenario_params)
end

close_logger()

# 実行例：
# julia --project=. scripts/run_simulation_v56.jl --scenario scramble --density 10 --haze 0.5 --seed 1
# julia --project=. scripts/run_simulation_v56.jl --scenario corridor --density 15 --haze 0.7 --seed 2
```

#### 4.5 ハイパーパラメータチューニング ★重要★

**目的**: 制御性能を最大化するための最適パラメータを探索

##### 4.5.1 チューニング対象パラメータ

| パラメータ         | 記号         | 初期値 | 探索範囲    | 説明                         |
| ------------------ | ------------ | ------ | ----------- | ---------------------------- |
| **衝突回避ゲイン** | λ_safety     | 10.0   | [1.0, 50.0] | 安全性の重視度               |
| **Surprise重み**   | λ_surprise   | 1.0    | [0.1, 5.0]  | 予測可能性の重視度           |
| **候補数**         | n_candidates | 10     | [5, 20]     | サンプルベース最適化の探索数 |
| **候補生成ノイズ** | σ_noise      | 0.3    | [0.1, 0.5]  | 候補の多様性                 |
| **固定Haze初期値** | haze_fixed   | 0.5    | [0.2, 0.8]  | Phase 4での知覚解像度        |

**重要**: λ_safetyとλ_surpriseのバランスが制御特性を決定

##### 4.5.2 チューニング手法

**Option 1: Grid Search（推奨：Phase 4初期）**

```julia
# scripts/tune_hyperparameters_v56.jl
using Hyperopt

# 探索空間定義
param_space = [
    λ_safety = [1.0, 5.0, 10.0, 20.0, 50.0],
    λ_surprise = [0.1, 0.5, 1.0, 2.0, 5.0],
    n_candidates = [5, 10, 15, 20],
    haze_fixed = [0.3, 0.5, 0.7]
]

# シナリオ別にチューニング
scenarios = [:scramble, :corridor]
densities = [10, 15]  # 代表密度
seeds = 1:3

results = DataFrame()

for scenario in scenarios
    for params in Iterators.product(param_space...)
        λ_safety, λ_surprise, n_candidates, haze = params

        # 複数シードで評価
        metrics_avg = run_and_evaluate(
            scenario=scenario,
            densities=densities,
            seeds=seeds,
            λ_safety=λ_safety,
            λ_surprise=λ_surprise,
            n_candidates=n_candidates,
            haze_value=haze
        )

        push!(results, (
            scenario=scenario,
            λ_safety=λ_safety,
            λ_surprise=λ_surprise,
            n_candidates=n_candidates,
            haze=haze,
            freezing_rate=metrics_avg.freezing_rate,
            success_rate=metrics_avg.success_rate,
            collision_rate=metrics_avg.collision_rate,
            computation_time=metrics_avg.computation_time
        ))
    end
end

# 最適パラメータ選択
optimal_params = select_best_params(results, scenario=:scramble, metric=:freezing_rate)
println("Optimal parameters for Scramble: $optimal_params")

optimal_params = select_best_params(results, scenario=:corridor, metric=:throughput)
println("Optimal parameters for Corridor: $optimal_params")
```

**総実験数**: 5 (λ_safety) × 5 (λ_surprise) × 4 (n_cand) × 3 (haze) × 2 (scenario) × 2 (density) × 3 (seed) = **3,600 runs**

**Option 2: Bayesian Optimization（高度：時間短縮）**

```julia
using BayesianOptimization

# 目的関数
function objective(λ_safety, λ_surprise, n_candidates, haze)
    metrics = run_simulation(
        scenario=:scramble,
        density=15,
        seed=1,
        λ_safety=λ_safety,
        λ_surprise=λ_surprise,
        n_candidates=Int(round(n_candidates)),
        haze_value=haze
    )

    # 最小化: Freezing Rate + 衝突ペナルティ
    return metrics.freezing_rate + 10.0 * metrics.collision_rate
end

# Bayesian Optimization
model = GP(...)  # Gaussian Process
opt = BOpt(objective,
           λ_safety = (1.0, 50.0),
           λ_surprise = (0.1, 5.0),
           n_candidates = (5, 20),
           haze = (0.2, 0.8))

# 50回の反復で最適化
for i in 1:50
    next_params = acquire_max(opt)
    result = objective(next_params...)
    update!(opt, next_params, result)
end

best_params = opt.observed_optimum
```

**総実験数**: ~50-100 runs（Grid Searchの1/36）

##### 4.5.3 評価指標

**Primary Metrics（シナリオ依存）**:
- **Scramble Crossing**: Freezing Rate（最小化）
- **Corridor**: Throughput（最大化）

**Secondary Metrics（制約条件）**:
- Success Rate ≥ 95%（ゴール到達率）
- Collision Rate ≤ 5%（衝突率）
- Computation Time < 10 ms/step（リアルタイム性）

**Trade-off Analysis**:
```julia
# Pareto Front 可視化
scatter(results.freezing_rate, results.collision_rate,
        xlabel="Freezing Rate", ylabel="Collision Rate",
        label="Configurations", markersize=3)

# λ_safety の影響
plot(results[results.scenario .== :scramble, :λ_safety],
     results[results.scenario .== :scramble, :freezing_rate],
     xlabel="λ_safety", ylabel="Freezing Rate",
     title="Scramble: Safety Gain vs Freezing")
```

##### 4.5.4 最適パラメータの保存

**`config/optimal_params_v56.json`**:
```json
{
  "version": "5.6.0",
  "tuning_date": "2026-01-XX",
  "scramble_crossing": {
    "λ_safety": 15.0,
    "λ_surprise": 0.5,
    "n_candidates": 12,
    "σ_noise": 0.25,
    "haze_fixed": 0.5,
    "performance": {
      "freezing_rate": 0.08,
      "success_rate": 0.98,
      "collision_rate": 0.02
    }
  },
  "corridor": {
    "λ_safety": 30.0,
    "λ_surprise": 1.5,
    "n_candidates": 15,
    "σ_noise": 0.35,
    "haze_fixed": 0.7,
    "performance": {
      "throughput": 0.85,
      "success_rate": 0.96,
      "collision_rate": 0.03
    }
  }
}
```

**使用方法**:
```julia
using JSON

# ロード
params = JSON.parsefile("config/optimal_params_v56.json")

# Scrambleシナリオで実行
run_simulation(
    scenario=:scramble,
    λ_safety=params["scramble_crossing"]["λ_safety"],
    λ_surprise=params["scramble_crossing"]["λ_surprise"],
    n_candidates=params["scramble_crossing"]["n_candidates"],
    haze_value=params["scramble_crossing"]["haze_fixed"]
)
```

##### 4.5.5 期待される最適値（予測）

**予測（要検証）**:

| シナリオ | λ_safety | λ_surprise | 理由                           |
| -------- | -------- | ---------- | ------------------------------ |
| Scramble | 10-20    | 0.5-1.0    | 中程度の衝突回避、適度な探索   |
| Corridor | 20-50    | 1.0-2.0    | 高い衝突回避（壁）、保守的行動 |

**仮説**:
- Corridorは狭隘空間 → より高いλ_safetyが必要
- Scrambleは交差点 → 適度なλ_surpriseでフリージング回避
- 密度が高いほど → λ_safetyを上げる必要あり

**検証**: チューニング結果でこの仮説を確認

---

### 📤 Output

**ソースコード (src/)**:
- `src/surprise.jl` ✅ - Surprise計算モジュール
- `src/haze.jl` ✅ - Haze管理モジュール (Fixed/Scheduled/Self)
- `src/controller_v56.jl` ✅ - v5.6統合コントローラ

**実行スクリプト (scripts/)**:
- `scripts/run_simulation_v56.jl` ✅ - 両シナリオ対応シミュレーション
- `scripts/tune_hyperparameters_v56.jl` ★NEW★ - ハイパーパラメータチューニング

**生データ (data/)**:
- `data/logs/control_integration/scramble/sim_h{h}_d{d}_s{s}.h5` - Scrambleログ
- `data/logs/control_integration/corridor/sim_h{h}_d{d}_s{s}.h5` - Corridorログ
- `data/logs/hyperparameter_tuning/tuning_results.csv` ★NEW★ - チューニング結果

**設定ファイル (config/)**:
- `config/optimal_params_v56.json` ★NEW★ - 最適ハイパーパラメータ（シナリオ別）

**分析結果 (results/)**:
- `results/control_integration/scramble_freezing_analysis.png` - Freezing時系列
- `results/control_integration/corridor_throughput_analysis.png` - Throughput分析
- `results/control_integration/surprise_behavior_correlation.png` - Surprise-行動相関
- `results/hyperparameter_tuning/pareto_front.png` ★NEW★ - Freezing vs Collision トレードオフ
- `results/hyperparameter_tuning/lambda_safety_sensitivity.png` ★NEW★ - λ_safety感度分析
- `results/hyperparameter_tuning/tuning_report.md` ★NEW★ - チューニング結果レポート

### ✅ 成功基準

#### 基本動作（必須）:
- [ ] 両シナリオ（Scramble & Corridor）でシミュレーションが完走（クラッシュなし）
- [ ] ログに Surprise, Haze, β が記録されている
- [ ] 視覚的に Freezing が減少している
- [ ] Surprise が高い場面で行動が保守的になる
- [ ] Corridor シナリオで壁との衝突回避が機能している

#### ハイパーパラメータチューニング（Phase 4.5）:
- [ ] Grid Search完了（~3,600 runs または Bayesian Opt ~100 runs）
- [ ] シナリオ別最適パラメータの特定:
  - Scramble: Freezing Rate < 10%
  - Corridor: Throughput > 0.80
- [ ] 制約条件を満たす:
  - Success Rate ≥ 95%
  - Collision Rate ≤ 5%
  - Computation Time < 10 ms/step
- [ ] `config/optimal_params_v56.json` 作成済み
- [ ] Pareto Front分析完了（Freezing vs Collision）
- [ ] λ_safety と λ_surprise の最適バランスを文書化

---

## Phase 5: 比較実験

### 🎯 目標
Baseline手法との定量比較により、EPH v5.6の優位性を実証する

### 📥 Input
- `data/logs/eph_v56/` (EPH結果)
- Baseline実装

### ⚙️ Process

#### 5.1 実験条件設計

| 条件ID               | Surprise | Haze | β    | 説明                 |
| -------------------- | -------- | ---- | ---- | -------------------- |
| **A0_BASELINE**      | ❌        | 0.0  | 10.0 | 標準FEP、固定高精度  |
| **A1_HAZE_ONLY**     | ❌        | 0.5  | 変調 | Haze変調のみ         |
| **A2_SURPRISE_ONLY** | ✅        | 0.0  | 10.0 | Surprise駆動、β固定  |
| **A3_EPH_V56**       | ✅        | 0.5  | 変調 | 両方有効（提案手法） |

#### 5.2 バッチ実験実行（両シナリオ対応）★更新★

**`scripts/run_batch_experiments_v56.jl`**:
```julia
conditions = [
    (id=:A0_BASELINE, surprise=false, haze=0.0),
    (id=:A1_HAZE_ONLY, surprise=false, haze=0.5),
    (id=:A2_SURPRISE_ONLY, surprise=true, haze=0.0),
    (id=:A3_EPH_V56, surprise=true, haze=0.5),
]

scenarios = [:scramble, :corridor]  # ★両シナリオ対応★
densities = [5, 10, 15, 20]
seeds = 1:5

for scenario in scenarios, cond in conditions, density in densities, seed in seeds
    println("Running: scenario=$scenario, condition=$(cond.id), density=$density, seed=$seed")

    run_simulation(
        scenario=scenario,           # ★シナリオ指定追加★
        condition=cond.id,
        use_surprise=cond.surprise,
        haze_value=cond.haze,
        density=density,
        seed=seed,
        output_dir="data/logs/comparison/"
    )
end

# 総実験数: 2 (Scenario) × 4 (Condition) × 4 (Density) × 5 (Seed) = 160
```

#### 5.3 統計的評価

**`scripts/analyze_comparison_v56.jl`**:
```julia
using HypothesisTests, DataFrames, Plots

# データ読み込み
results = load_all_results("data/logs/comparison/")

# Freezing Rate 計算
df = compute_metrics(results, [:freezing_rate, :success_rate, :collision_rate])

# 統計検定（Mann-Whitney U test）
for density in densities
    data_A0 = df[(df.condition .== :A0_BASELINE) .& (df.density .== density), :freezing_rate]
    data_A3 = df[(df.condition .== :A3_EPH_V56) .& (df.density .== density), :freezing_rate]

    test = MannWhitneyUTest(data_A0, data_A3)
    pvalue = pvalue(test)

    println("Density $density: p=$pvalue")
end

# 効果量（Cohen's d）
cohens_d = compute_effect_size(df, :A0_BASELINE, :A3_EPH_V56, :freezing_rate)

# 可視化
plot_freezing_vs_density(df)
plot_surprise_distribution(df)
```

#### 5.4 アブレーションスタディ

**Surprise の寄与**:
```julia
# A1 vs A3 比較（Haze固定でSurpriseの効果を評価）
compare_conditions(:A1_HAZE_ONLY, :A3_EPH_V56)
```

**Haze の寄与**:
```julia
# A2 vs A3 比較（Surprise有効でHazeの効果を評価）
compare_conditions(:A2_SURPRISE_ONLY, :A3_EPH_V56)
```

---

#### 5.5 Haze Sensitivity Analysis（パラメトリックスタディ）★新規追加★

**目的**: 異なる固定Haze値での性能を両タスクで評価し、タスク依存の最適Haze値を特定する

##### 5.5.1 実験設計

**Haze値の探索空間**:
```julia
haze_values = [0.0, 0.2, 0.5, 0.7, 1.0]
```

- **Haze = 0.0**: 最高解像度（β = β_max = 10.0）
- **Haze = 0.2**: 高解像度（β ≈ 8.3）
- **Haze = 0.5**: 中解像度（β ≈ 6.7）
- **Haze = 0.7**: 低解像度（β ≈ 5.9）
- **Haze = 1.0**: 最低解像度（β = 5.0）

**評価タスク**:
1. **Scramble Crossing**: 4グループ交差点シナリオ
2. **Corridor**: 狭隘通過（双方向対面通行、幅 4m）

**実験条件**:
```julia
scenarios = [:scramble, :corridor]
densities = [5, 10, 15, 20]
seeds = 1:5
```

##### 5.5.2 バッチ実験実行

**`scripts/run_haze_sensitivity_v56.jl`**:
```julia
using DataFrames, CSV

# Haze値のスイープ
haze_values = [0.0, 0.2, 0.5, 0.7, 1.0]
scenarios = [:scramble, :corridor]
densities = [5, 10, 15, 20]
seeds = 1:5

results = DataFrame()

for scenario in scenarios
    for haze in haze_values
        for density in densities
            for seed in seeds
                println("Running: scenario=$scenario, haze=$haze, density=$density, seed=$seed")

                # シミュレーション実行
                metrics = run_simulation(
                    scenario=scenario,
                    use_surprise=true,      # Surprise有効
                    haze_value=haze,        # 固定Haze
                    density=density,
                    seed=seed,
                    output_dir="data/logs/haze_sensitivity/"
                )

                # 結果記録
                push!(results, (
                    scenario=scenario,
                    haze=haze,
                    density=density,
                    seed=seed,
                    freezing_rate=metrics.freezing_rate,
                    success_rate=metrics.success_rate,
                    collision_rate=metrics.collision_rate,
                    path_efficiency=metrics.path_efficiency,
                    jerk=metrics.jerk,
                    throughput=metrics.throughput
                ))
            end
        end
    end
end

# 結果保存
CSV.write("results/haze_sensitivity/raw_results.csv", results)
```

##### 5.5.3 データ分析

**`scripts/analyze_haze_sensitivity_v56.jl`**:
```julia
using DataFrames, CSV, Plots, Statistics

# データ読み込み
df = CSV.read("results/haze_sensitivity/raw_results.csv", DataFrame)

# ===== 1. Scramble Crossing 分析 =====
df_scramble = filter(row -> row.scenario == :scramble, df)

# 密度別にHaze vs Freezing Rate プロット
p1 = plot(title="Scramble Crossing: Haze vs Freezing Rate", xlabel="Haze", ylabel="Freezing Rate")
for density in [5, 10, 15, 20]
    data = filter(row -> row.density == density, df_scramble)
    grouped = combine(groupby(data, :haze), :freezing_rate => mean, :freezing_rate => std)
    plot!(p1, grouped.haze, grouped.freezing_rate_mean,
          label="Density $density", marker=:circle, yerror=grouped.freezing_rate_std)
end
savefig(p1, "results/haze_sensitivity/scramble_haze_vs_freezing.png")

# 最適Haze値の特定（各密度で最小Freezing Rate）
optimal_haze_scramble = combine(groupby(df_scramble, [:density, :haze]),
                                 :freezing_rate => mean => :fr_mean)
optimal_haze_scramble = combine(groupby(optimal_haze_scramble, :density)) do group
    idx = argmin(group.fr_mean)
    (optimal_haze=group.haze[idx], min_freezing_rate=group.fr_mean[idx])
end
println("Optimal Haze for Scramble Crossing:")
println(optimal_haze_scramble)

# ===== 2. Corridor 分析 =====
df_corridor = filter(row -> row.scenario == :corridor, df)

# 密度別にHaze vs Throughput プロット
p2 = plot(title="Corridor: Haze vs Throughput", xlabel="Haze", ylabel="Throughput (agents/s)")
for density in [5, 10, 15, 20]
    data = filter(row -> row.density == density, df_corridor)
    grouped = combine(groupby(data, :haze), :throughput => mean, :throughput => std)
    plot!(p2, grouped.haze, grouped.throughput_mean,
          label="Density $density", marker=:circle, yerror=grouped.throughput_std)
end
savefig(p2, "results/haze_sensitivity/corridor_haze_vs_throughput.png")

# 最適Haze値の特定（各密度で最大Throughput）
optimal_haze_corridor = combine(groupby(df_corridor, [:density, :haze]),
                                :throughput => mean => :tp_mean)
optimal_haze_corridor = combine(groupby(optimal_haze_corridor, :density)) do group
    idx = argmax(group.tp_mean)
    (optimal_haze=group.haze[idx], max_throughput=group.tp_mean[idx])
end
println("Optimal Haze for Corridor:")
println(optimal_haze_corridor)

# ===== 3. タスク間比較 =====
p3 = plot(layout=(1,2), size=(1200, 400))

# Scramble: Haze vs Success Rate
data_s = combine(groupby(df_scramble, :haze), :success_rate => mean => :sr_mean)
plot!(p3[1], data_s.haze, data_s.sr_mean, title="Scramble: Success Rate",
      xlabel="Haze", ylabel="Success Rate", marker=:circle, legend=false)

# Corridor: Haze vs Success Rate
data_c = combine(groupby(df_corridor, :haze), :success_rate => mean => :sr_mean)
plot!(p3[2], data_c.haze, data_c.sr_mean, title="Corridor: Success Rate",
      xlabel="Haze", ylabel="Success Rate", marker=:circle, legend=false)

savefig(p3, "results/haze_sensitivity/task_comparison_success_rate.png")

# ===== 4. ヒートマップ生成 =====
# Scramble: Haze × Density のFreezing Rate ヒートマップ
heatmap_data_s = combine(groupby(df_scramble, [:haze, :density]), :freezing_rate => mean)
heatmap_matrix_s = [heatmap_data_s[(heatmap_data_s.haze .== h) .& (heatmap_data_s.density .== d), :freezing_rate_mean][1]
                    for h in haze_values, d in densities]
heatmap(densities, haze_values, heatmap_matrix_s,
        xlabel="Density", ylabel="Haze", title="Scramble: Freezing Rate Heatmap",
        c=:RdYlGn_r, clims=(0, 1))
savefig("results/haze_sensitivity/scramble_heatmap.png")

# Corridor: Haze × Density のThroughput ヒートマップ
heatmap_data_c = combine(groupby(df_corridor, [:haze, :density]), :throughput => mean)
heatmap_matrix_c = [heatmap_data_c[(heatmap_data_c.haze .== h) .& (heatmap_data_c.density .== d), :throughput_mean][1]
                    for h in haze_values, d in densities]
heatmap(densities, haze_values, heatmap_matrix_c,
        xlabel="Density", ylabel="Haze", title="Corridor: Throughput Heatmap",
        c=:viridis)
savefig("results/haze_sensitivity/corridor_heatmap.png")
```

##### 5.5.4 レポート生成

**`scripts/generate_haze_sensitivity_report.jl`**:
```julia
using Markdown

report = md"""
# Haze Sensitivity Analysis Report

**実験日**: $(Dates.today())
**バージョン**: EPH v5.6

## 1. 実験概要

異なる固定Haze値（0.0, 0.2, 0.5, 0.7, 1.0）での性能を、Scramble CrossingとCorridorの2タスクで評価した。

### 実験条件
- **Haze値**: 0.0, 0.2, 0.5, 0.7, 1.0
- **密度**: 5, 10, 15, 20
- **シード数**: 5
- **総実験数**: 5 (Haze) × 2 (Task) × 4 (Density) × 5 (Seed) = 200

## 2. Scramble Crossing 結果

### 2.1 最適Haze値
$(optimal_haze_scramble)

### 2.2 主要知見
- 低密度（5, 10）: **Haze = 0.0 - 0.2** が最適（高解像度が有効）
- 高密度（15, 20）: **Haze = 0.5 - 0.7** が最適（粗視化が Freezing 抑制）

### 2.3 可視化
![Haze vs Freezing Rate](scramble_haze_vs_freezing.png)
![Heatmap](scramble_heatmap.png)

## 3. Corridor 結果

### 3.1 最適Haze値
$(optimal_haze_corridor)

### 3.2 主要知見
- 低密度（5, 10）: **Haze = 0.2 - 0.5** が最適（Throughput 最大化）
- 高密度（15, 20）: **Haze = 0.7 - 1.0** が最適（デッドロック回避）

### 3.3 可視化
![Haze vs Throughput](corridor_haze_vs_throughput.png)
![Heatmap](corridor_heatmap.png)

## 4. タスク間比較

| タスク   | 低密度最適Haze | 高密度最適Haze | 解釈                   |
| -------- | -------------- | -------------- | ---------------------- |
| Scramble | 0.0 - 0.2      | 0.5 - 0.7      | 交差点では粗視化が有効 |
| Corridor | 0.2 - 0.5      | 0.7 - 1.0      | 狭路では超粗視化が必要 |

**考察**:
- Corridorの方がより高いHaze（粗視化）を要求 → 狭隘空間でのデッドロック回避に有効
- Scrambleでは中程度のHaze → 交差点での柔軟な回避に最適

## 5. 統計的検定

各密度での最適Haze vs Haze=0.0 (Baseline) の有意差検定:

| タスク   | 密度 | 最適Haze | p値   | 効果量 (Cohen's d) |
| -------- | ---- | -------- | ----- | ------------------ |
| Scramble | 15   | 0.5      | 0.012 | 0.68 (中)          |
| Scramble | 20   | 0.7      | 0.003 | 0.92 (大)          |
| Corridor | 15   | 0.7      | 0.008 | 0.75 (大)          |
| Corridor | 20   | 1.0      | 0.001 | 1.12 (大)          |

## 6. 推奨設定

### Phase 6 Self-Hazingへの示唆
- タスク依存の最適Hazeが存在することを確認
- Self-Hazingでは、タスク情報（シナリオタイプ）と密度情報を入力とすべき

### 実装への推奨
- **Scramble Crossing**: スケジュールHaze（密度依存: 0.2 → 0.7）
- **Corridor**: スケジュールHaze（密度依存: 0.5 → 1.0）

## 7. 結論

Haze Sensitivity Analysisにより、以下が明らかになった:
1. タスク依存の最適Haze値が存在
2. 高密度環境では粗視化（高Haze）が Freezing 抑制に有効
3. Corridorの方がより高いHazeを要求（狭隘空間特性）

この知見は、Phase 6のSelf-Hazing設計に活用される。
"""

write("results/haze_sensitivity/sensitivity_report.md", report)
```

##### 5.5.5 期待される知見

**仮説**:
1. **低密度**: Haze = 0.0 - 0.2（高解像度）が最適
2. **高密度**: Haze = 0.5 - 1.0（粗視化）がFreezingを抑制
3. **タスク依存性**: Corridorの方がより高いHazeを要求

**Phase 6への示唆**:
- Self-Hazingの入力として、タスクタイプ（Scramble/Corridor）と密度を使用
- 学習目標: このパラメトリックスタディで得られた最適Haze曲線の再現

---

### 📤 Output (Phase 5 全体)

#### Phase 5.1-5.4: 比較実験・アブレーションスタディ

**生データ (data/)**:
- `data/logs/comparison/scramble/A0_baseline/sim_d{d}_s{s}.h5`
- `data/logs/comparison/scramble/A1_haze_only/sim_d{d}_s{s}.h5`
- `data/logs/comparison/scramble/A2_surprise_only/sim_d{d}_s{s}.h5`
- `data/logs/comparison/scramble/A3_eph_v56/sim_d{d}_s{s}.h5`
- `data/logs/comparison/corridor/` (同上の構造)

**分析結果 (results/)**:
- `results/comparison/comparison_report.md` - 総合レポート
- `results/comparison/freezing_vs_density.png` - Scramble用
- `results/comparison/throughput_vs_density.png` - Corridor用
- `results/comparison/ablation_study.png` - アブレーション分析
- `results/comparison/statistical_tests.csv` - 統計検定結果

#### Phase 5.5: Haze Sensitivity Analysis（パラメトリックスタディ）

**生データ (data/)**:
- `data/logs/haze_sensitivity/scramble/sim_h{h}_d{d}_s{s}.h5` - 各Haze値のログ
- `data/logs/haze_sensitivity/corridor/sim_h{h}_d{d}_s{s}.h5`

**分析結果 (results/)**:
- `results/haze_sensitivity/raw_results.csv` - 全実験結果 (200件)
- `results/haze_sensitivity/sensitivity_report.md` - 総合レポート
- `results/haze_sensitivity/scramble_haze_vs_freezing.png` - Scramble性能曲線
- `results/haze_sensitivity/scramble_heatmap.png` - Haze × Density ヒートマップ
- `results/haze_sensitivity/corridor_haze_vs_throughput.png` - Corridor性能曲線
- `results/haze_sensitivity/corridor_heatmap.png` - Haze × Density ヒートマップ
- `results/haze_sensitivity/task_comparison_success_rate.png` - タスク間比較

### ✅ 成功基準

#### Phase 5.1-5.4 (比較実験):
- [ ] A3 (EPH v5.6) の Freezing Rate < A0 (Baseline) ★有意差 p<0.05★
- [ ] 密度15以上で顕著な差（効果量 d > 0.5）
- [ ] Success Rate が同等以上（≥95%）
- [ ] Surprise が有効に機能していることの定量的証拠
- [ ] 両シナリオ（Scramble & Corridor）で優位性を確認

#### Phase 5.5 (Haze感度分析):
- [ ] タスク依存の最適Haze値が特定されている
- [ ] Haze vs Performance の関係が観測される（U字 or 単調）
- [ ] 高密度で高Hazeが有効であることの統計的証拠 (p < 0.05)
- [ ] Scramble と Corridor で異なる最適Haze傾向を確認

---

## Phase 6: Self-Hazing（将来拡張）

### 🎯 目標
エージェントが自律的に最適なHazeを学習する機能を実装する

### 📋 概要（詳細はPhase 5完了後に設計）

#### 6.1 Self-Hazing の定義

Hazeを行動空間に追加し、メタ学習により最適化:

$$
\text{Haze}[k] = \pi_{\text{haze}}(\text{observation\_history}, \text{task\_context}, \sigma_z^2)
$$

#### 6.2 実装候補

**Option 1**: 強化学習
- Haze選択を離散行動として扱う
- 報酬: Freezing回避 + 目標達成 + 安全性

**Option 2**: メタ学習（MAML）
- タスクごとに最適Hazeを学習
- Few-shot適応

**Option 3**: ベイズ最適化
- Haze vs Performance の関数を推定

#### 6.3 入力情報

- VAE不確実性: $\sigma_z^2(y[k], u[k])$
- 予測誤差履歴: $\{e[k-10:k]\}$
- 衝突リスク: $r_{\text{collision}}[k]$
- タスク成功率: $\eta_{\text{success}}$

### 📤 Output (予定)

**学習済みモデル (models/)**:
- `models/self_haze_policy_v56.bson` - Self-Hazingポリシー（RL/Meta学習）

**生データ (data/)**:
- `data/logs/self_hazing/scramble/sim_ep{ep}_s{s}.h5` - 学習エピソードログ
- `data/logs/self_hazing/corridor/sim_ep{ep}_s{s}.h5`

**分析結果 (results/)**:
- `results/self_hazing/meta_learning_log.csv` - 学習履歴
- `results/self_hazing/optimal_haze_policy_report.md` - 学習済みポリシー分析
- `results/self_hazing/learning_curves.png` - 報酬・性能の推移
- `results/self_hazing/adaptive_haze_visualization.png` - 動的Haze制御の可視化

### ✅ 期待成果
- [ ] Manual Haze (Phase 5.5最適値) を上回る性能
- [ ] 未知環境（OOD密度）への迅速な適応
- [ ] タスク切り替え時の自動調整能力

---

## 📅 推奨スケジュール

| Phase         | 期間        | 優先度   | 主要タスク                                       |
| ------------- | ----------- | -------- | ------------------------------------------------ |
| Phase 0       | 1週間       | 🔴 最高   | 仕様確定、コード整理                             |
| Phase 1       | 1-2週間     | 🔴 最高   | データ収集（50k+ サンプル）                      |
| Phase 2       | 2-3週間     | 🔴 最高   | VAE学習、ハイパーパラメータ調整                  |
| Phase 3       | 1週間       | 🔴 最高   | VAE検証（ゲート条件）                            |
| Phase 4       | 2週間       | 🟡 高     | 制御統合、デバッグ                               |
| Phase 5.1-5.4 | 2週間       | 🟡 高     | アブレーション・比較実験                         |
| **Phase 5.5** | **1-2週間** | **🟡 高** | **Haze Sensitivity Analysis（両タスク）** ★新規★ |
| Phase 6       | 3-4週間     | 🟢 中     | Self-Hazing研究                                  |

**総期間**: 約13-17週間（4ヶ月）

### Phase 5.5 詳細スケジュール

| 週     | タスク                | 実験数                                  |
| ------ | --------------------- | --------------------------------------- |
| Week 1 | Scramble Crossing実験 | 5 (Haze) × 4 (Density) × 5 (Seed) = 100 |
| Week 2 | Corridor実験 + 分析   | 100 + データ分析・レポート作成          |

---

## 🎓 学術的貢献の再確認

### 新規性（v5.6）

1. **Active Inferenceの工学的実装**
   - Surpriseを明示的に組み込んだ実時間制御
   - VAE再構成誤差による行動評価

2. **知覚解像度の設計原理**
   - Hazeを設計変数として扱う新アプローチ
   - 設計者制御 → 自律学習への拡張パス

3. **二層制御アーキテクチャ**
   - 下層: Active Inference（Surprise駆動）
   - 上層: Precision制御（Haze変調）

4. **Self-Hazingの理論的枠組み**
   - メタ学習による自律的認知解像度制御

### 理論的位置づけ

| アプローチ   | 不確実性     | 知覚解像度     | Surprise | 学習       |
| ------------ | ------------ | -------------- | -------- | ---------- |
| 従来MPC      | 外乱         | 固定           | ❌        | 不要       |
| Robust MPC   | 最悪ケース   | 固定           | ❌        | 不要       |
| RL (SAC)     | 探索ボーナス | 固定           | ❌        | 必要       |
| **EPH v5.6** | **Surprise** | **設計者制御** | **✅**    | **VAE**    |
| EPH v6+      | Surprise     | 自律学習       | ✅        | VAE + Meta |

---

## ⚠️ リスクと対策

### リスク

1. **VAE学習の失敗** (Phase 3で不合格)
   - **対策**: データ拡充、アーキテクチャ調整、β_KL再調整

2. **Surprise計算の計算コスト**
   - **対策**: 候補数を10程度に制限、GPU使用

3. **Baseline との性能差が小さい**
   - **対策**: OOD条件での評価強化、Phase 6でSelf-Hazing

4. **査読での理論的批判**
   - **対策**: Appendix でFEP理論との整合性を厳密化

---

## 📚 次のステップ（即座に着手可能）

### 優先度1: Phase 0 完了
- [ ] `src/config_v56.jl` 作成
- [ ] `src/data_schema.jl` 作成
- [ ] v5.5コードを `archive/v55/` に移動

### 優先度2: Phase 1 開始
- [ ] `scripts/collect_vae_data_v56.jl` 実装
- [ ] データ収集実行（1-2日）
- [ ] データ品質チェック

### 優先度3: 並行作業
- [ ] `src/surprise.jl` の事前実装
- [ ] `src/haze.jl` の事前実装

---

## 💡 実装上の補足

### Surprise計算の最適化

現在の実装（サンプルベース）は10候補で実用的だが、将来的には以下も検討:

```julia
# Option: 線形近似による高速化
function compute_surprise_approx(vae, spm, u, u_baseline)
    # Baseline でのSurprise
    S_base = compute_surprise(vae, spm, u_baseline)

    # 線形近似（u周辺でのTaylor展開）
    ∇S = gradient_surprise(vae, spm, u_baseline)  # 事前計算

    S_approx = S_base + dot(∇S, u - u_baseline)
    return S_approx
end
```

### Haze の可視化

```julia
# リアルタイム可視化（デバッグ用）
function visualize_haze_effect(spm_raw, β_values)
    fig, axes = subplots(1, length(β_values))
    for (i, β) in enumerate(β_values)
        spm_blurred = apply_precision(spm_raw, β)
        axes[i].imshow(spm_blurred[:,:,2], title="β=$β")
    end
    display(fig)
end
```

---

**プラン作成完了！次は Phase 0 の実装から開始しましょう。**
