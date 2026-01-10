# EPH v5.6 理論フレームワーク

**Version**: 5.6.1
**Date**: 2026-01-10
**Status**: 🟢 Active Development
**Changes from v5.6.0**: VAE訓練をHaze=0に変更、Surpriseをハイブリッド型に再設計

---

## 📋 変更サマリー (v5.5 → v5.6)

| 項目 | v5.5 | v5.6 | 理由 |
|------|------|------|------|
| **Surprise** | 不使用 | 自由エネルギーの項として追加 | Active Inferenceの理論的要請 |
| **Haze定義** | `Agg(σ_z²)` (VAE自動計算) | 設計パラメータ（任意設定） | 知覚解像度の設計者制御 |
| **VAE σ_z²** | Hazeの主要ソース | 補助変数（Self-hazingで利用可） | 役割の明確化 |
| **β変調** | `β = f(Haze_VAE)` | `β = f(Haze_design)` | 設計パラメータとの連動 |
| **Self-hazing** | 未定義 | Phase 6で実装予定 | 将来の拡張方向 |

---

## 1. 理論的基盤

### 1.1 Active Inference と Expected Free Energy

Active Inference（能動的推論）では、エージェントは **Expected Free Energy (EFE)** を最小化する行動 $\boldsymbol{u}$ を選択する：

$$
\boldsymbol{u}^* = \arg\min_{\boldsymbol{u}} G(\boldsymbol{u})
$$

EFE は以下のように分解される：

$$
G(\boldsymbol{u}) = \underbrace{\mathbb{E}[-\log p(\boldsymbol{o}|\boldsymbol{s}, \boldsymbol{u})]}_{\text{Surprise (Pragmatic Value)}} + \underbrace{D_{KL}[q(\boldsymbol{s}|\boldsymbol{o}, \boldsymbol{u}) \| p(\boldsymbol{s}|\boldsymbol{u})]}_{\text{Ambiguity (Epistemic Value)}}
$$

本研究では、工学的実装の簡潔性のため **Ambiguity項を省略**し、Surprise項と目標達成項を中心に構成する。

---

### 1.2 自由エネルギーの定義 (v5.6)

v5.6における自由エネルギー $F[k]$ は、以下の3項で構成される：

$$
F(\boldsymbol{u}[k]) = F_{\text{goal}}(\boldsymbol{u}) + F_{\text{safety}}(\boldsymbol{u}) + \lambda_s \cdot S(\boldsymbol{u})
$$

#### (1) 目標到達項

$$
F_{\text{goal}}(\boldsymbol{u}) = \|\hat{\boldsymbol{x}}[k+1](\boldsymbol{u}) - \boldsymbol{x}_g\|^2
$$

- $\hat{\boldsymbol{x}}[k+1]$: 行動 $\boldsymbol{u}$ による予測位置

#### (2) 安全性項（障害回避）

$$
F_{\text{safety}}(\boldsymbol{u}) = \sum_{m,n} \phi(\hat{\boldsymbol{y}}_{m,n}[k+1](\boldsymbol{u}))
$$

- $\hat{\boldsymbol{y}}[k+1]$: VAEによる予測SPM
- $\phi(\cdot)$: 衝突危険性のポテンシャル関数

#### (3) Surprise項 ★v5.6.1: ハイブリッド型★

$$
S(\boldsymbol{u}) = \alpha \cdot \underbrace{\mathbb{E}[\sigma_z^2(\boldsymbol{y}, \boldsymbol{u})]}_{\text{Epistemic}} + \beta \cdot \underbrace{(1 + \|\boldsymbol{u}\|) \cdot \mathbb{E}[\sigma_z^2(\boldsymbol{y}, \boldsymbol{u})]}_{\text{Aleatoric (近似)}}
$$

- **意味**: 「現在のSPMと行動 $\boldsymbol{u}$ のペアにおける epistemic 不確実性」
- **役割**: 学習済みの馴染みのある行動パターンを選好、大きな行動にペナルティ
- **計算**: VAEエンコーダの潜在変数分散 $\sigma_z^2$ を利用

**設計の鍵（v5.6.1）**:
- VAEを **Haze=0（最高解像度）** のSPMで訓練
- 実行時の Haze>0 による情報損失が $\sigma_z^2$ の増加として現れる
- Hazeとの単調結合が理論的に保証される

---

### 1.3 行動生成（勾配降下）

最適行動は自由エネルギーの勾配降下により求める：

$$
\frac{\partial F}{\partial \boldsymbol{u}} = \frac{\partial F_{\text{goal}}}{\partial \boldsymbol{u}} + \frac{\partial F_{\text{safety}}}{\partial \boldsymbol{u}} + \lambda_s \frac{\partial S}{\partial \boldsymbol{u}}
$$

**計算の流れ**:
1. $\boldsymbol{u}_{\text{init}}$ を初期化（前ステップの値 or ゼロ）
2. ForwardDiff で $\nabla_{\boldsymbol{u}} F$ を計算
3. $\boldsymbol{u} \leftarrow \boldsymbol{u} - \eta \nabla_{\boldsymbol{u}} F$
4. クリップ: $\boldsymbol{u} \in [-u_{\max}, u_{\max}]$

**注意**: VAEを通じた勾配計算が必要 → ForwardDiff + Flux の統合

---

## 2. Haze と Precision の設計

### 2.1 Haze の定義（v5.6）

**Haze は設計者が制御する知覚解像度のメタパラメータ**である。

$$
\text{Haze}[k] \in [0, 1]
$$

- **0**: 最高解像度（鋭敏な知覚）
- **1**: 最低解像度（粗い知覚）

#### Haze の設定方法

##### Mode 1: 固定Haze（Phase 1-5）
```julia
Haze = 0.5  # 全エピソードで固定
```

##### Mode 2: スケジュールHaze（設計者制御）
```julia
function get_haze(density, collision_risk)
    if density > 20
        return 0.9  # 超混雑 → 超粗視化
    elseif density > 10
        return 0.6  # 混雑 → 中程度
    elseif collision_risk > 0.8
        return 0.8  # 危険 → 粗視化
    else
        return 0.2  # 通常 → 高解像度
    end
end
```

##### Mode 3: Self-Hazing（Phase 6以降）★将来拡張★
```julia
function self_hazing(agent_state, vae_model)
    # VAE不確実性を一要素として使用
    σ_z² = vae_uncertainty(vae_model, spm, u)

    # 予測誤差履歴
    pred_error = prediction_error_history(agent_state)

    # タスクパフォーマンス
    success_rate = task_performance(agent_state)

    # メタ学習モデル
    Haze = meta_learner(σ_z², pred_error, success_rate)

    return Haze
end
```

---

### 2.2 Precision β の変調

Haze から知覚精度 β への変換関数：

$$
\beta[k] = f_{\text{precision}}(\text{Haze}[k])
$$

#### 実装例（逆双曲線）

$$
\beta = \frac{\beta_{\max}}{1 + \alpha \cdot \text{Haze}}
$$

- $\beta_{\max}$: 最大精度（例: 10.0）
- $\alpha$: 感度パラメータ（例: 1.0）

```julia
function precision_modulation(haze::Float64; β_max=10.0, α=1.0)
    β = β_max / (1.0 + α * haze)
    return clamp(β, 1.0, β_max)
end
```

---

### 2.3 SPM生成時の知覚変調

β は SPM の soft aggregation に影響する：

$$
\text{SPM}_{\text{ch2}}[m,n] = \frac{\sum_i w_i \exp(\beta \cdot \phi_i)}{\sum_i \exp(\beta \cdot \phi_i)}
$$

- **高 β** (低Haze): 鋭敏な知覚 → 近くの障害物を強調
- **低 β** (高Haze): 粗い知覚 → 広範囲を平均化

---

## 3. VAE の役割（v5.6）

### 3.1 アーキテクチャ（Pattern D維持）

```
Encoder (Action-Dependent):
  (y[k], u[k]) → q(z | y[k], u[k]) = N(μ_z, σ_z²)

Decoder (Action-Conditioned):
  (z, u[k]) → ŷ[k+1]

Reconstruction (Surprise計算用):
  (y[k], u[k]) → Encoder → z → Decoder(z, u) → ŷ_recon
```

### 3.2 VAEの2つの役割

| 役割 | 入力 | 出力 | 用途 |
|------|------|------|------|
| **予測** | $(y[k], u[k])$ | $\hat{y}[k+1]$ | 安全性項 $F_{\text{safety}}$ |
| **再構成** | $(y[k], u[k])$ | $y_{\text{recon}}$ | Surprise項 $S$ |

### 3.3 学習目的関数

$$
\mathcal{L}_{\text{VAE}} = \underbrace{\|\boldsymbol{y}[k+1] - \hat{\boldsymbol{y}}[k+1]\|^2}_{\text{予測誤差}} + \beta_{\text{KL}} \cdot \underbrace{D_{KL}[q(\boldsymbol{z}|\boldsymbol{y}, \boldsymbol{u}) \| p(\boldsymbol{z})]}_{\text{正則化}}
$$

- $\beta_{\text{KL}}$: KL重み（例: 0.1 〜 1.0）

### 3.4 VAE不確実性 σ_z² の位置づけ

**v5.5では**: Haze ≡ $\sigma_z^2$ （主役）
**v5.6では**: $\sigma_z^2$ は補助変数（Self-hazingで利用可能だが必須ではない）

```julia
# v5.5 (旧)
μ, logσ = encode(vae, spm, u)
Haze = mean(exp.(2 .* logσ))  # 自動計算

# v5.6 (新)
Haze = 0.5  # 設計者設定（固定 or スケジュール）
# σ_z²はログのみ、またはSelf-hazingで使用
```

---

## 4. 実装フロー

### 4.1 メインループ

```julia
for step in 1:max_steps
    for agent in agents
        # ===== Step 1: 観測 =====
        SPM_raw = generate_spm(agent, others, obstacles)

        # ===== Step 2: 知覚変調 =====
        Haze = get_haze_value(mode, agent)  # Mode 1/2/3
        β = precision_modulation(Haze)
        SPM = apply_precision(SPM_raw, β)  # 内部でsoft-maxの鋭さを変更

        # ===== Step 3: 行動生成（Active Inference）=====
        u_optimal = compute_action_with_surprise(
            agent, SPM, vae_model,
            λ_safety=10.0, λ_surprise=1.0
        )

        # ===== Step 4: 状態更新 =====
        agent.vel += (u_optimal - damping * agent.vel) * dt
        agent.pos += agent.vel * dt

        # ===== Step 5: ログ記録 =====
        log(agent.id, SPM, u_optimal, Haze, β, surprise)
    end
end
```

### 4.2 Surprise計算の詳細

```julia
function compute_surprise(vae::ActionConditionedVAE, spm::Array, u::Vector)
    # SPMを4Dテンソルに変換 (16,16,3,1)
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # Encode & Decode (再構成)
    μ, logσ = encode(vae, spm_input, u_input)
    z = μ  # 決定論的（平均を使用）
    spm_recon = decode_with_u(vae, z, u_input)

    # 再構成誤差（Surprise）
    surprise = mean((spm_input .- spm_recon).^2)

    return Float64(surprise)
end
```

### 4.3 勾配計算の実装課題

**問題**: ForwardDiff を通じて VAE（Flux model）を微分する必要がある
**解決策**:
- Option A: Zygote によるVAEの勾配計算 + ForwardDiffとの併用
- Option B: サンプルベース最適化（現在のrun_simulation.jlの実装）
- Option C: Surprise項を近似的に扱う（線形近似など）

**Phase 1-3では Option B（サンプルベース）を推奨**

```julia
function compute_action_with_surprise_sampling(agent, spm, vae, params)
    # 候補生成
    u_baseline = compute_action_baseline(agent, spm)
    candidates = [u_baseline + randn(2) * 0.3 for _ in 1:10]

    best_u = u_baseline
    min_F = Inf

    for u_cand in candidates
        # 目標項
        x_next = predict_position(agent, u_cand)
        F_goal = norm(x_next - agent.goal)^2

        # 安全項（VAE予測）
        y_pred = predict_spm(vae, spm, u_cand)
        F_safety = collision_potential(y_pred)

        # Surprise項
        S = compute_surprise(vae, spm, u_cand)

        # 総合評価
        F_total = F_goal + params.λ_safety * F_safety + params.λ_surprise * S

        if F_total < min_F
            min_F = F_total
            best_u = u_cand
        end
    end

    return best_u
end
```

---

## 5. 実験デザイン

### 5.1 アブレーションスタディ

| 条件 | Surprise | Haze | 説明 |
|------|---------|------|------|
| **A0_BASELINE** | ❌ | Fixed (0.0) | 標準FEP、β固定 |
| **A1_HAZE_ONLY** | ❌ | Fixed (0.5) | Haze変調のみ |
| **A2_SURPRISE_ONLY** | ✅ | Fixed (0.0) | Surprise駆動、β固定 |
| **A3_EPH_FIXED** | ✅ | Fixed (0.5) | 両方有効、Haze固定 |
| **A4_EPH_SCHEDULED** | ✅ | Scheduled | 両方有効、Haze適応 |

### 5.2 評価指標

| 指標 | 定義 | 目標 |
|------|------|------|
| **Freezing Rate** | 速度 < 0.1 m/s が 2秒以上の割合 | < 5% |
| **Success Rate** | ゴール到達率 | > 80% |
| **Collision Rate** | 衝突発生率 | < 20% |
| **Path Efficiency** | 直線距離 / 実経路長 | > 0.7 |
| **Jerk** | 加速度変化率の時間平均 | 低いほど良 |

---

## 6. 将来拡張: Self-Hazing (Phase 6)

### 6.1 Self-Hazing の定義

Self-Hazingは、エージェントが自身の経験から**最適な知覚解像度を学習する**機能である。

#### 入力
- VAE不確実性: $\sigma_z^2(y[k], u[k])$
- 予測誤差履歴: $\{e[k-T:k]\}$
- タスク成功率: $\eta_{\text{success}}$
- 衝突履歴: $\{c[k-T:k]\}$

#### 出力
- 最適Haze: $\text{Haze}^*[k]$

#### 学習手法
- **Option 1**: 強化学習（Haze選択を行動空間に追加）
- **Option 2**: メタ学習（MAML等）
- **Option 3**: ベイズ最適化（Haze vs Performance）

### 6.2 実装スケジュール
- **Phase 6.1**: Self-hazing基盤の構築
- **Phase 6.2**: 学習アルゴリズムの実装
- **Phase 6.3**: 性能評価（Manual vs Self）

---

## 7. 学術的貢献

### 7.1 新規性

1. **Active Inferenceの工学的実装**
   Surpriseを明示的に組み込んだ実時間制御

2. **知覚解像度の設計原理**
   Hazeを設計変数として扱う新しいアプローチ

3. **二層制御アーキテクチャ**
   - 下層: Active Inference（行動生成）
   - 上層: Precision制御（知覚変調）

4. **Self-Hazingの理論的枠組み**
   メタ学習による自律的認知解像度制御

### 7.2 理論的位置づけ

| 手法 | 不確実性の扱い | 知覚解像度 | 学習 |
|------|--------------|-----------|------|
| **従来MPC** | 外乱として扱う | 固定 | 不要 |
| **Robust MPC** | 最悪ケース設計 | 固定 | 不要 |
| **RL (SAC等)** | 探索ボーナス | 固定 | 必要 |
| **EPH v5.5** | VAE不確実性 | 自動変調 | VAE学習 |
| **EPH v5.6** | Surprise + Haze | 設計者制御 | VAE学習 |
| **EPH v6+ (Self)** | Surprise + Haze | 自律学習 | VAE + Meta |

---

## 8. 実装上の注意点

### 8.1 勾配計算の課題

**問題**: $\partial S / \partial \boldsymbol{u}$ の計算がVAEを通じて必要
**現実的解法**: サンプルベース最適化（10〜20候補）

### 8.2 計算コスト

| 項目 | 計算量 | 対策 |
|------|--------|------|
| VAE Forward | 中 | GPU使用 |
| Surprise計算 | 高（候補数×VAE） | 候補数を10程度に制限 |
| 勾配計算 | 不要（サンプルベース） | - |

### 8.3 ハイパーパラメータ

| パラメータ | 推奨値 | 調整範囲 |
|----------|--------|---------|
| $\lambda_{\text{safety}}$ | 10.0 | 5.0 〜 20.0 |
| $\lambda_{\text{surprise}}$ | 1.0 | 0.1 〜 5.0 |
| Haze (固定) | 0.5 | 0.0 〜 1.0 |
| $\beta_{\max}$ | 10.0 | 5.0 〜 20.0 |
| $\alpha$ | 1.0 | 0.5 〜 2.0 |

---

## 9. まとめ

### v5.6の核心

1. **Surprise**: Active Inferenceの理論的要請として必須
2. **Haze**: 設計者が制御する知覚解像度パラメータ
3. **VAE**: 予測とSurprise計算の道具（Hazeとは独立）
4. **Self-Hazing**: Phase 6での将来拡張

### 実装戦略

- **Phase 1-3**: VAE学習・検証（Surprise機能付き）
- **Phase 4-5**: 固定Haze（0.5）での制御統合・比較実験
- **Phase 6**: Self-Hazingの研究開発

---

**次のステップ**: この理論フレームワークに基づいた実装プラン（`implementation_plan_v56.md`）の作成
