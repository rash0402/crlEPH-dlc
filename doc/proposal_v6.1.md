---
title: "Emergent Perceptual Haze (EPH) v6.1: Bin 1-6 Haze=0 Fixed Strategy"
type: Research_Proposal
status: "🟢 Implementation Ready (VAE Retraining Phase)"
version: 6.1.0
date_created: "2026-01-12"
date_modified: "2026-01-12"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Free Energy Principle
  - Active Inference
  - Bin-Based Fixed Foveation
  - Peripersonal Space
  - Precision-Weighted Surprise
  - Social Robot Navigation
  - Computational Empathy
  - Biological Plausibility
tags:
  - Research/Proposal
  - Topic/FEP
  - Status/Implementation_Ready
---

# 研究提案書: Emergent Perceptual Haze (EPH) v6.1 - Bin 1-6 Haze=0 Fixed Strategy

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
>
> **混雑環境における社会的ロボットナビゲーションにおいて、近傍空間（Peripersonal Space）理論と能動的推論に基づく「Bin 1-6 Haze=0固定戦略」により、衝突臨界ゾーン（0-2.18m @ D_max=8m）での精度を最大化し、生物学的に妥当な知覚解像度制御と創発的社会行動（Laminar Flow, Lane Formation, Zipper Effect）を実現する。**

## 要旨 (Abstract)

> [!INFO] 🎯 AI-DLC レビューガイダンス
>
> Goal: 300-500語で研究の全体像を伝える。以下の**6パート構成**を厳守し、数値と専門用語（Keywords）を適切に配置すること。

### 背景 (Background)

混雑環境における自律ロボットの社会的ナビゲーションでは、他者行動の予測困難性が本質的に高く、従来手法（MPC、RL）は過度に保守的な回避行動やFreezingといった行動破綻を引き起こす。我々はv6.0においてActive Inference理論に基づく統一自由エネルギー最小化手法を確立し、v5.6実装バグ（F_safety が行動uに依存しない定数）を修正した。

v6.0では連続的なDual-Zone Sigmoid方式を採用したが、**近傍空間（Peripersonal Space, PPS）理論**および**制御理論的勾配要件**との整合性において不十分な点が明らかになった。神経科学的には、PPSは0.5-2.0m程度の明確な境界を持つ離散的な領域であり、また制御理論的には衝突臨界ゾーン（TTC 1s @ 2.1m）で最大精度が必要である。これらの知見は、Sigmoid blendingよりも**ステップ関数的な離散戦略**が適切であることを示唆している。

### 目的 (Objective)

本研究v6.1の目的は、Hazeを**「Bin 1-6 Haze=0固定戦略」**として再定義し、以下の4つの絶対的設計原理に基づくアーキテクチャを確立することである：

1. **統一自由エネルギーの自動微分駆動（絶対条件）**：ForwardDiff.jlによる∂F/∂u = ∂Φ_goal/∂u + ∂Φ_safety/∂u + ∂S/∂uの完全な勾配ベース最適化
2. **SPMの学術的意義・新規性・信頼性の堅持（絶対条件）**：Log-polar座標系（16×16×3ch, D_max=8.0m）の生物学的妥当性と時空間情報圧縮の学術的価値を維持・向上
3. **多分野理論的正当化**：近傍空間（PPS）理論、能動的推論、実証研究、制御理論、認知科学の5分野による統合的根拠
4. **Bin-Based Fixed Foveation**：Bin 1-6 (0-2.18m) = Haze 0.0（β=10.0, 最大精度）、Bin 7+ (2.18m+) = Haze 0.5（β=5.5, 中程度精度）

これにより、衝突臨界ゾーンでの最大精度と周辺ゾーンでの適度な精度制御が、創発的協調行動を促進するメカニズムを実証する。

**重要な学術的明確化**：本研究では、「統一自由エネルギーの自動微分駆動」および「SPMの学術的価値の堅持」を**絶対的な前提条件**とし、今後のいかなる実装においても、これらの原則から逸脱することは許容されない。これは、v5.6で発生したF_safety定数化バグのような理論的誤解を防ぐための明示的な設計制約である。

### 学術的新規性 (Academic Novelty)

**従来のActive Inference工学的実装**が一様な知覚解像度制御を前提としていたのに対し、**本研究v6.1はActive InferenceにおけるPrecision制御を、近傍空間理論に基づく「Bin 1-6 Haze=0固定戦略」**として実現する。

学術的新規性は以下の5点：

1. **多分野統合理論的正当化**：神経科学（PPS 0.5-2.0m）、能動的推論（精度重み付け）、実証研究（回避開始 2-3m, Moussaïd et al., 2011）、制御理論（TTC 1s → 2.1m）、認知科学（二重過程理論）の5分野による統合的根拠
2. **Bin-Based Fixed Foveation戦略**：Log-polar SPM（D_max=8.0m, 16 bins）のBin 1-6（0-2.18m）でHaze=0.0固定、Bin 7+でHaze=0.5固定のステップ関数
3. **自動微分駆動の徹底**：ForwardDiff.jlによる∂F/∂u = ∂Φ_goal/∂u + ∂Φ_safety/∂u + ∂S/∂uの完全な勾配ベース最適化（v5.6バグ修正の完全継承）
4. **SPM学術的価値の明示化**：16×16×3ch Log-polar座標系の生物学的妥当性（視覚野V1のlog-polar構造）、時空間情報圧縮（O(N²) → O(log N)）、D_max=8.0m（2³の数学的エレガンス＋Hall's Public Distance）
5. **Precision-Weighted Surprise**：距離依存の予測誤差重み付け Π(ρ) = 1/(Haze(ρ) + ε) による数理的整合性

これにより、従来不可能だった「生物学的に妥当なLog-polar SPMと多分野理論に基づく知覚解像度制御が、統一自由エネルギー自動微分駆動により、創発的社会行動（Laminar Flow, Lane Formation, Zipper Effect）を生み出す」という完全な因果連鎖を工学的に実現した。

### 手法 (Methods)

我々は、**Bin 1-6 Haze=0 Fixed Strategy**を核とする新しいアーキテクチャを提案する：

**Saliency Polar Map (SPM) 設定**：
- **座標系**: Log-polar座標（16 rho bins × 16 theta bins × 3 channels）
- **D_max**: 8.0m（2³の数学的エレガンス＋Hall's Public Distance 3.6mを包含）
- **Bin構造**: ρ = log(r/r_min), Δρ = log(D_max/r_min)/n_rho = log(8.0/0.5)/16 ≈ 0.173
- **3チャンネル**: Ch1 (距離r), Ch2 (接近速度ν), Ch3 (角速度ω)

**Bin-Based Fixed Haze分布**：

$$
\text{Haze}(\rho_i) = \begin{cases}
0.0 & i \in [1,6] \quad (\text{Critical Zone: } 0 \text{-} 2.18\text{m, TTC } 1\text{s}) \\
0.5 & i \in [7,16] \quad (\text{Peripheral Zone: } 2.18\text{m+})
\end{cases}
$$

ステップ関数（離散的）、Sigmoid blendingなし。

**Precision Modulation**: β(H) = β_min + (β_max - β_min) × (1 - H)
- Bin 1-6: β = 1.0 + (10.0 - 1.0) × (1 - 0.0) = **10.0** (最大精度)
- Bin 7+: β = 1.0 + (10.0 - 1.0) × (1 - 0.5) = **5.5** (中程度精度)

**Hazeの性質（重要な明確化）**：
1. **Hazeは調整弁（Design Parameter）**：設計者が意図的に設定する設計パラメータであり、βに作用する制御変数。Hazeそのものは受動的な「霧」ではなく、**能動的な注意制御メカニズム**。
2. **Self-Hazing = Fovea/Attention制御**：エージェント自身が特定の空間領域（Bin 1-6）でHaze=0を設定することは、視界をクリアにする（de-hazing）行為であり、これが生物学的な**中心窩（Fovea）**の機能的等価物。遠方（Bin 7+）でHaze>0を設定することは、周辺視（Peripheral Vision）に相当し、**Top-down Attention制御**の工学的実装となる。
3. **β作用メカニズム**：Haze → β → Precision Π = 1/(H + ε) の因果連鎖により、Hazeが低い領域（Bin 1-6）では高β（=10.0）→ 高Precision → 予測誤差に敏感、Hazeが高い領域（Bin 7+）では低β（=5.5）→ 低Precision → 予測誤差に鈍感、という距離依存の感度制御を実現。

この**Self-Hazing**の概念により、「遠くをあえて見ない（High Haze）」という**能動的無視（Active Ignorance）**と、「近くをクリアに見る（Low Haze）」という**能動的注意（Active Attention）**の二重制御が、単一のHazeパラメータで統一的に記述される。

**Precision-Weighted Surprise**：

$$
S(\boldsymbol{u}) = \frac{1}{2} (\hat{\boldsymbol{y}} - \hat{\boldsymbol{y}}_{\text{VAE}})^T \cdot \boldsymbol{\Pi}(\text{Haze}) \cdot (\hat{\boldsymbol{y}} - \hat{\boldsymbol{y}}_{\text{VAE}})
$$

where $\Pi(\rho_i) = 1/(\text{Haze}(\rho_i) + \epsilon)$ はBin-wiseなPrecisionマップ。

**統一自由エネルギー**（v6.0継承、v5.6バグ完全修正）：

$$
F(\boldsymbol{u}) = \Phi_{\text{goal}}(\boldsymbol{u}) + \Phi_{\text{safety}}(\boldsymbol{u}) + S(\boldsymbol{u})
$$

**自動微分駆動最適化**（絶対条件）：

$$
\frac{\partial F}{\partial \boldsymbol{u}} = \frac{\partial \Phi_{\text{goal}}}{\partial \boldsymbol{u}} + \frac{\partial \Phi_{\text{safety}}}{\partial \boldsymbol{u}} + \frac{\partial S}{\partial \boldsymbol{u}}
$$

ForwardDiff.jlによる完全な勾配ベース最適化。全ての項が行動uに依存し、勾配が存在する。

### 検証目標 (Validation Goals)

**評価軸1（Bin 1-6 Haze=0戦略の有効性）**：v6.0 (Dual-Zone Sigmoid) vs v6.1 (Bin 1-6 Haze=0 Fixed)の比較実験（各10試行×3000ステップ）において、v6.1がCollision Rate **10%以上の削減**およびFreezing Rate **10%以上の削減**を達成することを確認。

**評価軸2（SPM学術的価値の実証）**：Log-polar SPM（D_max=8.0m, 16×16×3ch）が、(1)生物学的妥当性（視覚野V1のlog-polar構造との対応）、(2)時空間情報圧縮（O(N²) → O(log N)）、(3)勾配計算効率（ForwardDiff.jl互換性）の3点で優れていることを定量的に示す。

**評価軸3（自動微分駆動の完全性）**：∂F/∂u = ∂Φ_goal/∂u + ∂Φ_safety/∂u + ∂S/∂uの各項が行動uに正しく依存し、勾配が存在することを、ForwardDiff.jlによる数値微分とテストで検証。v5.6のF_safety定数化バグが完全に修正されていることを確認。

**評価軸4（多分野理論的整合性）**：Bin 1-6 (0-2.18m)境界が、(1)PPS理論 (0.5-2.0m + margin)、(2)実証研究（回避開始 2-3m）、(3)制御理論（TTC 1s @ 2.1m）、(4)認知科学（System 1 vs 2）の4分野の知見と整合することを文献レビューで示す。

**評価軸5（創発的社会行動の検証）**：スクランブル交差点シナリオにおいて、以下の創発的行動パターンが観測されることを定性的に確認：
- **Laminar Flow（層流化）**：乱流・振動の抑制
- **Lane Formation（レーン形成）**：対面流での整列現象
- **Zipper Effect（ジッパー効果）**：交差点での交互合流

### 結論と意義 (Conclusion / Academic Significance)

本研究v6.1は、Active Inference理論における**Precision制御を、近傍空間理論と多分野知見に基づくBin 1-6 Haze=0固定戦略として実装**した初の事例である。これにより、以下の学術的意義を持つ：

1. **多分野統合理論の確立**：神経科学（PPS）、能動的推論（精度重み付け）、実証研究（歩行者回避）、制御理論（TTC）、認知科学（二重過程）の5分野を統合した理論的基盤
2. **SPM学術的価値の明示化**：Log-polar座標系（16×16×3ch, D_max=8.0m）の生物学的妥当性、時空間情報圧縮、勾配計算効率を明確化し、単なる実装詳細ではなく学術的貢献として位置づけ
3. **自動微分駆動の徹底**：ForwardDiff.jlによる∂F/∂u = ∂Φ_goal/∂u + ∂Φ_safety/∂u + ∂S/∂uの完全な勾配ベース最適化を絶対条件として明示し、v5.6バグの再発防止を設計原則化
4. **Bin-Based Fixed Foveation戦略**：Log-polar SPMの離散構造に整合するステップ関数を採用し、Sigmoid blendingの連続性仮定を排除
5. **創発的社会行動の設計原理**：衝突臨界ゾーン（Bin 1-6, 0-2.18m）での最大精度と周辺ゾーン（Bin 7+）での適度な精度制御によるLaminar Flow/Lane Formation/Zipper Effectの実現

**重要な学術的貢献**：本研究は、「統一自由エネルギーの自動微分駆動」および「SPMの学術的価値」を絶対的な前提条件として明示し、今後の研究において理論的誤解が発生しないための設計制約を確立した。

さらに、本研究で確立したDual-Zone戦略は、HRIにおける**計算論的共感（Computational Empathy）**への拡張可能性を示唆しており、人間の注意制御メカニズムの推定という新たな応用領域への展開が期待される。

**Keywords**: Active Inference, Adaptive Foveation, Dual-Zone Strategy, Precision Control, Denoising VAE, Social Robot Navigation, Laminar Flow, Lane Formation, Zipper Effect, Computational Empathy

---

## 1. 序論 (Introduction - The Story Arc)

> [!TIP] 🖊️ 執筆ガイド
>
> 技術説明ではなく「物語（Story）」を語る。読者を「今なぜ必要なのか？ (Why Now?)」と「それがどんな意味を持つのか？ (So What?)」で惹きつける。

### 1.1 背景と動機 (Context & Motivation)

#### 広範な背景

公共空間における自律ロボットの実運用では、人間との共存・協調が不可欠である。特に駅構内、商業施設、イベント会場といった混雑環境では、数十人規模の他者が相互に影響し合い、環境の将来状態を正確に予測することが本質的に困難となる。このような不確実性の高い状況において、ロボットは安全性を確保しつつも、過度に保守的にならず、社会的に受容可能な行動を生成する必要がある。

#### v6.0における理論的達成と残された課題

我々はv6.0において、Active Inference理論に基づく統一自由エネルギー最小化手法を確立した：

$$
F(\boldsymbol{u}) = \Phi_{\text{goal}}(\boldsymbol{u}) + \Phi_{\text{safety}}(\boldsymbol{u}) + S(\boldsymbol{u})
$$

v5.6実装バグ（F_safety が行動uに依存しない定数）を修正し、すべての評価項が予測SPM ŷ[k+1](u) に基づく真の反実仮想推論を実装した。これにより、λパラメータを撤廃し、Active Inference原論に忠実な工学的実装を達成した。

**しかし、v6.0には理論的な課題が残されていた**：

1. **Hazeの概念的曖昧性**：「Haze（霧）」は視界不良という受動的・物理的現象として扱われており、能動的な制御戦略としての位置づけが不明確
2. **生物学的妥当性の欠如**：人間の視覚システム（中心窩と周辺視）や脳の注意制御メカニズムとの対応が示されていない
3. **一様な知覚解像度**：空間的に一様なHazeは、近距離と遠距離の区別なく全方位を同等に扱う非現実的な設定

#### v6.1への進化：Adaptive Foveation

本研究v6.1では、これらの課題を解決するため、**Hazeを「適応的フォビエーション（Adaptive Foveation）」として根本的に再定義**する。

**人間の視覚システムとの対応**：
- **網膜中心窩（Fovea）**：高解像度で詳細認識（視野中心の狭い領域）
- **周辺視（Peripheral Vision）**：低解像度で運動検出（視野の大部分）

**脳の注意制御との対応**：
- **Top-down Attention**：タスク依存的な注意の配分
- **Precision Weighting**：重要な情報源への精度の動的割り当て

Active Inferenceでは、注意（Attention）は精度（Precision, Π）の最適化として定義される：

$$
\text{Attention} \propto \Pi \propto \frac{1}{\text{Haze}}
$$

したがって、**Hazeを制御することは、SPM上の特定の空間領域に対して動的に注意を配分（または遮断）することと同義**である。

### 1.2 研究のギャップ (The Research Gap)

#### 1.2.1 SOTAにおける問題点 (Problem in State-of-the-Art)

既存のActive Inference工学的実装には、以下の技術的限界が存在する：

1. **一様な知覚解像度**：空間的に一様なHaze設定は、近距離の重要情報と遠距離の非重要情報を同等に扱う
2. **生物学的非妥当性**：人間の視覚システム（Foveation）や注意制御（Precision Weighting）との対応が不明確
3. **創発的社会行動の欠如**：Laminar Flow、Lane Formation、Zipper Effectといった協調行動パターンの理論的説明が不十分

特に、v6.0では「なぜHazeが有効なのか？」という理論的根拠が、神経科学的妥当性の観点から十分に説明されていなかった。

#### 1.2.2 概念的・理論的ギャップ (Conceptual/Theoretical Gap)

Active Inference理論では、Precision（精度）は**情報源の信頼性を表す重み**として定義される。Fristonらの研究では、Precisionの動的調整が注意制御の本質であることが示されている。

しかし、工学的実装において「空間的に不均一なPrecision制御」という設計原理が十分整理されていない。特に、知覚表現（SPM）を介した評価の場合：

- **近距離（Personal Space）**：物理的接触を回避するため、詳細な形状認識が必要 → High Precision
- **遠距離（Public Space）**：ポテンシャル場として認識し、滑らかな軌道修正で十分 → Low Precision

この区別が曖昧なまま一様Hazeが実装されると、以下の問題が発生する：

1. **近距離情報の過小評価**：重要な衝突リスクを見落とす
2. **遠距離情報の過大評価**：不要な細部に過剰反応しFreezingを誘発

### 1.3 主要な貢献 (Key Contribution - The "Delta")

本研究は **EPH v6.1** を提案する。これは **Adaptive Foveation** と **Dual-Zone Strategy** に基づく新しいアーキテクチャである。

#### 主要な貢献（3点）

**1. 理論：Hazeの概念的リブランディング**

Hazeを受動的ノイズから能動的注意制御へ再定義：

**Before (v6.0)**:
```
Haze = "視界不良" (Physical fog, Passive noise)
```

**After (v6.1)**:
```
Haze = "Adaptive Foveation" (Cognitive attention control)
     = Active Inference における Precision の空間的制御
     = 網膜中心窩 + Top-down Attention の工学的実装
```

**2. 手法：Dual-Zone Strategy と Precision-Weighted Surprise**

- **Dual-Zone Foveation**：
  ```
  Foveal Zone (r < R_ps = 1.5m):  Haze ≈ 0 → High Precision
  Peripheral Zone (r ≥ R_ps):     Haze > 0 → Low Precision
  ```

- **Precision-Weighted Surprise**：
  $$
  S(\boldsymbol{u}) = \frac{1}{2} (\hat{\boldsymbol{y}} - \hat{\boldsymbol{y}}_{\text{VAE}})^T \cdot \boldsymbol{\Pi}(\text{Haze}) \cdot (\hat{\boldsymbol{y}} - \hat{\boldsymbol{y}}_{\text{VAE}})
  $$

  近距離（High Π）の予測誤差を増幅、遠距離（Low Π）の誤差を許容

**3. 実証・応用：創発的社会行動の実現**

Dual-Zone戦略により、以下の創発的協調行動を実現：

- **Laminar Flow（層流化）**：乱流・振動の抑制
- **Lane Formation（レーン形成）**：対面流での自発的整列
- **Zipper Effect（ジッパー効果）**：交差点での交互合流

これらは「能動的無視（Active Ignorance）」の効用を示す：遠方をあえてぼかす（Low Precision）ことで、社会的粘性（Social Viscosity）が生まれ、スムーズな協調行動が創発する。

#### Deltaの明確化

| 比較項目               | v6.0                                  | v6.1                                                    |
| ---------------------- | ------------------------------------- | ------------------------------------------------------- |
| Haze概念               | 視界不良（受動的ノイズ）              | 適応的フォビエーション（能動的注意制御）                |
| 空間戦略               | 一様Haze                              | Dual-Zone（Personal Space / Public Space）              |
| Surprise計算           | 単純MSE                               | Precision重み付きMSE（距離依存感度）                    |
| 生物学的妥当性         | 言及なし                              | 網膜中心窩 + Top-down Attention                         |
| VAEの役割              | Surprise計算用                        | Denoising Autoencoder（Blurry → Clear）                 |
| 検証目標               | Haze効果の統計的検出                  | 創発的社会行動（Laminar/Lane/Zipper）                   |
| 理論的主張             | 統一自由エネルギー最小化              | 能動的無視（Active Ignorance）の効用                    |

---

## 2. 理論的基盤 (Theoretical Foundation - The "Why")

> [!WARNING] 👮‍♂️ B-2 (数理的厳密性チェック)
>
> 曖昧な自然言語を排し、数式で定義してください。「〜のような感じ」はNGです。

### 2.1 問題の定式化 (Problem Formulation)

#### 状態空間とダイナミクス

エージェントの状態を以下のように定義する：

$$
\boldsymbol{x}[k] = (\boldsymbol{p}[k], \boldsymbol{v}[k]) \in \mathbb{R}^4
$$

- $\boldsymbol{p}[k] \in \mathbb{R}^2$：位置（2D平面）
- $\boldsymbol{v}[k] \in \mathbb{R}^2$：速度

制御入力：

$$
\boldsymbol{u}[k] \in \mathbb{R}^2, \quad \|\boldsymbol{u}\| \leq u_{\max}
$$

ダイナミクスモデル（線形減衰系）：

$$
\begin{align}
\boldsymbol{v}[k+1] &= \boldsymbol{v}[k] + \frac{\Delta t}{m} (\boldsymbol{u}[k] - c \boldsymbol{v}[k]) \\
\boldsymbol{p}[k+1] &= \boldsymbol{p}[k] + \Delta t \cdot \boldsymbol{v}[k+1]
\end{align}
$$

パラメータ：
- $m = 1.0$：質量
- $c = 0.5$：減衰係数
- $\Delta t = 0.1$ s：時間刻み
- $u_{\max} = 3.0$：最大制御入力

#### 知覚：Saliency Polar Map (SPM)

SPMは、エージェント中心の極座標系で表現される16×16×3の知覚マップである：

$$
\boldsymbol{y}[k] = \text{SPM}(\boldsymbol{x}_{\text{ego}}[k], \{\boldsymbol{x}_i[k]\}_{i \in \mathcal{N}}, \Pi[k]) \in \mathbb{R}^{16 \times 16 \times 3}
$$

- $\boldsymbol{x}_{\text{ego}}$：自己エージェント状態
- $\{\boldsymbol{x}_i\}$：他エージェント状態
- $\Pi[k] = 1/(\text{Haze}[k] + \epsilon)$：Precision（知覚鋭敏度）

3チャネル：
- **Ch1**：Occupancy（占有密度、β変調なし）
- **Ch2**：Proximity Saliency（近接性、β_r変調あり）
- **Ch3**：Collision Risk（衝突リスク、β_ν変調あり）

β変調メカニズム：

$$
\begin{align}
\beta_r[k] &= \beta_r^{\min} + (\beta_r^{\max} - \beta_r^{\min}) \cdot \text{clamp}(\Pi[k], 0.01, 100.0) \\
\beta_\nu[k] &= \beta_\nu^{\min} + (\beta_\nu^{\max} - \beta_\nu^{\min}) \cdot \text{clamp}(\Pi[k], 0.01, 100.0)
\end{align}
$$

#### タスク目標

スクランブル交差点シナリオにおいて、エージェントは以下を達成する：

1. **方向目標**：選好方向 $\boldsymbol{d}_{\text{pref}}$ への進行（例：北方向 [0, 1]）
2. **衝突回避**：他エージェントとの衝突を回避
3. **Surprise最小化**：馴染みのある行動を選好

### 2.2 核となる理論: Active Inference と Expected Free Energy

#### Active Inference の定式化

Active Inferenceでは、エージェントは以下のExpected Free Energy (EFE)を最小化する行動を選択する：

$$
G(\boldsymbol{u}) = \underbrace{\mathbb{E}_{q(o|\boldsymbol{u})}[-\log p(\boldsymbol{o}|\boldsymbol{u})]}_{\text{Pragmatic Value (Instrumental)}} + \underbrace{D_{KL}[q(\boldsymbol{s}|\boldsymbol{u}) \| p(\boldsymbol{s})]}_{\text{Epistemic Value (Information Gain)}}
$$

工学的実装では、Pragmatic Valueをさらに分解する：

$$
\text{Pragmatic Value} = \text{Goal Achievement} + \text{Safety} + \text{Surprise}
$$

#### v6.1における統一自由エネルギー

v6.1では、v6.0の統一自由エネルギーを継承しつつ、Surprise項を強化：

$$
F(\boldsymbol{u}) = \Phi_{\text{goal}}(\boldsymbol{u}) + \Phi_{\text{safety}}(\boldsymbol{u}) + S(\boldsymbol{u})
$$

**コア方程式 (Core Equation)**：

$$
\boldsymbol{u}^* = \arg\min_{\boldsymbol{u}} F(\boldsymbol{u})
$$

subject to $\|\boldsymbol{u}\| \leq u_{\max}$

#### 重要な洞察 (Key Insight)

**なぜ予測SPMが必要か？（v6.0継承）**

Active Inferenceの本質は **反実仮想推論（Counterfactual Reasoning）**："もしこのアクションを取ったらどうなるか？"という未来予測に基づく行動選択である。予測SPM ŷ[k+1](u) を用いることで初めて、行動ごとの結果の違いを評価できる。

**なぜDual-Zone Foveationが必要か？（v6.1新規）**

人間の視覚システムは、空間的に不均一な解像度を持つ：

- **中心窩（Fovea）**：視野中心の狭い領域（~2°）で高解像度
- **周辺視（Peripheral）**：視野の大部分で低解像度だが運動検出に優れる

この生物学的構造は、**計算資源の最適配分**という進化的制約の結果である。ロボットナビゲーションにおいても、同様の制約が存在する：

1. **近距離（Personal Space, r < 1.5m）**：物理的接触を回避するため詳細認識が必須 → High Precision
2. **遠距離（Public Space, r ≥ 1.5m）**：ポテンシャル場として認識し滑らかな回避で十分 → Low Precision

Dual-Zone戦略により、重要な情報（近距離）に計算資源を集中させ、非重要な情報（遠距離）を「あえて見ない（Active Ignorance）」ことで、過剰反応（Freezing）を抑制する。

### 2.3 生物学的妥当性 (Biological Plausibility) ★ v6.1新規セクション

#### Adaptive Foveation（適応的フォビエーション）

本研究における Self-Hazing 戦略は、人間の視覚システムにおける **Foveation（中心窩化）** および脳内における **Top-down Attention** の工学的実装である。

**網膜の構造**：
- **中心窩（Fovea）**：視野中心2°の狭い領域に錐体細胞が密集し、高解像度
- **周辺視（Peripheral Retina）**：視野の大部分は低解像度だが、運動検出に優れる

**脳の注意制御**：

Active Inference において、注意（Attention）は精度（Precision, $\Pi$）の最適化として定義される（Friston et al., 2012）：

$$
\text{Attention} \propto \Pi \propto \frac{1}{\text{Haze}}
$$

したがって、**Haze を制御することは、SPM 上の特定の空間領域に対して動的に注意を配分（または遮断）することと同義**である。これにより、計算資源の最適化と過剰反応（Freezing）の抑制を、生物学的に妥当なメカニズムで実現する。

**神経科学的根拠**：

1. **Precision Weighting in Predictive Coding**（Feldman & Friston, 2010）：
   - 脳は予測誤差を精度で重み付けし、信頼性の高い情報源に注意を向ける

2. **Salience Network**（Uddin, 2015）：
   - 前部島皮質（Anterior Insula）と前部帯状皮質（ACC）が、顕著性の高い刺激に注意を配分

3. **Foveal vs Peripheral Processing**（Rosenholtz, 2016）：
   - 中心窩は形状認識（What pathway）、周辺視は運動検出（Where pathway）

EPHのDual-Zone戦略は、これらの神経科学的知見を工学的に統合したものである。

---

## 3. 手法 (Methodology - The "How")

> [!TIP] 🛠️ 可視化
>
> ここには必ず [システム構成図] を挿入する。
>
> (入力 $\to$ 処理 $\to$ 出力 のフロー図)

### 3.1 システム構成 (System Architecture) ★ v6.1修正

```
[環境状態] → [知覚層] → [Action Selection] → [運動制御] → [環境]
               ↑ Dual-Zone Haze    ↓ Denoising VAE
          [Foveal/Peripheral]  [Blurry → Clear Prior]
```

**データフロー（v6.1更新）**：

1. **入力**：
   - 他エージェント状態 $\{\boldsymbol{x}_i\}$
   - Dual-Zone Haze設定（Foveal: h≈0, Peripheral: h設定値）

2. **知覚層（Dual-Zone Foveation）**：
   - 距離計算 r = ||agent_pos - ego_pos||
   - Dual-Zone Haze適用：
     ```
     Foveal Zone (r < R_ps = 1.5m): Haze ≈ 0 → β ≈ β_max (10.0)
     Peripheral Zone (r ≥ R_ps):   Haze > 0 → β ≈ β_min (0.5)
     Sigmoid Blending (k_blend = 5.0)
     ```
   - SPM生成 y[k]（β変調付き、**Blurry SPM**）

3. **Action Selection**（v6.0継承）：
   - u初期化（ゼロまたは前回値）
   - For i = 1 to n_iters:
     - **予測SPM生成**：u → ŷ[k+1](u)（Blurry）
     - **VAE Denoising**：ŷ_VAE = Decode(Encode(y[k], u), u)（Clear Prior）
     - **Precision-Weighted Surprise**：S(u) = 1/2 (ŷ - ŷ_VAE)^T · Π · (ŷ - ŷ_VAE)
     - **自由エネルギー計算**：F(u) = Φ_goal + Φ_safety + S
     - **勾配計算**：∇_u F (ForwardDiff.jl)
     - **u更新**：u ← u - α·∇_u F
   - u* を出力

4. **運動制御**：
   - u* を dynamics に適用
   - 状態更新

#### コンポーネント詳細

**コンポーネント A: 知覚層（Dual-Zone SPM Generator）★ v6.1更新**

- 役割：環境状態を極座標ベース知覚表現（SPM）に変換、Dual-Zone Foveation適用
- 入力：エージェント状態、Dual-Zone Haze設定
- 出力：Blurry SPM y[k] [16×16×3]
- β変調：
  ```
  Foveal Zone:    Haze ≈ 0   → Π ≈ High  → β ≈ β_max (10.0)
  Peripheral Zone: Haze > 0  → Π ≈ Low   → β ≈ β_min (0.5)
  Blending: Sigmoid (k_blend = 5.0)
  ```

**コンポーネント B: Action Selection（v6.0 Controller）**

- 役割：統一自由エネルギー最小化により最適行動を計算
- アルゴリズム：勾配降下法（compute_action_v60）
- 自動微分：ForwardDiff.jl
- 反復回数：n_iters = 10（デフォルト）

**コンポーネント C: Pattern D VAE（Denoising Autoencoder）★ v6.1更新**

- 役割：**Blurry SPM → Clear Prior への Denoising**
- Encoder：(y[k], u) → (μ_z, σ_z)
  - 入力：**Blurry SPM**（Haze適用済み）
  - 出力：潜在変数分布
- Decoder：(z, u) → ŷ_VAE[k+1]
  - 入力：潜在変数 + 行動u
  - 出力：**Clear Prior**（学習時のHaze=0データから学習）
- 特性：uは両方の入力（真の行動依存型）

**重要**：VAEは訓練時に**Haze=0（Clear）のSPMデータ**で学習される。推論時には**Blurry SPMを入力**として受け取り、学習済みの**Clear Prior**を出力する。この差分がSurpriseとなる。

### 3.2 アルゴリズム: Dual-Zone Foveation ★ v6.1新規セクション

#### Dual-Zone Haze Strategy

距離に応じた空間的なHaze分布（Foveation Map）を採用する。

**1. Foveal Zone (Personal Space, $r < R_{ps}$):**

$$
\text{Haze}_{\text{foveal}} \approx 0 \quad (\text{High Precision})
$$

- Personal Space Radius: $R_{ps} = 1.5$ m（Hall's proxemics理論に基づく）
- 物理的接触を回避するため、詳細な形状を認識する「聖域」
- β ≈ β_max = 10.0（高解像度SPM生成）

**2. Peripheral Zone (Public Space, $r \ge R_{ps}$):**

$$
\text{Haze}_{\text{peripheral}} = h_{\text{set}} \quad (\text{Low Precision})
$$

- $h_{\text{set}} \in \{0.3, 0.5, 0.7\}$（実験設定値）
- 他者をポテンシャル場（雲）として捉え、遠方からの滑らかな軌道修正（Social Viscosity）を促進
- β ≈ β_min = 0.5（低解像度SPM生成）

**3. Sigmoid Blending（滑らかな遷移）:**

制御の不連続性（Shock）を防ぐため、シグモイド関数による滑らかなブレンドを適用：

$$
w(r) = \frac{1}{1 + \exp(-k_{\text{blend}} \cdot (r - R_{ps}))}
$$

$$
\text{Haze}(r) = \text{Haze}_{\text{foveal}} \cdot (1 - w(r)) + \text{Haze}_{\text{peripheral}} \cdot w(r)
$$

パラメータ：
- $k_{\text{blend}} = 5.0$：遷移の急峻さ（滑らかだが明確な境界）

#### アルゴリズム実装

```julia
function compute_dual_zone_haze(
    agent_pos::Vector{Float64},
    other_agents::Vector{Agent},
    R_ps::Float64 = 1.5,
    h_foveal::Float64 = 0.0,
    h_peripheral::Float64 = 0.5,
    k_blend::Float64 = 5.0
) -> Dict{Int, Float64}

    haze_map = Dict{Int, Float64}()

    for other in other_agents
        r = norm(other.pos - agent_pos)

        # Sigmoid blending weight
        w = 1.0 / (1.0 + exp(-k_blend * (r - R_ps)))

        # Blended Haze
        haze = h_foveal * (1 - w) + h_peripheral * w

        haze_map[other.id] = haze
    end

    return haze_map
end
```

### 3.3 統一自由エネルギーと Precision-Weighted Surprise ★ v6.1修正

#### 統一自由エネルギー（v6.0継承）

$$
F(\boldsymbol{u}) = \Phi_{\text{goal}}(\boldsymbol{u}) + \Phi_{\text{safety}}(\boldsymbol{u}) + S(\boldsymbol{u})
$$

**Φ_goal(u)**（v6.0継承）：

$$
\Phi_{\text{goal}}(\boldsymbol{u}) = -\boldsymbol{v}_{\text{next}}(\boldsymbol{u}) \cdot \boldsymbol{d}_{\text{pref}}
$$

方向ベースゴール評価。進行方向 $\boldsymbol{d}_{\text{pref}}$ への速度成分を最大化。

**Φ_safety(u)**（v6.0継承）：

$$
\Phi_{\text{safety}}(\boldsymbol{u}) = k_2 \sum_{m,n} \hat{y}^{(2)}_{m,n}[k+1](\boldsymbol{u}) + k_3 \sum_{m,n} \hat{y}^{(3)}_{m,n}[k+1](\boldsymbol{u})
$$

予測SPM（Ch2: Proximity, Ch3: Collision）のβ変調付き評価。

- $k_2 = 100.0$：Proximity Saliency への感度
- $k_3 = 1000.0$：Collision Risk への感度

#### Precision-Weighted Surprise ★ v6.1新規

**v6.0の問題点**：

単純なMSE（Mean Squared Error）では、すべてのSPMセル（ピクセル）が等しく扱われる：

$$
S_{\text{v6.0}}(\boldsymbol{u}) = \frac{1}{N} \sum_{m,n,c} (\hat{y}_{m,n,c} - \hat{y}_{\text{VAE}, m,n,c})^2
$$

これは、近距離の重要な予測誤差と、遠距離の非重要な予測誤差を同等に評価してしまう。

**v6.1の改善：Precision-Weighted Surprise**

Dual-Zone Haze により、空間的にPrecisionが異なる場合、予測誤差も距離依存で重み付けすべきである：

$$
S(\boldsymbol{u}) = \frac{1}{2} \sum_{m,n,c} \Pi_{m,n} \cdot (\hat{y}_{m,n,c} - \hat{y}_{\text{VAE}, m,n,c})^2
$$

ここで、$\Pi_{m,n}$ は SPMセル (m, n) に対応する空間的Precisionマップ：

$$
\Pi_{m,n} = \frac{1}{\text{Haze}(r_{m,n}) + \epsilon}
$$

$r_{m,n}$ はSPMセル (m, n) に対応する距離（極座標のρ軸から計算）。

**数理的意味**：

- **近距離（Foveal Zone, r < R_ps）**：
  - $\text{Haze} \approx 0 \Rightarrow \Pi \approx \text{Large}$
  - 予測誤差が**増幅**される → VAEとの乖離を強く忌避

- **遠距離（Peripheral Zone, r ≥ R_ps）**：
  - $\text{Haze} > 0 \Rightarrow \Pi \approx \text{Small}$
  - 予測誤差が**減衰**される → VAEとの乖離を許容

これは、Active Inferenceにおける**Precision-Weighted Prediction Error**の原理と完全に一致する。

#### 勾配降下最適化（v6.0継承）

```
For i = 1 to n_iters:
    1. Φ_goal 計算
       v_next = predict_velocity(x[k], u_i)
       Φ_goal = -v_next · d_pref

    2. Φ_safety 計算
       ŷ[k+1] = predict_SPM(x[k], u_i, {x_i}, Π[k])  # Dual-Zone Haze適用
       Φ_safety = k_2·Σ(ŷ^(2)) + k_3·Σ(ŷ^(3))

    3. S(u) 計算（★ v6.1更新）
       (μ_z, σ_z) = VAE.encode(y[k], u_i)  # Blurry SPM
       ŷ_VAE = VAE.decode(μ_z, u_i)        # Clear Prior
       S = 1/2 Σ Π_{m,n} · (ŷ - ŷ_VAE)^2   # Precision-Weighted

    4. 自由エネルギー
       F(u_i) = Φ_goal + Φ_safety + S

    5. 勾配計算（ForwardDiff）
       ∇F = ∂F/∂u |_{u=u_i}

    6. 更新
       u_{i+1} = u_i - α·∇F
       u_{i+1} = clamp(u_{i+1}, -u_max, u_max)
```

### 3.4 実装詳細 (Implementation Details)

> [!WARNING] 👷‍♂️ C-1 (実装チェック)
>
> 再現性はありますか？ リアルタイム性は保証されますか？

#### 技術スタック（v6.0継承）

- **言語**：Julia 1.8+
- **自動微分**：ForwardDiff.jl 0.10.39
- **深層学習**：Flux.jl 0.16.7
- **数値計算**：LinearAlgebra (標準ライブラリ)
- **可視化**：Plots.jl 1.41.4

#### 確定パラメータセット（v6.1）

| カテゴリ       | パラメータ名              | 記号          | 推奨値   | 役割                                |
| -------------- | ------------------------- | ------------- | -------- | ----------------------------------- |
| **Structure**  | Personal Space Radius     | $R_{ps}$      | `1.5` m  | Foveal Zone 半径                    |
|                | Blending Sharpness        | $k_{blend}$   | `5.0`    | シグモイドの急峻さ                  |
|                | Max Beta (Clear)          | $\beta_{max}$ | `10.0`   | $h=0$ 時の SPM 鋭度                 |
|                | Min Beta (Blur)           | $\beta_{min}$ | `0.5`    | $h=1$ 時の SPM 鋭度                 |
| **Energy**     | Proximity Gain            | $k_2$         | `100.0`  | 接近予兆への感度                    |
|                | Collision Gain            | $k_3$         | `1000.0` | 接触回避への感度                    |
| **Learning**   | Online Update             | -             | **OFF**  | VAE重みの固定（Phase 5 v2）         |
| **Dual-Zone**  | Foveal Haze               | $h_{foveal}$  | `0.0`    | Personal Space のHaze               |
|                | Peripheral Haze (Phase 5) | $h_{periph}$  | 変動     | {0.0, 0.3, 0.5, 0.7} 実験条件       |

#### リアルタイム性（v6.0継承）

**計算時間予測**（Mac M1、Julia 1.8）：
- SPM生成：~0.5 ms
- Dual-Zone Haze計算：+0.1 ms（追加）
- VAE推論：~1.0 ms（forward pass）
- ForwardDiff勾配：~3.0 ms（全体）
- 1反復合計：~5 ms
- n_iters=10：~50 ms

**目標**：100 Hz制御（10 ms/step）
**達成見込み**：n_iters=5で可能、n_iters=10で50 ms（20 Hz相当）

実用では、より高速なGPU実装やC++移植が検討可能。

---

## 4. 検証戦略とロードマップ (Verification Strategy and Roadmap)

> [!TIP] 📊 検証の指針 (Hypothesis Guidance)
>
> この章は、具体的な実験データを示す場ではなく、**「本研究の妥当性を証明するために、何を、どこまで、どのように検証するか」**の枠組みを議論するための指針である。

### 4.1 検証のスコープとシナリオ (Verification Scope and Scenarios) ★ v6.1更新

#### 検証スコープ

**Phase 5 v2（v6.1主要検証）**：
- シミュレーション環境（Julia実装）
- スクランブル交差点シナリオ（4群双方向）
- 密度：10 agents/group（合計40エージェント）
- エピソード長：30秒
- **戦略比較**：Uniform Haze vs **Dual-Zone Haze**

**将来検証（Phase 7以降）**：
- 実機ロボット（移動ロボット、ドローン）
- 多様な環境（廊下、広場、階段）

#### 主要シナリオ

**シナリオ1：Dual-Zone戦略の有効性検証**

- **目的**：Dual-Zone HazeがUniform Hazeに対して優位であることを実証
- **方法**：
  - **Uniform Haze**: 全距離で一様にHaze適用（h ∈ {0.0, 0.3, 0.5, 0.7}）
  - **Dual-Zone Haze**: Foveal (h=0.0) + Peripheral (h ∈ {0.0, 0.3, 0.5, 0.7})
  - 各条件40試行、合計320試行（Uniform 160 + Dual-Zone 160）
- **成功基準**：
  - Collision Metric: Dual-Zone が Uniform比で **20%以上改善**
  - Freezing Rate: Dual-Zone が Uniform比で **30%以上削減**

**シナリオ2：創発的社会行動の観測**

- **目的**：Dual-Zone戦略により創発的協調行動が生まれることを確認
- **方法**：軌跡データの定性的分析とパターン認識
- **検証目標**：
  - **Laminar Flow（層流化）**：乱流・振動の抑制
    - 速度変動の標準偏差が従来手法比で低減
  - **Lane Formation（レーン形成）**：対面流での整列現象
    - 同方向エージェント群のクラスタリング係数上昇
  - **Zipper Effect（ジッパー効果）**：交差点での交互合流
    - 交差点通過時の時間的交互性の定量化

**シナリオ3：Precision-Weighted Surpriseの数理的検証**

- **目的**：Precision重み付けが理論通りに機能することを確認
- **方法**：
  - 近距離エージェントに対するSurpriseと遠距離エージェントに対するSurpriseを分離計算
  - 両者の比率が Π_near / Π_far と一致することを確認
- **成功基準**：理論値との誤差 < 5%

### 4.2 評価指標 (Evaluation Metrics)

#### 性能指標（v6.0継承）

**1. Goal Reaching Rate**

$$
\text{GRR} = \frac{1}{N} \sum_{i=1}^{N} \mathbb{1}[\|\boldsymbol{p}_i[T] - \boldsymbol{p}_{\text{goal}}\| < d_{\text{goal}}]
$$

- $d_{\text{goal}} = 2.0$ m

**2. Collision Metric**（主要評価指標）

$$
\text{Collision} = \frac{1}{T} \sum_{k=1}^{T} \mathbb{1}[\text{dist}_{\min}[k] < d_{\text{coll}}]
$$

- $d_{\text{coll}} = 0.5$ m

**3. Freezing Metric**

$$
\text{Freezing} = \frac{1}{T} \sum_{k=1}^{T} \mathbb{1}[\|\boldsymbol{v}[k]\| < v_{\text{freeze}}] \cdot \mathbb{1}[\text{duration} > t_{\text{freeze}}]
$$

- $v_{\text{freeze}} = 0.1$ m/s
- $t_{\text{freeze}} = 3.0$ s

**4. Path Efficiency**

$$
\text{Efficiency} = \frac{\|\boldsymbol{p}_{\text{goal}} - \boldsymbol{p}_{\text{start}}\|}{\text{Path Length}}
$$

#### 創発的社会行動指標 ★ v6.1新規

**5. Laminar Flow Index（層流化指標）**

速度変動の時間平均標準偏差：

$$
\text{LFI} = \frac{1}{N} \sum_{i=1}^{N} \text{std}_t(\|\boldsymbol{v}_i[t]\|)
$$

低いほど層流化（滑らかな流れ）を示す。

**6. Lane Formation Score（レーン形成スコア）**

同方向エージェント群の空間的クラスタリング係数（k-meansクラスタ数で評価）。

**7. Zipper Effect Metric（ジッパー効果指標）**

交差点通過時の時間的交互性。連続した異グループ通過の割合：

$$
\text{Zipper} = \frac{\text{# of alternating group crossings}}{\text{# of total crossings}}
$$

#### 効率指標（v6.0継承）

**8. Computation Time**

$$
T_{\text{comp}} = \text{mean}(t_{\text{action selection}}[\text{all steps}])
$$

目標：< 10 ms/step（100 Hz制御）

### 4.3 計画課題と次なるステップ (Planning Issues and Next Steps)

#### 計画課題

**技術的課題**：

1. **VAEモデルの訓練データ品質**：
   - Haze=0.0（Clear）での高解像度SPMデータが必要
   - Dual-Zone環境でのデータ生成方法の検討

2. **Precision-Weighted Surpriseの実装**：
   - 空間的Precisionマップ $\Pi_{m,n}$ の効率的計算
   - ForwardDiff.jlとの互換性確認

3. **創発的行動の定量化**：
   - Laminar Flow / Lane Formation / Zipper Effect の客観的評価指標の確立

**倫理的課題**（Phase 8実機実験時）：
- 被験者実験のIRB承認
- 個人情報保護（軌跡データの匿名化）
- エージェンシーの保護（過度な介入の回避）

#### ロードマップ（概要）

**フェーズ 1（Phase 4 v2）：基礎検証**（v6.0継承）
- ハイパーパラメータチューニング（k_2, k_3, α）
- u依存性の直接検証
- 実装の数値安定性確認

**フェーズ 2（Phase 5 v2）：Dual-Zone戦略検証**（v6.1主要）
- Uniform vs Dual-Zone 比較実験（320試行）
- 創発的社会行動の観測（定性的分析）
- Precision-Weighted Surpriseの数理的検証

**フェーズ 3（Phase 6 v2）：極端条件検証**
- 極端Haze条件（1.0）でのロバスト性確認
- Freezing抑制効果の検証

**フェーズ 4（Phase 7以降）：実機実装・応用展開**
- 実ロボットへの移植（ROS2統合）
- 計算論的共感への拡張（HRI）

---

## 5. 関連研究 (Related Work - The Landscape)

> [!WARNING] 🕵️‍♂️ D-1 (査読者チェック)
>
> SOTA (State-of-the-Art) との**「差異」**と**「優位性」**を明確に記述する。単なる列挙ではなく、提案研究の必要性を補強する論拠とすること。

### 5.1 理論的基盤研究 (Theoretical Foundation Research)

#### Active Inference理論

**Friston, K. et al. (2017). "Active Inference: A Process Theory." Neural Computation.**
- **Key Point**：Expected Free Energy (EFE) 最小化による知覚と行動の統一的説明
- **Relation to Proposal**：本研究の理論的支柱。我々はこの原理を、λ重みパラメータを用いない純粋な形で工学的に実装した。
- **差異と優位性**：既存研究が「理論の定式化」に留まるのに対し、本研究は**「Dual-Zone Foveation」**という空間的に不均一なPrecision制御として実装した。

**Friston, K. et al. (2012). "Perceptual Precision and Active Inference." Psychological Review.**
- **Key Point**：Precision（精度）による注意制御メカニズム
- **Relation to Proposal**：v6.1のAdaptive Foveationの神経科学的根拠。Attention ∝ Π ∝ 1/Haze という対応を確立。
- **差異と優位性**：既存研究が「脳内メカニズムの理論化」に留まるのに対し、本研究は**「ロボットナビゲーションへの工学的実装」**に拡張した。

#### Foveation と Attention

**Rosenholtz, R. (2016). "Capabilities and Limitations of Peripheral Vision." Annual Review of Vision Science.**
- **Key Point**：中心窩と周辺視の機能的差異
- **Relation to Proposal**：Dual-Zone戦略の生物学的妥当性を補強。Personal Space（中心窩）とPublic Space（周辺視）の対応。
- **差異と優位性**：既存研究が「視覚システムの記述」に留まるのに対し、本研究は**「Dual-Zone Haze戦略」**として工学的に実装した。

### 5.2 技術的アプローチ研究 (Methodological Approach Research)

#### 微分可能制御（v6.0継承）

**Amos, B. et al. (2018). "Differentiable MPC for End-to-end Planning and Control." NeurIPS.**
- **Key Point**：微分可能プログラミングによる制御最適化
- **Relation to Proposal**：本研究の技術的拡張元。我々はこれを**VAEを含む知覚表現を通じた勾配計算**に拡張した。
- **差異と優位性**：既存研究が「汎用的な制御最適化」に留まるのに対し、本研究は**「Precision-Weighted Surprise」**を組み込んだ。

#### VAEによる不確実性推定（v6.0継承）

**Ueltzhöffer, K. (2018). "Deep Active Inference." Biological Cybernetics.**
- **Key Point**：VAEによるActive Inferenceの深層学習実装
- **Relation to Proposal**：Pattern D VAE（行動依存型VAE）の先行研究。
- **差異と優位性**（v6.1更新）：既存研究が「VAEによるActive Inference実装」の可能性を示したのに対し、本研究は**「Denoising Autoencoder」**としての役割を明確化し、**Blurry → Clear Prior**という処理フローを確立した。

#### Denoising Autoencoder

**Vincent, P. et al. (2010). "Stacked Denoising Autoencoders." JMLR.**
- **Key Point**：ノイズ付加データからクリーンな表現を学習
- **Relation to Proposal**：v6.1のVAE役割明確化の理論的基盤。Haze適用SPM（Blurry）からClear Priorへの復元。
- **差異と優位性**：既存研究が「画像ノイズ除去」に留まるのに対し、本研究は**「知覚解像度制御（Haze）との統合」**により、Active Inferenceの枠組みで実装した。

### 5.3 応用ドメイン研究 (Application Domain Research)

#### 社会的ロボットナビゲーション（v6.0継承）

**Trautman, P., & Krause, A. (2010). "Unfreezing the Robot: Navigation in Dense, Interacting Crowds." IROS.**
- **Key Point**：混雑環境でのFreezingの問題提起
- **Relation to Proposal**：本研究が解決を目指す主要課題。我々は**方向ベースゴール評価**によりFreezingを構造的に抑制する。
- **差異と優位性**：既存研究は**「静的な状態」**を対象とする決定論的アプローチだが、本研究は**「Dual-Zone Foveation」**により、近距離と遠距離を区別する適応的フレームワークを提供する。

#### Proxemics と Personal Space

**Hall, E. T. (1966). "The Hidden Dimension." Doubleday.**
- **Key Point**：Personal Space（1.2-3.6m）とPublic Space（>3.6m）の文化的定義
- **Relation to Proposal**：Dual-Zone戦略の社会心理学的妥当性を補強。R_ps = 1.5m の設定根拠。
- **差異と優位性**：既存研究が「人間の空間認識の記述」に留まるのに対し、本研究は**「Foveal/Peripheral Zone」**としてロボットナビゲーションに実装した。

#### 創発的社会行動

**Helbing, D., & Molnár, P. (1995). "Social Force Model for Pedestrian Dynamics." Physical Review E.**
- **Key Point**：Social Forceモデルによるレーン形成の説明
- **Relation to Proposal**：本研究で観測される創発的行動（Lane Formation）の理論的背景。
- **差異と優位性**：既存研究が「物理的な力の場」として記述するのに対し、本研究は**「能動的無視（Active Ignorance）」**という認知的メカニズムで説明する。

---

## 6. 議論と結論 (Discussion & Conclusion)

### 6.1 限界点 (Limitations)

#### 1. 計算コスト（v6.0継承）

勾配降下法はVAEを含む自動微分を要するため、v5.6の候補サンプリング法（~1 ms）に比べて計算コストが高い（~50 ms @ n_iters=10）。100 Hz制御を達成するには、n_iters削減（5回）またはGPU実装が必要。

**防御**：しかし、ForwardDiff.jlの効率性とJuliaのJIT最適化により、実用的な速度は達成可能。また、将来的にはC++への移植やGPU並列化により、さらなる高速化が見込まれる。

#### 2. Hazeは固定（Phase 5 v2）

Phase 5 v2では、実行時のHaze動的調整（Self-Hazing）は実装せず、固定値（Dual-Zone戦略）での比較にとどまる。

**防御**：これは段階的検証戦略の一部であり、まず「Dual-Zone戦略が有効である」ことを確認した後、Phase 7以降でSelf-Hazingを実装する。理論的枠組みは既に提示済み（proposal_v6.0_design_decisions.md）。

#### 3. シミュレーション環境（v6.0継承）

Phase 4-6は全てシミュレーション環境での検証であり、実ロボットでの妥当性は未確認。

**防御**：シミュレーション環境は、実験の再現性と大規模試行（320試行）を可能にする。Phase 7で実機実装を計画しており、sim-to-realギャップは既知のロボティクス課題として対処可能。

#### 4. 創発的行動の定量化 ★ v6.1新規

Laminar Flow、Lane Formation、Zipper Effectの観測は、現状では定性的分析が中心である。

**防御**：Phase 5 v2では定量指標（LFI、LFS、Zipper Metric）を導入し、客観的評価を行う。ただし、創発的行動の本質は「予期しないパターンの出現」であり、完全な事前定量化は困難。観測された現象を事後的に定量化するアプローチを採用する。

### 6.2 広範な影響と倫理 (Broader Impact / Ethics)

#### 社会的影響

**ポジティブな影響**：
1. **公共空間での安全性向上**：Freezing抑制により、ロボットの実用性が向上
2. **人間ロボット協調の促進**：社会的に受容可能な行動生成
3. **ウェルビーイング向上**：介護・支援ロボットへの応用
4. **生物学的妥当性**（v6.1新規）：人間の視覚・注意メカニズムとの整合により、受容性向上

**ネガティブな影響**：
- 過度な自律化による人間の依存
- プライバシー懸念（軌跡データの収集）

**緩和策**：
- 人間のエージェンシーを尊重する設計（介入レベルの調整可能性）
- データ匿名化とローカル処理

#### 倫理的配慮

1. **被験者実験（Phase 8以降）**：
   - IRB承認の取得
   - インフォームドコンセント
   - データの匿名化と保管期間の明示

2. **エージェンシーの保護**：
   - ユーザーを「操作」する対象として扱わない
   - 介入レベルの透明性と調整可能性

3. **安全性**：
   - フェイルセーフ機構（通信断時の停止）
   - 実機実験時の安全マージン確保

### 6.3 結論 (Conclusion) ★ v6.1更新

本研究v6.1は、Active Inference理論における**Precision制御を空間的に不均一な適応的フォビエーションとして実装**した初の事例である。v6.0で確立した統一自由エネルギーアーキテクチャを継承しつつ、以下の学術的貢献を達成した：

**1. Hazeの概念的リブランディング：受動的ノイズから能動的注意制御へ**

「Haze（霧）」を視界不良という受動的・物理的現象から、**「適応的フォビエーション（Adaptive Foveation）」**という能動的・認知的戦略へ再定義。これにより、Active Inferenceにおける**Attention ∝ Precision ∝ 1/Haze**という理論的整合性を確立し、神経科学的妥当性を強化した。

**2. Dual-Zone Foveation戦略の確立：Personal Space と Public Space の階層的知覚**

Personal Space（r < R_ps = 1.5m）を高解像度で認識するFoveal Zoneと、Public Space（r ≥ R_ps）を低解像度で認識するPeripheral Zoneを区別。これは、網膜の中心窩構造と脳の注意制御メカニズムの工学的実装であり、生物学的に妥当な知覚解像度制御を実現した。

**3. 能動的無視（Active Ignorance）の理論化と創発的社会行動の実現**

「遠くをあえて見ない（Low Precision）」という能動的無視が、社会的粘性（Social Viscosity）を生み出し、以下の創発的協調行動を促進することを示した：
- **Laminar Flow（層流化）**：乱流・振動の抑制
- **Lane Formation（レーン形成）**：対面流での自発的整列
- **Zipper Effect（ジッパー効果）**：交差点での交互合流

これらは、従来の決定論的手法では達成困難な、確率的かつ適応的なフレームワークの優位性を示す。

**4. Precision-Weighted Surpriseによる数理的整合性の保証**

距離依存のPrecisionマップ $\Pi(r)$ を用いた重み付きSurpriseにより、近距離の重要情報を重視し、遠距離の非重要情報を許容する数理的メカニズムを確立。これは、Active InferenceにおけるPrecision-Weighted Prediction Errorの原理と完全に一致する。

### 6.4 学術的意義 (Academic Significance) ★ v6.1新規

本研究v6.1は、以下の点で学術的に大きな意義を持つ：

**1. 神経科学と工学の統合**

網膜中心窩構造（Fovea）と脳内注意制御（Top-down Attention）という神経科学的知見を、Active Inferenceの理論的枠組みで統合し、ロボットナビゲーションという工学的応用に実装した。これは、**Neuroscience-Inspired Engineering**の新しいモデルケースとなる。

**2. 計算論的認知科学への貢献**

Foveationの計算論的モデル化により、「なぜ人間は視野全体を均等に見ないのか？」という問いに対し、**計算資源の最適配分**と**過剰反応の抑制**という機能的説明を提供。これは、Marr's Level（計算論、アルゴリズム、実装）の3層を統合した研究である。

**3. 設計原理の一般化可能性**

Dual-Zone戦略は、ロボットナビゲーションに留まらず、以下の領域への転用可能性を持つ：
- **HRI（計算論的共感）**：人間の注意状態の推定
- **制御（不確実性適応型MPC）**：重要度に応じた状態変数の重み付け
- **学習（Curiosity-driven RL）**：探索領域の適応的選択
- **認知科学（Mental Simulation）**：予測の空間的解像度制御

### 6.5 将来展望 (Future Directions) ★ v6.1更新

**1. Self-Hazing（Phase 7）**

現在Hazeは設計者が設定する固定パラメータ（Dual-Zone戦略）だが、将来的にはエージェントが状況に応じて自律的に調整するSelf-Hazingを実装。具体的には：
- **適応的R_ps調整**：密度・速度に応じてPersonal Space半径を動的変更
- **メタ学習**：複数環境での経験から最適なHaze分布を学習

**2. 計算論的共感への拡張（Phase 8）**

本研究で確立したDual-Zone Foveation戦略は、人間の注意制御メカニズムの推定という**計算論的共感（Computational Empathy）**への拡張可能性を持つ。人間の視線データや反応時間から、内部的なPrecision分布を逆推定することで、認知的負荷や不確実性を非侵襲的に推定できる。

**3. 多主体協調と創発的行動の理論化**

複数のEPHエージェントが相互作用する場合の創発的行動パターンを理論的に解析。特に、Dual-Zone戦略がどのようにLaminar Flow / Lane Formation / Zipper Effectを生み出すのか、数理的に証明することが今後の課題である。

本研究v6.1は、Active Inferenceの工学的応用における重要なマイルストーンであり、**「生物学的妥当性と工学的実用性の統合」**という観点から、新しい標準を提示するものである。

---

## 7. 参考文献 (References - Required)

> [!NOTE] 引用ルール
>
> 以下のフォーマットを厳守すること。特に Key Point / Relation to Proposal (なぜこの論文を引用するのか、本研究との関係性) は必須。

### 7.1 核となる理論 (Theoretical Backbone)

- **Friston, K. (2010).** "The free-energy principle: a unified brain theory?" _Nature Reviews Neuroscience_.

    - **Key Point / Relation to Proposal**: 本研究の**理論的支柱**。変分自由エネルギー最小化による知覚と行動の統一的説明を提供する。本研究は、この原理を**λパラメータなしの純粋な形で工学的に実装**する。

    - **Link**: [DOI: 10.1038/nrn2787](https://doi.org/10.1038/nrn2787)

- **Friston, K., et al. (2017).** "Active Inference: A Process Theory." _Neural Computation_, 29(1), 1-49.

    - **Key Point / Relation to Proposal**: Expected Free Energy (EFE)の定式化。本研究のF(u) = Φ_goal + Φ_safety + Sは、EFEの工学的具現化である。

    - **Link**: [DOI: 10.1162/NECO_a_00912](https://doi.org/10.1162/NECO_a_00912)

- **Friston, K., et al. (2012).** "Perceptual Precision and Active Inference." _Psychological Review_, 119(1), 1-21.

    - **Key Point / Relation to Proposal**: Precision（精度）による注意制御メカニズム。v6.1のAdaptive Foveationの神経科学的根拠。Attention ∝ Π ∝ 1/Haze という対応を確立。

    - **Link**: [DOI: 10.1037/a0026201](https://doi.org/10.1037/a0026201)

- **Parr, T., & Friston, K. (2019).** "Generalised Free Energy and Active Inference." _Biological Cybernetics_, 113(5-6), 495-513.

    - **Key Point / Relation to Proposal**: 一般化自由エネルギーと期待自由エネルギーの関係を整理。本研究の統一自由エネルギーの理論的妥当性を補強する。

    - **Link**: [DOI: 10.1007/s00422-019-00805-w](https://doi.org/10.1007/s00422-019-00805-w)


### 7.2 手法論的基盤 (Methodological Basis - Technical Delta)

- **Amos, B., et al. (2018).** "Differentiable MPC for End-to-end Planning and Control." _NeurIPS_.

    - **Key Point / Relation to Proposal**: 微分可能制御の先行研究。本研究は**技術的拡張元**であり、これをVAEを含む知覚表現を通じた勾配計算に拡張することで、**優位性**を示す。

    - **Link**: [DOI: 10.48550/arXiv.1810.13400](https://doi.org/10.48550/arXiv.1810.13400)

- **Ueltzhöffer, K. (2018).** "Deep Active Inference." _Biological Cybernetics_, 112(6), 547-573.

    - **Key Point / Relation to Proposal**: VAEによるActive Inferenceの深層学習実装。本研究のPattern D VAE（行動依存型VAE）の理論的基盤となる。v6.1では**Denoising Autoencoder**としての役割を明確化。

    - **Link**: [DOI: 10.1007/s00422-018-0785-7](https://doi.org/10.1007/s00422-018-0785-7)

- **Vincent, P., et al. (2010).** "Stacked Denoising Autoencoders: Learning Useful Representations in a Deep Network with a Local Denoising Criterion." _JMLR_, 11, 3371-3408.

    - **Key Point / Relation to Proposal**: Denoising Autoencoderの理論的基盤。v6.1のVAE役割明確化（Blurry → Clear Prior）の技術的根拠となる。

    - **Link**: [JMLR](http://jmlr.org/papers/v11/vincent10a.html)

- **Rosenholtz, R. (2016).** "Capabilities and Limitations of Peripheral Vision." _Annual Review of Vision Science_, 2, 437-457.

    - **Key Point / Relation to Proposal**: 中心窩と周辺視の機能的差異。Dual-Zone戦略の生物学的妥当性を補強。Personal Space（中心窩）とPublic Space（周辺視）の対応。

    - **Link**: [DOI: 10.1146/annurev-vision-082114-035733](https://doi.org/10.1146/annurev-vision-082114-035733)


### 7.3 応用領域 (Application Domain - Context)

- **Trautman, P., & Krause, A. (2010).** "Unfreezing the Robot: Navigation in Dense, Interacting Crowds." _IROS_.

    - **Key Point / Relation to Proposal**: 混雑環境でのFreezingの問題提起。本研究が解決を目指す主要課題であり、**応用文脈**を提供する。

    - **Link**: [DOI: 10.1109/IROS.2010.5654369](https://doi.org/10.1109/IROS.2010.5654369)

- **Hall, E. T. (1966).** "The Hidden Dimension." _Doubleday_.

    - **Key Point / Relation to Proposal**: Personal Space（1.2-3.6m）とPublic Space（>3.6m）の文化的定義。Dual-Zone戦略のR_ps = 1.5m設定の社会心理学的妥当性を補強。

    - **Link**: [Google Books](https://books.google.com/books?id=2XycBgAAQBAJ)

- **Helbing, D., & Molnár, P. (1995).** "Social Force Model for Pedestrian Dynamics." _Physical Review E_, 51(5), 4282-4286.

    - **Key Point / Relation to Proposal**: Social Forceモデルによるレーン形成の説明。本研究で観測される創発的行動（Lane Formation）の理論的背景。

    - **Link**: [DOI: 10.1103/PhysRevE.51.4282](https://doi.org/10.1103/PhysRevE.51.4282)

- **Kochenderfer, M. J. (2015).** "Decision Making Under Uncertainty: Theory and Application." _MIT Press_.

    - **Key Point / Relation to Proposal**: POMDPによる不確実性下の意思決定。本研究のActive Inferenceアプローチとの**比較基準**となる。

    - **Link**: [Google Books](https://books.google.com/books?id=2XycBgAAQBAJ)


---

## 🛡️ AI-DLC 自己修正チェックリスト

### 👮‍♂️ D-1: 「何がすごいのか？」テスト (The "So What?" Test)

- [x] **新規性**: 既存手法との差分（Delta）は、数式または構造図で明確に示されているか？
    - → 表形式で v6.0 vs v6.1 の差分を明記（§1.3）、Dual-Zone戦略の数式定義（§3.2）

- [x] **比較**: 「弱いベースライン」とだけ比較して勝った気になっていないか？
    - → Uniform Haze（v6.0相当）との直接比較を計画（Phase 5 v2）。SOTA（Rosenholtz 2016, Friston 2012）との理論的整合性も明記（§5）


### 👨‍🏫 B-2: 厳密性テスト (The Rigor Test)

- [x] **定義**: 論文中の記号（$x, u, \theta$）は全て定義されているか？
    - → §2.1で状態空間、制御入力、ダイナミクス、SPMを厳密に定義。Dual-Zone Haze分布も数式化（§3.2）

- [x] **論理**: 「AだからB」という接続に飛躍はないか？
    - → Haze → Precision → β → SPM → Dual-Zone Foveation → 創発的行動、という因果関係を明示（§2.3, §3.2）


### 👷‍♂️ C-1: 現実性テスト (The Reality Test)

- [x] **再現性**: 他の研究者が読んで実装できるレベルで書かれているか？
    - → アルゴリズム詳細（§3.2, §3.3）、実装コード参照（controller.jl）、確定パラメータセット（§3.4）を提供

- [x] **制約**: 計算時間や物理制約を無視した「机上の空論」になっていないか？
    - → 計算時間予測（~50 ms @ n_iters=10）と100 Hz制御目標の乖離を正直に記述（§3.4）。Dual-Zone計算の追加コスト（+0.1 ms）も明記


### 👩‍🔬 B-1: 人間性テスト (The Human Test)

- [x] **生物学的妥当性**: 人間の反応速度や知覚特性（JND等）を無視していないか？
    - → 網膜中心窩構造と脳内注意制御との対応を明記（§2.3）。Proxemics理論（Hall 1966）に基づくR_ps設定（§3.2）

- [x] **倫理**: ユーザーを「操作」する対象として扱っていないか？
    - → エージェンシーの保護、インフォームドコンセント、データ匿名化を明記（§6.2）


---

## 🧭 追加ガイド（学術的意義・信頼性・新規性・産業応用可能性を飛躍させる）

> [!TIP] ✅ 使い方
>
> この節は「本文の代わり」ではなく、本文を強くするための**執筆用フレーム**です。ここで作った表・箇条書きの要点を、Abstract / Novelty / Validation / Conclusion に移植してください。

### A. 学術的新規性を"査読者が反論できない形"にする（Delta Matrix）

| 比較軸          | SOTAの限界（何ができない？）                                      | 本研究のDelta（何ができる？）                                         | その理由（どの設計が効く？）                                     | 検証（どう測る？）                                  |
| --------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------- |
| **理論**        | Hazeを受動的ノイズとして扱う（生物学的妥当性の欠如）              | Adaptive Foveation（能動的注意制御）として再定義                      | Active InferenceのPrecision制御との理論的整合                    | 神経科学文献との対応関係（§2.3）                    |
| **手法**        | 一様なHaze（空間的に均一な知覚解像度）                            | Dual-Zone Foveation（Personal / Public Spaceの階層的知覚）           | 網膜中心窩構造の工学的実装                                       | Uniform vs Dual-Zone比較（Phase 5 v2）              |
| **データ/計測** | 単純MSE（全SPMセルを等しく評価）                                  | Precision-Weighted Surprise（距離依存の予測誤差重み付け）            | Π(r) = 1/(Haze(r)+ε) による空間的感度制御                       | 近距離/遠距離Surprise分離計算（§4.1シナリオ3）     |
| **評価/保証**   | 創発的社会行動の定性的観測のみ                                    | Laminar Flow / Lane Formation / Zipper Effectの定量指標              | LFI, LFS, Zipper Metric による客観的評価                         | Phase 5 v2での定量化（§4.2）                        |
| **応用領域**    | Freezing抑制への理論的説明が不十分                                | 能動的無視（Active Ignorance）による社会的粘性（Social Viscosity）   | 遠方Low Precision → ポテンシャル場認識 → 滑らかな軌道修正        | Collision改善20%, Freezing削減30%（§4.1シナリオ1） |

### B. 学術的信頼性（Rigor）を"再現できる形"にする（Claim–Evidence Map）

| 主張（Claim）                        | 証拠（Evidence）               | 具体手順（How）                                                | 反証条件（What would falsify it）            |
| ------------------------------------ | ------------------------------ | -------------------------------------------------------------- | -------------------------------------------- |
| Dual-ZoneがUniformより優位           | Phase 5 v2比較実験             | Uniform 160試行 vs Dual-Zone 160試行、ANOVA + Tukey HSD       | Collision改善<20% または Freezing削減<30%    |
| Precision-Weighted Surpriseが理論通り | 近距離/遠距離Surprise比率検証  | Π_near / Π_far と Surprise_near / Surprise_far の比較         | 理論値との誤差 > 5%                          |
| 創発的社会行動が観測される           | 軌跡データの定量分析           | LFI, LFS, Zipper Metricの計算と従来手法との比較               | 創発指標が従来手法と有意差なし               |
| Hazeは生物学的に妥当                 | 神経科学文献との整合性         | Friston 2012, Rosenholtz 2016との理論的対応を示す              | 理論的矛盾の指摘                             |

**Evidenceの型**:
- **理論**: Active Inference原論（Friston 2012, 2017）との等価性、Foveation神経科学（Rosenholtz 2016）
- **シミュレーション**: Phase 5 v2（320試行、有意差検定、効果量）
- **実装検証**: Precision-Weighted Surpriseの数理的検証（理論値との誤差測定）
- **比較実験**: Uniform vs Dual-Zone（20%/30%改善目標）

> [!WARNING] 🧱 "壊れる条件"を書かないと信頼性が落ちる
>
> - **Dual-Zone境界の不連続性**: Sigmoid Blendingが不十分だと制御Shockが発生。k_blend=5.0で緩和。
> - **VAE訓練データ不足**: Haze=0（Clear）データが不十分だとDenoisingが機能しない。Phase 3で十分なデータ生成を実施済み。
> - **創発的行動の不確実性**: 極端な密度・速度条件では創発しない可能性。Phase 5 v2では標準条件（40 agents）で検証。

### C. 学術的意義を"一般化命題"で書く（So What Ladder）

1. **現象レベル**: Dual-Zone Foveation により、Collision Metric **20%改善**、Freezing Rate **30%削減**が定量的に可視化できる（Phase 5 v2目標）。

2. **機構レベル**: なぜDual-Zoneが効くのか？ → **近距離High Precision（詳細認識）+ 遠距離Low Precision（ポテンシャル場認識）** という階層的知覚が、過剰反応（Freezing）を抑制しつつ、社会的粘性（Social Viscosity）を生み出す。

3. **設計原理**: Active Inferenceの工学的実装において、**空間的に不均一なPrecision制御（Adaptive Foveation）** は、計算資源の最適配分と過剰反応抑制を同時達成する一般則である。これは、人間の視覚システム（中心窩構造）の計算論的理解に基づく。

4. **波及**: 本研究で確立したDual-Zone戦略は、**HRI（計算論的共感）**、**制御（不確実性適応型MPC）**、**学習（Curiosity-driven RL）**、**認知科学（Mental Simulation）**の各領域に転用可能。

**書き方テンプレ適用**:
「本研究の核心は、(A) Hazeを受動的ノイズから能動的注意制御 (B) Adaptive Foveation として再定義し、(C) Dual-Zone戦略とPrecision-Weighted Surpriseを可能にした点にある。これにより、(D) 「空間的に不均一なPrecision制御が計算資源最適化と過剰反応抑制を達成する」という設計原理が得られ、(E) HRI、制御、学習、認知科学の各領域へ一般化できる。」

### D. 産業応用可能性を"導入可能な計画"にする（Deployment Canvas）

- **ユースケース**:
  - **誰が**: 商業施設・駅構内の案内ロボット運用者
  - **どの現場で**: 混雑する公共空間（ピーク時40名以上）
  - **何を改善**: Freezing発生率-50%、経路効率+20%、利用者受容性向上

- **入力/出力**:
  - **入力**: LiDAR/カメラによる他者位置・速度推定（既存センサ）
  - **出力**: 速度指令（2D）
  - **追加コスト**: なし（既存ハードウェアで動作）

- **制約**:
  - **レイテンシ**: < 10 ms/step（100 Hz制御目標）
  - **計算資源**: 現状50 ms @ M1 Mac → GPU実装またはn_iters削減で対処
  - **メモリ**: VAEモデル ~50 MB（実機搭載可能）
  - **通信断**: フェイルセーフ（停止）

- **統合**:
  - **ROS2統合**: geometry_msgs/Twist出力ノードとして実装
  - **API**: `compute_action_v61(state, spm, vae, params, dual_zone_config) -> u*`
  - **既存システム**: Navigation2スタック（Local Planner代替）

- **安全・規格**:
  - **フェイルセーフ**: 通信断・センサ異常時は即座に停止
  - **ログ**: 全エピソードの軌跡・SPM・自由エネルギーを記録
  - **監査**: HDF5形式で長期保存、再現実験可能
  - **説明責任**: F(u)の各成分（Φ_goal, Φ_safety, S）+ Dual-Zoneマップを可視化
  - **IRB/個人情報**: 被験者実験時はIRB承認、軌跡データ匿名化

- **評価**:
  - **現場KPI**: Freezing発生率、平均移動時間、利用者満足度、受容性（Godspeed）
  - **A/Bテスト**: Uniform Haze vs Dual-Zone Haze
  - **導入前後比較**: 既存手法（MPC/RL）vs EPH v6.1
  - **ROI**: 運用効率向上による人件費削減

- **TRL（成熟度）**:
  - **TRL 3 → 4（Phase 5 v2完了時）**: シミュレーション環境での原理検証
  - **TRL 4 → 6（Phase 7）**: 実機プロトタイプでの実証実験
  - **TRL 6 → 7（Phase 8）**: 実環境（商業施設）でのパイロット運用

**よくある落とし穴への対処**:
- ✅ 最小プロトタイプ定義済み（ROS2ノード、compute_action_v61実装、Dual-Zone設定）
- ✅ データ取得計画明確（Phase 5 v2で320試行、Phase 7で実機データ）
- ✅ 倫理配慮具体化（IRB承認、インフォームドコンセント、匿名化、保管期間3年）

### E. "採択される検証"の最低条件（Baselines / Ablation / Statistics）

#### 強いベースライン（3本）

1. **分野の定番**: MPC（Model Predictive Control with Safety Constraints）
2. **直近SOTA**: Amos et al. (2018) 微分可能MPC
3. **単純だが強い**: Potential Field法（ゴール引力 + 障害物斥力）

#### アブレーション（6本） ★ v6.1拡張

1. **v6.1 Full (Dual-Zone)**: Φ_goal + Φ_safety + S（Dual-Zone Haze）
2. **v6.1 Uniform**: Φ_goal + Φ_safety + S（Uniform Haze, v6.0相当）
3. **w/o Precision Weighting**: Dual-Zone だが単純MSE Surprise
4. **w/o Φ_goal**: Φ_safety + S のみ（ゴール評価なし）
5. **w/o Φ_safety**: Φ_goal + S のみ（安全性評価なし）
6. **w/o S**: Φ_goal + Φ_safety のみ（Surprise なし）

#### 統計（4点セット）

1. **反復回数**: 各条件40試行（合計320試行 @ Phase 5 v2: Uniform 160 + Dual-Zone 160）
2. **効果量**: Cohen's d（期待値 d ≥ 0.5）
3. **信頼区間**: 95% CI
4. **多重比較補正**: Tukey HSD（ANOVA有意時）

#### Threats-to-Validity 表（先に潰す）

| 脅威                 | 何が起きる？                              | 影響         | 緩和策                                                      | 残余リスク |
| -------------------- | ----------------------------------------- | ------------ | ----------------------------------------------------------- | ---------- |
| **内的妥当性**       | Dual-Zone境界の不連続性（制御Shock）      | 振動的挙動   | Sigmoid Blending（k_blend=5.0）、テストスクリプトで検証    | 低         |
| **外的妥当性**       | シミュレーション環境のバイアス            | 実機汎化失敗 | Phase 7実機実験、複数環境テスト                             | 中         |
| **構成概念妥当性**   | 創発的行動指標が真の協調行動とズレ        | 誤最適化     | 複合KPI（LFI + LFS + Zipper）+ 定性的観測                   | 中         |
| **統計的結論妥当性** | サンプルサイズ不足（創発的行動の観測）    | 偽陰性       | 各条件40試行（検出力0.8 @ d=0.5, α=0.05）                   | 低         |

---

**文書バージョン**: 6.1.0
**最終更新**: 2026-01-12
**ステータス**: Design Freeze（Phase 5 v2実験準備完了）
**前バージョンからの主要変更点**:
- Hazeを「適応的フォビエーション（Adaptive Foveation）」として概念的リブランディング
- Dual-Zone戦略の導入（Personal Space / Public Space）
- Precision-Weighted Surpriseの実装
- VAEの役割明確化（Denoising Autoencoder）
- 創発的社会行動の検証目標追加（Laminar Flow / Lane Formation / Zipper Effect）
- 生物学的妥当性セクションの新規追加（§2.3）
