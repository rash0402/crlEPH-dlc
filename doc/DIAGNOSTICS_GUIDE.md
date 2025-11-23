# EPH実験診断システム利用ガイド

## 概要

このガイドでは、EPH（Emergent Perceptual Haze）フレームワークの包括的な診断システムの使用方法を説明します。

診断システムは4つのフェーズで構成されています：

1. **Phase 1: システム健全性診断** - 物理的整合性と数値安定性
2. **Phase 2: GRU予測性能診断** - ニューラル予測器の精度評価
3. **Phase 3: 勾配駆動システム診断** - Expected Free Energy最適化の検証
4. **Phase 4: Self-Haze動力学分析** - 創発行動の特性評価

---

## 1. ログ生成

### 1.1 通常実験でのログ生成

`main.jl`は自動的に包括的なログを生成します：

```bash
cd src_julia
julia --project=. main.jl
```

実験終了時（Ctrl+C）、ログが以下に保存されます：
```
data/logs/eph_experiment_2025-11-23_12-20-53.jld2
```

### 1.2 テスト実験でのログ生成

短時間のテスト実験：

```bash
cd src_julia
julia --project=. test_logging.jl
```

100ステップの実験を実行し、即座に診断結果を表示します。

---

## 2. ログ分析

### 2.1 診断スクリプトの実行

```bash
cd src_julia
julia --project=. ../scripts/analyze_experiment.jl ../data/logs/eph_experiment_2025-11-23_12-20-53.jld2
```

### 2.2 出力の解釈

#### Phase 1: システム健全性

```
📐 Physical Consistency
  Velocity:
    Mean: 8.71 units/s
    Max:  12.77 units/s
    ✓ No velocity constraint violations
```

**判定基準:**
- ✅ **HEALTHY**: NaN/Inf検出なし、制約違反なし
- ⚠️ **DEGRADED**: NaN/Inf検出あり、または制約違反あり

**よくある問題:**
- `⚠️ WARNING: SPM values outside expected range!`
  - 原因: 速度チャンネルの値が大きい（正常）
  - 対処: Occupancy channelが0-1範囲内であれば問題なし

---

#### Phase 2: GRU予測性能

```
🎯 Prediction Error Analysis
  Total MSE:
    Mean:   0.035
```

**性能評価基準:**
- ✅ **EXCELLENT**: Mean MSE < 0.01
- ✓ **GOOD**: Mean MSE < 0.1
- ⚠️ **MODERATE**: Mean MSE < 0.5
- ❌ **POOR**: Mean MSE >= 0.5 → GRU再学習が必要

**Linear Predictor使用時:**
- 予測誤差が大きい（3.0+）のは正常
- Linear Predictorは簡易的な運動学モデル
- 高精度予測が必要な場合はGRUモデルを使用

**GRU Predictor使用時:**
- Mean MSE > 0.1 → モデル再学習を検討
- Saturation > 80% → モデル容量不足、隠れ層を拡大

---

#### Phase 3: 勾配駆動システム

```
∇ Gradient Statistics
  ||∇G|| (EFE gradient):
    Mean:   0.225
    Zero gradients: 0 / 50 (0.00%)
    ✓ Gradients flowing normally
```

**診断指標:**

| 項目 | 正常範囲 | 問題の兆候 |
|------|---------|-----------|
| Gradient norm | 0.1 - 10.0 | > 50%がゼロ → 局所最適 |
| Action continuity | < 10.0 | > 10.0 → 数値不安定 |
| EFE improvement | > 50%成功 | < 50% → 最適化失敗 |

**よくある問題:**
- `⚠️ WARNING: <50% optimization success rate`
  - 原因: 勾配降下の反復回数不足（max_iter < 5）
  - 対処: `EPHParams.max_iter`を増やす（推奨: 10）

---

#### Phase 4: Self-Haze動力学

```
🌫️  Self-Haze Distribution
  Mean:   0.452
  State Distribution:
    Isolated (h > 0.5): 0 / 50 (0.00%)
    Grouped  (h ≤ 0.5): 50 / 50 (100.00%)
```

**分析視点:**

1. **状態遷移の確認**
   - 遷移数 = 0 → エージェントが一つの状態に固定
   - 頻繁な遷移 → 動的なself-haze調整が機能

2. **Occupancy-Haze相関**
   - 期待: 強い負の相関（r < -0.5）
   - 高occupancy → 低haze → 障害物回避モード
   - 低occupancy → 高haze → 探索モード

3. **Velocity-Haze相関**
   - 弱い相関（|r| < 0.3）→ 独立した動力学
   - 強い相関 → self-hazeが速度に直接影響

**創発行動の評価:**

| 指標 | 値 | 解釈 |
|------|-----|------|
| Final coverage | > 95% | 優れた探索性能 |
| Collisions | 0 | 完全な衝突回避 |
| State transitions | > 10 | 動的な環境適応 |

---

## 3. Self-Haze特性と創発機能

### 3.1 パラメータ設定と予測される創発行動

#### 設定1: 探索特化型
```julia
EPHParams(
    h_max = 0.9,         # 高い最大haze
    α = 15.0,            # 高感度応答
    Ω_threshold = 0.02   # 低い閾値（すぐに高haze）
)
```

**予測される創発機能:**
- ✓ ラフパスショートカット（障害物近接時に高haze→通り抜け）
- ✓ 高速探索（リスク許容）
- ⚠️ 衝突リスク増加

---

#### 設定2: 均等分散型
```julia
EPHParams(
    h_max = 0.3,         # 低い最大haze
    α = 3.0,             # 緩やかな応答
    Ω_threshold = 0.10   # 高い閾値（低hazeを維持）
)
```

**予測される創発機能:**
- ✓ 密集回避（常に低haze→他者を避ける）
- ✓ 均等カバレッジ
- ⚠️ 探索速度低下

---

#### 設定3: Stigmergic Trail形成
```julia
EPHParams(
    h_max = 0.6,
    α = 8.0,
    γ = 5.0             # 高いhaze減衰率（局所性強化）
)
```

**予測される創発機能:**
- ✓ 環境hazeによる経路記憶
- ✓ 他エージェントの軌跡追従
- ✓ 協調探索パターン

---

### 3.2 診断スクリプトでの確認方法

パラメータを変更して実験を実行：

```bash
# 1. Types.jlでEPHParamsのデフォルト値を変更
# 2. 実験を実行
cd src_julia
julia --project=. main.jl

# 3. Ctrl+Cで終了後、診断を実行
julia --project=. ../scripts/analyze_experiment.jl ../data/logs/eph_experiment_*.jld2
```

**Phase 4の出力を重点的にチェック:**
- State distribution（isolated vs grouped比率）
- Transition rate（遷移頻度）
- Final coverage（探索効率）
- Collision count（衝突回避性能）

---

## 4. トラブルシューティング

### 問題1: NaN/Inf検出

```
❌ CRITICAL: NaN/Inf detected in 15 timesteps!
```

**対処:**
1. Learning rate (`η`)を下げる: `0.1 → 0.05`
2. Gradient clippingを追加（EPH.jl）
3. SPMのGaussian splattingのσを調整

---

### 問題2: 勾配消失

```
⚠️ WARNING: >50% zero gradients
```

**対処:**
1. `max_iter`を増やす: `5 → 10`
2. `λ`（pragmatic term weight）を調整
3. EFE関数のスケーリングを確認

---

### 問題3: GRU予測誤差が大きい

```
❌ POOR: Mean error >= 0.5
```

**対処:**
1. GRUモデルを再学習: `./scripts/update_gru.sh`
2. 学習データを増やす（より長い実験）
3. Hidden sizeを拡大: `128 → 256`

---

## 5. 高度な使用例

### 5.1 パラメータスイープ実験

```julia
# sweep_selfhaze.jl
h_max_values = [0.3, 0.5, 0.7, 0.9]
α_values = [3.0, 8.0, 15.0]

for h_max in h_max_values, α in α_values
    params = EPHParams(h_max=h_max, α=α)
    # ... 実験実行 ...
    # ... ログ保存 ...
end

# 各ログを分析して比較
```

### 5.2 カスタム分析スクリプト

```julia
using JLD2

# ログ読み込み
data = load("data/logs/eph_experiment_*.jld2")

# Self-haze時系列の可視化
self_haze = data["agent_self_haze_values"]
using Plots
plot(self_haze, title="Self-Haze Dynamics")

# 相関分析
occupancy = data["agent_occupancy_measures"]
correlation = cor(vcat(self_haze...), vcat(occupancy...))
```

---

## 6. まとめ

このシステムにより、以下が可能になります：

✅ **プロジェクトの健全性確認**
- 物理制約の遵守
- 数値安定性の検証

✅ **GRU予測の機能確認**
- 予測精度の定量評価
- モデル容量の診断

✅ **偏微分駆動システムの検証**
- 勾配フローの健全性
- 最適化性能の評価

✅ **Self-haze特性と創発機能の議論**
- パラメータ設定の影響分析
- 創発行動の定量的評価
- 設計指針の獲得

---

## 参考資料

- `src_julia/utils/ExperimentLogger.jl` - ロギングシステム実装
- `scripts/analyze_experiment.jl` - 診断スクリプト
- `doc/20251121_Emergent Perceptual Haze (EPH).md` - 理論背景
- `CLAUDE.md` - プロジェクト全体の開発ガイド
