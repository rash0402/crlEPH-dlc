---
title: "Emergent Perceptual Haze (EPH)" type: Research_Proposal 
status: "🟢 Finalized for Implementation" 
version: "5.1.0"
date: "2025-12-18"
date_modified: "2025-12-19"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
---



# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
> 
> 混雑環境におけるロボットナビゲーションの**立ち往生（Freezing Robot Problem）という課題を、不確実性を知覚解像度（Precision）**へ適応的に変換するFEPベースの統合アーキテクチャ EPH により解決し、固定Precisionの従来手法と比較して Freezing 発生率を 20% 以上低減する。

## 要旨 (Abstract)

### 背景 (Background)

公共空間におけるサービスロボットの実運用では、安全性と社会的受容性の両立が不可欠である。しかし、混雑環境では他者行動の予測困難性が増大し、従来のモデル予測制御（MPC）や強化学習（RL）は過度に保守的となり、不自然な回避や**立ち往生（Freezing）**を引き起こす。これは、不確実性を行動生成を調停する能動的な設計変数として扱えていないことに起因する。

### 目的 (Objective)

本研究の目的は、自由エネルギー原理（FEP）に基づき、不確実性を **Haze（推論的不確実性のプロキシ）** として定量化し、それを知覚表現の解像度（Precision）制御に結び付けることで、混雑環境下でも安定かつ滑らかな移動を実現することである。

### 学術的新規性 (Academic Novelty)

本研究の新規性は、FEPにおける Precision 制御を、単なる予測誤差の重み付けではなく、**自己中心 SPM（対数スケール極座標）における適応的知覚解像度制御**として実装した点にある。不確実性が高い場合には知覚をあえて平均化し、確信度が高い場合には鋭敏化するという「認知的な柔軟性」を付与する。

### 手法 (Methods)

提案手法 **EPH** は、(i) 観測の SPM 変換（16x16, 210度FOV）、(ii) VAE 世界モデルによる将来予測と Haze（予測分散）推定、(iii) Haze に基づく Precision 導出、(iv) Precision による SPM soft 集約パラメータ $\beta(H)$ の変調、(v) 自由エネルギー最小化（Julia/ForwardDiff）に基づく行動生成の 5 段階で構成される。

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

### 2.3 Haze の概念的位置付け

Haze は、ロボットが内部世界モデルに基づいて形成する**認識論的不確実性（epistemic uncertainty）の代理量**として定義される。「現在の観測と内部モデルのもとで、将来状態をどの程度まで信頼して予測できないか」を表す内部的指標である。

### 2.4 Haze の学術的意義

#### 2.4.1 数理学的観点：不確実性の構造化と情報幾何

Haze は、潜在空間分散 $\boldsymbol{\sigma}_z^2$ という高次元量を単一のスカラー指標へ集約し、さらにそれを soft 集約パラメータ $\beta$ へ射影することで、**不確実性 → 知覚構造の変形 → 行動生成** という写像を微分可能に連鎖させた点に新規性がある。これは情報幾何学における Fisher 情報量と知覚解像度の接続という課題への具体的実装を与える。

#### 2.4.2 制御工学的観点：適応的 Precision と系の安定性

本研究の変調は、**メタ適応制御（meta-adaptive control）** の一形態である。知覚表現の解像度を制御することで、間接的に行動生成の保守性・積極性を連続的に調節する。これは explorative / exploitative 行動バランスを「認知的注意の配分問題」として再定式化したものである。

#### 2.4.3 ロボット研究的観点：社会的受容性と実装可能性

Freezing を「高不確実性下で過剰な知覚解像度により勾配が特異化する現象」として因果的に説明し、Haze による適応的解像度制御で構造的に抑制可能であることを示す。

#### 2.4.4 生物学的観点：予測符号化と注意の神経基盤

SPM における $\beta$ 変調は、Precision を知覚フィルタの鋭さ（softmin/max の温度）として空間的に実装した点で、生物の注意機構（上丘の saliency map 変調等）の計算論的モデルとしての新規性を持つ。

## 3. 手法 (Methodology)

### 3.1 知覚表現：SPM の 16x16 / 3 チャネル構成

- **視野角**: 前方 210度。背後 150度は死角。
    
- **解像度**: $16 \times 16$。
    
- **チャネル**: (1) 占有密度、(2) 近接顕著性、(3) 動的衝突危険性。
    

#### 3.3.2 ch2：近接顕著性（Proximity Saliency）

表面距離 $d^{surf}$ を Haze 適応型 softmin により集約。

$$\bar{r}_{m,n}[k] = -\frac{1}{\beta_r[k,m,n]} \log \sum_{i \in \mathcal{I}_{m,n}[k]} \exp(-\beta_r[k,m,n] d_i^{surf}[k])$$

### 3.2 Haze の厳密な定義と VAE

VAE の潜在分散 $\boldsymbol{\sigma}_z^2[k]$ を予測の不確実性とみなし、Haze を定義する。

$$H[k] = \mathrm{Agg}\big(\boldsymbol{\sigma}_z^2[k]\big)$$

Precision $\Pi[k] = 1/(H[k] + \epsilon)$ は、SPM の $\beta$ 変調および制御入力生成の重みとなる。

### 3.3 行動生成：メタ評価ベース FEP

指定方向（東西南北）へのスムーズなフローを **Prior Preference** $P(y)$ として定義し、Julia の `ForwardDiff` で $u = \text{clamp}(u, -u_{max}, u_{max})$ を算出する。

## 4. 検証戦略 (Verification Strategy)

- **タスク**: トーラス世界でのスクランブル交差点横断（4グループ色分け）。
    
- **評価指標**: Success Rate, Collision Rate, Freezing Rate, Jerk, 最小 TTC。
    
- **アブレーション**: 固定 $\beta$ (Baseline) との比較による適応 $\beta(H)$ の優位性実証。
    

## 5. 関連研究 (Related Work)

Friston(2010) の FEP を知覚解像度制御へと拡張し、Trautman et al.(2015) が指摘した Freezing 問題を設計原理レベルで抑制する。

## 6. 議論と結論 (Discussion & Conclusion)

不確実性が高い時は知覚を平均化して行動を安定させ、低い時は鋭い知覚で迅速に回避するという **不確実性適応型知覚解像度制御** を確立した。HRI、群制御、AI Safety への一般化が期待される。

**Keywords**: Free Energy Principle, Active Inference, Emergent Perceptual Haze, Precision Control, Social Navigation