# Shepherding Experiment Guide

Phase 4 Shepherding 実験の実行方法とベストプラクティス

## 概要

Shepherding タスクは、EPH コントローラーを持つ犬エージェントが、BOIDS アルゴリズムに従う羊の群れをゴール位置まで誘導するマルチエージェントシミュレーションです。

**主要技術:**
- **ShepherdingEPHv2**: SPM ベースの Social Value を使用
- **Soft-binning**: Zygote 互換の微分可能な角度ビニング
- **Adaptive weights**: コンパクト性とゴール誘導の動的バランス

## 基本的な使い方

### クイックスタート

```bash
# デフォルト設定（羊5匹、100ステップ）
./scripts/run_shepherding_experiment.sh

# テストモード（短時間実行）
./scripts/run_shepherding_experiment.sh --test
```

### コマンドラインオプション

```bash
./scripts/run_shepherding_experiment.sh [OPTIONS]

Options:
  --n-sheep NUM       羊の数（デフォルト: 5）
  --n-dogs NUM        犬の数（デフォルト: 1）
  --steps NUM         シミュレーションステップ数（デフォルト: 100）
  --world-size NUM    ワールドサイズ（デフォルト: 400）
  --seed NUM          乱数シード（デフォルト: 42）
  --test              テストモード（羊3匹、50ステップ）
```

## 推奨シード値

Shepherding タスクは初期配置に敏感です。以下の検証済みシード値を使用することを推奨します：

### 小規模（羊 5匹、100ステップ）

| Seed | ゴール到達 | 最終距離 | 備考 |
|------|----------|---------|------|
| 42   | ✓        | ~28     | **推奨**: デフォルト、安定 |

```bash
./scripts/run_shepherding_experiment.sh --seed 42
```

### 大規模（羊 20匹、500ステップ）

| Seed | ゴール到達 | 最終距離 | 備考 |
|------|----------|---------|------|
| 300  | ✓        | ~27     | **最良**: 最も近い収束 |
| 100  | ✓        | ~70     | **推奨**: 良好な結果 |
| 200  | ✓        | ~81     | 成功 |
| 999  | ✓        | ~79     | 成功 |
| 42   | 部分成功  | ~124    | ゴール未到達（要調整）|

```bash
# 最良の結果
./scripts/run_shepherding_experiment.sh --n-sheep 20 --steps 500 --seed 300

# 安定した結果
./scripts/run_shepherding_experiment.sh --n-sheep 20 --steps 500 --seed 100
```

**成功率**: 5つのシードテストで 4/5 (80%) 成功

## 評価基準

シミュレーションは以下の3つの基準で評価されます：

1. **ゴール到達** (`goal_reached`): 最終距離 < 100 units
2. **ゴールへの前進** (`moved_towards_goal`): 初期距離 > 最終距離
3. **群れの一貫性維持** (`maintained_cohesion`): 最終コンパクト性 < 2 × 初期コンパクト性

すべての基準を満たすと **TEST PASSED ✓**、一部のみ満たすと **TEST PARTIAL** となります。

## 実験例

### 例1: 基本的なシミュレーション

```bash
./scripts/run_shepherding_experiment.sh
```

**期待される出力:**
```
[4/4] Final state:
  Sheep COM:       [278.0, 289.0]
  Compactness:     ~10
  Goal distance:   27.97

============================================================
TEST PASSED ✓
============================================================
```

### 例2: スケールアップ実験

```bash
./scripts/run_shepherding_experiment.sh --n-sheep 20 --steps 500 --seed 300
```

**期待される出力:**
```
[4/4] Final state:
  Sheep COM:       [285.2, 292.8]
  Compactness:     ~8
  Goal distance:   26.79

============================================================
TEST PASSED ✓
============================================================
```

### 例3: カスタム設定

```bash
# より大きなワールドで長時間実験
./scripts/run_shepherding_experiment.sh \
  --n-sheep 15 \
  --steps 1000 \
  --world-size 600 \
  --seed 100
```

## トラブルシューティング

### ゴールに到達しない

**原因**: 初期配置が悪い、ステップ数が不足

**解決策**:
1. 推奨シードを使用
2. `--steps` を増やす（例: 500 → 1000）
3. 異なるシードを試す

```bash
# シードを変更して再試行
./scripts/run_shepherding_experiment.sh --seed 100
```

### 羊が分散する

**原因**: BOIDS の cohesion/separation バランスが不適切

**解決策**: `src_julia/agents/SheepAgent.jl` の重み調整

```julia
# SheepAgent.jl 内
initial_weights=[1.5, 1.0, 1.0]  # [separation, alignment, cohesion]
```

### 再現性がない

**確認事項**:
- `--seed` オプションを使用しているか？
- 同じパラメータ（羊の数、ステップ数など）を使用しているか？

```bash
# 再現可能な実行
./scripts/run_shepherding_experiment.sh --seed 42
```

## 結果の保存場所

実験結果は以下に保存されます：

```
src_julia/data/logs/shepherding_eph_YYYY-MM-DD_HH-MM-SS.jld2
```

**含まれるデータ:**
- 各ステップの羊と犬の位置
- コンパクト性の時系列
- ゴール距離の時系列

## 次のステップ

### 1. 結果の分析

```julia
using JLD2

# データ読み込み
data = load("src_julia/data/logs/shepherding_eph_2025-11-25_XX-XX-XX.jld2")

# 軌跡の可視化、メトリクスのプロットなど
```

### 2. パラメータチューニング

`src_julia/control/ShepherdingEPHv2.jl` の調整：
- `λ_compact`: コンパクト性の重み
- `λ_goal`: ゴール誘導の重み
- `η`: 学習率
- `max_iter`: 最適化イテレーション数

### 3. 複数犬の実験

```bash
# 3匹の犬で協調制御
./scripts/run_shepherding_experiment.sh --n-dogs 3 --n-sheep 20 --seed 300
```

**注意**: 複数犬のサポートは現在開発中です。

## 参考資料

- **理論**: `doc/technical_notes/SocialValue_ActiveInference.md`
- **Phase ガイド**: `doc/PHASE_GUIDE.md` § Phase 4
- **実装**: `CURRENT_TASK.md` (Phase 4 完了報告)
- **実験レポート**: `EXPERIMENT_REPORT_2025-11-25.md`

## バージョン情報

- **Phase**: 4 (Shepherding)
- **Controller**: ShepherdingEPHv2
- **Last Updated**: 2025-11-25
- **Status**: ✅ Production Ready

---

**問題報告・改善提案**: GitHub Issues または直接コミットにて
