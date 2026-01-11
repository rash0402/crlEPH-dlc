# Haze Mechanism Deep Dive Analysis Report

**Generated**: 2026-01-11
**Analysis Type**: SPM Spatial Distribution & Free Energy Correlation

---

## Executive Summary

診断メトリクスとSPM空間分布の深掘り分析により、Hazeメカニズムの動作を定量的に把握しました。

###重要な発見**

1. **β Modulation は正常動作**: Haze 0→1 で β 450.5→5.0 (90倍範囲)
2. **SPM特性は変化している**: Variance -35.6%, Radial gradient +16%
3. **しかしFree Energyへの影響は minimal**: F_total変動0.06%のみ
4. **強い負の相関を発見**: SPM variance vs S(u) で r=-0.80

---

## 1. β Modulation Verification

| Haze | Precision (Π) | β_r (mean) | β_ν (mean) |
|------|--------------|------------|------------|
| 0.0  | 100.00       | 450.50     | 450.50     |
| 0.5  | 2.00         | 9.50       | 9.50       |
| 1.0  | 1.00         | 5.00       | 5.00       |

**Status**: ✅ **WORKING**
β = β_min + (β_max - β_min) × Π の式は正しく機能しています。

---

## 2. SPM Spatial Characteristics

### 2.1 Global Statistics

#### Channel 2 (Proximity Saliency)

| Haze | Mean   | Variance | Inner (ρ<8) | Outer (ρ≥8) | Radial Gradient |
|------|--------|----------|-------------|-------------|-----------------|
| 0.0  | 0.180  | 0.02104  | 0.265       | 0.095       | -0.170          |
| 0.5  | 0.164  | 0.01316  | 0.233       | 0.095       | -0.138          |
| 1.0  | 0.166  | 0.01355  | 0.237       | 0.095       | -0.142          |

**Key Findings**:
- **Variance減少**: -35.6% (H=0→1) → 空間的に均質化
- **Inner領域減少**: -10.6% (0.265→0.237) → 近距離の強調が減る
- **Outer領域不変**: 0.095付近で一定 → 遠距離は影響なし
- **Radial gradientフラット化**: -0.170→-0.142 (16%減少)

#### Channel 3 (Collision Risk)

| Haze | Mean   | Variance | Inner | Outer | Radial Gradient |
|------|--------|----------|-------|-------|-----------------|
| 0.0  | 0.182  | 0.02157  | 0.268 | 0.095 | -0.173          |
| 0.5  | 0.166  | 0.01396  | 0.238 | 0.095 | -0.143          |
| 1.0  | 0.167  | 0.01388  | 0.239 | 0.095 | -0.145          |

**Similar pattern**: Ch3もCh2とほぼ同じ傾向

---

### 2.2 Regional Analysis

**Inner vs Outer Ratio**:
```
H=0.0: Inner/Outer = 2.79  (sharp contrast)
H=0.5: Inner/Outer = 2.46  (moderate)
H=1.0: Inner/Outer = 2.50  (moderate)
```

**Angular Distribution**:
- Front vs Side difference: 微小 (<0.3%)
- Hazeによる変化も minimal → 主に radial effectが支配的

---

## 3. Free Energy Component Analysis

### 3.1 Component Magnitudes

| Haze | F_goal | F_safety | S(u)  | F_total |
|------|--------|----------|-------|---------|
| 0.0  | 0.0201 | 0.5183   | 0.7532| 1.2916  |
| 0.5  | 0.0200 | 0.5182   | 0.7531| 1.2914  |
| 1.0  | 0.0204 | 0.5186   | 0.7534| 1.2924  |

**ΔF_total (H=0→1)**: +0.0008 (+0.06%)

### 3.2 Contribution Ratios (λ weights applied)

With λ_goal=1.0, λ_safety=1.0, λ_surprise=1.0:

| Component | H=0.0 | H=0.5 | H=1.0 |
|-----------|-------|-------|-------|
| Goal      | 1.6%  | 1.6%  | 1.6%  |
| Safety    | 40.1% | 40.1% | 40.1% |
| Surprise  | 58.3% | 58.3% | 58.3% |

**Observation**: 構成比がHaze値に無関係で一定 → Hazeの影響がF成分に伝播していない

---

## 4. Correlation Analysis

### 4.1 SPM vs F_safety

|         | Ch2 Mean | Ch2 Var | Ch3 Mean | Ch3 Var |
|---------|----------|---------|----------|---------|
| H=0.0   | -0.24    | -0.28   | -0.23    | -0.26   |
| H=0.5   | -0.33    | -0.49   | -0.32    | -0.48   |
| H=1.0   | -0.35    | -0.50   | -0.34    | -0.50   |

**Pattern**: 負の相関 → SPM値が高いほどF_safetyが低い（直感的）

### 4.2 SPM vs S(u) (Surprise)

|         | Ch2 Mean | Ch2 Var | Ch3 Mean | Ch3 Var |
|---------|----------|---------|----------|---------|
| H=0.0   | -0.56    | -0.64   | -0.55    | -0.63   |
| H=0.5   | -0.63    | **-0.79** | -0.62  | -0.79   |
| H=1.0   | -0.64    | **-0.80** | -0.63  | -0.80   |

**Strong negative correlation**: r=-0.80 between Ch2 Variance and S(u)
- **解釈**: SPMが空間的に均質（低variance） → VAE再構成が容易 → 低Surprise
- Hazeが高いほど相関が強化 → メカニズムの一貫性を示唆

---

## 5. Mechanism Interpretation

### 5.1 理論的予測 vs 実測

**理論**:
```
Haze↑ → Precision↓ → β↓ → exp(-ρ*β) larger
→ SPM saliency値が増大（特に遠距離）
→ 空間的にブラー（variance増加）
```

**実測**:
```
Haze↑ → β↓ (確認済み)
→ Inner領域のsaliency **減少** (-10.6%)
→ Variance **減少** (-35.6%)
→ Radial gradientがフラット化 (+16%)
```

### 5.2 矛盾の原因仮説

#### 仮説A: Gaussian Weighting効果
```julia
spm[i, j, 2] = max(spm[i, j, 2], weight * saliency)
weight = exp(-(d_rh^2 + d_th^2) / (2 * σ^2))
```
- `max()`を使用 → 各セルに最も高いsaliency値を持つ障害物が寄与
- β大→シャープ→最近接障害物だけが極端に高い値
- β小→スムーズ→複数障害物が平均化された値

**しかし**: これでは Inner領域減少を説明できない

#### 仮説B: Agent Distribution効果
- Inner領域に障害物が少ない特定の空間配置
- β大 → 遠くの障害物がInner領域のセルにGaussianでブリード
- β小 → ブリード効果減少

**検証が必要**

#### 仮説C: 時間平均の影響
- 動的環境で障害物配置が変化
- β大 → 瞬間的に高いsaliency、時間変動大
- β小 → 安定した中程度のsaliency

**要調査**

---

## 6. Why Minimal Behavioral Impact?

### 6.1 SPM変化はあるが、F_totalがほぼ不変

**原因分析**:

1. **F_safety計算がSPM全体の統計量に依存？**
   - SPM meanやmaxを使用している可能性
   - Varianceは使われていない？

2. **λバランス問題**:
   - λ_surprise=1.0が支配的（58%）
   - Surprise項がSPM変化に鈍感

3. **Action候補選択の問題**:
   - n_candidates=8で離散的
   - 微小なF差が行動選択に反映されない

4. **Saturation効果**:
   - F_safety, S(u)が既に飽和領域？
   - SPM変化がF変化に線形に伝播しない

### 6.2 推奨される追加調査

- [ ] `compute_safety_free_energy(spm, u, params)`の実装を詳細確認
- [ ] SPM→F変換の数式を追跡
- [ ] λ_safety=0.1など極端な値でテスト
- [ ] より困難なシナリオ（density=40, width=2.0）で再検証

---

## 7. Conclusions

### 7.1 What Works

✅ **β Modulation**: 理論通りに動作
✅ **SPM特性変化**: Variance, Gradient変化を確認
✅ **診断メトリクス**: 詳細な内部状態を可視化可能

### 7.2 What Doesn't

⚠️ **Behavioral Impact**: SPM変化がF_totalにほぼ伝播しない
⚠️ **Theoretical Mismatch**: Inner領域減少は理論と逆

### 7.3 Critical Questions

1. **なぜInner領域がHaze↑で減少するのか？**
   → Gaussian weighting、agent distribution、時間平均の複合効果？

2. **なぜSPM変化がF_totalに反映されないのか？**
   → F計算式の調査が必須

3. **Hazeメカニズムは機能しているのか？**
   → β modulationは動作、しかし行動への影響経路が不明

---

## 8. Next Steps

### Priority 1: Controller Investigation
- `compute_safety_free_energy()`の数式を確認
- SPM→F変換の詳細を追跡
- どのSPM統計量（mean/max/variance）が使われているか

### Priority 2: Parameter Tuning
- λ_safety を0.1-0.5に下げてHaze効果を顕在化
- より極端なHaze範囲（0.0-2.0）でテスト

### Priority 3: Scenario Hardening
- density=40, corridor_width=2.0の極限条件
- 制約が強い環境でHaze影響を増幅

### Priority 4: Theoretical Reconciliation
- Inner領域減少の原因を数理的に解明
- シミュレーション例でステップバイステップ検証

---

## References

- Diagnostic test: `results/diagnostic_test_20260111_103506/`
- SPM visualization: `results/spm_analysis/spm_spatial_comparison.png`
- Data: 3 experiments × 300 steps × 20 agents = 18,000 samples
