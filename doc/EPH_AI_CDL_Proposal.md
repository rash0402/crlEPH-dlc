---
title: "Emergent Perceptual Haze (EPH)"
type: Research_Proposal
status: "🟢 Finalized for Implementation (v5.2 Compatible)"
version: "5.2.0"
date: "2025-12-18"
date_modified: "2026-01-08"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
---

# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
> 
> 混雑環境におけるロボットナビゲーションの**立ち往生（Freezing Robot Problem）**という課題を、不確実性（Haze）を知覚解像度（Precision）へ適応的に変換するFEPベースの統合アーキテクチャ EPH により解決し、固定Precisionの従来手法と比較して Freezing 発生率を 20% 以上低減する。さらに、本原理は群知能（Swarm Intelligence）における局所的な鋭さ変調により、渋滞や分断を抑制する一般則へと拡張される。

## 要旨 (Abstract)

### 背景 (Background)

公共空間におけるサービスロボットの実運用では、安全性と社会的受容性の両立が不可欠である。しかし、混雑環境では他者行動の予測困難性が増大し、従来のモデル予測制御（MPC）や強化学習（RL）は過度に保守的となり、不自然な回避や**立ち往生（Freezing）**を引き起こす。これは、不確実性を行動生成を調停する能動的な設計変数として扱えていないことに起因する。

### 目的 (Objective)

本研究の目的は、自由エネルギー原理（FEP）に基づき、不確実性を **Haze（推論的不確実性のプロキシ）** として定量化し、それを知覚表現の解像度（Precision）制御に結び付けることで、混雑環境下でも安定かつ滑らかな移動を実現することである。

### 学術的新規性 (Academic Novelty)

本研究の新規性は、FEPにおける Precision 制御を、単なる予測誤差の重み付けではなく、**自己中心 SPM（対数スケール極座標）における適応的知覚解像度制御**として実装した点にある。
v5.2 では特に、Precision を **(1) 推論用（固定・重み）** と **(2) 知覚用（可変・解像度）** に明確に分離し、Haze に基づく $\beta$ 変調によって知覚構造そのものを適応的に変形する設計とした。

### 手法 (Methods)

提案手法 **EPH** は、以下の5段階で構成される：
1. **観測の SPM 変換**: 16x16, 210度FOVの自己中心表現。
2. **VAE 世界モデル**: 将来予測と Haze（潜在分散の算術平均）の推定。
3. **因果的更新**: 循環依存を避けるため、時刻 $k$ の Haze を時刻 $k+1$ の制御に用いる ($H[k] \to \beta[k+1]$)。
4. **知覚解像度制御**: Haze に基づき SPM の soft 集約パラメータ $\beta$ を変調。
5. **自由エネルギー最小化**: 勾配法による行動生成。

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

### 2.3 Haze の厳密な定義 (v5.2)

Haze は、ロボットが内部世界モデル(VAE)に基づいて形成する**認識論的不確実性（epistemic uncertainty）の代理量**として定義される。

$$H[k] = \mathrm{Agg}(\boldsymbol{\sigma}_z^2[k]) = \frac{1}{D} \sum_{d=1}^D \sigma_{z,d}^2[k]$$

ここで、$\mathrm{Agg}$ には**算術平均**を採用し、潜在空間全体の平均的な予測不確実性を捉える。

### 2.4 Precision の役割分離 (v5.2)

v5.2 では Precision の役割を以下のように分離した：
1. **推論 Precision (Inference Precision)**: 自由エネルギー項の重み（固定）。
2. **知覚解像度パラメータ (Perceptual Resolution Parameter $\beta$)**: SPM の鋭さを制御する変数（可変）。

$$ \beta[k] = \beta^{\min} + (\beta^{\max} - \beta^{\min}) \cdot s\left(\frac{1}{H[k] + \epsilon}\right) $$

## 3. 手法 (Methodology)

### 3.1 知覚表現：SPM の 16x16 / 3 チャネル構成

- **視野角**: 前方 210度。背後 150度は死角。
- **解像度**: $16 \times 16$。
- **チャネル**: (1) 占有密度、(2) 近接顕著性、(3) 動的衝突危険性。

#### 3.3.2 ch2：近接顕著性（Proximity Saliency）
表面距離 $d^{surf}$ を Haze 適応型 softmin により集約。不確実性が高い場合（$\beta$ 小）、距離情報は平均化され、局所的な障害物への過剰反応が抑制される。

### 3.2 群知能への拡張 (Swarm Intelligence Extension)

EPH は単体ロボットに加え、群知能システムへも拡張される。
各エージェントは局所的な運動予測誤差から **局所 Haze** を推定し、それに基づいて分離・結合行動の鋭さを変調する。これにより、局所的な「迷い」が集団全体へ伝播し、適応的な渋滞解消や分断回避が創発する。

### 3.3 行動生成：メタ評価ベース FEP

指定方向（東西南北）へのスムーズなフローを **Prior Preference** $P(y)$ として定義し、Julia の `ForwardDiff` で勾配降下を行う。
$$\boldsymbol{u}[k] = -\eta \nabla_{\boldsymbol{x}} F[k]$$

## 4. 検証戦略 (Verification Strategy)

- **タスク**: トーラス世界でのスクランブル交差点横断（4グループ色分け）。
- **評価指標**: Success Rate, Collision Rate, Freezing Rate, Jerk, 最小 TTC。
- **アブレーション**: 固定 $\beta$ (Baseline) との比較による適応 $\beta(H)$ の優位性実証。
- **拡張検証**: 群知能指標（Throughput, 渋滞指標, 分断率）による評価。

## 5. 関連研究 (Related Work)

Friston(2010) の FEP を知覚解像度制御へと拡張し、Trautman et al.(2015) が指摘した Freezing 問題を設計原理レベルで抑制する。v5.2 では特に、Kendall & Gal (2017) の不確実性分類に基づき、Haze を aleatoric uncertainty の操作的プロキシとして位置付けた。

## 6. 議論と結論 (Discussion & Conclusion)

不確実性が高い時は知覚を平均化して行動を安定させ、低い時は鋭い知覚で迅速に回避するという **不確実性適応型知覚解像度制御** を確立した。HRI、群制御、AI Safety への一般化が期待される。

**Keywords**: Free Energy Principle, Active Inference, Emergent Perceptual Haze, Precision Control, Social Navigation, Swarm Intelligence