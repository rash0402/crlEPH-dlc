---

title: "Emergent Perceptual Haze (EPH)"
type: Research_Proposal
status: "🟢 Active Development"
version: 5.6.0
date_created: "2025-12-18"
date_modified: "2026-01-10"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Free Energy Principle
  - Active Inference
  - Surprise Minimization
  - Social Navigation
  - Uncertainty Modeling
  - Precision Control
  - Swarm Intelligence
  - Perceptual Precision
  - Uncertainty-Adaptive Control
tags:
  - Research/Proposal
  - Topic/FEP
  - Status/Active
changelog:
  - version: 5.6.0
    date: "2026-01-10"
    changes:
      - "Surprise項を自由エネルギーに統合（Active Inference整合性確保）"
      - "Hazeを設計パラメータとして再定義（VAE自動計算から分離）"
      - "VAEの役割を予測+Surprise計算に明確化"
      - "Self-Hazingを将来拡張として追加"
---



# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
>
> 不確実性を **Surprise（予測困難度）** と **Haze（知覚解像度パラメータ）** の二層制御として扱う Active Inference の工学的実装アーキテクチャ **EPH (Emergent Perceptual Haze)** を提案する。本手法は、Surprise最小化による行動選択と、Hazeによる知覚解像度の適応的変調を組み合わせることで、単体ロボットおよび群知能システムにおける停止・振動・分断といった不確実性起因の行動破綻を構造的に抑制する。


## 要旨 (Abstract)

### 背景 (Background)

公共空間や多主体環境における自律ロボットの実運用では、安全性と社会的受容性を両立しつつ、不確実性の高い状況に柔軟に適応する能力が不可欠である。しかし、混雑環境や他者との相互作用が支配的な状況では、他者行動や環境変化の予測困難性が本質的に増大し、従来のモデル予測制御（MPC）や強化学習（RL）に基づく手法は、過度に保守的な回避行動、不安定な振動、さらには行動停止（Freezing）といった不確実性起因の行動破綻を引き起こしやすい。

これらの問題は、不確実性を抑制すべきノイズや誤差としてのみ扱い、行動生成を調停する設計変数として明示的に組み込んでこなかったことに起因する。特に、**Active Inferenceで中心的役割を果たすSurprise（予測困難度）** の最小化が実装されておらず、かつ環境や他者に対する確信度の違いが、知覚や意思決定の「鋭さ」にどのように反映されるべきかという設計原理が、工学的に十分整理されていない。

### 目的 (Objective)

本研究の目的は、自由エネルギー原理（Free Energy Principle; FEP）および Active Inference の理論的枠組みに基づき、以下の二層制御機構を確立することである：

1. **行動層（Action Layer）**: **Surprise** を自由エネルギーの項として明示的に組み込み、予測困難な行動を回避する
2. **知覚層（Perception Layer）**: **Haze** を設計パラメータとして導入し、知覚解像度を適応的に変調する

提案する EPH は、Surpriseによる行動評価と、Hazeによる知覚変調を統合することで、不確実性が高い状況では馴染みのある行動を選択しつつ知覚表現を平均化し、確信度が高い状況では効率的かつ鋭敏な判断を可能とする。

### 学術的新規性 (Academic Novelty)

本研究の学術的新規性は、以下の3点にある：

1. **Active Inferenceの工学的実装**: Surpriseをネットワーク（VAE）の再構成誤差として定量化し、行動選択の目的関数に統合した
2. **知覚解像度の設計原理**: Hazeを設計者が制御可能なパラメータとして導入し、Precision（知覚鋭敏度）の変調を実現した
3. **二層制御アーキテクチャ**: SurpriseとHazeを独立した設計次元として分離し、それぞれの役割を明確化した

さらに、将来拡張として **Self-Hazing（自律的Haze学習）** の理論的枠組みを提示し、設計者制御から自律制御への進化パスを示す。

### 理論的位置づけ

本研究は、FEPの工学的再解釈として位置付けられる。従来の解釈では Precision が予測誤差の信頼性重みとして暗黙的に用いられてきたが、本研究では以下の明確な分離を行う：

- **推論Precision**: 予測誤差項の重み（固定値として扱う）
- **知覚解像度パラメータ β**: Hazeから導出され、SPM生成時の集約の鋭さを制御

この分離により、理論的混乱を回避しつつ、工学的に実装可能な制御構造を確立する。

---

# 1. 序論 (Introduction)

## 1.1 背景 (Background)

公共空間においてロボットが人間と共存しながら活動するためには、安全性のみならず、周囲との調和や社会的受容性を満たす行動生成が求められる。特に駅構内、商業施設、イベント会場といった混雑環境では、他者の行動が相互に影響し合い、環境の将来状態を正確に予測することが本質的に困難となる。

このような状況下において、従来のモデル予測制御（MPC）や強化学習（RL）に基づくナビゲーション手法は、安全性を優先するあまり、過度に保守的な回避行動や、微小な予測誤差に対する過剰反応を示すことがある。その結果として、ロボットがその場で停止してしまう **Freezing**、あるいは前進と回避を繰り返す振動的挙動が発生し、実運用における信頼性を著しく損なう。

Freezing はしばしば「失敗事例」や「チューニング不足」として扱われてきたが、実際には、**不確実性の高い状況において最適な行動選択と知覚の粒度制御が統合されていない**設計そのものに起因する構造的問題であると考えられる。

### Active Inferenceにおける Surprise の役割

自由エネルギー原理（FEP）に基づく Active Inference では、エージェントは **Expected Free Energy (EFE)** を最小化する行動を選択する。EFEは以下のように分解される：

$$
G(\boldsymbol{u}) = \underbrace{\mathbb{E}[-\log p(\boldsymbol{o}|\boldsymbol{s}, \boldsymbol{u})]}_{\text{Surprise (リスク)}} + \underbrace{D_{KL}[q(\boldsymbol{s}|\boldsymbol{o}, \boldsymbol{u}) \| p(\boldsymbol{s}|\boldsymbol{u})]}_{\text{Ambiguity (曖昧性)}}
$$

**Surprise** は、観測 $\boldsymbol{o}$ が状態 $\boldsymbol{s}$ と行動 $\boldsymbol{u}$ の組み合わせにおいてどれだけ「予想外」であるかを表す。Surpriseが高い行動（例: 学習していないパターン、OOD条件）は避けられ、馴染みのある行動が選好される。

しかし、従来の工学的実装では、このSurprise項が省略されるか、暗黙的にしか扱われてこなかった。本研究では、Surpriseを **VAE再構成誤差** として定量化し、行動選択に明示的に組み込む。

### 知覚解像度の設計課題

さらに、「確信が持てない状況では、どの程度まで環境を詳細に見るべきか」という認知的制御原理が、工学的に明示されてこなかった点に本質的な課題が存在する。本研究では、この問題を **Haze** という設計パラメータによって解決する。

## 1.2 目的 (Objective)

本研究の目的は、自由エネルギー原理（FEP）および Active Inference の枠組みに基づき、以下の二層制御機構を実現することである：

### 行動層：Surprise最小化

行動選択において、以下の拡張自由エネルギーを最小化する：

$$
F(\boldsymbol{u}) = F_{\text{goal}}(\boldsymbol{u}) + F_{\text{safety}}(\boldsymbol{u}) + \lambda_s \cdot S(\boldsymbol{u})
$$

ここで、$S(\boldsymbol{u})$ はSurprise（VAE再構成誤差）であり、学習済みの馴染みのある行動を選好する効果を持つ。

### 知覚層：Haze変調

知覚解像度を制御するパラメータ **Haze** を導入し、それに基づいてPrecision $\beta$ を変調する：

$$
\beta[k] = f_{\text{precision}}(\text{Haze}[k])
$$

Hazeは設計者が制御する変数であり、以下の3モードを想定する：
- **固定モード**: Haze = 0.5（全エピソードで一定）
- **スケジュールモード**: 環境状態（密度、リスク）に応じて設定
- **Self-Hazingモード**: エージェントが自律的に学習（Phase 6で実装予定）

### 統合されたシステム

提案するEPHは、SurpriseによるOOD回避と、Hazeによる知覚粗視化を統合することで、不確実性が高い状況でも安定した行動生成を実現する。

本研究は、混雑環境における単体ロボットの社会ナビゲーションを主要な応用例としつつも、その射程を単体システムに限定せず、群知能や分散型自律システムにおいても成立する一般的な設計原理として提示することを目指す。

## 1.3 学術的新規性 (Academic Novelty)

本研究の学術的新規性は、以下の3点にある：

### (1) Active Inference の工学的実装

従来の工学的実装で省略されてきた **Surprise項** を、VAE再構成誤差として定量化し、自由エネルギーに明示的に組み込んだ。これにより、理論と実装の整合性を確保した。

$$
S(\boldsymbol{u}) = \|\boldsymbol{y}[k] - \text{VAE}_{\text{recon}}(\boldsymbol{y}[k], \boldsymbol{u})\|^2
$$

### (2) Haze の設計原理

Hazeを **設計者が制御可能なメタパラメータ** として導入し、VAEの潜在空間不確実性（$\sigma_z^2$）とは独立した設計次元として扱う。これにより、以下が可能となる：

- 設計者による明示的な知覚解像度制御
- VAEの学習とは独立したHaze設定（固定、スケジュール）
- 将来的なSelf-Hazing（自律学習）への拡張パス

### (3) 二層制御アーキテクチャ

SurpriseとHazeを独立した制御層として分離：

| 層 | 制御対象 | 入力 | 出力 | 役割 |
|----|---------|------|------|------|
| **行動層** | 行動選択 | SPM, Goal, Surprise | $\boldsymbol{u}^*$ | OOD回避、目標達成 |
| **知覚層** | 知覚解像度 | Haze | $\beta$ | 集約の鋭さ制御 |

この分離により、各層の設計と検証が独立して行えるという工学的利点が生まれる。

### (4) Precision 概念の明確化

自由エネルギー原理における Precision の曖昧さを解消：

- **推論Precision**: 予測誤差の信頼性重み（理論的概念、固定値）
- **知覚解像度パラメータ β**: 実装上の制御変数（Hazeから導出）

この分離により、理論的混乱を回避しつつ、実装可能な設計構造を確立した。

### (5) Self-Hazing の理論的枠組み

将来拡張として、エージェントが自律的に最適Hazeを学習する **Self-Hazing** の理論的枠組みを提示：

$$
\text{Haze}[k] = \pi_{\text{haze}}(\text{observation\_history}, \text{task\_context}, \sigma_z^2, \ldots)
$$

これは **メタ学習**（学習の学習）に相当し、設計者制御から自律制御への進化パスを示す。

---

# 2. 理論的基盤 (Theoretical Foundation)

本章では、本研究で提案する Emergent Perceptual Haze（EPH）v5.6 の理論的基盤を整理する。まず、対象とする運動モデルと行動生成の枠組みを定式化し、次に **Active Inference に基づく自由エネルギー（Surprise統合版）** を定義する。その上で、不確実性指標 Haze の再定義、Precision の役割分離、および循環依存の解消について詳述する。

---

## 2.1 問題定式化 (Problem Formulation)

本研究では、移動ロボットの運動を以下の 2 次遅れ系としてモデル化する。

$$
M \ddot{\boldsymbol{x}}[k] + D \dot{\boldsymbol{x}}[k] = \boldsymbol{u}[k]
$$

ここで、$\boldsymbol{x}[k] \in \mathbb{R}^2$ はロボットの位置、$\dot{\boldsymbol{x}}[k]$ は速度、$\boldsymbol{u}[k]$ は制御入力を表す。$M$ および $D$ はそれぞれ質量行列および粘性行列である。

ロボットの目的は、目標位置 $\boldsymbol{x}_g$ への到達と、他エージェントや障害物との衝突回避を同時に満たす行動を生成することである。本研究では、この目的を **拡張自由エネルギー最小化問題（Surprise統合版）** として定式化する。

---

## 2.2 工学的自由エネルギーの定義（v5.6: Surprise統合版）

自由エネルギー原理（Free Energy Principle; FEP）は、本来、知覚と行動を統一的に説明する理論的枠組みであり、予測誤差を最小化する方向に内部状態や行動が更新されると解釈される。本研究では、この考え方を工学的に解釈し、**Surpriseを明示的に含む拡張自由エネルギー** を行動生成のための目的関数として定義する。

### 2.2.1 自由エネルギーの定義（v5.6）

本研究における自由エネルギー $F[k]$ は、**予測された将来のSPMと、現在の行動のSurprise** に基づいて定義される。

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
F_{\text{safety}}(\boldsymbol{u}) = \lambda_{\text{safe}} \sum_{m,n} \phi(\hat{\boldsymbol{y}}_{m,n}[k+1](\boldsymbol{u}))
$$

- $\hat{\boldsymbol{y}}[k+1]$: VAEによる予測SPM
- $\phi(\cdot)$: 衝突危険性のポテンシャル関数（例: Ch2, Ch3の重み付き和）

#### (3) Surprise項 ★v5.6 新規追加★

$$
S(\boldsymbol{u}) = \|\boldsymbol{y}[k] - \text{VAE}_{\text{recon}}(\boldsymbol{y}[k], \boldsymbol{u})\|^2
$$

**意味**: 「現在のSPM $\boldsymbol{y}[k]$ と行動 $\boldsymbol{u}$ のペアがどれだけ予想外か」

**計算方法**:

$$
\text{VAE}_{\text{recon}}(\boldsymbol{y}, \boldsymbol{u}) = \text{Decoder}(\text{Encoder}(\boldsymbol{y}, \boldsymbol{u}), \boldsymbol{u})
$$

1. VAEのEncoderで $(y[k], u[k]) \to q(z|y, u) = \mathcal{N}(\mu_z, \sigma_z^2)$ を推定
2. 平均 $\mu_z$ を使用（決定論的）
3. Decoderで $(z=\mu_z, u) \to y_{\text{recon}}$ を再構成
4. 元のSPMとの二乗誤差を計算

**役割**:
- **低Surprise**: 学習済みの馴染みのある行動 → 選好される
- **高Surprise**: 未学習のOOD行動 → 回避される

**理論的根拠**:
Active Inferenceにおいて、エージェントはSurpriseを最小化する行動を選択する。これは「予測可能な状態を維持する」という生物学的原理に対応する。

---

### 2.2.2 予測ベース行動生成（Pattern D: Action-Dependent Uncertainty World Model）

本研究の核心は、自由エネルギーが操作指令値 $\boldsymbol{u}[k]$ を通じて予測 SPM **および Surprise** に依存する点にある。v5.6 (Pattern D) では VAE は以下の **行動依存エンコーダ構造** を持つ：

**エンコーダ**（現在状態と行動から潜在分布を推定）：

$$
q_\phi(\boldsymbol{z} \mid \boldsymbol{y}[k], \boldsymbol{u}[k])
=
\mathcal{N}(\boldsymbol{\mu}_z, \mathrm{diag}(\boldsymbol{\sigma}_z^2))
$$

**デコーダ**（潜在変数 + 操作指令値から将来 SPM を予測）：

$$
\hat{\boldsymbol{y}}[k+1] = f_{\text{dec}}(\boldsymbol{z}, \boldsymbol{u}[k])
$$

**重要な設計原則（v5.6）**:
- **エンコーダに $\boldsymbol{u}$ が入力される**: 潜在分布 $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ は行動に依存して変化する
- **VAEの役割は予測とSurprise計算**: $\sigma_z^2$ はVAEの内部変数であり、Hazeとは **独立** である
- **Hazeは設計パラメータ**: 設計者が外部から設定（固定、スケジュール、Self-Hazing）

この設計により：
- $\boldsymbol{z}$ = 「状態 $\boldsymbol{y}$ で行動 $\boldsymbol{u}$ をとった時の遷移の符号化」
- $\boldsymbol{\sigma}_z^2$ = 「その遷移の不確実性」（将来Self-Hazingで利用可能）
- $\hat{\boldsymbol{y}}$ = 「$\boldsymbol{z}$ の世界で $\boldsymbol{u}$ を実行した結果」
- $S(\boldsymbol{u})$ = 「$(y, u)$ ペアの予測困難度」

制御入力は、**操作指令値に関する拡張自由エネルギーの最小化**として生成される：

$$
\boldsymbol{u}^*[k]
=
\arg\min_{\boldsymbol{u}}
\left[
F_{\text{goal}}(\boldsymbol{u}) + F_{\text{safety}}(\boldsymbol{u}) + \lambda_s \cdot S(\boldsymbol{u})
\right]
$$

**実装における近似**:
勾配計算が複雑なため、サンプルベース最適化を使用：

```julia
candidates = [u_baseline + noise for _ in 1:10]
u_optimal = argmin(F(u) for u in candidates)
```

---

### 2.2.3 勾配計算の理論的枠組み

理論的には、$\boldsymbol{u}$ に関する自由エネルギーの勾配は以下のチェーンルールにより計算される：

$$
\frac{\partial F}{\partial \boldsymbol{u}}
=
\frac{\partial F_{\text{goal}}}{\partial \boldsymbol{u}}
+
\sum_{m,n}
\frac{\partial \phi(\hat{\boldsymbol{y}}_{m,n})}{\partial \hat{\boldsymbol{y}}_{m,n}}
\cdot
\frac{\partial \hat{\boldsymbol{y}}_{m,n}}{\partial \boldsymbol{u}}
+
\lambda_s \frac{\partial S}{\partial \boldsymbol{u}}
$$

ここで：
- $\partial \hat{\boldsymbol{y}}_{m,n} / \partial \boldsymbol{u}$ : VAEを通じた予測SPMの勾配
- $\partial S / \partial \boldsymbol{u}$ : Surpriseの勾配（VAE再構成を通じて計算）

**実装上の課題**:
VAEがFluxで実装されているため、ForwardDiff経由の自動微分が複雑である。Phase 1-5では **サンプルベース最適化** を採用し、Phase 6以降で勾配ベース最適化を検討する。

---

## 2.3 Precision 概念の整理と役割分離（v5.6改訂）

自由エネルギー原理において Precision は、予測誤差の信頼性を表す重みとして導入される（Feldman & Friston, 2010）。しかし、工学的実装においては、Precision が複数の役割を暗黙的に担ってしまい、理論的混乱を招く場合がある。

v5.6では、Precisionを以下の2つに明確に分離する：

### 2.3.1 推論における Precision（Inference Precision）

推論における Precision は、予測誤差項の信頼性重みとして自由エネルギーに現れる量であり、FEP における本来の定義に対応する。本研究では、この推論 Precision は **固定値として扱い**、学習や制御の対象とはしない。

### 2.3.2 知覚解像度を制御するパラメータ（Perceptual Resolution Parameter）

$\beta$ は、自由エネルギー中の誤差項を直接重み付けする量ではなく、知覚表現（SPM）における soft 集約の鋭さを制御するメタパラメータである。この役割分離により、Precision の二重利用による理論的不整合を回避する。

$$
\beta[k] = f_{\text{precision}}(\text{Haze}[k])
$$

ここで、**Haze は設計者が制御するパラメータ** であり、VAEの $\sigma_z^2$ とは独立である。

**数式例（逆双曲線）**:

$$
\beta[k] = \frac{\beta_{\max}}{1 + \alpha \cdot \text{Haze}[k]}
$$

- $\beta_{\max}$: 最大知覚精度（例: 10.0）
- $\alpha$: 感度パラメータ（例: 1.0）
- $\text{Haze}[k] \in [0, 1]$: 設計パラメータ

**解釈**:
- $\text{Haze} = 0$ → $\beta = \beta_{\max}$ → 鋭敏な知覚
- $\text{Haze} = 1$ → $\beta = \beta_{\max} / 2$ → 粗い知覚

---

## 2.4 不確実性指標 Haze の定義（v5.6改訂：設計パラメータ化）

### 2.4.1 不確実性の種類と本研究の立場

不確実性は大きく **エピステミック不確実性**（知識不足）と **アレアトリック不確実性**（本質的ランダム性）に分類される。本研究における Haze は、**知覚解像度を制御するための設計パラメータ** であり、特定の不確実性源に限定されない。

v5.6では、Hazeを以下のように再定義する：

### 2.4.2 Haze の新定義（v5.6）

**Haze は設計者が設定する知覚解像度のメタパラメータである。**

$$
\text{Haze}[k] \in [0, 1]
$$

#### Haze の設定方法

##### (1) 固定モード（Phase 1-5で使用）

$$
\text{Haze}[k] = \text{const.} \quad \text{(e.g., 0.5)}
$$

全エピソードを通じて一定値を使用。

##### (2) スケジュールモード（設計者制御）

環境状態に応じて設計者が事前定義したルールで設定：

$$
\text{Haze}[k] =
\begin{cases}
0.9 & \text{if } \rho[k] > 20 \text{ (超混雑)} \\
0.6 & \text{if } \rho[k] > 10 \text{ (混雑)} \\
0.8 & \text{if } r_{\text{collision}}[k] > 0.8 \text{ (高リスク)} \\
0.2 & \text{otherwise (通常)}
\end{cases}
$$

ここで、$\rho[k]$ は局所密度、$r_{\text{collision}}[k]$ は衝突リスク。

##### (3) Self-Hazingモード（Phase 6で実装予定）★将来拡張★

エージェントが自律的に最適Hazeを学習：

$$
\text{Haze}[k] = \pi_{\text{haze}}(\boldsymbol{h}[k])
$$

ここで、$\boldsymbol{h}[k]$ は以下の情報を含む履歴ベクトル：
- VAE不確実性: $\sigma_z^2(y[k], u[k])$
- 予測誤差履歴: $\{e[k-T:k]\}$
- タスク成功率: $\eta_{\text{success}}$
- 衝突履歴: $\{c[k-T:k]\}$

学習手法:
- **Option 1**: 強化学習（Haze選択を行動空間に追加）
- **Option 2**: メタ学習（MAML等）
- **Option 3**: ベイズ最適化

### 2.4.3 VAE不確実性 $\sigma_z^2$ との関係（v5.6明確化）

**重要**: v5.5では Haze ≡ $\text{Agg}(\sigma_z^2)$ と定義していたが、v5.6では **Hazeと$\sigma_z^2$は独立** である。

| 変数 | 定義 | 役割 | 制御者 |
|------|------|------|--------|
| $\sigma_z^2$ | VAE潜在空間の分散 | VAEの内部変数 | VAE学習 |
| Haze | 知覚解像度パラメータ | β変調の入力 | 設計者 or Self-Hazing |

**Phase 1-5**: Hazeは固定値（0.5）、$\sigma_z^2$はログのみ
**Phase 6**: Self-Hazingで $\sigma_z^2$ を入力の一要素として使用可能

---

## 2.5 循環依存の解消と因果順序（v5.6）

v5.6では、Surprise、Haze、β、SPMの因果関係が明確化される。

### 2.5.1 因果フロー

```
[Time k]
1. Haze[k] を取得（固定 or スケジュール or Self-Hazing）
2. β[k] = f_precision(Haze[k]) を計算
3. SPM[k] を生成（β[k]で集約の鋭さを制御）
4. 候補行動 u_i を生成
5. 各 u_i について:
   - F_goal(u_i) を計算
   - F_safety(u_i) を計算（VAE予測使用）
   - S(u_i) を計算（VAE再構成誤差）
   - F_total(u_i) = F_goal + F_safety + λ_s * S
6. u*[k] = argmin F_total(u_i) を選択
7. 状態更新

[Time k+1]
（繰り返し）
```

### 2.5.2 循環依存の非存在

v5.6では、以下の理由により循環依存が存在しない：

1. **Hazeは外部パラメータ**: VAEの出力（$\sigma_z^2$）に依存しない
2. **Surpriseは行動評価**: 行動選択の結果としてのみ計算される
3. **βはHazeから一方向的に導出**: SPM生成前に確定

### 2.5.3 Self-Hazingにおける潜在的循環（Phase 6）

Self-Hazingでは、以下の循環が生じる可能性がある：

```
Haze[k] → β[k] → SPM[k] → u[k] → Performance → Haze[k+1]
```

これは **メタ学習** の枠組みで扱われる。Hazeの更新は行動決定よりも遅い時間スケールで行われるため、実質的な循環は発生しない。

---

## 2.6 本章のまとめ

本章では、EPH v5.6 の理論的基盤を整理した。

**主要な理論的貢献**:

1. **Surprise統合**: Active Inferenceの要請であるSurpriseを、VAE再構成誤差として定量化し、自由エネルギーに統合した

2. **Haze再定義**: Hazeを設計パラメータとして再定義し、VAE不確実性（$\sigma_z^2$）とは独立した設計次元として扱った

3. **Precision分離**: 推論Precisionと知覚解像度パラメータβを明確に分離し、理論的混乱を回避した

4. **二層制御**: Surprise駆動の行動選択層と、Haze駆動の知覚変調層を分離した

5. **Self-Hazingの理論的枠組み**: 将来拡張として、自律的Haze学習の方向性を示した

**因果関係の整理**:
- Haze → β → SPM生成
- SPM + Goal + VAE → Action候補生成
- Action候補 → Surprise計算 → 最適Action選択

この設計により、理論的厳密性（FEP準拠）と実装可能性（サンプルベース最適化）を両立させた。

---

# 3. 手法 (Methodology)

本章では、EPH v5.6の具体的な実装手法を詳述する。システム全体構成、知覚表現（SPM）、世界モデル（Action-Conditioned VAE）、Surprise計算、行動生成、Haze に基づく知覚解像度制御の順に説明する。

---

## 3.1 システム全体構成 (System Overview)

EPH v5.6 は、以下の二層制御アーキテクチャで構成される：

### 3.1.1 全体フロー

```
[知覚層：Perceptual Layer]
Raw Sensors → SPM_raw → Precision β (from Haze) → SPM_modulated

[行動層：Action Layer]
SPM_modulated + Goal + VAE → Action Candidates
  → Evaluate F_goal + F_safety + λ_s*Surprise
  → Select u* = argmin F
  → Execute
```

### 3.1.2 VAE の二重の役割（v5.6）

VAEは以下の2つの機能を提供する：

| 機能 | 入力 | 出力 | 用途 |
|------|------|------|------|
| **予測** | $(y[k], u[k])$ | $\hat{y}[k+1]$ | 安全性項 $F_{\text{safety}}$ |
| **再構成** | $(y[k], u[k])$ | $y_{\text{recon}}$ | Surprise項 $S$ |

**重要**: VAEの潜在空間不確実性 $\sigma_z^2$ は、Phase 1-5では直接使用されない。Phase 6のSelf-Hazingで利用可能。

### 3.1.3 行動生成経路（Action Generation Path）

```
Goal x_g ────┐
             ├─→ F_goal(u)
u candidates─┤
             ├─→ F_safety(u) (via VAE prediction)
SPM[k] ──────┤
             └─→ S(u) (via VAE reconstruction)
                  ↓
              F_total = F_goal + F_safety + λ_s*S
                  ↓
              u* = argmin F_total
```

### 3.1.4 知覚解像度制御経路（Perceptual Resolution Control Path）

```
Haze設定 ──→ Haze[k] ──→ β[k] = f_precision(Haze[k])
                           ↓
SPM_raw ──────────────→ apply_precision(SPM_raw, β) ──→ SPM[k]
```

**Haze設定の3モード**:
- Mode 1: 固定（0.5）
- Mode 2: スケジュール（密度・リスク依存）
- Mode 3: Self-Hazing（Phase 6）

---

## 3.2 知覚表現：Saliency Polar Map (SPM)

### 3.2.1 SPM の概要

SPM（Saliency Polar Map）は、自己中心的な極座標グリッド $(r, \theta)$ 上で定義される $16 \times 16 \times 3$ の三次元配列である。3つのチャネルは以下の意味を持つ：

- **Ch1 (Occupancy)**: 占有密度
- **Ch2 (Proximity Saliency)**: 近接顕著性（soft-maxによる集約）
- **Ch3 (Dynamic Collision Risk)**: 動的衝突危険性

### 3.2.2 チャネル1：占有密度 (Occupancy)

占有密度は、各セル内に存在する他エージェント数を正規化した値である：

$$
\text{SPM}_{\text{ch1}}[m, n] = \frac{N_{m,n}}{N_{\max}}
$$

- $N_{m,n}$: セル $(m, n)$ 内のエージェント数
- $N_{\max}$: 正規化定数

### 3.2.3 チャネル2：近接顕著性 (Proximity Saliency) ★β変調の対象★

近接顕著性は、各セル内の他エージェントとの距離を soft-max 集約により統合する：

$$
\text{SPM}_{\text{ch2}}[m, n] =
\begin{cases}
\displaystyle
\frac{\sum_{i \in \mathcal{N}_{m,n}} w_i \exp(\beta \cdot \phi_i)}{\sum_{i \in \mathcal{N}_{m,n}} \exp(\beta \cdot \phi_i)} & \text{if } |\mathcal{N}_{m,n}| > 0 \\
0 & \text{otherwise}
\end{cases}
$$

ここで：
- $\mathcal{N}_{m,n}$: セル $(m, n)$ に対応する他エージェント集合
- $w_i = 1 / (d_i + \epsilon)$: 距離の逆数
- $\phi_i = -d_i$: 近接ポテンシャル（距離が近いほど高い）
- $\beta$: **Hazeから導出されるPrecisionパラメータ**

**βの効果**:
- **高β** (低Haze): 最も近い障害物を強調（鋭敏）
- **低β** (高Haze): 全ての障害物を平均化（粗視化）

**数式解釈**:
$$
\lim_{\beta \to \infty} \text{SPM}_{\text{ch2}}[m, n] = \max_{i \in \mathcal{N}_{m,n}} w_i \quad \text{(最大値選択)}
$$

$$
\lim_{\beta \to 0} \text{SPM}_{\text{ch2}}[m, n] = \frac{1}{|\mathcal{N}_{m,n}|} \sum_{i \in \mathcal{N}_{m,n}} w_i \quad \text{(平均)}
$$

### 3.2.4 チャネル3：動的衝突危険性 (Dynamic Collision Risk)

Ch3は、他エージェントの速度を考慮した動的な衝突リスクを表現する：

$$
\text{SPM}_{\text{ch3}}[m, n] =
\frac{\sum_{i \in \mathcal{N}_{m,n}} r_i \exp(\beta \cdot \psi_i)}{\sum_{i \in \mathcal{N}_{m,n}} \exp(\beta \cdot \psi_i)}
$$

ここで：
- $r_i$: エージェント $i$ との衝突リスク
- $\psi_i = -\text{TTC}_i$: Time-to-Collision の逆数

衝突リスクは以下で定義：

$$
r_i =
\begin{cases}
\displaystyle
\frac{1}{\text{TTC}_i + \epsilon} \cdot \max(0, \cos \theta_{\text{rel},i}) & \text{if TTC}_i < T_{\text{threshold}} \\
0 & \text{otherwise}
\end{cases}
$$

- $\theta_{\text{rel},i}$: 相対速度ベクトルと位置ベクトルのなす角
- $T_{\text{threshold}}$: TTCの閾値（例: 5秒）

---

## 3.3 集約演算子 Agg の定義（v5.6明示）

v5.6では、集約演算子 $\text{Agg}$ を soft-max として明示的に定義する：

$$
\text{Agg}_{\beta}(w_1, \ldots, w_N; \phi_1, \ldots, \phi_N)
=
\frac{\sum_{i=1}^N w_i \exp(\beta \cdot \phi_i)}{\sum_{i=1}^N \exp(\beta \cdot \phi_i)}
$$

この演算子は、$\beta$ により以下の連続的な補間を実現する：

| β | 動作 | 解釈 |
|---|------|------|
| $\beta \to 0$ | 算術平均 | 粗い知覚（全要素を均等に扱う） |
| $\beta = 1$ | ボルツマン重み | 標準的な重み付き平均 |
| $\beta \to \infty$ | max演算子 | 鋭敏な知覚（最も顕著な要素のみ） |

**設計上の利点**:
- 微分可能（勾配ベース最適化が可能）
- 温度パラメータとの対応が明確
- 統計力学的解釈（分配関数）

---

## 3.4 世界モデル：Action-Conditioned VAE による将来 SPM 予測とSurprise計算（v5.6）

### 3.4.1 VAE の構造（Pattern D）

v5.6では、Action-Dependent Encoder と Action-Conditioned Decoder を持つ Pattern D アーキテクチャを採用する。

**入力・出力**:
- 訓練データ: $(y[k], u[k], y[k+1])$ トリプレット
- 予測: $\hat{y}[k+1] = \text{Decoder}(z, u[k])$
- Surprise: $S = \|y[k] - \text{Decoder}(\text{Encoder}(y[k], u[k]), u[k])\|^2$

### 3.4.2 エンコーダ（状態と行動から潜在分布を推定）

$$
q_\phi(\boldsymbol{z} \mid \boldsymbol{y}[k], \boldsymbol{u}[k])
=
\mathcal{N}(\boldsymbol{\mu}_z(\boldsymbol{y}, \boldsymbol{u}), \mathrm{diag}(\boldsymbol{\sigma}_z^2(\boldsymbol{y}, \boldsymbol{u})))
$$

**実装**:
```julia
# 1. SPM特徴抽出
y_features = CNN(y)  # (16,16,3) → (512,)

# 2. Action特徴抽出
u_features = MLP(u)  # (2,) → (64,)

# 3. 統合
joint_features = concat(y_features, u_features)  # (576,)

# 4. 潜在分布パラメータ推定
μ_z, logσ_z = MLP(joint_features)  # (576,) → (32,), (32,)
```

**$\sigma_z^2$ の役割（v5.6）**:
- VAEの内部変数（学習対象）
- Phase 1-5: 直接使用せず、ログのみ記録
- Phase 6: Self-Hazingの入力候補として利用可能

### 3.4.3 デコーダ（潜在変数 + 操作指令値から将来予測）

$$
\hat{\boldsymbol{y}}[k+1] = f_{\text{dec}}(\boldsymbol{z}, \boldsymbol{u}[k])
$$

**実装**:
```julia
# 1. 潜在変数を特徴に変換
z_features = MLP(z)  # (32,) → (256,)

# 2. Action特徴
u_features = MLP(u)  # (2,) → (64,)

# 3. 統合
combined = concat(z_features, u_features)  # (320,)

# 4. SPM再構成
ŷ = Deconv_CNN(combined)  # (320,) → (16,16,3)
```

### 3.4.4 VAE の学習目的関数

$$
\mathcal{L}_{\text{VAE}} = \underbrace{\|\boldsymbol{y}[k+1] - \hat{\boldsymbol{y}}[k+1]\|^2}_{\text{予測誤差}} + \beta_{\text{KL}} \cdot \underbrace{D_{KL}[q(\boldsymbol{z}|\boldsymbol{y}, \boldsymbol{u}) \| \mathcal{N}(0, I)]}_{\text{正則化}}
$$

- $\beta_{\text{KL}}$: KL重み（例: 0.1 〜 1.0）

### 3.4.5 Pattern D の設計根拠（v5.6明確化）

Pattern D（Action-Dependent Encoder）を採用する理由：

1. **Counterfactual Surprise**: 同一状態 $y[k]$ に対して異なる行動 $u$ でのSurpriseを評価可能

2. **行動依存の不確実性**: $\sigma_z^2(y, u)$ により「この行動がどれだけ予測困難か」を表現

3. **Hazeとの分離**: $\sigma_z^2$ はVAEの内部変数であり、Hazeとは独立（v5.6の設計原則）

---

## 3.5 操作指令値に関する行動生成（v5.6: Surprise統合版）

### 3.5.1 行動生成の目的関数

v5.6では、拡張自由エネルギーを最小化する行動を選択する：

$$
\boldsymbol{u}^*[k]
=
\arg\min_{\boldsymbol{u}}
\left[
F_{\text{goal}}(\boldsymbol{u}) + \lambda_{\text{safe}} \cdot F_{\text{safety}}(\boldsymbol{u}) + \lambda_s \cdot S(\boldsymbol{u})
\right]
$$

#### 目標項

$$
F_{\text{goal}}(\boldsymbol{u}) = \|\hat{\boldsymbol{x}}[k+1](\boldsymbol{u}) - \boldsymbol{x}_g\|^2
$$

**計算**: 運動モデルにより $\boldsymbol{u}$ から $\hat{\boldsymbol{x}}[k+1]$ を予測

#### 安全性項

$$
F_{\text{safety}}(\boldsymbol{u}) = \max_{m,n} \hat{\boldsymbol{y}}_{m,n}^{\text{(ch3)}}[k+1](\boldsymbol{u})
$$

**計算**: VAEで $(y[k], u) \to \hat{y}[k+1]$ を予測し、Ch3（動的衝突リスク）の最大値を取得

#### Surprise項（v5.6）

$$
S(\boldsymbol{u}) = \|\boldsymbol{y}[k] - \text{VAE}_{\text{recon}}(\boldsymbol{y}[k], \boldsymbol{u})\|^2
$$

**計算手順**:
1. Encode: $\mu_z, \sigma_z = \text{Encoder}(y[k], u)$
2. $z = \mu_z$ （決定論的、平均を使用）
3. Decode: $y_{\text{recon}} = \text{Decoder}(z, u)$
4. $S = \text{MSE}(y[k], y_{\text{recon}})$

### 3.5.2 サンプルベース最適化（v5.6実装方針）

勾配計算の複雑さを回避するため、Phase 1-5ではサンプルベース最適化を使用：

```julia
function compute_action_v56(agent, spm, vae, params)
    # 1. Baseline行動
    u_baseline = compute_action_baseline(agent, spm)

    # 2. 候補生成
    candidates = [u_baseline]
    for i in 1:9
        noise = randn(2) * 0.3
        push!(candidates, u_baseline + noise)
    end

    # 3. 評価
    best_u = u_baseline
    min_F = Inf

    for u in candidates
        u = clamp(u, -u_max, u_max)

        # 目標項
        x_next = predict_position(agent, u)
        F_goal = norm(x_next - agent.goal)^2

        # 安全項（VAE予測）
        ŷ = predict_spm(vae, spm, u)
        F_safety = maximum(ŷ[:,:,3])

        # Surprise項
        S = compute_surprise(vae, spm, u)

        # 総合評価
        F_total = F_goal + λ_safe * F_safety + λ_s * S

        if F_total < min_F
            min_F = F_total
            best_u = u
        end
    end

    return best_u
end
```

### 3.5.3 ハイパーパラメータ

| パラメータ | 推奨値 | 調整範囲 | 役割 |
|----------|--------|---------|------|
| $\lambda_{\text{safe}}$ | 10.0 | 5.0 〜 20.0 | 安全性の重み |
| $\lambda_s$ | 1.0 | 0.1 〜 5.0 | Surpriseの重み |
| 候補数 | 10 | 5 〜 20 | サンプルベース最適化 |

---

## 3.6 Haze に基づく知覚解像度制御（β 変調）

### 3.6.1 Hazeの取得

v5.6では、以下の3モードでHazeを取得する：

#### Mode 1: 固定Haze（Phase 1-5）

```julia
function get_haze_fixed()
    return 0.5  # 固定値
end
```

#### Mode 2: スケジュールHaze

```julia
function get_haze_scheduled(agent, environment)
    density = environment.local_density
    collision_risk = agent.collision_risk

    if density > 20
        return 0.9  # 超混雑 → 超粗視化
    elseif density > 10
        return 0.6  # 混雑 → 中程度
    elseif collision_risk > 0.8
        return 0.8  # 高リスク → 粗視化
    else
        return 0.2  # 通常 → 高解像度
    end
end
```

#### Mode 3: Self-Hazing（Phase 6）

```julia
function get_haze_self_adaptive(agent, vae)
    # VAE不確実性
    μ, logσ = encode(vae, agent.spm, agent.last_action)
    σ_z² = mean(exp.(2 .* logσ))

    # 予測誤差履歴
    pred_error = agent.prediction_error_history

    # タスクパフォーマンス
    success_rate = agent.task_success_rate

    # メタ学習モデル
    haze = meta_learner(σ_z², pred_error, success_rate)

    return haze
end
```

### 3.6.2 PrecisionβへのMismatch


$$
\beta[k] = \frac{\beta_{\max}}{1 + \alpha \cdot \text{Haze}[k]}
$$

```julia
function precision_modulation(haze::Float64; β_max=10.0, α=1.0)
    β = β_max / (1.0 + α * haze)
    return clamp(β, 1.0, β_max)
end
```

### 3.6.3 SPM生成への適用

```julia
function generate_spm(agent, others, haze::Float64)
    # 1. Haze → β
    β = precision_modulation(haze)

    # 2. Raw SPM生成
    spm_raw = compute_spm_raw(agent, others)

    # 3. β変調（Ch2, Ch3に適用）
    spm_ch2 = apply_softmax_aggregation(spm_raw_ch2, β)
    spm_ch3 = apply_softmax_aggregation(spm_raw_ch3, β)

    return cat(spm_raw_ch1, spm_ch2, spm_ch3, dims=3)
end
```

---

## 3.7 群知能への拡張 (Swarm Intelligence Extension)

EPHは単体ロボットに限定されず、群知能システムへも拡張可能である。

### 3.7.1 局所Hazeの導入

各エージェント $i$ が独立したHaze $H_i[k]$ を持つ：

$$
\beta_i[k] = f_{\text{precision}}(H_i[k])
$$

### 3.7.2 Self-Hazingにおける群の影響

Self-Hazingでは、近傍エージェントの状態も考慮可能：

$$
H_i[k] = \pi_{\text{haze}}(\boldsymbol{h}_i[k], \{\boldsymbol{h}_j[k] : j \in \mathcal{N}_i\})
$$

- $\mathcal{N}_i$: エージェント $i$ の近傍集合

### 3.7.3 評価指標

群知能拡張では、以下の指標を追加：
- **群分断率**: 連結成分数の変化
- **Lane Formation**: レーン形成の秩序パラメータ
- **Throughput**: 単位時間あたりの通過エージェント数

---

## 3.8 本章のまとめ

本章では、EPH v5.6の具体的な実装手法を詳述した。

**主要な実装要素**:

1. **二層制御**: Surprise駆動の行動層と、Haze駆動の知覚層の分離

2. **VAEの二重機能**: 予測（安全性評価）とSurprise計算（行動評価）

3. **Haze設定の3モード**: 固定、スケジュール、Self-Hazing

4. **サンプルベース最適化**: 勾配計算の複雑さを回避

5. **SPM集約のβ変調**: soft-maxによる知覚解像度制御

**実装の鍵**:
- Phase 1-5: 固定Haze（0.5）でシステムを検証
- Phase 6: Self-Hazingによる自律化

この設計により、理論的厳密性と実装可能性を両立させた。

---

# 4. 検証戦略 (Verification Strategy)

本章では、EPH v5.6の性能を検証するための実験設計、評価指標、比較手法を定義する。

---

## 4.1 検証シナリオと前提条件

### 4.1.1 シミュレーション環境

**環境設定**:
- トーラス世界（周期境界条件）
- 2Dナビゲーション
- 離散時間ステップ（dt = 0.033秒、30 FPS）

**シナリオ**:
1. **Scramble Crossing**: 4グループが交差点で交差
2. **Corridor**: 双方向対面通行（幅4-6m）

### 4.1.2 混雑度の操作的定義

混雑度 $\rho$ を以下で定義：

$$
\rho = \frac{N_{\text{agents}}}{A_{\text{area}}}
$$

実験では以下の密度を使用：
- $\rho \in \{5, 10, 15, 20, 25\}$ エージェント/エリア

### 4.1.3 学習と評価の分離（再現性・一般化の前提）

**データ分割**:
- **Train**: 密度 5, 10, 15（シード 1-3）
- **Val**: 密度 5, 10, 15（シード 4）
- **Test IID**: 密度 5, 10, 15（シード 5）
- **Test OOD**: 密度 20, 25（シード 1）

### 4.1.4 OOD（未知条件）評価

以下の3種類のOOD条件を評価：
1. **未知混雑度**: 密度20, 25
2. **未知他者モデル**: 学習時と異なる行動パターン
3. **観測ノイズ**: SPM構築時のノイズ付加

---

## 4.2 評価指標 (Evaluation Metrics)

### 4.2.1 Primary Outcome：Freezing Rate

**定義**:

$$
\text{Freezing Rate} = \frac{N_{\text{freeze}}}{N_{\text{agents}}}
$$

ここで、エージェントは以下の条件を満たす時Freezingと判定：

$$
\|\dot{\boldsymbol{x}}[k]\| < \epsilon_v \quad \text{for } t > T_{\text{freeze}}
$$

- $\epsilon_v = 0.1$ m/s（速度閾値）
- $T_{\text{freeze}} = 2.0$ 秒（継続時間閾値）

**目標**: EPH Freezing Rate < Baseline Freezing Rate（統計的有意差）

### 4.2.2 Secondary Outcomes

| 指標 | 定義 | 目標 |
|------|------|------|
| **Success Rate** | ゴール到達率 | > 80% |
| **Collision Rate** | 衝突発生率 | < 20% |
| **Path Efficiency** | 直線距離 / 実経路長 | > 0.7 |
| **Jerk** | $\|\|\ddot{\boldsymbol{u}}\|\|$ の時間平均 | 低いほど良 |
| **Min TTC** | Time-to-Collisionの最小値 | > 1.0秒 |
| **Throughput** | 単位時間あたりの通過数 | 高いほど良 |

---

## 4.3 比較手法（Baselines）

### 4.3.1 アブレーションスタディ

| 条件ID | Surprise | Haze | β | 説明 |
|--------|---------|------|---|------|
| **A0_BASELINE** | ❌ | 0.0 | 10.0 | 標準FEP、固定高精度 |
| **A1_HAZE_ONLY** | ❌ | 0.5 | 変調 | Haze変調のみ |
| **A2_SURPRISE_ONLY** | ✅ | 0.0 | 10.0 | Surprise駆動、β固定 |
| **A3_EPH_V56** | ✅ | 0.5 | 変調 | **提案手法（両方有効）** |

### 4.3.2 古典的手法（オプション）

- **Social Force Model**: Helbing et al. (2000)
- **ORCA**: van den Berg et al. (2011)

### 4.3.3 モデル予測制御系（オプション）

- **Robust MPC**: 最悪ケース設計
- **Tube MPC**: 不確実性集合

### 4.3.4 学習ベース手法（オプション）

- **SA-CADRL**: Chen et al. (2017)
- **SAC**: Soft Actor-Critic

---

## 4.4 統計的検証

### 4.4.1 検定手法

**Mann-Whitney U Test**: A3 vs A0のFreeing Rate比較

$$
H_0: \text{median}(\text{FR}_{\text{A3}}) = \text{median}(\text{FR}_{\text{A0}})
$$

$$
H_1: \text{median}(\text{FR}_{\text{A3}}) < \text{median}(\text{FR}_{\text{A0}})
$$

有意水準: $\alpha = 0.05$

### 4.4.2 効果量

Cohen's d:

$$
d = \frac{\bar{x}_{\text{A3}} - \bar{x}_{\text{A0}}}{\sqrt{\frac{s_{\text{A3}}^2 + s_{\text{A0}}^2}{2}}}
$$

解釈:
- $|d| < 0.2$: 小
- $0.2 \leq |d| < 0.5$: 中
- $|d| \geq 0.5$: 大

---

## 4.5 本章のまとめ

検証戦略のポイント:

1. **Primary Outcome**: Freezing Rate（EPHの核心目標）
2. **アブレーション**: Surprise、Hazeの個別効果を分離評価
3. **OOD評価**: 未学習条件での頑健性確認
4. **統計的厳密性**: 有意差検定と効果量

---

# 5. 関連研究 (Related Work)

本章では、EPH v5.6の理論的・技術的背景となる関連研究を整理する。

---

## 5.1 自由エネルギー原理と Active Inference

**Friston (2010)** は、生物の知覚と行動を統一的に説明する自由エネルギー原理（FEP）を提唱した。FEPでは、生物は感覚入力の **Surprise** を最小化するように行動する。

**Active Inference** (Friston et al., 2015) は、FEPの行動生成への応用であり、エージェントは **Expected Free Energy (EFE)** を最小化する：

$$
G(\boldsymbol{u}) = \mathbb{E}[-\log p(\boldsymbol{o}|\boldsymbol{s}, \boldsymbol{u})] + D_{KL}[q(\boldsymbol{s}|\boldsymbol{o}, \boldsymbol{u}) \| p(\boldsymbol{s}|\boldsymbol{u})]
$$

本研究は、このSurprise項を **VAE再構成誤差** として工学的に実装した初の試みである。

## 5.2 不確実性の分類と推定手法

不確実性は大きく **エピステミック不確実性**（知識不足）と **アレアトリック不確実性**（本質的ランダム性）に分類される (Kendall & Gal, 2017)。

本研究では、Hazeをこれらの不確実性に限定せず、**設計者が制御可能なメタパラメータ** として扱う点が特徴である。

## 5.3 ナビゲーションと衝突回避手法

### 5.3.1 古典的モデル

- **Social Force Model** (Helbing et al., 2000): 人間群集の動力学モデル
- **ORCA** (van den Berg et al., 2011): 最適相互衝突回避

これらの手法は不確実性を明示的に扱わない。

### 5.3.2 モデル予測制御（MPC）

**Robust MPC** は最悪ケース設計により不確実性に対処するが、過度に保守的となりFreezingを引き起こしやすい。

本研究は、Surpriseによる行動評価とHazeによる知覚変調により、保守性と柔軟性のバランスを実現する。

## 5.4 学習ベース手法と温度パラメータ

**Entropy-regularized RL** (Haarnoja et al., 2018) は、エントロピー項により探索を促進する。しかし、これは行動分布の多様性を制御するものであり、知覚解像度の制御ではない。

本研究のHazeは、行動層ではなく **知覚層** に介入する点で本質的に異なる。

## 5.5 知覚表現と極座標表現

**Saliency Polar Map (SPM)** は、自己中心的な極座標グリッドであり、ロボットナビゲーションで広く使用される (Chen et al., 2017)。

本研究の新規性は、SPMの集約の鋭さを **Haze** により動的に変調することで、不確実性適応型の知覚構造を実現した点にある。

## 5.6 本章のまとめ

EPH v5.6は、以下の点で既存研究と差別化される：

1. **Active Inference の工学的実装**: Surpriseを明示的に統合
2. **Haze の設計原理**: VAE不確実性とは独立した設計次元
3. **二層制御**: 行動層と知覚層の分離

---

# 6. 議論と限界 (Discussion and Limitations)

本章では、EPH v5.6の理論的意義、限界、将来展望を議論する。

---

## 6.1 Freezing 抑制のメカニズムに関する考察

EPH v5.6は、以下の2つのメカニズムによりFreezingを抑制する：

### (1) Surprise最小化

Surpriseが高い行動（OOD、未学習）を回避することで、エージェントは **馴染みのある行動パターン** を選好する。これにより、予測困難な状況でも安定した行動が生成される。

### (2) Haze変調

高Haze（低β）では、SPMの集約が粗視化され、局所的な障害物への過剰反応が抑制される。これにより、「目の前の障害物に固執して動けなくなる」現象が回避される。

---

## 6.2 不確実性の解釈と理論的位置付け

v5.6では、不確実性を以下の2つの独立した概念として扱う：

| 概念 | 定義 | 制御者 | 役割 |
|------|------|--------|------|
| **Surprise** | 予測困難度 | VAE学習 | 行動評価 |
| **Haze** | 知覚解像度パラメータ | 設計者 or Self-Hazing | β変調 |

この分離により、理論的明確性と工学的柔軟性を両立させた。

---

## 6.3 Precision 分離設計の意義

従来のFEP実装では、Precisionが「推論の重み」と「知覚の鋭さ」の両方を暗黙的に担っていた。v5.6では、以下の明確な分離を行った：

- **推論Precision**: 理論的概念（固定値）
- **知覚解像度β**: 実装上の制御変数（Hazeから導出）

この分離は、理論と実装の対応関係を明確化し、工学的設計の自由度を高める。

---

## 6.4 Self-Hazingの展望（Phase 6）

Self-Hazingは、エージェントが自律的に最適Hazeを学習する機能である。これは **メタ学習**（学習の学習）に相当し、以下の利点を持つ：

- 設計者の介入を減らす
- 未知環境への適応能力
- タスク依存の最適化

実装手法:
- 強化学習（Haze選択を行動空間に追加）
- メタ学習（MAML等）
- ベイズ最適化

---

## 6.5 限界と失敗モード

### 6.5.1 VAE学習の失敗

VAEの予測精度が不十分な場合、Surpriseが正しく計算されず、行動選択が不適切になる。

**対策**: Phase 3の厳格な検証基準（Counterfactual Success Rate > 70%）

### 6.5.2 サンプルベース最適化の限界

候補数が少ない場合、真の最適行動を見逃す可能性がある。

**対策**: 候補数を10〜20程度に設定、Phase 6で勾配ベース最適化を検討

### 6.5.3 計算コスト

Surprise計算には VAE Forward Pass が必要であり、計算コストが増加する。

**対策**: GPU使用、候補数の制限、軽量VAEアーキテクチャ

---

## 6.6 今後の展望

### 6.6.1 実環境実験

シミュレーション検証後、実ロボットでの検証を実施予定。

### 6.6.2 Self-Hazingの実装（Phase 6）

メタ学習によるHazeの自律的最適化。

### 6.6.3 群知能への拡張

局所Hazeによる分散型制御の実現。

---

## 6.7 本章のまとめ

EPH v5.6は、Active InferenceのSurprise最小化と、Hazeによる知覚解像度制御を統合することで、Freezing抑制という実用的課題に理論的根拠を与えた。

Self-Hazingという将来展望により、設計者制御から自律制御への進化パスを示した。

---

# 7. 結論 (Conclusion)

本研究では、自由エネルギー原理（FEP）および Active Inference に基づく二層制御アーキテクチャ **Emergent Perceptual Haze (EPH) v5.6** を提案した。

## 主要な貢献

1. **Surprise統合**: Active Inferenceの理論的要請であるSurpriseを、VAE再構成誤差として定量化し、自由エネルギーに明示的に組み込んだ

2. **Haze設計原理**: Hazeを設計パラメータとして再定義し、VAE不確実性とは独立した設計次元として扱った

3. **二層制御**: Surprise駆動の行動層と、Haze駆動の知覚層を分離した

4. **Precision分離**: 推論Precisionと知覚解像度パラメータβを明確に分離し、理論的混乱を回避した

5. **Self-Hazingの枠組み**: 将来拡張として、自律的Haze学習の理論的基盤を提示した

## 実装戦略

- **Phase 1-3**: VAE学習・検証（Prediction + Surprise）
- **Phase 4-5**: 固定Haze（0.5）での制御統合・比較実験
- **Phase 6**: Self-Hazingの研究開発

## 学術的意義

EPH v5.6は、理論的厳密性（FEP準拠）と実装可能性（サンプルベース最適化）を両立させ、Freezing Robot Problemという実用的課題に対する理論的解決策を提示した。

## 今後の展望

Self-Hazingによる自律化、実環境実験、群知能への拡張により、本研究の射程は単体ロボットナビゲーションを超えて、広範な不確実性適応型AIシステムへと拡大する。

---

**謝辞 (Acknowledgments)**

本研究は、東京電機大学の研究環境および関係者の支援により実施された。

---

**参考文献 (References)**

1. Friston, K. (2010). The free-energy principle: a unified brain theory? *Nature Reviews Neuroscience*, 11(2), 127-138.

2. Friston, K., et al. (2015). Active inference and epistemic value. *Cognitive Neuroscience*, 6(4), 187-214.

3. Kendall, A., & Gal, Y. (2017). What uncertainties do we need in Bayesian deep learning for computer vision? *NeurIPS*.

4. Helbing, D., et al. (2000). Simulating dynamical features of escape panic. *Nature*, 407(6803), 487-490.

5. van den Berg, J., et al. (2011). Reciprocal n-body collision avoidance. *Robotics Research*, 3-19.

6. Chen, Y. F., et al. (2017). Socially aware motion planning with deep reinforcement learning. *IROS*.

7. Haarnoja, T., et al. (2018). Soft actor-critic algorithms and applications. *arXiv:1812.05905*.

---

**付録 (Appendices)**

## 付録 A: Surprise計算の詳細

VAE再構成誤差の計算手順：

```julia
function compute_surprise(vae, spm, u)
    # 1. Reshape
    spm_input = Float32.(reshape(spm, 16, 16, 3, 1))
    u_input = Float32.(reshape(u, 2, 1))

    # 2. Encode
    μ, logσ = encode(vae, spm_input, u_input)

    # 3. Use mean (deterministic)
    z = μ

    # 4. Decode
    spm_recon = decode_with_u(vae, z, u_input)

    # 5. MSE
    surprise = mean((spm_input .- spm_recon).^2)

    return Float64(surprise)
end
```

## 付録 B: Haze変調の数理

Precision変調関数の導出：

$$
\beta(\text{Haze}) = \frac{\beta_{\max}}{1 + \alpha \cdot \text{Haze}}
$$

境界条件:
- $\text{Haze} = 0$ → $\beta = \beta_{\max}$ (最高精度)
- $\text{Haze} = 1$ → $\beta = \beta_{\max} / (1 + \alpha)$ (最低精度)

感度パラメータ $\alpha$ の効果:
- $\alpha$ 大 → Hazeの影響が強い
- $\alpha$ 小 → Hazeの影響が弱い

---

**END OF DOCUMENT**
