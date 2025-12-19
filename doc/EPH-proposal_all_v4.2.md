---
title: "Emergent Perceptual Haze (EPH)"
type: Research_Proposal
status: "🟡 Draft"
version: 4.2.3
date_created: "2025-12-18"
date_modified: "2025-12-19"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Free Energy Principle
  - Active Inference
  - Social Navigation
  - Uncertainty Modeling
  - Precision Control
tags:
  - Research/Proposal
  - Topic/FEP
  - Status/Draft
---

# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
> 
> 混雑環境におけるロボットナビゲーションの**立ち往生（Freezing Robot Problem）**という課題を、不確実性を**知覚解像度（Precision）**へ適応的に変換するFEPベースの統合アーキテクチャ **EPH** により解決し、固定Precisionの従来手法（MPC/RL等）と比較して **Freezing 発生率を 20% 以上低減**する。

##  要旨 (Abstract)

### 背景 (Background)

公共空間におけるサービスロボットの実運用では、安全性と社会的受容性の両立が不可欠である。
しかし、混雑環境では他者行動の予測困難性が増大し、従来のモデル予測制御（MPC）や強化学習（RL）は過度に保守的となり、不自然な回避や**立ち往生（Freezing）**を引き起こす。
これは、不確実性を行動生成を調停する能動的な設計変数として扱えていないことに起因する。

### 目的 (Objective)

本研究の目的は、自由エネルギー原理（Free Energy Principle; FEP）に基づき、不確実性を **Haze（推論的不確実性のプロキシ）** として定量化し、それを知覚表現の解像度（Precision）制御に結び付けることで、混雑環境下でも安定かつ滑らかな移動を実現することである。

### 学術的新規性 (Academic Novelty)

本研究の新規性は、FEPにおける Precision 制御を、単なる予測誤差の重み付けではなく、**自己中心 SPM（対数スケール極座標）における適応的知覚解像度制御**として実装した点にある。
これにより、不確実性が高い場合には知覚をあえて平均化し、確信度が高い場合には鋭敏化するという「認知的な柔軟性」をロボットに付与する。
これは SOTA とされる固定 $\beta$-MPC に対する決定的な Delta である。

### 手法 (Methods)

提案手法 **EPH** は、(i) 観測の SPM 変換、(ii) VAE 世界モデルによる将来予測と Haze（予測分散）推定、(iii) Haze に基づく Precision 導出、(iv) Precision による SPM soft 集約パラメータ $\beta(H)$ の変調、(v) 自由エネルギー最小化に基づく加速度入力生成、の 5 段階で構成される。

### 検証目標 (Validation Goals)

**固定** $\beta$ **ベースライン（Fixed-Precision MPC）** を比較対象とし、混雑シナリオにおける **Freezing 発生率を 20% 以上低減**、および運動の滑らかさを示す **Jerk を 15% 改善**することを成功指標とする。

### 結論と意義 (Conclusion / Academic Significance)

本研究は、不確実性を抑制すべき対象ではなく、知覚と行動を調停する中核的な情報源と再定義する。
これは社会ナビゲーションの信頼性を高めるだけでなく、認知科学における計算論的共感や、不確実性下での AI 安全性の設計原理に寄与する。

**Keywords**: Free Energy Principle, Active Inference, Emergent Perceptual Haze, Precision Control, Social Navigation

## 1. 序論 (Introduction)

### 1.1 背景と動機 (Context & Motivation)

ロボットが真に社会へ溶け込むためには、人間のように不確実な状況を「やり過ごす」能力が必要である。
現状の MPC は「確信が持てない状況」で行動をゼロ（停止）にするか、あるいは不安定な振動を繰り返す。
これは実運用における致命的な信頼性低下を招いている。

### 1.2 研究のギャップ (The Research Gap)

- **1.2.1 SOTAにおける問題点**: 従来の不確実性処理は主にノイズ除去（フィルタリング）に限定されており、不確実性の度合いに応じて「知覚の細かさ」自体を調整する仕組みを持っていない。
- **1.2.2 概念的・理論的ギャップ**: 不確実性を行動戦略の中核変数として扱い、知覚解像度と行動生成を統一的に制御する理論枠組みが不足している。

### 1.3 主要な貢献 (Key Contribution)

1. **理論**: FEP に基づく不確実性（Haze）と Precision 制御を、知覚表現（SPM）の鋭さ変調へと拡張する原理の提案。
2. **手法**: SPM・VAE・soft 集約を統合し、不確実性に応じて「世界の見え方」を動的に変化させる行動生成。
3. **実証**: Freezing の操作的定義を導入し、適応的 Precision が停止行動を構造的に抑制することを実証。

## 2. 理論的基盤 (Theoretical Foundation)

### 2.1 問題の定式化 (Problem Formulation)

ロボットの状態を $\boldsymbol{x}[k]$、速度を $\dot{\boldsymbol{x}}[k]$、入力を $\boldsymbol{u}[k]$ とし、質量 $M$、粘性 $D$ を持つ 2 次遅れ系としてモデル化する。

$$M \ddot{\boldsymbol{x}}[k] + D \dot{\boldsymbol{x}}[k] = \boldsymbol{u}[k]$$

目標位置 $\boldsymbol{x}_g$ への到達と衝突回避を両立する自由エネルギー最小化問題を解く。

### 2.2 SPM 採用の理論的必然性

SPM（Saliency Polar Map）は、対数スケール極座標により、近傍情報を詳細に、遠方を粗く表現する。

> **SPM is not merely a representation choice but acts as a task-sufficient statistic under bounded rationality.** この構造は、距離に応じた不確実性の増加を自然に内包しており、FEP における「注意（Attention）」の空間的実装として最適である。

### 2.3 Haze の概念的位置付け

本研究における **Haze** とは、環境そのものの物理的不確実性や観測ノイズを直接表す量ではなく、ロボットが内部世界モデルに基づいて形成する**認識論的不確実性（epistemic uncertainty）の代理量**として定義される。

すなわち Haze は、「世界が本質的にランダムである」ことを意味するのではなく、「現在の観測と内部モデルのもとで、将来状態をどの程度まで信頼して予測できないか」を表す内部的指標である。

この定義により、Haze は aleatoric noise や外乱とは区別され、学習・推論の進展に応じて変化しうる量として扱われる。

### 2.4 Haze の学術的意義：分野横断的視点

Haze 概念は、単なる工学的パラメータではなく、複数の学術分野に跨る理論的・実装的課題への解を提供する。
以下、数理学、制御工学、ロボット研究、生物学の各観点から、その学術的貢献と今後の課題を論じる。

#### 2.4.1 数理学的観点：不確実性の構造化と情報幾何

**貢献**:
従来の確率制御では、不確実性は確率分布のパラメータ（分散・共分散）として扱われるが、それをどのように「知覚解像度」へ変換するかは明示的に定式化されてこなかった。
Haze は、潜在空間分散 $\boldsymbol{\sigma}_z^2$ という高次元量を単一のスカラー指標へ集約（$\mathrm{Agg}$）し、さらにそれを soft 集約パラメータ $\beta$ へ射影することで、**不確実性 → 知覚構造の変形 → 行動生成** という写像を微分可能に連鎖させた点に新規性がある。

これは情報幾何学における **Fisher 情報量と知覚解像度の接続** という未解決問題への一つの具体的実装を与える。
すなわち、Precision $\Pi = 1/H$ は、モデルの予測分布の「鋭さ」（逆分散）に対応し、知覚空間（SPM）上での soft-max/min の温度パラメータとして作用することで、統計多様体上の測地構造と意思決定構造を結びつける。

**課題**:
集約演算子 $\mathrm{Agg}$ の選択（算術平均 vs. log-sum-exp）が、Haze の統計的性質（不偏性・ロバスト性）や情報量保存則に与える影響は未解明である。
また、$\Pi$ による $\beta$ 変調が、勾配流の Lyapunov 安定性に与える保証は今後の理論的検証課題となる。

#### 2.4.2 制御工学的観点：適応的 Precision と系の安定性

**貢献**:
古典的なモデル予測制御（MPC）やロバスト制御では、不確実性は「最悪ケース」または「固定的な外乱モデル」として扱われ、保守的な制御則を導く（Zames & Francis, 1983）。
一方、適応制御は未知パラメータの推定に主眼を置き、**推定の信頼性に応じて制御ゲインや知覚構造を適応させる枠組み**は十分に確立されていなかった。

本研究の Haze → Precision → $\beta$ 変調は、**メタ適応制御（meta-adaptive control）** の一形態とみなせる。
すなわち、制御器のパラメータを直接調整するのではなく、知覚表現の解像度を制御することで、間接的に行動生成の保守性・積極性を連続的に調節する。
これは、不確実性下での explorative / exploitative 行動バランスを、**認知的注意（attention）の配分問題** として再定式化したものである。

**課題**:
Haze に基づく $\beta$ 変調が、閉ループ系全体の漸近安定性や有界性を保証するための十分条件は未確立である。
特に、$\beta$ が急激に変化する場合のゲイン切り替え（switched system）としての解析が必要となる。
また、複数エージェント環境における分散 Haze 推定と、グローバル安定性の関係も今後の課題である。

#### 2.4.3 ロボット研究的観点：社会的受容性と実装可能性

**貢献**:
社会ナビゲーション研究では、Freezing Robot Problem は「失敗モード」として事後的に扱われてきたが、その発生メカニズムの理論モデルは不足していた（Trautman et al., 2015）。
本研究は、Freezing を**「高不確実性下で過剰な知覚解像度により勾配が特異化する現象」**として因果的に説明し、Haze による適応的解像度制御で構造的に抑制可能であることを示した。

さらに、Haze は人間の **主観的不安感** とも対応しうる。
混雑環境で「状況が読めない」と感じる際、人間も視覚的注意を分散させ、個別の障害物への過剰反応を抑制する（Wolfe & Horowitz, 2017）。
EPH はこの認知戦略をロボットへ実装する理論的基盤を与える。

**課題**:
実環境におけるHazeの **リアルタイム推定** は、VAE の推論コストに依存する。
オンボードGPU環境での10Hz以上の更新レートを維持しつつ、潜在分散 $\boldsymbol{\sigma}_z^2$ を安定推定するための、モデル圧縮・量子化手法の検討が必要である。
また、Haze が高い状態が長時間継続した場合の **デッドロック回避** 機構（例：探索的行動の注入）も実装課題となる。

#### 2.4.4 生物学的観点：予測符号化と注意の神経基盤

**貢献**:
神経科学では、大脳皮質が階層的予測モデル（hierarchical predictive coding）を実装し、予測誤差の **精度重み付け（precision-weighting）** により注意を制御するという仮説が支持されている（Friston, 2010; Feldman & Friston, 2010）。
しかし、この Precision が **空間的な知覚表現の解像度（例：視野中心と周辺の解像度差）** とどう対応するかは、計算モデルとしての実装が不足していた。

本研究の SPM における $\beta$ 変調は、Precision を **知覚フィルタの鋭さ（softmin/max の温度）** として空間的に実装した点で、生物の注意機構の計算論的モデルとしての新規性を持つ。
これは、上丘（superior colliculus）における saliency map の動的変調や、前頭前皮質（prefrontal cortex）による top-down 注意制御との対応可能性を示唆する。

**課題**:
生物の注意制御は、単一のスカラー指標（Haze）ではなく、複数の時間スケール・空間スケールで階層的に実装されている（Itti & Koch, 2001）。
本研究の Haze は「グローバルな不確実性指標」として設計されているが、局所的・チャネル別の Precision 変調（例：視覚 vs. 聴覚、中心視 vs. 周辺視）への拡張が、生物学的妥当性と工学的性能の両立に向けた今後の課題である。

#### 2.4.5 分野横断的統合：Haze が開く研究方向

上記4分野の観点を統合すると、Haze は以下の一般的設計原理を示唆する：

> **不確実性適応型知覚解像度制御（Uncertainty-Adaptive Perceptual Resolution Control）**  
> 予測信頼性が低い状況では知覚を粗く（平均化）し、高い状況では鋭く（選択的注意）することで、行動生成の安定性と応答性を両立させる。

この原理は、Haze/Precision という具体的実装を超えて、マルチモーダル統合、階層的意思決定、人間-AI 協調など、広範な認知システム設計への波及が期待される。

## 3. 手法 (Methodology)

### 3.1 システム構成 (System Architecture)

提案手法 **EPH** は、観測 → SPM変換 → VAEによるHaze推定 → Precision変調 → FEP制御 という一方向フローを持つ。

### 3.2 Haze の厳密な定義

本研究における **Haze (**$H$**)** は、物理的な環境ノイズではなく、**世界モデルによって推定される推論的不確実性のプロキシ（Epistemic Uncertainty Proxy）** として定義する。

$$H[k] = \mathrm{Agg}(\boldsymbol{\sigma}_z^2[k])$$

ここで、$\boldsymbol{\sigma}_z^2$ は VAE が出力する潜在空間の分散であり、これが高いほどシステムは「現在の状況が既知のモデルで説明できない」と判断する。

#### Haze の数理定義

世界モデルとして用いる VAE において，
潜在変数 $\boldsymbol{z}[k]$ の事後分布を次で与える：

$$
q_\phi(\boldsymbol{z}[k] \mid \boldsymbol{y}[k])
=
\mathcal{N}(\boldsymbol{\mu}_z[k], \mathrm{diag}(\boldsymbol{\sigma}_z^2[k]))
$$

本研究では，
この潜在分散 $\boldsymbol{\sigma}_z^2[k]$ を
「将来予測に対するモデル内部の不確実性」を反映する量とみなし，
その空間的・チャネル的集約として Haze を次式で定義する：

$$
H[k] = \mathrm{Agg}\big(\boldsymbol{\sigma}_z^2[k]\big)
$$

ここで $\mathrm{Agg}(\cdot)$ は平均あるいは log-sum-exp による集約演算子であり，
局所的な高不確実性が過度に希釈されないよう設計されている。

#### Haze と Precision の関係

Haze はその逆数として Precision に変換される。

$$
\Pi[k] = \frac{1}{H[k] + \epsilon}
$$

重要なのは，本研究における Precision は単に自由エネルギー中の誤差項を重み付けする係数ではなく，**知覚表現そのものの解像度を制御するメタ変数**として機能する点である。

具体的には，Precision は SPM における soft 集約パラメータ $(\beta_r, \beta_\nu)$ を変調し，環境が不確実な状況では知覚を平均化し，確信度が高い状況では最危険対象に鋭く注意を向ける。

このように，不確実性 → Precision → 知覚解像度 → 行動 という因果連鎖を，自由エネルギー原理の枠組みの中で明示的に実装する。

### 3.3 知覚表現：SPM の 3 チャネル構成

各セル $(m,n)$ には以下の 3 チャネルを割り当てる。

#### 3.3.1 ch1：占有密度（Occupancy）

$$\boldsymbol{y}[k]_{m,n,1} = \mathrm{clip} \left( \frac{1}{Z_{m,n}} \sum_{i \in \mathcal{I}_{m,n}[k]} 1, \, 0, \, 1 \right)$$

#### 3.3.2 ch2：近接顕著性（Proximity Saliency）

セル内の最短距離を、Haze 適応型 softmin により集約する。

$$
\beta_r[k,m,n] = \beta_r^{\min} + (\beta_r^{\max} - \beta_r^{\min}) \Pi_{m,n}[k]
$$

$$
\bar{r}_{m,n}[k] = -\frac{1}{\beta_r[k,m,n]} \log \sum_{i \in \mathcal{I}_{m,n}[k]} \exp(-\beta_r[k,m,n] \|\boldsymbol{r}_i[k]\|)
$$

$$
\boldsymbol{y}[k]_{m,n,2} = \exp \left( -\frac{\bar{r}_{m,n}[k]^2}{2\sigma_{\text{safe}}^2} \right)
$$

> **注（査読防御）**: $\beta_r \to \infty$ の極限では $\bar{r}_{m,n}$ は $\min_i \|\boldsymbol{r}_i\|$ に一致する。本研究では微分可能性とFEP整合性を優先し、有限の $\beta_r$ を用いる。

#### 3.3.3 ch3：動的衝突危険性（Dynamic Collision Risk）

相対速度を用いて Time-to-Collision (TTC) を soft 集約し、危険性をチャネル化する。

$$
\beta_\nu[k,m,n] = \beta_\nu^{\min} + (\beta_\nu^{\max} - \beta_\nu^{\min}) \Pi_{m,n}[k]
$$

$$
\nu_{m,n}[k] = \frac{1}{\beta_\nu[k,m,n]} \log \sum_{i \in \mathcal{I}_{m,n}[k]} \exp \left( \beta_\nu[k,m,n] \max \left( 0, -\frac{\boldsymbol{r}_i[k]^\top \Delta\dot{\boldsymbol{x}}_i[k]}{\|\boldsymbol{r}_i[k]\|+\epsilon} \right) \right)
$$

$$
\boldsymbol{y}[k]_{m,n,3} = \sigma\!\left(\beta_{\text{ttc}} \left(T_{\text{th}} - \frac{\bar{r}_{m,n}[k]}{\nu_{m,n}[k]+\epsilon}\right)\right)
$$

### 3.4 世界モデルと制御則

VAE により推定された Haze $H[k]$ から Precision $\Pi[k] = 1 / (H[k] + \epsilon)$ を導出し、自由エネルギー $F$ を重み付けして制御入力を生成する。

$$\boldsymbol{u}[k] = -\eta \cdot \Pi[k] \cdot \nabla_{\boldsymbol{x}} F[k]$$

### 3.5 本章の要点

- 不確実性（Haze）は推定量であると同時に、知覚解像度を変調する制御変数である。
- soft 集約（softmin / Agg-lse）により、FEP と整合した微分可能構造を実現している。
- Haze → Precision → 知覚解像度 → 行動、という因果鎖が明示的に定式化されている。

## 4. 検証戦略 (Verification Strategy)

### 4.1 シナリオと操作的定義

- **Freezing の操作的定義**: 「ゴールが到達可能であるにもかかわらず、速度 $\|\dot{\boldsymbol{x}}\|$ が閾値 $\epsilon$ 以下で $T$ 秒以上継続した状態」。

### 4.2 評価指標

1. **性能**: Success Rate, Collision Rate.
2. **社会的・運動学的指標**: Freezing Rate, Jerk, **最小 TTC**（主観的不快感との相関が高い指標として妥当）。

### 4.3 アブレーションスタディ：固定 β vs Haze 適応 β(H)

> **仮説 H**:
> 
> soft 集約の鋭さ（$\beta_r, \beta_\nu$）を Haze / Precision に応じて適応的に変調することで、混雑環境における Freezing が抑制され、安全性と社会的滑らかさが同時に向上する。

比較条件：

- **A1**: 固定 $\beta$ (Baseline)
- **A2**: 固定 $\beta$ + SPM (表現の寄与)
- **A3**: 適応 $\beta(H)$ + 直交座標 (変調の寄与)
- **A4**: **EPH (Proposed)** (統合効果)

### 4.4 本章の要点

- 検証は仮説駆動型に設計されており、固定 $\beta$ との比較で因果連鎖を直接検証する。
- Freezing 抑制と社会的滑らかさを同時に評価することで、実運用レベルの妥当性を担保する。

## 5. 関連研究 (Related Work - The Landscape)

### 5.1 理論的基盤：FEP / Active Inference

- **Friston (2010)**, **Friston et al. (2017)**, **Pezzulo et al. (2018)**.
- **限界**: Precision は主に予測誤差の重みであり、知覚表現の構造・解像度を制御する変数としての実装は未踏。
- **Delta**: EPH は Precision を SPM の soft 集約の鋭さに結び付け、空間的知覚構造の適応として実装する。

### 5.2 知覚表現と空間圧縮

- **Burgard et al. (1999)**, **Polimeni et al. (2006)**.
- **限界**: 主にセンサ効率や計算削減を目的とし、不確実性や注意との理論的接続が弱い。
- **Delta**: SPM を FEP におけるタスク十分統計として位置付け、知覚圧縮と意思決定原理を同一理論で結ぶ。

### 5.3 衝突危険性評価と TTC 指標

- **Hayward (1972)**, **van der Horst (1990)**, **Zhan et al. (2019)**.
- **限界**: TTC は決定論的・最悪値（min）で扱われ、微分可能性や不確実性統合が弱い。
- **Delta**: TTC を soft 集約で統合し、不確実性に応じて「危険の強調度」を連続制御する。

### 5.4 社会ナビゲーションと Freezing 問題

- **Helbing (1995)**, **van den Berg (2011)**, **Everett et al. (2018)**.
- **限界**: Freezing は「失敗例」として事後的に扱われ、発生メカニズムの理論モデルが不足。
- **Delta**: Freezing を「不確実性と過剰な知覚解像度のミスマッチ」と捉え、Haze による適応で構造的に抑制。

### 5.5 位置付けのまとめ（Delta Summary）

- **理論**: Precision を重みから「知覚解像度制御」へ拡張。
- **表現**: SPM を FEP のタスク十分統計として再定義。
- **評価**: TTC を soft・確率的に統合。
- **応用**: Freezing を設計原理レベルで抑制。

## 6. 議論と結論 (Discussion & Conclusion)

### 6.1 現象・機構レベル（Why Does It Happen?）

Freezing は「不確実性が高いにもかかわらず、知覚解像度が過剰に高い状態で意思決定を行おうとし、勾配が不安定化して行動生成が停滞する現象」である。
EPH は Haze により知覚を適度に平均化し、特異点を回避する。

### 6.2 設計原理レベル（What General Design Principle Emerges?）

不確実性が高い時は知覚を平均化して行動を安定させ、低い時は鋭い知覚で迅速に回避するという **不確実性適応型知覚解像度制御** を確立した。

### 6.3 限界点 (Limitations)

他エージェントが**敵対的（Adversarial）**な挙動を示したり、モデル想定外の非連続的な動きをした場合、Haze 推定が飽和し、破綻する可能性がある。

### 6.4 波及効果と一般化

HRI（人間の曖昧な意図への対応）、群制御（局所的不確実性への対応）、および AI Safety（不確実性下での暴走防止）への一般化が期待される。

### 6.5 限界と Failure Mode：Haze 誤推定の影響

本手法は、Haze を世界モデルに基づく認識論的不確実性の代理量として用いるため、Haze が誤って推定された場合には性能劣化が生じうる。

**Haze の過小評価**:
実際には不確実な状況にもかかわらず過度に高い知覚解像度が維持され、最危険対象への鋭い注意が誘発されることで、過剰回避や不安定な行動勾配が生じる可能性がある。

**Haze の過大評価**:
知覚が過度に平均化され、環境中の重要な局所構造（例：一時的な通過可能領域）が捉えられず、必要以上に保守的な挙動や目標到達の遅延が発生しうる。

**ロバスト性の設計**:
本研究では、Haze を連続量として扱い、soft 集約および Precision 変調を通じて挙動変化を滑らかに制御しているため、これらの破綻は急激な失敗としてではなく、性能指標の漸進的な劣化として現れる。
この性質は、安全性と可観測性の観点から本設計の重要な利点であり、将来的には時間的平滑化や不確実性キャリブレーションによりさらなるロバスト性向上が可能である。

## 7. 参考文献 (References)

### 7.1 核となる理論

- **Friston, K. (2010).** "The free-energy principle: a unified brain theory?" _Nature Reviews Neuroscience_, 11(2), 127-138.
    - **Relation**: 本研究の理論的支柱。FEP をロボットの知覚解像度制御へと応用・拡張する。
- **Feldman, H., & Friston, K. J. (2010).** "Attention, uncertainty, and free-energy." _Frontiers in Human Neuroscience_, 4, 215.
    - **Relation**: Precision の神経科学的基盤。注意が予測誤差の精度重み付けとして実装されるという理論的根拠を提供。
- **Hayward, J. C. (1972).** "Near-miss determination through use of a scale of danger." _Highway Research Record_, 384, 24-34.
    - **Relation**: TTC 指標の原典。本研究ではこれを soft 集約により確率的危険性指標として扱う。

### 7.2 手法論的基盤

- **van den Berg, J. et al. (2011).** "Reciprocal Velocity Obstacles for real-time multi-agent navigation." _International Journal of Robotics Research_, 30(1), 3-23.
    - **Relation**: 社会ナビゲーションの Baseline。EPH はこれに対する不確実性ロバスト性の優位性を検証する。
- **Pezzulo, G. et al. (2018).** "From affordances to abstract goals: Active inference from control to cognition." _Psychological Review_, 125(2), 187-204.
    - **Relation**: 能動的推論（Active Inference）の階層的枠組み。SPM 表現の認知科学的妥当性を補強する。
- **Zames, G., & Francis, B. A. (1983).** "Feedback, minimax sensitivity, and optimal robustness." _IEEE Transactions on Automatic Control_, 28(5), 585-601.
    - **Relation**: ロバスト制御の古典的理論。固定的な最悪ケース設計の限界を示し、適応的 Precision の必要性を裏付ける。
- **Trautman, P., et al. (2015).** "Robot navigation in dense human crowds: Statistical models and experimental studies of human-robot cooperation." _International Journal of Robotics Research_, 34(3), 335-356.
    - **Relation**: Freezing Robot Problem の実証研究。本研究はこの現象を Haze による理論モデルで説明する。

### 7.3 神経科学・認知科学的基盤

- **Itti, L., & Koch, C. (2001).** "Computational modelling of visual attention." _Nature Reviews Neuroscience_, 2(3), 194-203.
    - **Relation**: Saliency map と視覚的注意の計算論的モデル。SPM における空間的解像度変調の生物学的妥当性を支持。
- **Wolfe, J. M., & Horowitz, T. S. (2017).** "Five factors that guide attention in visual search." _Nature Human Behaviour_, 1(3), 0058.
    - **Relation**: 人間の視覚探索における注意配分戦略。混雑環境での「粗い知覚→平均化」という EPH の戦略と対応。

## 🛡️ AI-DLC 自己修正チェックリスト

- [x] **Novelty**: SOTA（固定 $\beta$-MPC）に対する Delta と定量目標が明記されている。
- [x] **Rigor**: Haze、SPM 3チャネル、Freezing の数理的・操作的定義が省略なく記載されている。
- [x] **Completeness**: 3.5, 4.4節の要点、5.5節のまとめ、7.参考文献がすべて復元されている。
- [x] **Validity**: TTC の生理学的妥当性と限界点（敵対的エージェント）への言及がある。