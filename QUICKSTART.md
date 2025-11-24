# EPH実験 クイックスタートガイド

## 🚀 最速スタート（3ステップ）

### 1️⃣ 標準ワークフローを実行

```bash
./scripts/run_complete_workflow.sh standard
```

これだけで以下が自動実行されます：
- ✅ GRUトレーニングデータ収集（3000ステップ）
- ✅ GRU予測モデル学習
- ✅ 4種類のパラメータ設定で診断実験（各5000ステップ）
- ✅ 包括的な分析レポート生成

**所要時間:** 約20-30分

---

### 2️⃣ 結果を確認

```bash
# 最新のログを分析
cd src_julia
julia --project=. ../scripts/analyze_experiment.jl ../data/logs/<最新のファイル>.jld2
```

---

### 3️⃣ 完了！

結果は以下に保存されています：
- `data/logs/` - 実験ログ（診断データ）
- `data/training/` - GRUトレーニングデータ
- `data/models/` - 学習済みGRUモデル

---

## 📋 ワークフロー詳細

### ワークフロータイプ

| タイプ | 用途 | データ収集 | 診断実験 | 所要時間 | コマンド |
|--------|------|-----------|---------|---------|---------|
| **quick** | 動作確認 | 500 | 1000 | ~2分 | `./scripts/run_complete_workflow.sh quick` |
| **standard** | 標準実験（推奨） | 3000 | 5000 | ~25分 | `./scripts/run_complete_workflow.sh standard` |
| **full** | 完全分析 | 10000 | 10000 | ~60分 | `./scripts/run_complete_workflow.sh full` |
| **custom** | カスタム設定 | 可変 | 可変 | 可変 | `./scripts/run_complete_workflow.sh custom` |

---

## 🔧 個別スクリプト使用

### データ収集のみ

```bash
# デフォルト（3000ステップ、10エージェント）
./scripts/collect_gru_training_data.sh

# カスタム（5000ステップ、15エージェント）
./scripts/collect_gru_training_data.sh 5000 15
```

### GRU学習のみ

```bash
./scripts/gru/update_gru.sh
```

**注意:** GRU予測器はシステムのデフォルトです。初回起動前に必ずGRU学習を実行してください。Linear予測器はGRU訓練データ収集時のみ使用されます。

### 診断実験のみ

```bash
# クイックテスト（1000ステップ）
./scripts/run_quick_diagnostic.sh

# 総合診断（4パラメータ設定、各1000ステップ）
./scripts/run_diagnostic_experiments.sh

# カスタムステップ数で総合診断（例：5000ステップ）
./scripts/run_diagnostic_experiments.sh diagnostic 5000
```

### ログ分析のみ

```bash
cd src_julia
julia --project=. ../scripts/analyze_experiment.jl <ログファイル>
```

---

## 📊 実験結果の見方

### Phase 1: システム健全性

```
✅ HEALTHY - すべて正常
⚠️  DEGRADED - 問題あり（詳細確認）
```

**確認項目:**
- 速度・加速度制約違反
- NaN/Inf検出
- 物理的整合性

### Phase 2: GRU予測性能

```
✅ EXCELLENT: Mean MSE < 0.01
✓ GOOD: Mean MSE < 0.1
⚠️  MODERATE: Mean MSE < 0.5
❌ POOR: Mean MSE >= 0.5 → 再学習推奨
```

### Phase 3: 勾配駆動システム

```
✓ Gradients flowing normally - 勾配フロー正常
⚠️  WARNING: >50% zero gradients - 勾配消失の可能性
```

### Phase 4: Self-Haze動力学

```
✓ Strong negative correlation (Ω vs h) - 期待通りの動作
✅ Perfect collision avoidance - 衝突なし
✓ Excellent exploration (>95% coverage) - 優れた探索
```

---

## 🛠️ トラブルシューティング

### Q: "No training data found"と表示される

**A:** データ収集を実行してください：
```bash
./scripts/collect_gru_training_data.sh
```

### Q: GRU学習が失敗する

**A:** トレーニングデータが不足している可能性があります：
```bash
# データ量を確認
cd src_julia
julia --project=. verify_training_data.jl

# 不足している場合は追加収集
./scripts/collect_gru_training_data.sh 2000 10
```

### Q: 診断実験でエラーが発生する

**A:** 依存関係を再インストール：
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Q: メモリ不足エラー

**A:** エージェント数を減らすか、ステップ数を減らしてください：
```bash
./scripts/run_complete_workflow.sh custom
# プロンプトで小さい値を入力（例：1000ステップ、5エージェント）
```

---

## 📚 詳細ドキュメント

- **[DIAGNOSTICS_GUIDE.md](doc/DIAGNOSTICS_GUIDE.md)** - 診断システム完全ガイド
- **[scripts/README.md](scripts/README.md)** - スクリプト詳細説明
- **[CLAUDE.md](CLAUDE.md)** - プロジェクト全体ガイド
- **[README.md](README.md)** - プロジェクト概要

---

## 💡 ヒント

### 1. 初回は必ずクイックテスト

```bash
./scripts/run_complete_workflow.sh quick
```

動作確認後に本格的な実験を実行することを推奨します。

### 2. バックグラウンド実行

長時間実験はバックグラウンドで：

```bash
nohup ./scripts/run_complete_workflow.sh standard > workflow.log 2>&1 &

# 進捗確認
tail -f workflow.log
```

### 3. 複数パラメータ比較

異なるパラメータで実験を繰り返し、結果を比較：

```bash
# 実験1: デフォルト
./scripts/run_complete_workflow.sh standard

# 実験2: 異なるパラメータ
# Types.jlでEPHParamsを編集後
./scripts/run_complete_workflow.sh standard
```

---

**準備完了！** 🎉

`./scripts/run_complete_workflow.sh standard` を実行して、EPH実験を開始してください。
