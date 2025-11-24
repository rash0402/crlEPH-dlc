# EPH Phase Implementation Guide

**Version**: 1.0
**Last Updated**: 2025-11-24
**Status**: Phase 1 ✅ Completed | Phase 2 🔧 Implemented (未統合) | Phase 3 📋 Planned

---

## 概要

このドキュメントは、Emergent Perceptual Haze (EPH) フレームワークの段階的実装を説明します。EPHは、Saliency Polar Map (SPM) の精度変調を通じて、Active Inferenceベースのマルチエージェント制御を実現します。

**理論的背景:**
- [EPH理論フレームワーク](../technical_notes/EmergentPerceptualHaze_EPH.md)
- [SPM詳細仕様](../technical_notes/SaliencyPolarMap_SPM.md)

---

## Phase 1: Scalar Self-Haze（スカラー自己ヘイズ）

### ステータス: ✅ 実装済み・統合済み

### 概要

Phase 1は、**全方向一様な精度変調**を実装します。エージェントの占有率（SPMのOccupancy平均）に基づいてスカラーhaze値を計算し、全SPMビンに一様に適用します。

### 理論

$$
h_{self}(\Omega) = h_{max} \cdot \sigma(-\alpha(\Omega - \Omega_{threshold}))
$$

$$
\Pi(r,\theta) = \Pi_{base}(r,\theta) \cdot (1-h_{self})^{\gamma}
$$

**意味:**
- 低占有率（孤立状態） → 高haze → 低精度 → 探索促進
- 高占有率（密集状態） → 低haze → 高精度 → 衝突回避

### 実装ファイル

| ファイル | 説明 | 主要関数 |
|---------|------|---------|
| `src_julia/control/SelfHaze.jl` | Self-haze計算 | `compute_self_haze()` |
| | | `compute_precision_matrix(spm, h_self::Float64, params)` |
| | | `compute_belief_entropy()` |
| `src_julia/control/EPH.jl` | EPHコントローラー | `compute_eph_action()` |
| `src_julia/Simulation.jl` | シミュレーションループ | `update_agents!()` |

### パラメータ

```julia
EPHParams(
    h_max = 0.8,          # 最大haze値
    α = 10.0,             # Sigmoid勾配（急峻さ）
    Ω_threshold = 0.05,   # 占有率閾値
    γ = 2.0,              # 精度変調指数
    Π_max = 10.0,         # 基底精度
    decay_rate = 0.5      # 距離減衰率
)
```

### 検証

```bash
# Phase 1検証（3テスト）
./scripts/run_basic_validation.sh 1
```

**検証内容:**
1. SelfHazeモジュールインポート
2. EPHモジュールインポート
3. Self-haze計算の正常性（0 ≤ h ≤ h_max）

### 実験統合

Phase 1は以下の実験で使用されています：
- `scripts/baseline_comparison.jl` - ベースライン比較（EPH vs Potential Field vs DWA）
- `scripts/shepherding_experiment.jl` - Shepherding実験（EPH Dogs vs Boids Sheep）

---

## Phase 2: 2D Environmental Haze（2次元環境ヘイズ）

### ステータス: 🔧 実装済み（実験への統合は未実施）

### 概要

Phase 2は、**空間的に変化する精度変調**と**環境ヘイズの統合**を実装します。

**主要機能:**
1. **Self-haze行列**: 各SPMビン(r,θ)ごとに独立したhaze値
2. **Environmental haze**: 環境グリッド（haze_grid）からのサンプリング
3. **Haze合成**: Self-hazeとEnvironmental hazeのmax演算子による統合
4. **Stigmergy**: Lubricant/Repellent hazeの堆積

### 理論

#### Self-Haze行列

$$
\mathcal{H}_{self}(r,\theta) = h_{max} \cdot \sigma(-\alpha(\Omega(r,\theta) - \Omega_{threshold}))
$$

各SPMビンの局所占有率に基づき、方向・距離依存のhaze値を計算。

#### Environmental Haze

$$
\mathcal{H}_{env}(r,\theta) = \text{sample}(\text{haze\_grid}, \mathbf{x}(r,\theta))
$$

エージェントのSPMビン位置に対応するワールド座標から、環境ヘイズをサンプリング（バイリニア補間）。

#### Haze合成

$$
\mathcal{H}_{total}(r,\theta) = \max(\mathcal{H}_{self}(r,\theta), \mathcal{H}_{env}(r,\theta))
$$

**解釈:**
- Self-haze: 内部調整（占有率ベース）
- Environmental haze: 外部ガイダンス（スティグメジー）
- 合成: 両者のうち高い方を採用

#### 精度変調

$$
\Pi(r,\theta) = \Pi_{base}(r,\theta) \cdot (1-\mathcal{H}_{total}(r,\theta))^{\gamma}
$$

空間的に変化する精度で、方向・距離ごとに独立した制御を実現。

### 実装ファイル

| ファイル | 説明 | 主要関数 |
|---------|------|---------|
| `src_julia/control/SelfHaze.jl` | 2D self-haze | `compute_self_haze_matrix()` |
| | | `compute_precision_matrix(spm, h_matrix::Matrix, params)` |
| `src_julia/control/EnvironmentalHaze.jl` | 環境haze | `sample_environmental_haze()` |
| | | `compose_haze()` |
| | | `deposit_haze_trail!()` |
| | | `decay_haze_grid!()` |

### Hazeタイプ

| タイプ | 効果 | 用途 |
|--------|------|------|
| **Lubricant Haze** | Haze↓ → Precision↑ | リーダーが追従者へのガイダンストレイルを生成 |
| **Repellent Haze** | Haze↑ → Precision↓ | 探索済み領域をマーク、多様な探索を促進 |

### 検証

```bash
# Phase 2検証（5ユニットテスト）
./scripts/run_basic_validation.sh 2

# 詳細テスト
~/.juliaup/bin/julia --project=src_julia scripts/test_phase2_haze.jl
```

**検証内容:**
1. 2D空間Self-Haze計算（方向依存性）
2. Environmental Hazeサンプリング（バイリニア補間）
3. Haze合成（max演算子）
4. 2D Hazeによる精度変調（空間的変化）
5. Lubricant/Repellent Haze堆積

**全テスト合格:** ✅

### 実験統合（未実施）

Phase 2の実験統合は**保留中**です。Phase 1ベースラインを確立後、以下のシナリオで統合予定：

**候補シナリオ:**
1. **Leader-Follower Formation**: リーダーがLubricant trailを生成、フォロワーが追従
2. **Coordinated Exploration**: Repellent hazeで探索領域の重複を回避
3. **Shepherding with Stigmergy**: 犬エージェントがhaze trailで羊を誘導

**統合前の要件:**
- Phase 1パラメータ最適化完了
- ベースライン性能の確立（shepherding実験で収束成功）

### 使用例（コードスニペット）

```julia
using .EnvironmentalHaze

# 1. 環境hazeをサンプリング
h_env = EnvironmentalHaze.sample_environmental_haze(
    agent, env, spm_params.Nr, spm_params.Ntheta, spm_params.d_max
)

# 2. Self-hazeを計算
h_self = SelfHaze.compute_self_haze_matrix(spm, eph_params)

# 3. Hazeを合成
h_total = EnvironmentalHaze.compose_haze(h_self, h_env)

# 4. 精度行列を計算
Π = SelfHaze.compute_precision_matrix(spm, h_total, eph_params)

# 5. Lubricant trailを堆積（リーダーが使用）
EnvironmentalHaze.deposit_haze_trail!(env, leader_agent, :lubricant, 0.3)

# 6. Haze減衰（毎ステップ呼び出し）
EnvironmentalHaze.decay_haze_grid!(env, 0.99)
```

---

## Phase 3: Full Tensor Haze（完全テンソルヘイズ）

### ステータス: 📋 計画段階

### 概要

Phase 3は、**チャネル依存の精度変調**を実装します。SPMの3チャネル（Occupancy, Radial Velocity, Tangential Velocity）ごとに独立したhaze値を持ちます。

### 理論

$$
\mathcal{H} \in [0,1]^{N_r \times N_\theta \times N_c}
$$

$$
\Pi_c(r,\theta) = \Pi_{base,c}(r,\theta) \cdot (1-\mathcal{H}_c(r,\theta))^{\gamma_c}
$$

**期待される効果:**
- Occupancyチャネルの高haze → 障害物を無視（lubricant）
- Velocityチャネルの低haze → 速度情報に敏感（tracking）

### 実装計画

**予定されるファイル:**
- `src_julia/control/TensorHaze.jl` - チャネル依存haze計算
- `src_julia/control/EPH_Tensor.jl` - テンソルhaze対応EPHコントローラー

### 検証計画

- 単体テスト: `scripts/test_phase3_tensor.jl`
- 統合テスト: Phase 2統合後に着手

---

## ディレクトリ構造

```
crlEPH-dlc/
├── doc/
│   ├── technical_notes/
│   │   ├── EmergentPerceptualHaze_EPH.md      # EPH理論
│   │   └── SaliencyPolarMap_SPM.md            # SPM理論
│   └── implementation/
│       └── Phase_Implementation_Guide.md       # 本ドキュメント
├── src_julia/
│   ├── control/
│   │   ├── SelfHaze.jl                        # Phase 1&2
│   │   ├── EnvironmentalHaze.jl               # Phase 2
│   │   └── EPH.jl                              # Phase 1コントローラー
│   └── ...
└── scripts/
    ├── README.md                               # スクリプト一覧
    ├── run_basic_validation.sh                # Phase 1&2検証
    ├── test_phase2_haze.jl                    # Phase 2ユニットテスト
    ├── baseline_comparison.jl                 # Phase 1実験
    └── shepherding_experiment.jl              # Phase 1実験
```

---

## 開発ワークフロー

### 新機能開発時

1. **理論ドキュメント更新** (`doc/technical_notes/`)
2. **実装** (`src_julia/control/`)
3. **単体テスト作成** (`scripts/test_phaseX_*.jl`)
4. **検証スクリプト更新** (`scripts/run_basic_validation.sh`)
5. **このガイド更新** (本ドキュメント)
6. **実験統合検討** (`scripts/README.md` 更新)

### 検証フロー

```bash
# 全Phase検証（推奨）
./scripts/run_basic_validation.sh all

# Phase別検証
./scripts/run_basic_validation.sh 1      # Phase 1のみ
./scripts/run_basic_validation.sh 2      # Phase 2のみ

# 後方互換性検証
./scripts/run_basic_validation.sh compat
```

---

## トラブルシューティング

### Phase 1

**Q1: Self-hazeが常に0または1になる**
A: `α`（Sigmoid勾配）が大きすぎる可能性。`α=10.0` → `α=5.0` に減らしてみてください。

**Q2: 探索行動が発現しない**
A: `Ω_threshold`が高すぎる可能性。`Ω_threshold=0.05` → `0.02` に減らしてみてください。

### Phase 2

**Q3: Environmental hazeが効かない**
A: `env.haze_grid`が初期化されているか確認。`Environment(400.0, 400.0, grid_size=20)` のように`grid_size`を指定してください。

**Q4: Haze合成後も変化がない**
A: Self-hazeとEnvironmental hazeの値域を確認。`compose_haze()` はmax演算子なので、片方が常に1.0だと効果がありません。

---

## 参考リンク

- **スクリプト一覧**: [scripts/README.md](../../scripts/README.md)
- **EPH理論**: [technical_notes/EmergentPerceptualHaze_EPH.md](../technical_notes/EmergentPerceptualHaze_EPH.md)
- **SPM理論**: [technical_notes/SaliencyPolarMap_SPM.md](../technical_notes/SaliencyPolarMap_SPM.md)
- **プロジェクト開発ガイド**: [CLAUDE.md](../../CLAUDE.md)

---

## 更新履歴

| 日付 | Phase | 内容 |
|------|-------|------|
| 2025-11-24 | 全般 | 初版作成（Phase 1完了、Phase 2実装済み、Phase 3計画） |
