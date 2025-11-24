# Scripts Directory

実験実行・検証・分析のためのスクリプト集

## 📚 Phase実装について

EPHフレームワークは段階的に実装されています。詳細は以下を参照してください：

**[Phase Implementation Guide](../doc/implementation/Phase_Implementation_Guide.md)**

- **Phase 1**: Scalar Self-Haze（スカラー自己ヘイズ） - ✅ 実装済み・統合済み
- **Phase 2**: 2D Environmental Haze（2次元環境ヘイズ） - 🔧 実装済み（未統合）
- **Phase 3**: Full Tensor Haze（完全テンソルヘイズ） - 📋 計画段階

---

## ✅ 基礎検証スクリプト（推奨）

### `run_basic_validation.sh`
**EPH基礎機能検証 - Phase 1 & Phase 2の動作確認**

Phase 1（Scalar Self-Haze）、Phase 2（Environmental Haze）、および後方互換性を検証します。

```bash
# 全検証実行（推奨）
./scripts/run_basic_validation.sh all

# Phase 1のみ
./scripts/run_basic_validation.sh 1

# Phase 2のみ
./scripts/run_basic_validation.sh 2

# 後方互換性のみ
./scripts/run_basic_validation.sh compat
```

**検証内容:**
1. **Phase 1検証**
   - SelfHazeモジュールインポート
   - EPHモジュールインポート
   - Self-haze計算の正常性

2. **Phase 2検証**
   - EnvironmentalHazeモジュールインポート
   - 5つのユニットテスト実行
     - 2D空間Self-Haze計算
     - Environmental Hazeサンプリング
     - Haze合成（max演算子）
     - 2D Hazeによる精度変調
     - Lubricant/Repellent Haze堆積

3. **後方互換性検証**
   - 既存実験スクリプトの構文チェック

**所要時間:** 約1分
**用途:** 実装変更後の動作確認、リグレッションテスト

---

### `test_phase2_haze.jl`
**Phase 2環境Haze詳細ユニットテスト**

Phase 2機能を5つの独立したテストで検証します。

```bash
~/.juliaup/bin/julia --project=src_julia scripts/test_phase2_haze.jl
```

**所要時間:** 約30秒
**用途:** Phase 2実装の詳細検証、デバッグ

---

## 🎯 総合ワークフロー

### `run_complete_workflow.sh`
**完全自動化ワークフロー - データ収集→GRU学習→実験**

全工程を自動実行します：
1. 古いデータのクリーンアップ（オプション）
2. GRUトレーニングデータ収集
3. GRUモデル学習（オプション）
4. 総合実験の実行
5. サマリーレポート生成

```bash
# 標準ワークフロー（推奨）
./scripts/run_complete_workflow.sh standard

# クイックテスト（100ステップ、GRU学習スキップ）
./scripts/run_complete_workflow.sh quick

# フルワークフロー（5000ステップ、完全分析）
./scripts/run_complete_workflow.sh full

# カスタム設定（対話的に設定）
./scripts/run_complete_workflow.sh custom
```

**ワークフロータイプ:**

| タイプ | データ収集 | 実験ステップ | エージェント | GRU学習 | 所要時間 |
|--------|----------|------------|------------|---------|---------|
| quick | 500 | 1000 | 5 | なし | ~2分 |
| standard | 3000 | 5000 | 10 | あり | ~25分 |
| full | 10000 | 10000 | 15 | あり | ~60分 |

---

## 🧪 実験スクリプト

### `baseline_comparison.jl`
**EXP-1: ベースライン比較実験（EPH vs Potential Field vs DWA）**

EPHと他の手法を比較評価します。

```bash
~/.juliaup/bin/julia --project=src_julia scripts/baseline_comparison.jl
```

---

### `shepherding_experiment.jl`
**Shepherding実験（EPH Dogs vs Boids Sheep）**

EPH制御の犬エージェントがBoidsベースの羊エージェントを誘導するシナリオです。

```bash
~/.juliaup/bin/julia --project=src_julia scripts/shepherding_experiment.jl
```

---

### `run_shepherding_experiment.sh`
**Shepherding実験ランナー（対話型）**

Shepherding実験を対話形式で実行します。

```bash
./scripts/run_shepherding_experiment.sh
```

---

### `eph_parameter_optimization.jl`
**パラメータ最適化スクリプト**

EPHパラメータの最適化を実行します。

```bash
~/.juliaup/bin/julia --project=src_julia scripts/eph_parameter_optimization.jl
```

---

## 📊 データ収集スクリプト

### `collect_gru_training_data.sh`
**GRU予測器用トレーニングデータ収集**

```bash
# デフォルト（3000ステップ、10エージェント）
./scripts/collect_gru_training_data.sh

# カスタム（5000ステップ、15エージェント）
./scripts/collect_gru_training_data.sh 5000 15
```

**機能:**
- 既存データの保持/削除を選択可能
- 自動データ検証
- 収集後に統計サマリー表示

---

## 📊 分析スクリプト

### `analyze_experiment.jl`
**ログファイルの包括的診断**

実験結果の詳細分析を実行します。

```bash
~/.juliaup/bin/julia --project=src_julia scripts/analyze_experiment.jl data/logs/<logfile>.jld2
```

**診断内容:**
- システム健全性（物理制約、数値安定性）
- GRU予測性能
- 勾配駆動システム（EFE最適化）
- Self-Haze動力学と創発行動

---

## 🛠️ その他のスクリプト

### `run_experiment.sh`
通常のEPH実験実行（ビジュアライゼーション付き）

```bash
./scripts/run_experiment.sh
```

Julia EPHサーバー + Python viewerを起動します。

---

### `run_server.sh` / `run_viewer.sh`
個別にサーバーまたはビューアを起動します。

```bash
./scripts/run_server.sh    # EPHサーバーのみ
./scripts/run_viewer.sh    # ビューアのみ
```

---

### `setup_env.sh`
環境セットアップスクリプト

```bash
./scripts/setup_env.sh
```

---

## 🧠 GRU予測器関連（Phase 2用）

GRU予測器の学習・更新スクリプトは `scripts/gru/` にあります。

### `gru/update_gru.sh`
**GRU予測モデルの更新（推奨）**

```bash
./scripts/gru/update_gru.sh
```

データ収集→学習→モデル保存を自動実行します。

### その他のGRUスクリプト
- `pretrain_gru.jl` - GRU事前学習
- `train_gru.jl` - GRU学習
- `train_predictor.jl` - 予測器学習
- `update_gru_model.jl` - モデル更新
- `update_gru_weighted.jl` - 重み付き学習

---

## 📁 出力ファイル

すべてのログは以下に保存されます：
```
src_julia/data/logs/
├── validation_2025-11-24_12-30-00.jld2
├── shepherding_2025-11-24_13-16-00.jld2
└── baseline_2025-11-23_21-37-00.jld2
```

---

## 📖 詳細ドキュメント

詳細については以下を参照：
- **[CLAUDE.md](../CLAUDE.md)** - プロジェクト全体の開発ガイド
- **[doc/20251121_Emergent Perceptual Haze (EPH).md](../doc/20251121_Emergent%20Perceptual%20Haze%20(EPH).md)** - EPH理論フレームワーク
- **[doc/20251120_Saliency Polar Map (SPM).md](../doc/20251120_Saliency%20Polar%20Map%20(SPM).md)** - SPM詳細仕様
