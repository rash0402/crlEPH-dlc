# Scripts Directory

実験実行・診断・分析のためのスクリプト集

## 🚀 診断実験スクリプト

### `run_quick_diagnostic.sh`
**クイック診断（推奨：初回テスト用）**

100ステップの短時間実験を実行し、即座に診断結果を表示します。

```bash
./scripts/run_quick_diagnostic.sh
```

**所要時間:** 約10秒
**用途:** 実装変更後の動作確認、診断システムのテスト

---

### `run_diagnostic_experiments.sh`
**総合診断実験（推奨：本格的な評価用）**

複数のself-hazeパラメータ設定で実験を実行し、創発機能の違いを評価します。

```bash
# デフォルト設定（1000ステップ × 4パターン）
./scripts/run_diagnostic_experiments.sh

# カスタム設定
./scripts/run_diagnostic_experiments.sh my_experiment 2000
```

**実験パターン:**
1. **default** - デフォルト設定（h_max=0.8, α=10.0）
2. **exploration** - 探索特化型（h_max=0.9, α=15.0） → ラフパスショートカット
3. **uniform** - 均等分散型（h_max=0.3, α=3.0） → 密集回避
4. **stigmergic** - Stigmergic trail（γ=5.0） → 経路記憶

**所要時間:** 約5-10分
**出力:** 各設定の診断レポート + ログファイル

---

## 📊 分析スクリプト

### `analyze_experiment.jl`
**ログファイルの包括的診断**

Phase 1-4すべての診断を実行します。

```bash
cd src_julia
julia --project=. ../scripts/analyze_experiment.jl ../data/logs/<logfile>.jld2
```

**診断内容:**
- Phase 1: システム健全性（物理制約、数値安定性）
- Phase 2: GRU予測性能
- Phase 3: 勾配駆動システム（EFE最適化）
- Phase 4: Self-Haze動力学と創発行動

---

## 🛠️ その他のスクリプト

### `run_experiment.sh`
通常のEPH実験実行（ビジュアライゼーション付き）

```bash
./scripts/run_experiment.sh
```

Julia EPHサーバー + Python viewerを起動します。

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
data/logs/
├── diagnostic_default_2025-11-23_12-30-00.jld2
├── diagnostic_exploration_2025-11-23_12-35-00.jld2
├── diagnostic_uniform_2025-11-23_12-40-00.jld2
└── diagnostic_stigmergic_2025-11-23_12-45-00.jld2
```

---

## 📖 詳細ドキュメント

診断システムの詳細については以下を参照：
- **[doc/DIAGNOSTICS_GUIDE.md](../doc/DIAGNOSTICS_GUIDE.md)** - 診断システム利用ガイド
- **[CLAUDE.md](../CLAUDE.md)** - プロジェクト全体の開発ガイド
