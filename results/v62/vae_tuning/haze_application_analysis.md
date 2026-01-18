# Haze適用タイミングの理論的分析（確定版）

**日時**: 2026-01-13（最終更新）
**目的**: VAE学習とHaze適用の正しい関係を明確化
**結論**: ✅ VAE学習時はHaze=0、推論時にPrecision Mapで重み付け

---

## ユーザー指摘の核心

> **ユーザー指摘**: 「VAE学習はh_peripheral=0.0で行わないと意味がないのでは？hazeは後で人間設計者により付与するのだから，VAEが曖昧に学習してしまうとHazeの効果が現れない」

**評価**: ✅ **100%正しい**（プロポーザル準拠を確認）

---

## 理論的根拠

### VAEの役割

```
VAEの目的: エージェントの真の状態遷移ダイナミクスを学習

入力:  (y[k], u[k])  ← Haze=0の高精度SPM
処理:  q(z|y,u) → z → p(y[k+1]|z,u)
出力:  ŷ[k+1]       ← Haze=0の高精度予測
```

VAEは「真の環境状態」を学習する必要がある。もしVAE学習時にHazeを適用すると：
- VAEは「ボヤけたSPM」から「ボヤけたSPM」への遷移を学習
- VAEの予測能力自体が劣化
- Precision-Weighted Surpriseの意味が失われる

---

### Hazeの役割（推論時）

```
Hazeの目的: 空間的な注意の重み付けを人間設計者が指定

Critical Zone (0-2.18m):   Haze=0.0 → Π≈100 → 高い注意
Peripheral Zone (2.18m+):  Haze=0.5 → Π≈2   → 低い注意
```

**Hazeの適用箇所**:
1. ❌ SPM生成時には適用しない
2. ✅ Φ_safetyの重み付けに適用
3. ✅ Surpriseの重み付けに適用

---

## 現在の実装状況

### 問題1: `generate_spm_3ch`の`precision`引数

**実装 (spm.jl:92-113)**:
```julia
function generate_spm_3ch(
    config, agents_rel_pos, agents_rel_vel,
    r_agent, precision=1.0  # ★ precision引数
)
    # Adaptive β modulation
    beta_r = beta_r_min + (beta_r_max - beta_r_min) * precision
    beta_nu = beta_nu_min + (beta_nu_max - beta_nu_min) * precision

    # SPM generation with adaptive β
    saliency = exp(-rho_val * beta_r)   # ★ β_rがprecisionに依存
    risk = exp(beta_nu * ttc_inv) - 1.0 # ★ β_nuがprecisionに依存
```

**問題点**:
- `precision`がSPM生成時のβ変調に使われている
- つまり、**SPM自体がprecisionに応じて変化する**
- VAE学習時（precision=1.0）と推論時（precision変動）で**SPMの生成方法が異なる**
- これは理論的に不整合

---

### 問題2: 推論時のprecision適用

**実装 (controller.jl:705-710)**:
```julia
spm_pred = SPM.generate_spm_3ch(
    spm_config,
    agents_rel_pos,
    agents_rel_vel,
    AgentParams().r_agent,
    precision  # ★ precision渡している
)
```

**問題点**:
- `precision`（単一値）をSPM生成に渡している
- しかし、`precision_map`（配列）もあり、二重管理状態
- 理論的に、SPM生成にprecisionを適用すべきではない

---

## 正しい設計（理論的）

### フェーズ1: VAE学習

```julia
# データ収集時: Haze=0でエージェント制御
agent_control(h_peripheral=0.0)  # Critical Zone戦略で行動

# VAE学習時: Haze=0でSPM再生成
spm_t = generate_spm_3ch(config, pos, vel, r_agent, precision=1.0)
spm_t1 = generate_spm_3ch(config, pos_next, vel_next, r_agent, precision=1.0)

# VAE訓練
VAE.train(y[k]=spm_t, u[k], y[k+1]=spm_t1)
```

✅ **VAEは真の状態遷移を学習**

---

### フェーズ2: 推論時（Controller）

```julia
# SPM生成: Haze=0で生成（真の状態）
spm_current = generate_spm_3ch(config, pos, vel, r_agent, precision=1.0)
spm_pred = generate_spm_3ch(config, pos_next, vel_next, r_agent, precision=1.0)

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
```

✅ **Hazeは重み付けとして機能**

---

## 現在の実装状況（v6.2準拠性の検証）

### ✅ 正しい実装：trajectory_loader.jl

**VAE学習時のSPM生成 (trajectory_loader.jl:129)**:
```julia
# precision引数なし → デフォルト1.0（Haze=0相当）
spm = Main.SPM.generate_spm_3ch(
    spm_config, agents_rel_pos, agents_rel_vel, r_agent
)
```

✅ **プロポーザル準拠**：VAEは真の状態遷移（Haze=0）を学習

---

### ⚠️ 要確認：controller.jlのprecision引数

**推論時のSPM生成 (controller.jl:705)**:
```julia
spm_pred = SPM.generate_spm_3ch(
    spm_config, agents_rel_pos, agents_rel_vel,
    AgentParams().r_agent,
    precision  # ⚠️ この引数は古いコードの名残の可能性
)
```

**プロポーザル記載 (proposal_v6.2.md:747)**:
```julia
# SPM再生成（precision引数なし）
spm = Main.SPM.generate_spm_3ch(spm_config, agents_rel_pos, agents_rel_vel, r_agent)
```

**判断**: プロポーザルではprecision引数を渡していない。
推論時もHaze=0でSPM生成し、Precision Mapは重み付けにのみ使用すべき。

---

### ⚠️ 要確認：spm.jlのβ変調

**現在の実装 (spm.jl:105-113)**:
```julia
# Adaptive β modulation
precision_clamped = clamp(precision, 0.01, 100.0)
beta_r = params.beta_r_min + (params.beta_r_max - params.beta_r_min) * precision_clamped
beta_nu = params.beta_nu_min + (params.beta_nu_max - params.beta_nu_min) * precision_clamped
```

**問題点**: precisionによってβが変調され、SPM生成方法が変化してしまう

**プロポーザルの意図**:
- Precision-Weighted SafetyはSPM生成を変えるのではない
- 生成されたSPMに対する重み付けを変える

**推奨**: 固定β値を使用（beta_r_fixed, beta_nu_fixed）

---

## 理論的整合性の確認

### Precision-Weighted Safetyの意味

v6.2プロポーザルの核心：
```
Φ_safety(u; Π) = Σ_{i,j} Π(ρ_i) · [k_2·ch2(i,j) + k_3·ch3(i,j)]
```

これは：
- **SPMの生成方法を変えるのではない**
- **生成されたSPMに対する重み付けを変える**

つまり：
- Critical Zone: 同じSPMでも、Φ_safetyへの寄与が100倍
- Peripheral Zone: 同じSPMでも、Φ_safetyへの寄与が2倍

これが「Spatial Importance Weighting」の意味。

---

## 結論

### ユーザー指摘の評価
✅ **100%正しい**。VAEはHaze=0で学習すべき。

### 現在の実装の問題
❌ **理論的不整合**: `generate_spm_3ch`のprecision引数がβ変調に使われ、SPM生成方法がprecisionに依存してしまっている。

### 必要な修正
1. ✅ **VAE学習**: precision=1.0固定（すでに正しい）
2. ❌ **SPM生成**: precision引数を削除（または固定値使用）
3. ✅ **Φ_safety/S**: precision_mapで重み付け（すでに正しい）

### 理論的正当性
v6.2の「Precision-Weighted Safety」は：
- **SPMの生成を変えるのではない**
- **SPMに対する重み付けを変える**

この理解が正しいかどうか、プロポーザルを再確認する必要があります。

---

**報告者**: Claude Code
**レポート生成日時**: 2026-01-13
