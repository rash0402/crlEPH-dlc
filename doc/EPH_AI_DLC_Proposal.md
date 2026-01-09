---
title: "Emergent Perceptual Haze (EPH)"
type: Research_Proposal
status: "🟢 Finalized for Implementation (v5.5 Compatible)"
version: "5.5.0"
date: "2025-12-18"
date_modified: "2026-01-09"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
---

# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
>
> 不確実性を **知覚解像度（Perceptual Precision）** の可変設計として扱う Active Inference の工学的拡張アーキテクチャ **EPH (Emergent Perceptual Haze)** を提案する。本手法は、予測信頼性に応じて知覚・注意の鋭さを連続的に変調することで、単体ロボットおよび群知能システムにおける停止・振動・分断といった不確実性起因の行動破綻を構造的に抑制する。

## 要旨 (Abstract)

### 背景 (Background)

公共空間におけるサービスロボットの実運用では、安全性と社会的受容性の両立が不可欠である。しかし、混雑環境では他者行動の予測困難性が増大し、従来のモデル予測制御（MPC）や強化学習（RL）は過度に保守的となり、不自然な回避や**立ち往生（Freezing）**を引き起こす。これは、不確実性を行動生成を調停する能動的な設計変数として扱えていないことに起因する。

### 目的 (Objective)

本研究の目的は、自由エネルギー原理（FEP）に基づき、不確実性を **Haze（推論的不確実性のプロキシ）** として定量化し、それを知覚表現の解像度（Precision）制御に結び付けることで、混雑環境下でも安定かつ滑らかな移動を実現することである。

### 学術的新規性 (Academic Novelty)

本研究の学術的新規性は、不確実性を単なるノイズや外乱として扱うのではなく、**知覚解像度を調停する設計変数として明示的に導入した点**にある。自由エネルギー原理において用いられる Precision の概念は、従来、予測誤差の信頼性重みとして解釈されてきたが、本研究ではこれを工学的に再整理し、「推論に用いる Precision」と「知覚表現の鋭さを制御するパラメータ」を明確に分離する。

v5.5 では特に、**Action-Dependent Uncertainty VAE (Pattern D)** を導入し、エンコーダ（u依存）とデコーダ（u条件付き）を統合することで、不確実性が行動に依存して変動する因果構造（Counterfactual Haze）を実現する。SPM 自体は既存研究においても用いられてきた表現であるが、本研究の新規性は、Haze に基づく解像度変調と統合することで、不確実性と知覚構造、行動生成を単一の因果連鎖として結び付けた点にある。

### 手法 (Methods)

提案手法 **EPH** は、以下の構成要素から成る：
1. **知覚表現**: 16x16, 210度FOVの自己中心的 SPM（Saliency Polar Map）。
2. **Action-Dependent Uncertainty VAE (Pattern D)**: エンコーダで潜在分布を推定（u依存）、デコーダで将来SPM予測（u条件付き）。
3. **Haze の定義と因果的更新**: 行動依存の潜在分散から Haze を算出 ($H[k] = \text{Agg}(\sigma_z^2(y[k], u[k]))$)、循環依存は1step遅延で回避。
4. **知覚解像度制御**: Haze に基づき SPM の soft 集約パラメータ $\beta$ を変調 ($\beta[k] = \beta^{\min} + (\beta^{\max} - \beta^{\min}) \cdot s(1/(H[k]+\epsilon))$)。
5. **勾配ベース行動生成**: 自由エネルギー $F$ を $u$ で偏微分し、勾配降下により最適化。

## 1. 序論 (Introduction)

### 1.1 背景と動機

ロボットが真に社会へ溶け込むためには、人間のように不確実な状況を「やり過ごす」能力が必要である。現状の MPC は「確信が持てない状況」で行動をゼロ（停止）にするか、あるいは不安定な振動を繰り返す。これは実運用における致命的な信頼性低下を招いている。

### 1.2 研究のギャップ

- **1.2.1 SOTAにおける問題点**: 従来の不確実性処理は主にノイズ除去に限定されており、不確実性の度合いに応じて「知覚の細かさ」自体を調整する仕組みを持っていない。
- **1.2.2 概念的・理論的ギャップ**: 不確実性を行動戦略の中核変数として扱い、知覚解像度と行動生成を統一的に制御する理論枠組みが不足している。

## 2. 理論的基盤 (Theoretical Foundation)

### 2.1 問題の定式化

ロボットの状態を $\boldsymbol{x}[k]$、入力を $\boldsymbol{u}[k]$ とし、2 次遅れ系としてモデル化する。目標位置への到達と衝突回避を両立する自由エネルギー最小化問題を解く。

$$M \ddot{\boldsymbol{x}}[k] + D \dot{\boldsymbol{x}}[k] = \boldsymbol{u}[k]$$

### 2.2 SPM 採用の理論的必然性

SPM（Saliency Polar Map）は、対数スケール極座標により、近傍情報を詳細に、遠方を粗く表現する。この構造は、距離に応じた不確実性の増加を自然に内包しており、FEP における「注意（Attention）」の空間的実装として最適である。

### 2.3 Haze の定義と因果的更新 (v5.5)

Haze は、ロボットが内部世界モデル(VAE)に基づいて形成する**不確実性の操作的代理量**として定義される。本研究では、VAE の潜在分散を用いて以下のように定義する：

$$H[k] = \frac{1}{D} \sum_{d=1}^D \sigma_{z,d}^2(\boldsymbol{y}[k-1], \boldsymbol{u}[k-1])$$

ここで、$D$ は潜在次元数であり、**前時刻 $k-1$ の潜在分散**を用いることで、同一時刻内での循環依存を回避している。この因果順序により：

$$
\boldsymbol{y}[k] \;\rightarrow\; \boldsymbol{\sigma}_z^2[k] \;\rightarrow\; H[k+1] \;\rightarrow\; \beta[k+1] \;\rightarrow\; \boldsymbol{y}[k+1]
$$

時刻 $k$ の知覚表現は時刻 $k+1$ の解像度制御にのみ影響し、同一時刻内での自己参照は生じない。初期時刻における $H[0]$ は、事前設定値またはウォームアップ期間の平均値として与えられる。

### 2.4 Precision の役割分離 (v5.5)

v5.5 では Precision の役割を以下のように分離した：
1. **推論 Precision (Inference Precision)**: 自由エネルギー項の重み（固定）。
2. **知覚解像度パラメータ (Perceptual Resolution Parameter $\beta$)**: SPM の鋭さを制御する変数（可変）。

知覚解像度パラメータ $\beta$ は、Haze の逆数に基づき以下のように変調される：

$$ \beta[k] = \beta^{\min} + (\beta^{\max} - \beta^{\min}) \cdot s\left(\frac{1}{H[k] + \epsilon}\right) $$

ここで $s(\cdot)$ はシグモイド関数、$\epsilon$ は数値安定化定数である。Haze が高い（不確実性大）時は $\beta$ が小さく（知覚が平均化）、Haze が低い（確信度高）時は $\beta$ が大きく（知覚が鋭敏化）なる。

## 3. 手法 (Methodology)

### 3.1 知覚表現：SPM の 16x16 / 3 チャネル構成

- **視野角**: 前方 210度。背後 150度は死角。
- **解像度**: $16 \times 16$。
- **チャネル**: (1) 占有密度、(2) 近接顕著性、(3) 動的衝突危険性。

#### 3.1.1 ch2：近接顕著性（Proximity Saliency）
表面距離 $d^{surf}$ を Haze 適応型 softmin により集約。不確実性が高い場合（$\beta$ 小）、距離情報は平均化され、局所的な障害物への過剰反応が抑制される。

### 3.2 世界モデル：Action-Dependent Uncertainty VAE (Pattern D)

本研究では、世界モデルとして **Action-Dependent Uncertainty VAE (Pattern D)** を採用する。この構造の特徴は、エンコーダが行動に依存する点にある。

#### 3.2.1 VAE の構造

| 構成要素 | 入力 | 出力 |
|---------|------|------|
| **エンコーダ** | $(\boldsymbol{y}[k], \boldsymbol{u}[k])$ | $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ |
| **デコーダ** | $(\boldsymbol{z}, \boldsymbol{u}[k])$ | $\hat{\boldsymbol{y}}[k+1]$ |

**エンコーダ**は現在の SPM と行動から潜在分布 $q_\phi(\boldsymbol{z}[k] \mid \boldsymbol{y}[k], \boldsymbol{u}[k]) = \mathcal{N}(\boldsymbol{\mu}_z, \mathrm{diag}(\boldsymbol{\sigma}_z^2))$ を推定する。重要なのは、エンコーダが $\boldsymbol{u}$ に依存するため、潜在分散 $\boldsymbol{\sigma}_z^2$（Haze の源泉）が行動によって変動する点である。

**デコーダ**は潜在変数と操作指令値から将来 SPM を予測する：$\hat{\boldsymbol{y}}[k+1] = f_{\text{dec}}(\boldsymbol{z}[k], \boldsymbol{u}[k])$。

#### 3.2.2 Pattern D の利点

- **行動依存の不確実性**: 「急加速は危険（高Haze）」といった因果関係を表現可能
- **負の相関問題の解決**: 不確実性の高い状況＝高Hazeという自然な相関が期待される
- **Freezing 抑制メカニズム**: 危険行動に対するHazeペナルティとして機能

### 3.3 群知能への拡張 (Swarm Intelligence Extension)

EPH は単体ロボットに加え、群知能システムへも拡張される。
各エージェントは局所的な運動予測誤差から **局所 Haze** を推定し、それに基づいて分離・結合行動の鋭さを変調する。これにより、局所的な「迷い」が集団全体へ伝播し、適応的な渋滞解消や分断回避が創発する。

### 3.4 行動生成：Pattern D に基づく勾配降下

行動生成は、予測された将来 SPM に基づく自由エネルギーを最小化する問題として定式化される：

$$\boldsymbol{u}^*[k] = \arg\min_{\boldsymbol{u}} \mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k], \boldsymbol{u})}\left[ F[\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})] \right]$$

**Pattern D の特徴**は、期待値が $\boldsymbol{u}$ に依存する $q(\boldsymbol{z} \mid \boldsymbol{y}[k], \boldsymbol{u})$ に関して取られる点である。勾配計算には Reparameterization Trick を用いる。

自由エネルギー $F$ は以下で定義される：
$$F[\hat{\boldsymbol{y}}] = \|\hat{\boldsymbol{x}}[k+1] - \boldsymbol{x}_g\|^2 + \lambda \sum_{m,n} \phi(\hat{\boldsymbol{y}}_{m,n})$$

勾配降下により最適化：
$$\boldsymbol{u}[k] \leftarrow \boldsymbol{u}[k] - \eta \frac{\partial}{\partial \boldsymbol{u}} \mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y})}[F]$$

Julia の `ForwardDiff` による自動微分を用いて、デコーダを通じた勾配 $\partial F / \partial \boldsymbol{u}$ を効率的に計算する。

## 4. 検証戦略 (Verification Strategy)

- **タスク**: トーラス世界でのスクランブル交差点横断（4グループ色分け）。
- **評価指標**: Success Rate, Collision Rate, Freezing Rate, Jerk, 最小 TTC。
- **アブレーション**: 固定 $\beta$ (Baseline) との比較による適応 $\beta(H)$ の優位性実証。
- **拡張検証**: 群知能指標（Throughput, 渋滞指標, 分断率）による評価。

## 5. 関連研究 (Related Work)

Friston(2010) の FEP を知覚解像度制御へと拡張し、Trautman et al.(2015) が指摘した Freezing 問題を設計原理レベルで抑制する。v5.5 では特に、以下の点で既存研究を統合・拡張する：

- **不確実性のモデル化**: Kendall & Gal (2017) の不確実性分類に基づき、Haze を操作的代理量として定義
- **世界モデル構造**: Dreamer, PlaNet 等と同様の Action-Conditioned VAE (Pattern B) を採用
- **知覚解像度制御**: 不確実性と知覚構造、行動生成を単一の因果連鎖として統合した点が新規性

## 6. 議論と結論 (Discussion & Conclusion)

不確実性が高い時は知覚を平均化して行動を安定させ、低い時は鋭い知覚で迅速に回避するという **不確実性適応型知覚解像度制御** を確立した。HRI、群制御、AI Safety への一般化が期待される。

**Keywords**: Free Energy Principle, Active Inference, Emergent Perceptual Haze, Precision Control, Social Navigation, Swarm Intelligence