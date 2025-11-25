---
title: "Social Value in Active Inference: Theory and Implementation"
subtitle: "Active Inferenceにおける社会的価値の定式化とHaze変調との統合"
type: Technical_Note
status: 🟢 Active
version: 1.2
date_created: 2025-11-25
date_modified: 2025-11-25
revision_note: "SPM-based feature functions (v1.1→1.2)"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Active Inference
  - Social Value
  - Free Energy Principle
  - Pragmatic Value
  - Shepherding
  - Multi-agent Systems
  - Differentiable Prediction
  - SPM
  - Perceptual Grounding
---

# Social Value in Active Inference: Theory and Implementation

> [!ABSTRACT]
> **Purpose**: 本ドキュメントは、Active InferenceにおけるSocial Value（社会的価値）項の理論的基盤と実装方法を解説する。Free Energy Principleの基礎から始め、Expected Free Energy (EFE)の定式化、Pragmatic ValueとしてのSocial Valueの導出、そしてHaze変調との統合方法を学術的に厳密に説明する。Shepherdingタスクへの応用を具体例として示す。

---

## 0. Executive Summary

### 主要な概念

**Social Value**とは、Active Inferenceフレームワークにおいて**他のエージェントとの空間的・社会的関係性を維持・形成する動機**を表現するPragmatic Value項である。

**3つの重要な性質**：

1. **Pragmatic Valueの一種**: Epistemic Value（認識的価値）とは独立した、目標指向的な動機
2. **Hazeと相補的**: Hazeは知覚の精度を変調、Social Valueは行動の動機を提供
3. **Compactness不変性の解決**: 反発力のみでは不可能な集約行動を実現

**応用領域**：
- Shepherding（牧羊タスク）
- Flocking（群れ行動）
- Formation Control（隊列制御）
- Crowd Evacuation（避難誘導）

---

## 1. Free Energy Principle の基礎

### 1.1 自由エネルギーの定義

Free Energy Principle (FEP)は、生物システムが**変分自由エネルギー (Variational Free Energy, VFE)** を最小化することで環境との相互作用を行うという統一理論である（Friston, 2010）。

**変分自由エネルギー**:

$$
\boxed{F = \mathbb{E}_{q(s)}[\log q(s) - \log p(o, s)] = D_{KL}[q(s) || p(s|o)] - \log p(o)}
$$

ここで：
- $s$: 隠れ状態（環境の真の状態）
- $o$: 観測（エージェントが知覚する情報）
- $q(s)$: 隠れ状態の近似事後分布（エージェントの信念）
- $p(s|o)$: 真の事後分布
- $p(o)$: エビデンス（観測の周辺尤度）

**直感的解釈**:
- VFEは「真の事後分布」と「エージェントの信念」の乖離（KLダイバージェンス）を測る
- VFEを最小化 = より正確な信念を持つ = 予測誤差を減らす

### 1.2 自由エネルギーの分解

VFEは2つの項に分解される：

$$
F = \underbrace{\mathbb{E}_{q(s)}[\log q(s) - \log p(s)]}_{\text{Complexity}} - \underbrace{\mathbb{E}_{q(s)}[\log p(o|s)]}_{\text{Accuracy}}
$$

**Complexity項**: 事前分布からの逸脱（オッカムの剃刀）

**Accuracy項**: 観測の説明度（予測精度）

この分解により、FEPは「シンプルかつ正確なモデル」を追求することがわかる。

### 1.3 知覚と行動の統一

FEPは知覚（Perception）と行動（Action）を統一的に扱う：

**知覚**: $q(s)$ を更新してVFEを最小化（信念更新）

**行動**: $o$ を変化させてVFEを最小化（能動的推論、Active Inference）

この統一により、「世界を理解する（知覚）」と「世界を変える（行動）」が同じ原理（VFE最小化）で説明される。

---

## 2. Active Inference と Expected Free Energy

### 2.1 Expected Free Energy (EFE) の定義

Active Inferenceでは、エージェントは**将来の行動**を選択する際に、**Expected Free Energy (EFE)** を最小化する（Friston et al., 2015）。

$$
\boxed{G(\pi) = \mathbb{E}_{q(o_{\tau}, s_{\tau}|\pi)} \left[ \log q(s_{\tau}|o_{\tau}, \pi) - \log p(o_{\tau}, s_{\tau}) \right]}
$$

ここで：
- $\pi$: 行動方策（action policy）
- $\tau$: 将来の時刻
- $q(o_{\tau}, s_{\tau}|\pi)$: 方策 $\pi$ に従った場合の予測分布

**VFEとの違い**:
- **VFE**: 現在の観測に対する信念の誤差（知覚の問題）
- **EFE**: 将来の観測に対する期待誤差（行動選択の問題）

### 2.2 EFE の分解: Epistemic vs Pragmatic

EFEは2つの項に分解される：

$$
G(\pi) = \underbrace{\mathbb{E}_{q(o_{\tau}|\pi)} [D_{KL}[q(s_{\tau}|o_{\tau}, \pi) || q(s_{\tau}|\pi)]]}_{\text{Epistemic Value (情報獲得)}} - \underbrace{\mathbb{E}_{q(o_{\tau}|\pi)} [D_{KL}[q(o_{\tau}|\pi) || p^*(o_{\tau})]]}_{\text{Pragmatic Value (目標達成)}}
$$

#### Epistemic Value（認識的価値）

**意味**: 「この行動で不確実性を減らせるか？」

$$
\mathcal{I}(\pi) = \mathbb{E}_{q(o_{\tau}|\pi)} [D_{KL}[q(s_{\tau}|o_{\tau}, \pi) || q(s_{\tau}|\pi)]]
$$

- 行動後の信念 $q(s_{\tau}|o_{\tau}, \pi)$ と行動前の信念 $q(s_{\tau}|\pi)$ の差
- **情報獲得（Information Gain）**に相当
- 探索行動を駆動する

**具体例（EPH）**:
- SPMの占有チャネルが不確実（Haze高） → 移動して確認したい
- 障害物が多い領域 → 慎重に移動して衝突を避けたい

#### Pragmatic Value（実用的価値）

**意味**: 「この行動で目標に近づけるか？」

$$
\mathcal{P}(\pi) = -\mathbb{E}_{q(o_{\tau}|\pi)} [D_{KL}[q(o_{\tau}|\pi) || p^*(o_{\tau})]]
$$

- 予測される観測 $q(o_{\tau}|\pi)$ と望ましい観測 $p^*(o_{\tau})$ の差
- **Prior Preference（事前好み）**による目標指向
- 活用行動を駆動する

**具体例（EPH）**:
- 目標地点に到達したい
- 羊を特定の場所に集めたい ← **Social Valueはここ**

### 2.3 EFE最小化による行動選択

最適な行動は、EFEを最小化する方策 $\pi^*$ として選択される：

$$
\pi^* = \arg\min_{\pi} G(\pi)
$$

実装上は、勾配降下法による最適化：

$$
a_{t+1} = a_t - \eta \nabla_a G(a)
$$

ここで $\eta$ は学習率、$\nabla_a G(a)$ はEFEの行動に関する勾配。

---

## 3. Social Value の定式化

### 3.1 Social Value とは何か

**Social Value**は、**Pragmatic Valueの一種**であり、以下のような「他のエージェントとの関係性に関する目標」を表現する：

1. **集約（Aggregation）**: エージェント同士が適度に集まること
2. **分散（Dispersion）**: エージェント同士が適度に離れること
3. **隊形維持（Formation）**: 特定の空間配置を保つこと
4. **誘導（Guidance）**: 他のエージェントを特定の場所に導くこと

### 3.2 Prior Preference としての定式化

Active Inferenceでは、Pragmatic Valueを**望ましい状態の事前分布** $p^*(s)$ として表現する：

$$
\mathcal{P} = -\mathbb{E}_{q(s_{\tau}|\pi)} [\log p^*(s_{\tau})]
$$

**Prior Preference** $p^*(s)$ は、「こうなってほしい」という状態の確率分布：
- $p^*(s)$ が高い状態 = 望ましい状態
- $p^*(s)$ が低い状態 = 避けたい状態

**具体例（Shepherding）**:
- 望ましい状態: 羊が集まり、目標地点に近い
- 避けたい状態: 羊が散らばり、目標から遠い

### 3.3 Social Value の一般形と行動依存性

**重要な原則**:

1. **行動依存性**: Social Valueは**行動$a$に依存**する必要がある（$\nabla_a M_{\text{social}} \neq 0$）
2. **知覚的一貫性**: Social Valueは**SPM（知覚表現）から計算**するべき
3. **エージェント中心性**: 全知的な視点ではなく、自己の知覚に基づく

$$
\boxed{M_{\text{social}}(a) = \sum_{i} \lambda_i \cdot f_i(\text{SPM}(a))}
$$

ここで：
- $a$: エージェントの行動（速度ベクトル）
- $\text{SPM}(a)$: 行動$a$による**将来のSPM**（予測された知覚）
- $f_i(\text{SPM})$: SPMから計算される特徴関数
- $\lambda_i$: 各目標の重み

**因果連鎖（SPMベース）**:
```
行動 a
  ↓
自己の将来位置・速度 (p_future, v_future)
  ↓
SPM予測 (GRUまたは1-step forward simulation)
  ↓
特徴関数 f_i(SPM_predicted)
  ↓
M_social(a)
```

この定式化により：
- **勾配計算が自然**: SPM予測は微分可能 → $\nabla_a M_{\text{social}}$ が計算可能
- **GRU予測との整合**: Phase 2で実装済みのSPM予測器を直接利用
- **生物学的妥当性**: エージェントは自身の知覚（SPM）のみから意思決定

**SPMベースの主要特徴関数**:

#### 1. Angular Compactness（角度方向の密集度）

**Occupancyチャネルの角度分布のエントロピー**:

$$
f_{\text{compact}}^{\text{angular}}(\text{SPM}) = -\sum_{\theta=1}^{N_\theta} P(\theta) \log P(\theta)
$$

ここで：
$$
P(\theta) = \frac{\sum_{r} \text{SPM}_{\text{occ}}[r, \theta]}{\sum_{r,\theta'} \text{SPM}_{\text{occ}}[r, \theta']}
$$

- **意味**: 角度方向の占有確率分布のエントロピー
- **低エントロピー** → 特定の角度に集中 → 羊が集約されている
- **高エントロピー** → 全方向に分散 → 羊が散らばっている

**代替案（角度分散）**:

$$
f_{\text{compact}}^{\text{var}}(\text{SPM}) = \text{Var}_{\theta} \left[ \sum_r \text{SPM}_{\text{occ}}[r, \theta] \right]
$$

- 高分散 = 特定方向に偏在（状況に応じて良い/悪い）
- 低分散 = 均等に分布（散らばっている）

#### 2. Goal Direction Alignment（目標方向との整合性）

**目標方向への羊の配置評価**:

$$
f_{\text{goal}}(\text{SPM}, \theta_{\text{goal}}) = \sum_{\theta=1}^{N_\theta} w_{\theta}(\theta_{\text{goal}}) \cdot \sum_r \text{SPM}_{\text{occ}}[r, \theta]
$$

ここで：
$$
w_{\theta}(\theta_{\text{goal}}) = \cos(\theta - \theta_{\text{goal}})
$$

- $\theta_{\text{goal}}$: 犬から見た目標方向の角度インデックス
- **意味**: 目標方向に近いほど高い重み
- **最小化**: 羊が目標と反対側にいる状態を避ける
- **犬の最適位置**: 羊の後方（羊と目標の間に位置しない）

**Shepherding特化版**:

犬は羊の**後方から押す**位置を取るべき：

$$
f_{\text{goal}}^{\text{push}}(\text{SPM}, \theta_{\text{goal}}) = \sum_{\theta} \left| \text{angle\_diff}(\theta, \theta_{\text{goal}} + \pi) \right| \cdot \sum_r \text{SPM}_{\text{occ}}[r, \theta]
$$

- 羊が $\theta_{\text{goal}} + \pi$ 方向（目標の反対側）にいることを推奨
- これにより、犬が羊を後ろから押す形になる

#### 3. Radial Distribution（距離分布）

**Occupancyの動径方向分布**（オプション）:

$$
f_{\text{radial}}(\text{SPM}, r_{\text{prefer}}) = \sum_{r=1}^{N_r} (r - r_{\text{prefer}})^2 \cdot \sum_{\theta} \text{SPM}_{\text{occ}}[r, \theta]
$$

- $r_{\text{prefer}}$: 望ましい距離ビン（例: bin 3-4 = mid-range）
- **意味**: 羊が適切な距離にいるか
- **近すぎる** ($r$ 小) → 羊が逃げて散らばる
- **遠すぎる** ($r$ 大) → 制御が効かない

#### 4. Velocity Coherence（速度の整合性）

**RadialおよびTangentialチャネルの利用**（オプション）:

$$
f_{\text{velocity}}(\text{SPM}) = \text{Var}_{\theta} \left[ \sum_r \text{SPM}_{\text{radi}}[r, \theta] \right] + \text{Var}_{\theta} \left[ \sum_r \text{SPM}_{\text{tang}}[r, \theta] \right]
$$

- **意味**: 羊の速度方向の統一性
- **低分散** → 羊が同じ方向に移動（良い）
- **高分散** → 羊がバラバラの方向に移動（悪い）

### 3.4 Shepherding における Social Value（SPMベース）

Shepherdingタスクでは、以下の2つの目標を統合：

$$
\boxed{M_{\text{social}}^{\text{shepherd}}(a) = \lambda_{\text{compact}} \cdot f_{\text{compact}}^{\text{angular}}(\text{SPM}(a)) + \lambda_{\text{goal}} \cdot f_{\text{goal}}^{\text{push}}(\text{SPM}(a), \theta_{\text{goal}})}
$$

**SPMベースの行動依存性**:

```
犬の行動 a
  ↓
犬の将来位置・速度 (p_future, v_future)
  ↓
SPM予測 SPM(a) = predict_spm(p_future, v_future, sheep_list)
  |
  |--- Occupancyチャネル → f_compact(角度エントロピー)
  |--- Occupancyチャネル + 目標角度 → f_goal(後方押し出し)
  ↓
M_social(a)
```

**具体的な定式化**:

1. **Angular Compactness**（角度エントロピーで評価）:

$$
f_{\text{compact}}^{\text{angular}}(\text{SPM}) = -\sum_{\theta=1}^{N_\theta} P(\theta) \log P(\theta)
$$

$$
P(\theta) = \frac{\sum_{r} \text{SPM}_{\text{occ}}[r, \theta]}{\sum_{r,\theta'} \text{SPM}_{\text{occ}}[r, \theta']}
$$

- **最小化**: エントロピーが低い = 羊が特定方向に集中 = 良い
- **SPM利点**: GRU予測から直接計算可能

2. **Goal Pushing**（後方からの押し出し）:

$$
f_{\text{goal}}^{\text{push}}(\text{SPM}, \theta_{\text{goal}}) = -\sum_{\theta} \cos(\theta - (\theta_{\text{goal}} + \pi)) \cdot O(\theta)
$$

ここで：
$$
O(\theta) = \sum_r \text{SPM}_{\text{occ}}[r, \theta]
$$

- $\theta_{\text{goal}}$: 犬から見た目標方向（SPM座標系）
- $\theta_{\text{goal}} + \pi$: 目標の反対側（犬が位置すべき方向）
- **最小化**: 羊を目標と反対側に配置 → 犬が後方から押す形

**重みの例**:
- $\lambda_{\text{compact}} = 1.0$: 集約の重要度
- $\lambda_{\text{goal}} = 0.5$: 目標到達の重要度

**重みの調整による戦略変化**:

| Phase | $\lambda_{\text{compact}}$ | $\lambda_{\text{goal}}$ | 戦略 |
|-------|---------------------------|------------------------|------|
| Early | 2.0 | 0.5 | まず集約（Collecting） |
| Middle | 1.0 | 1.0 | 集約しながら誘導 |
| Late | 0.5 | 2.0 | 目標到達優先（Driving） |

**Strömbomとの比較**:
- **Strömbom**: 固定閾値でCollecting ↔ Driving切り替え
- **EPH + Social Value**: 連続的な重み調整で滑らかな遷移

---

## 4. Haze との関係

### 4.1 Haze の役割の復習

**Haze Tensor** $\mathcal{H}(r, \theta, c)$ は、SPM（Saliency Polar Map）上の**精度変調場**である：

$$
\Pi(r, \theta, c) = \Pi_{\text{base}}(r, \theta, c) \cdot (1 - h(r, \theta, c))^{\gamma}
$$

- $\Pi$: Precision（精度）
- $h \in [0, 1]$: Haze値（高いほど低精度）
- $\gamma > 0$: 感度パラメータ

**Hazeの効果**:
- **高Haze** → 低精度 → 情報を信頼しない → Epistemic Valueが小さい
- **低Haze** → 高精度 → 情報を信頼する → Epistemic Valueが大きい

### 4.2 Epistemic と Pragmatic の分離

**重要な原則**:

> **Hazeは Epistemic Term のみを変調し、Pragmatic Term（Social Value）は直接変調しない**

**理由**:
1. **Epistemic（認識的価値）**: 知覚の不確実性に関する項
   - Hazeは「知覚の信頼度」を変調
   - 「この情報をどれくらい信じるか」を調整
   - SPM空間で動作

2. **Pragmatic（実用的価値）**: 目標達成に関する項
   - 目標状態は知覚不確実性とは独立
   - 「何を達成したいか」は知覚精度とは無関係
   - 実空間での状態評価

**数式での表現**:

$$
G(a) = \underbrace{F_{\text{percept}}(a, \mathcal{H})}_{\text{Hazeで直接変調}} + \underbrace{M_{\text{social}}(a)}_{\text{Hazeで直接変調されない}}
$$

**注意**: Social Valueは行動$a$を通じて間接的にHazeの影響を受ける可能性がある。
- Hazeが行動選択に影響 → 行動が変化 → Social Valueも変化
- しかし、これは間接的な影響であり、直接的な変調ではない

### 4.3 相補的な役割

HazeとSocial Valueは相補的に機能する：

| 項 | Haze | Social Value |
|----|------|--------------|
| **変調対象** | Epistemic Value | — |
| **制御内容** | 知覚の精度 | 行動の動機 |
| **機能** | 衝突回避の強度調整 | 集約・誘導の目標設定 |
| **時間スケール** | 速い（毎ステップ） | 遅い（戦略レベル） |
| **空間範囲** | 局所的（SPMの特定bin） | 大域的（全エージェント） |

**具体例（Shepherding）**:

```
【Collecting Phase】
- Social Value: λ_compact = 2.0, λ_goal = 0.5
  → 「羊を集めろ！」という動機が強い

- Haze: 羊方向に低Haze、その他は高Haze
  → 羊に注意を集中、他は気にしない

結果: 犬が羊を積極的に集める


【Driving Phase】
- Social Value: λ_compact = 0.5, λ_goal = 2.0
  → 「目標に向かえ！」という動機が強い

- Haze: 前方に低Haze、後方に高Haze
  → 進行方向を注視、後ろは気にしない

結果: 犬が羊を目標に誘導
```

### 4.4 Compactness 不変性の解決

**Phase 3の発見**:
> 反発力のみのシステムでは、Haze操作はagent dispersion（分散度）を変更できない

**理論的説明**:
- Hazeは「既存の駆動力」を変調するだけ
- 反発力のみ → Hazeは反発の強さを変えるだけ
- 引力がない → 集約する力がない

**Social Valueによる解決**:
- Social Value = 新しい駆動力（集約への動機）
- Haze = その駆動力の空間的変調

**統合効果**:

$$
\text{Total Drive} = \underbrace{\text{Repulsion}}_{\text{Hazeで変調}} + \underbrace{\text{Social Attraction}}_{\text{新しい駆動力}}
$$

Hazeは Social Attractionの空間分布を変調し、効果的な集約を実現：
- 羊に近い方向: 低Haze → Social Attractionが強く働く → 積極的に集める
- 羊から遠い方向: 高Haze → Social Attractionが弱まる → 効率的

---

## 5. 実装方法

### 5.1 EPH Controller への統合（SPMベース実装）

**重要な原則**:
1. Social Valueは行動$a$による**将来のSPM予測**から計算
2. 羊の位置を直接使わず、SPMのOccupancyチャネルから計算
3. GRU予測器を使用（既存のPhase 2実装を活用）

```julia
"""
EFE with Social Value and Haze Modulation (SPM-based Implementation)
"""
function compute_efe_with_social_value(
    action::Vector{Float64},
    dog::Agent,
    sheep_list::Vector{SheepAgent},
    goal_position::Vector{Float64},
    params::EPHParams,
    gru_predictor::GRUPredictor  # Phase 2で実装済み
)
    # === 1. Predict future state from action ===
    dog_pos_future = dog.position + action * params.dt
    dog_vel_future = action

    # === 2. Predict future SPM using GRU ===
    # Option A: Use GRU predictor (preferred for trained models)
    spm_predicted = predict_spm_gru(
        gru_predictor,
        dog.spm_history,  # Past SPMs
        action,
        params
    )

    # Option B: Use 1-step forward simulation (for baseline)
    # spm_predicted = compute_spm_at_future_position(
    #     dog_pos_future,
    #     dog_vel_future,
    #     sheep_list,
    #     params
    # )

    # === 3. Epistemic Term (Haze-modulated) ===
    F_percept = compute_surprise_cost_with_haze(
        spm_predicted,
        dog.haze_matrix,
        params
    )

    # === 4. Pragmatic Term: Social Value (SPM-based) ===
    # 4.1 Compute goal direction in SPM coordinates
    goal_vec = goal_position - dog_pos_future
    θ_goal = atan(goal_vec[2], goal_vec[1]) - atan(dog_vel_future[2], dog_vel_future[1])
    θ_goal_idx = angle_to_spm_index(θ_goal, params.Nθ)

    # 4.2 Angular Compactness (from Occupancy channel)
    M_compact = compute_angular_compactness(spm_predicted, params)

    # 4.3 Goal Pushing (from Occupancy + goal direction)
    M_goal = compute_goal_pushing(spm_predicted, θ_goal_idx, params)

    # 4.4 Combined Social Value
    M_social = params.λ_compact * M_compact + params.λ_goal * M_goal

    # === 5. Total EFE ===
    G = F_percept + M_social

    return G
end

"""
Angular Compactness from SPM Occupancy channel
Low entropy = compact (good), high entropy = dispersed (bad)
"""
function compute_angular_compactness(
    spm::Array{Float64, 3},
    params::EPHParams
)
    # Extract occupancy channel (channel 1)
    occ = spm[1, :, :]  # Shape: (Nr, Nθ)

    # Sum over radial bins to get angular distribution
    O_θ = sum(occ, dims=1)  # Shape: (1, Nθ)
    O_θ = vec(O_θ)  # Shape: (Nθ,)

    # Normalize to probability distribution
    total = sum(O_θ)
    if total < 1e-6
        # No sheep visible → neutral cost
        return 0.0
    end

    P_θ = O_θ / total

    # Compute entropy
    H = 0.0
    for p in P_θ
        if p > 1e-10
            H -= p * log(p)
        end
    end

    # Return entropy (minimize for compactness)
    return H
end

"""
Goal Pushing: encourage sheep to be in direction opposite to goal
(so dog can push from behind)
"""
function compute_goal_pushing(
    spm::Array{Float64, 3},
    θ_goal_idx::Int,
    params::EPHParams
)
    # Extract occupancy channel
    occ = spm[1, :, :]  # Shape: (Nr, Nθ)

    # Sum over radial bins
    O_θ = sum(occ, dims=1)  # Shape: (1, Nθ)
    O_θ = vec(O_θ)  # Shape: (Nθ,)

    # Compute target direction: opposite to goal (dog should be behind sheep)
    θ_target = mod1(θ_goal_idx + params.Nθ ÷ 2, params.Nθ)

    # Angular cost: prefer sheep in target direction
    cost = 0.0
    for θ in 1:params.Nθ
        # Angular distance from target
        Δθ = min(abs(θ - θ_target), params.Nθ - abs(θ - θ_target))

        # Weight based on angular distance
        w = cos(2π * Δθ / params.Nθ)

        # Penalize if sheep NOT in target direction
        # (minimize → wants high occupancy at θ_target)
        cost -= w * O_θ[θ]
    end

    return cost
end
```

**SPMベース実装の利点**:

1. **勾配計算の効率性**:
   - SPM予測は既に微分可能（GRU/Zygoteで実装済み）
   - `action` → `spm_predicted` → `M_social` の全経路が微分可能
   - $\nabla_a M_{\text{social}}$ が自動的に計算される

2. **知覚的一貫性**:
   - 犬は自身のSPM（知覚）のみから意思決定
   - 羊の正確な位置を知らなくても機能
   - より生物学的に妥当

3. **Phase 2との統合**:
   - GRU予測器をそのまま利用可能
   - 追加の予測モデルが不要
   - 既存のインフラを最大活用

4. **計算効率**:
   - 羊の個別シミュレーションが不要（1-step forward baselineを除く）
   - O(N_r × N_θ) の計算量（羊の数に依存しない）

### 5.2 Surprise Cost の計算（Haze変調あり）

```julia
"""
Compute surprise cost with haze modulation
"""
function compute_surprise_cost_with_haze(
    spm::Array{Float64, 3},
    haze_matrix::Matrix{Float64},
    params::EPHParams
)
    F = 0.0
    Nr, Nθ, Nc = size(spm)

    for r in 1:Nr, θ in 1:Nθ, c in 1:Nc
        # Base precision
        π_base = params.Π_base[r, θ, c]

        # Haze modulation
        h = haze_matrix[r, θ]
        π_modulated = π_base * (1.0 - h)^params.γ

        # Precision-weighted squared error
        # (仮に temporal prediction errorとして)
        prediction_error = spm[r, θ, c]^2
        F += π_modulated * prediction_error
    end

    return F
end
```

### 5.3 動的な重み調整

```julia
"""
Adaptive weight adjustment based on task phase
"""
function adjust_social_value_weights(
    agent::Agent,
    other_agents::Vector{Agent},
    goal_position::Vector{Float64},
    params::EPHParams
)
    # Compute current compactness
    com = compute_center_of_mass(other_agents)
    C = mean([norm(a.position - com)^2 for a in other_agents])

    # Compute distance to goal
    D_goal = norm(com - goal_position)

    # Adaptive strategy
    if C > params.C_threshold_high
        # Highly dispersed → Focus on collecting
        λ_compact = 2.0
        λ_goal = 0.5
    elseif C < params.C_threshold_low
        # Already compact → Focus on driving
        λ_compact = 0.5
        λ_goal = 2.0
    else
        # Balanced
        λ_compact = 1.0
        λ_goal = 1.0
    end

    return (λ_compact, λ_goal)
end
```

### 5.4 Zygote による勾配降下

```julia
"""
Action selection via gradient descent on EFE
"""
function select_action_with_social_value(
    agent::Agent,
    other_agents::Vector{Agent},
    goal_position::Vector{Float64},
    params::EPHParams
)
    # Initialize with previous velocity
    a = copy(agent.velocity)

    # Gradient descent
    for iter in 1:params.n_gradient_steps
        # Compute gradient via automatic differentiation
        grad = gradient(a -> compute_efe_with_social_value(
            a, agent, other_agents, goal_position, params
        ), a)[1]

        # Update action
        a = a - params.η * grad

        # Clip to max speed
        if norm(a) > params.max_speed
            a = params.max_speed * normalize(a)
        end
    end

    return a
end
```

---

## 6. 理論的性質

### 6.1 Social Value の収束性

**命題1**: Social Valueが凸関数であれば、勾配降下はグローバル最小に収束する。

**証明スケッチ**:
1. Compactness項 $f_{\text{compact}}(s) = \sum_i ||\mathbf{p}_i - \mathbf{p}_{\text{COM}}||^2$ は凸
2. Goal Distance項 $f_{\text{goal}}(s) = ||\mathbf{p}_{\text{COM}} - \mathbf{p}_{\text{goal}}||^2$ は凸
3. 凸関数の非負線形結合は凸
4. 凸関数の勾配降下はグローバル最小に収束（学習率 $\eta$ が適切なら）

**実装上の注意**: Epistemic項は一般に非凸。収束はlocal minimumまで。

### 6.2 Haze と Social Value の関係

**命題2**: Haze変調はEpistemic項を**直接変調**するが、Social Value項は**直接変調しない**。

**理由**:

1. **数式上の独立性**:
   $$
   M_{\text{social}}(a) = f(\text{SPM}(a), \theta_{\text{goal}})
   $$
   この式にHaze $\mathcal{H}$ は**明示的に現れない**。

   (注: SPMベース定式化では、SPM予測から特徴関数を計算)

2. **間接的な影響は存在**:
   - Hazeが行動選択に影響 → 行動$a$が変化 → Social Valueも変化
   - しかし、これは$M_{\text{social}}$の定義自体が変わるわけではない

**形式的表現**:

$$
\frac{\partial M_{\text{social}}(a)}{\partial \mathcal{H}} = \frac{\partial M_{\text{social}}}{\partial a} \cdot \frac{\partial a}{\partial \mathcal{H}}
$$

- 第1項: Social Valueの行動感度（非ゼロ）
- 第2項: Hazeによる行動変化（Epistemic項を通じて非ゼロ）
- **積は非ゼロ**（間接的影響あり）

しかし、定義上の直接依存はない：

$$
\frac{\partial M_{\text{social}}(a, \mathcal{H})}{\partial \mathcal{H}} \bigg|_{a=\text{const}} = 0
$$

**実装上の含意**:
- Hazeは知覚精度の設計パラメータ
- Social Valueは目標状態の設計パラメータ
- 両者は異なる側面を制御するが、行動選択を通じて相互作用する

### 6.3 Compactness 不変性の形式的証明

**定理**: 反発力のみのシステム $F_{\text{repulsion}} = -\sum_{i \neq j} \nabla V_{\text{rep}}(||\mathbf{p}_i - \mathbf{p}_j||)$ において、Haze変調 $\mathcal{H}(r, \theta)$ は平衡状態のCompactness $C^*$ を変更しない。

**証明**:

1. 平衡状態: $\sum_j F_{ij}^{\text{rep}} = 0 \quad \forall i$

2. Haze変調: $F_{ij}^{\text{rep}} \to w_{ij}(\mathcal{H}) \cdot F_{ij}^{\text{rep}}$ ここで $w_{ij} > 0$

3. 新しい平衡: $\sum_j w_{ij} F_{ij}^{\text{rep}} = 0$

4. スケール不変性: $F_{ij}^{\text{rep}} \propto ||\mathbf{p}_i - \mathbf{p}_j||^{-n}$ なら、$w_{ij}$ の変化は相対位置のスケール変化のみ

5. Compactness $C = \text{Var}[\mathbf{p}_i]$ はスケール不変（相対位置が保存されるため）

**結論**: 反発のみでは絶対的なCompactnessは制御不可。引力（Social Value）が必須。

---

## 7. Shepherding への応用

### 7.1 問題設定

**エージェント**:
- **犬（Dog）**: EPH制御、目標は羊を集めて目標地点に誘導
- **羊（Sheep）**: BOIDS行動 + 犬からの逃走反応

**タスク**:
1. 散らばった羊を集約（Collecting）
2. 集約した羊を目標地点に誘導（Driving）

**評価指標**:
- Success Rate: 羊が目標領域に到達したか
- Time to Goal: 誘導完了までの時間
- Compactness: 羊の密集度（タスク中の平均）
- Dog Efficiency: 犬の移動距離

### 7.2 EPH Shepherding の実装

> [!NOTE]
> **最新の実装方法**: このセクションは実装の全体構造を示すスケルトンです。
> **Social ValueのSPMベース実装**については**Section 5.1**を参照してください。
> Section 5.1では、GRU予測器を使った最新のSPMベース特徴関数が定義されています。

**完全な実装例（構造のみ、詳細はSection 5.1参照）**:

```julia
# ========================================
# EPH Shepherding Agent
# ========================================

mutable struct DogAgent <: Agent
    position::Vector{Float64}
    velocity::Vector{Float64}
    spm::Array{Float64, 3}
    haze_self::Float64
    haze_matrix::Matrix{Float64}
    λ_compact::Float64
    λ_goal::Float64
end

function update_dog_agent!(
    dog::DogAgent,
    sheep_list::Vector{SheepAgent},
    goal_position::Vector{Float64},
    params::EPHParams
)
    # 1. Update SPM (perception of current state)
    dog.spm = compute_spm(dog, sheep_list, params)

    # 2. Compute self-haze (adaptive)
    occupancy = sum(dog.spm[1, :, :])  # Channel 1 = Occupancy
    dog.haze_self = compute_self_haze(occupancy, params)

    # 3. Adjust Social Value weights (adaptive)
    (dog.λ_compact, dog.λ_goal) = adjust_social_value_weights(
        dog, sheep_list, goal_position, params
    )

    # 4. Compute haze matrix (spatial modulation)
    dog.haze_matrix = compute_haze_for_shepherding(
        dog, sheep_list, goal_position, params
    )

    # 5. Select action via EFE minimization with gradient descent
    # IMPORTANT: This uses forward prediction of sheep reactions
    action = select_action_shepherding(
        dog, sheep_list, goal_position, params
    )

    # 6. Update position and velocity
    dog.velocity = 0.7 * action + 0.3 * dog.velocity  # Smoothing
    dog.position += dog.velocity * params.dt

    # Toroidal wrap
    dog.position = mod.(dog.position, params.world_size)
end

# ========================================
# Action Selection with Gradient Descent
# ========================================

function select_action_shepherding(
    dog::DogAgent,
    sheep_list::Vector{SheepAgent},
    goal_position::Vector{Float64},
    params::EPHParams
)
    # Initialize with previous velocity
    a = copy(dog.velocity)

    # Gradient descent on EFE
    for iter in 1:params.n_gradient_steps
        # Compute gradient via automatic differentiation
        # This automatically computes ∇_a M_social through forward prediction
        grad = gradient(a -> compute_efe_with_social_value(
            a, dog, sheep_list, goal_position, params
        ), a)[1]

        # Gradient descent step
        a = a - params.η * grad

        # Clip to max speed
        if norm(a) > params.max_speed
            a = params.max_speed * normalize(a)
        end
    end

    return a
end

# ========================================
# Haze Strategy for Shepherding
# ========================================

function compute_haze_for_shepherding(
    dog::DogAgent,
    sheep_list::Vector{SheepAgent},
    goal_position::Vector{Float64},
    params::EPHParams
)
    h_matrix = ones(Float64, params.Nr, params.Nθ)

    # Strategy 1: Low haze toward sheep (focus on sheep)
    com = compute_center_of_mass(sheep_list)
    sheep_direction_vec = com - dog.position
    sheep_angle = atan(sheep_direction_vec[2], sheep_direction_vec[1])

    # Convert to SPM angular index
    θ_sheep = angle_to_theta_index(sheep_angle, params.Nθ)

    # Low haze in ±30° around sheep direction
    for dθ in -2:2
        θ_idx = mod1(θ_sheep + dθ, params.Nθ)
        h_matrix[:, θ_idx] *= 0.5  # High precision toward sheep
    end

    # Strategy 2: Mid-distance high haze (avoid over-planning)
    h_matrix[3:5, :] *= 2.0  # Bins 3-5 = mid-range

    # Strategy 3: Combine with self-haze
    h_matrix = max.(h_matrix, dog.haze_self)

    # Clamp to [0, 1]
    clamp!(h_matrix, 0.0, 1.0)

    return h_matrix
end

# ========================================
# Sheep BOIDS Model
# ========================================

mutable struct SheepAgent
    position::Vector{Float64}
    velocity::Vector{Float64}
    boids_weights::Vector{Float64}  # [w_sep, w_ali, w_coh]
end

function update_sheep_agent!(
    sheep::SheepAgent,
    sheep_list::Vector{SheepAgent},
    dog_list::Vector{DogAgent},
    params::SheepParams
)
    # BOIDS forces
    f_sep = compute_separation(sheep, sheep_list, params)
    f_ali = compute_alignment(sheep, sheep_list, params)
    f_coh = compute_cohesion(sheep, sheep_list, params)

    # Flee from dogs
    f_flee = compute_flee_from_dogs(sheep, dog_list, params)

    # Weighted combination
    w = sheep.boids_weights
    f_total = w[1]*f_sep + w[2]*f_ali + w[3]*f_coh + f_flee

    # Update velocity and position
    sheep.velocity += f_total * params.dt

    # Speed limit
    if norm(sheep.velocity) > params.max_speed
        sheep.velocity = params.max_speed * normalize(sheep.velocity)
    end

    sheep.position += sheep.velocity * params.dt

    # Toroidal wrap
    sheep.position = mod.(sheep.position, params.world_size)
end

function compute_flee_from_dogs(
    sheep::SheepAgent,
    dog_list::Vector{DogAgent},
    params::SheepParams
)
    f_flee = zeros(2)

    for dog in dog_list
        d_vec = sheep.position - dog.position
        d = norm(d_vec)

        # Exponential decay
        if d < params.flee_range
            flee_strength = params.k_flee * exp(-d / params.r_fear)
            f_flee += flee_strength * normalize(d_vec)
        end
    end

    return f_flee
end
```

### 7.3 Strömbom との比較

**Strömbom (2014) の2フェーズアルゴリズム**:

```julia
function strombom_update!(dog::DogAgent, sheep_list, goal, params)
    com = compute_center_of_mass(sheep_list)
    max_dist = maximum([norm(s.position - com) for s in sheep_list])

    if max_dist > params.collecting_threshold
        # Collecting: gather stray sheep
        farthest = argmax([norm(s.position - com) for s in sheep_list])
        target = sheep_list[farthest].position +
                 params.offset * normalize(com - sheep_list[farthest].position)
    else
        # Driving: push toward goal
        target = com - params.driving_dist * normalize(goal - com)
    end

    # Simple movement toward target
    dog.velocity = params.dog_speed * normalize(target - dog.position)
    dog.position += dog.velocity * params.dt
end
```

**比較表**:

| 側面 | Strömbom | EPH + Social Value |
|------|----------|-------------------|
| **理論基盤** | ヒューリスティック | Active Inference + FEP |
| **フェーズ切り替え** | 固定閾値（max_dist > threshold） | 連続的（λ_compact/λ_goal動的調整） |
| **Haze利用** | なし | あり（知覚精度を空間的に変調） |
| **適応性** | 静的環境を仮定 | 時変BOIDS環境に対応 |
| **スケーラビリティ** | 1犬専用 | 複数犬の協調が理論的に可能 |
| **学習可能性** | ルール固定 | GRU Haze Policyで最適化可能 |
| **計算複雑度** | O(N) per step | O(N × G) (G=勾配ステップ数) |

---

## 8. 実験設計

### 8.1 評価実験の構成

**独立変数**:
1. **制御手法**: EPH, Strömbom, Random
2. **BOIDS時変性**: Static, Dynamic (3-phase)
3. **羊の数**: 10, 20, 50
4. **犬の数**: 1, 2

**従属変数**:
1. Success Rate
2. Time to Goal
3. Compactness (mean over trajectory)
4. Dog Efficiency (total distance traveled)
5. **Adaptation Index** = Performance_Dynamic / Performance_Static

**統計的検定**:
- 各条件で30回実行（seeds: 42-71）
- 対応のないt検定（EPH vs Strömbom）
- 効果量 Cohen's d
- 有意水準 α = 0.05

### 8.2 Ablation Study

**目的**: 各要素の寄与を明確化

| Condition | Social Value | Haze Modulation | 予想結果 |
|-----------|--------------|-----------------|---------|
| Baseline | ❌ | ❌ | 失敗（集約不可） |
| +Social Value | ✅ | ❌ | 部分的成功（非効率） |
| +Haze (uniform) | ❌ | ✅ | 失敗（動機なし） |
| **Full EPH** | ✅ | ✅ | 成功（効率的） |

**検証項目**:
1. Social Value なし → Compactness不変性により集約失敗
2. Haze なし → 集約可能だが非効率（過剰な衝突回避）
3. Full EPH → 集約 + 効率的誘導

---

## 9. Discussion

### 9.1 理論的意義

**Active Inferenceへの貢献**:
1. **Prior Preferenceの具体例**: Social Valueは「望ましい社会的状態」を明示的に定式化
2. **Epistemic-Pragmatic分離の実証**: Hazeは認識、Social Valueは動機として独立動作
3. **Multi-agent Active Inference**: 個体レベルのEFE最小化 → 集団レベルの協調行動

**Compactness不変性の理論的価値**:
- Negative Result の建設的活用
- Hazeの本質（変調器であり生成器ではない）の解明
- 新しい設計原則の確立

### 9.2 実装上の知見

**成功のための3要素**:
1. **Social Value**: タスク固有の目標を定式化
2. **Haze Modulation**: 知覚精度を空間的に調整
3. **適応的重み**: 環境変化に応じて $\lambda$ を動的調整

**避けるべき落とし穴**:
- Social Value を過度に複雑化（シンプルな2項で十分）
- Hazeの過剰変調（5×以上は不安定）
- 固定重み（適応性の喪失）

### 9.3 今後の研究方向

**Short-term** (Phase 4):
- BOIDS羊 + EPH犬の実装と検証
- Strömbomとの定量比較
- 時変BOIDS環境での適応性実証

**Mid-term**:
- GRU Haze Policyの学習（Meta-RL）
- 複数犬の協調Shepherding
- 実ロボット検証（Turtlebot3）

**Long-term**:
- 階層的Active Inference（個体↔群れ）
- 一般化されたSocial Value理論
- 他タスクへの展開（Flocking, Formation Control）

---

## 10. 参考文献

### Free Energy Principle & Active Inference

1. **Friston, K. J. (2010).** The free-energy principle: a unified brain theory? *Nature Reviews Neuroscience*, 11(2), 127-138.
   DOI: [10.1038/nrn2787](https://doi.org/10.1038/nrn2787)
   **ポイント**: FEPの統一的レビュー。VFEの定義と生物学的意義。

2. **Friston, K. J., Daunizeau, J., & Kiebel, S. J. (2009).** Reinforcement learning or active inference? *PLoS ONE*, 4(7), e6421.
   DOI: [10.1371/journal.pone.0006421](https://doi.org/10.1371/journal.pone.0006421)
   **ポイント**: Active InferenceとRLの関係。EFEの導出。

3. **Friston, K., Rigoli, F., Ognibene, D., Mathys, C., Fitzgerald, T., & Pezzulo, G. (2015).** Active inference and epistemic value. *Cognitive Neuroscience*, 6(4), 187-214.
   DOI: [10.1080/17588928.2015.1020053](https://doi.org/10.1080/17588928.2015.1020053)
   **ポイント**: Epistemic ValueとPragmatic Valueの分解。情報獲得行動の理論。

4. **Parr, T., & Friston, K. J. (2019).** Generalised free energy and active inference. *Biological Cybernetics*, 113(5-6), 495-513.
   DOI: [10.1007/s00422-019-00805-w](https://doi.org/10.1007/s00422-019-00805-w)
   **ポイント**: Generalized Free Energyの数学的厳密化。

### Shepherding & Collective Behavior

5. **Strömbom, D., Mann, R. P., Wilson, A. M., Hailes, S., Morton, A. J., Sumpter, D. J., & King, A. J. (2014).** Solving the shepherding problem: heuristics for herding autonomous, interacting agents. *Journal of The Royal Society Interface*, 11(100), 20140719.
   DOI: [10.1098/rsif.2014.0719](https://doi.org/10.1098/rsif.2014.0719)
   **ポイント**: 2フェーズShepherdingアルゴリズム。実験的検証あり。

6. **Couzin, I. D., Krause, J., James, R., Ruxton, G. D., & Franks, N. R. (2002).** Collective memory and spatial sorting in animal groups. *Journal of Theoretical Biology*, 218(1), 1-11.
   DOI: [10.1006/jtbi.2002.3065](https://doi.org/10.1006/jtbi.2002.3065)
   **ポイント**: Informed individualsによる群れ誘導。Shepherdingの生物学的基盤。

7. **Reynolds, C. W. (1987).** Flocks, herds and schools: A distributed behavioral model. *ACM SIGGRAPH Computer Graphics*, 21(4), 25-34.
   DOI: [10.1145/37402.37406](https://doi.org/10.1145/37402.37406)
   **ポイント**: BOIDSモデルの提案。Separation, Alignment, Cohesionの3ルール。

### Multi-agent Active Inference

8. **Çatal, O., Verbelen, T., Nauta, J., De Boom, C., & Dhoedt, B. (2020).** Learning perception and planning with deep active inference. *IEEE International Conference on Acoustics, Speech and Signal Processing (ICASSP)*, 3952-3956.
   DOI: [10.1109/ICASSP40776.2020.9054364](https://doi.org/10.1109/ICASSP40776.2020.9054364)
   **ポイント**: ニューラルネットワークによるActive Inference実装。

9. **Sajid, N., Ball, P. J., Parr, T., & Friston, K. J. (2021).** Active inference: Demystified and compared. *Neural Computation*, 33(3), 674-712.
   DOI: [10.1162/neco_a_01357](https://doi.org/10.1162/neco_a_01357)
   **ポイント**: Active InferenceとRL/MDPの数学的関係の整理。

### Precision & Attention

10. **Feldman, H., & Friston, K. J. (2010).** Attention, uncertainty, and free-energy. *Frontiers in Human Neuroscience*, 4, 215.
    DOI: [10.3389/fnhum.2010.00215](https://doi.org/10.3389/fnhum.2010.00215)
    **ポイント**: Precision weightingと注意機構の関係。Hazeの理論的基盤。

---

## Appendix: 数学的補足

### A.1 KLダイバージェンスの性質

$$
D_{KL}[q(s) || p(s)] = \int q(s) \log \frac{q(s)}{p(s)} ds
$$

**性質**:
1. 非負性: $D_{KL}[q || p] \geq 0$
2. 等号成立: $D_{KL}[q || p] = 0 \Leftrightarrow q = p$ (a.e.)
3. 非対称: $D_{KL}[q || p] \neq D_{KL}[p || q]$ (一般に)

### A.2 変分自由エネルギーの導出

ベイズの定理から:

$$
p(s|o) = \frac{p(o|s)p(s)}{p(o)}
$$

対数を取る:

$$
\log p(s|o) = \log p(o|s) + \log p(s) - \log p(o)
$$

両辺に $q(s)$ をかけて積分:

$$
\int q(s) \log p(s|o) ds = \int q(s) [\log p(o|s) + \log p(s)] ds - \log p(o)
$$

左辺を変形:

$$
\int q(s) \log p(s|o) ds = -D_{KL}[q(s) || p(s|o)]
$$

右辺を整理:

$$
-D_{KL}[q(s) || p(s|o)] = \mathbb{E}_{q(s)}[\log p(o,s)] - \mathbb{E}_{q(s)}[\log q(s)] - \log p(o)
$$

移項:

$$
\log p(o) = \underbrace{\mathbb{E}_{q(s)}[\log p(o,s)] - \mathbb{E}_{q(s)}[\log q(s)]}_{-F} + D_{KL}[q(s) || p(s|o)]
$$

$D_{KL} \geq 0$ より:

$$
\log p(o) \geq -F
$$

これがVFEの下界（Evidence Lower Bound, ELBO）の意味。

### A.3 勾配の計算（Zygoteによる自動微分）

EFE最小化:

$$
a^* = \arg\min_a G(a)
$$

勾配降下:

$$
a_{k+1} = a_k - \eta \nabla_a G(a_k)
$$

Zygoteの使用例:

```julia
using Zygote

function objective(a)
    return compute_efe_with_social_value(a, agent, others, goal, params)
end

# 勾配計算
grad = gradient(objective, a)[1]

# 更新
a_new = a - η * grad
```

---

**Document Status**: ✅ Complete (Revised)
**Version**: 1.2
**Last Updated**: 2025-11-25

**Revision History**:
- **v1.2** (2025-11-25): SPM-based feature functions
  - Social Value computed from SPM Occupancy channel (not raw positions)
  - Added: Angular Compactness (entropy), Goal Pushing (cosine weighting)
  - Integrates with GRU predictor (Phase 2)
  - More biologically plausible (perceptual grounding)
- **v1.1** (2025-11-25): Action-dependency correction
  - $M_{\text{social}}(a)$ not $M_{\text{social}}(s)$
  - Ensures $\nabla_a M_{\text{social}} \neq 0$ for gradient descent
- **v1.0** (2025-11-25): Initial version

**Key Features**:
- ✅ SPM-based perceptual grounding
- ✅ Action-dependent formulation
- ✅ Haze-modulated Epistemic term
- ✅ Integration with GRU predictor
- ✅ Shepherding task application

**Author**: Hiroshi Igarashi (AI-DLC, Tokyo Denki University)
**License**: Internal Research Document
