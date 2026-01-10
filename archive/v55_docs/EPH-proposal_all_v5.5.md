---

title: "Emergent Perceptual Haze (EPH)"
type: Research_Proposal
status: "🟡 Draft"
version: 5.5.0
date_created: "2025-12-18"
date_modified: "2026-01-09"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Free Energy Principle
  - Active Inference
  - Social Navigation
  - Uncertainty Modeling
  - Precision Control
  - Swarm Intelligence
  - Perceptual Precision
  - Uncertainty-Adaptive Control
tags:
  - Research/Proposal
  - Topic/FEP
  - Status/Draft
---



# 研究提案書: Emergent Perceptual Haze (EPH)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
> 
> 不確実性を **知覚解像度（Perceptual Precision）** の可変設計として扱う Active Inference の工学的拡張アーキテクチャ **EPH (Emergent Perceptual Haze)** を提案する。本手法は、予測信頼性に応じて知覚・注意の鋭さを連続的に変調することで、単体ロボットおよび群知能システムにおける停止・振動・分断といった 不確実性起因の行動破綻を構造的に抑制する。


## 要旨 (Abstract)

公共空間や多主体環境における自律ロボットの実運用では，安全性と社会的受容性を両立しつつ，不確実性の高い状況に柔軟に適応する能力が不可欠である。しかし，混雑環境や他者との相互作用が支配的な状況では，他者行動や環境変化の予測困難性が本質的に増大し，従来のモデル予測制御（MPC）や強化学習（RL）に基づく手法は，過度に保守的な回避行動，不安定な振動，さらには行動停止（Freezing）といった不確実性起因の行動破綻を引き起こしやすい。

これらの問題は，不確実性を抑制すべきノイズや誤差としてのみ扱い，行動生成を調停する設計変数として明示的に組み込んでこなかったことに起因する。特に，環境や他者に対する確信度の違いが，知覚や意思決定の「鋭さ」にどのように反映されるべきかという設計原理は，工学的に十分整理されていない。

本研究では，自由エネルギー原理（Free Energy Principle; FEP）および Active Inference に着想を得て，不確実性を **Haze** と呼ばれる操作的指標として定量化し，それを **知覚解像度（Perceptual Resolution）** の制御へ写像する行動生成アーキテクチャ **Emergent Perceptual Haze (EPH)** を提案する。EPH は，不確実性が高い状況では知覚表現を意図的に平均化し，確信度が高い状況では鋭敏化することで，行動勾配の特異化を回避しつつ，安定かつ滑らかな行動生成を実現する。

提案手法は，混雑ナビゲーションにおける Freezing の抑制を主要な検証対象としつつ，単体ロボットに限定されない一般的な設計原理として位置付けられる。本研究は，不確実性を抑制対象としてではなく，知覚と行動を調停する設計可能な情報源として再定義する点に学術的意義があり，社会ナビゲーション，群知能，および不確実性下における AI 安全性設計への理論的基盤を提供する。

---

# 1. 序論 (Introduction)

## 1.1 背景 (Background)

公共空間においてロボットが人間と共存しながら活動するためには，安全性のみならず，周囲との調和や社会的受容性を満たす行動生成が求められる。特に駅構内，商業施設，イベント会場といった混雑環境では，他者の行動が相互に影響し合い，環境の将来状態を正確に予測することが本質的に困難となる。

このような状況下において，従来のモデル予測制御（MPC）や強化学習（RL）に基づくナビゲーション手法は，安全性を優先するあまり，過度に保守的な回避行動や，微小な予測誤差に対する過剰反応を示すことがある。その結果として，ロボットがその場で停止してしまう **Freezing**，あるいは前進と回避を繰り返す振動的挙動が発生し，実運用における信頼性を著しく損なう。

Freezing はしばしば「失敗事例」や「チューニング不足」として扱われてきたが，実際には，不確実性の高い状況において過度に鋭い知覚・判断を維持しようとする設計そのものに起因する構造的問題であると考えられる。すなわち，「確信が持てない状況では，どの程度まで環境を詳細に見るべきか」という認知的制御原理が，工学的に明示されてこなかった点に本質的な課題が存在する。

## 1.2 目的 (Objective)

本研究の目的は，自由エネルギー原理（Free Energy Principle; FEP）および Active Inference の枠組みに着想を得て，不確実性を **Haze** と呼ばれる操作的指標として定量化し，それを **知覚解像度（Perceptual Resolution）** の制御に結び付けることで，不確実性起因の行動破綻を構造的に抑制する行動生成原理を確立することである。

提案する EPH は，不確実性が高い状況では知覚表現を平均化し，意思決定を安定化させる一方，確信度が高い状況では知覚を鋭敏化し，効率的かつ目的指向的な行動を可能とする。このような「不確実性に応じて世界の見え方を変える」設計原理は，従来の固定的な知覚・判断構造に基づく制御手法とは本質的に異なる。

本研究は，混雑環境における単体ロボットの社会ナビゲーションを主要な応用例としつつも，その射程を単体システムに限定せず，群知能や分散型自律システムにおいても成立する一般的な設計原理として提示することを目指す。

## 1.3 学術的新規性 (Academic Novelty)

本研究の学術的新規性は，不確実性を単なるノイズや外乱として扱うのではなく，**知覚解像度を調停する設計変数として明示的に導入した点**にある。自由エネルギー原理において用いられる Precision の概念は，従来，予測誤差の信頼性重みとして解釈されてきたが，本研究ではこれを工学的に再整理し，「推論に用いる Precision」と「知覚表現の鋭さを制御するパラメータ」を明確に分離する。

さらに，本研究では自己中心的な知覚表現である Saliency Polar Map（SPM）を採用し，その集約の鋭さを不確実性に応じて連続的に変調することで，知覚構造そのものを適応的に変形する。このような **不確実性適応型知覚解像度制御** は，固定温度パラメータを用いる既存の MPC，RL，あるいはエントロピー正則化に基づく探索制御とは異なり，行動生成以前の知覚段階に介入する点で本質的な差異を有する。

SPM 自体は既存研究においても用いられてきた表現であるが，本研究の新規性は，Haze に基づく解像度変調と統合することで，不確実性と知覚構造，行動生成を単一の因果連鎖として結び付けた点にある。この統合により，Freezing を含む行動破綻を事後的な失敗ではなく，設計原理の観点から説明・抑制する枠組みを提供する。


# 2. 理論的基盤 (Theoretical Foundation)

本章では，本研究で提案する Emergent Perceptual Haze（EPH）の理論的基盤を整理する。まず，対象とする運動モデルと行動生成の枠組みを定式化し，次に自由エネルギー原理（FEP）との関係を工学的観点から明確化する。その上で，不確実性指標 Haze の定義，Precision の役割分離，および循環依存の解消について詳述する。

---

## 2.1 問題定式化 (Problem Formulation)

本研究では，移動ロボットの運動を以下の 2 次遅れ系としてモデル化する。

$$
M \ddot{\boldsymbol{x}}[k] + D \dot{\boldsymbol{x}}[k] = \boldsymbol{u}[k]
$$

ここで，$\boldsymbol{x}[k] \in \mathbb{R}^2$ はロボットの位置，$\dot{\boldsymbol{x}}[k]$ は速度，$\boldsymbol{u}[k]$ は制御入力を表す。$M$ および $D$ はそれぞれ質量行列および粘性行列である。

ロボットの目的は，目標位置 $\boldsymbol{x}_g$ への到達と，他エージェントや障害物との衝突回避を同時に満たす行動を生成することである。本研究では，この目的を自由エネルギー最小化問題として定式化する。

---

## 2.2 工学的自由エネルギーの定義

自由エネルギー原理（Free Energy Principle; FEP）は，本来，知覚と行動を統一的に説明する理論的枠組みであり，予測誤差を最小化する方向に内部状態や行動が更新されると解釈される。本研究では，この考え方を工学的に解釈し，行動生成のための目的関数として自由エネルギーを定義する。

### 2.2.1 自由エネルギーの定義

本研究における自由エネルギー $F[k]$ は，**予測された将来の SPM** に基づいて定義される。

$$
F[k]
=
\|\hat{\boldsymbol{x}}[k+1] - \boldsymbol{x}_g\|^2
+
\lambda
\sum_{m,n}
\phi\!\left(\hat{\boldsymbol{y}}_{m,n}[k+1]\right)
$$

ここで：
- $\hat{\boldsymbol{x}}[k+1]$：予測された将来位置
- $\hat{\boldsymbol{y}}_{m,n}[k+1]$：VAE によって予測された将来の SPM
- $\phi(\cdot)$：衝突危険性を単調増加に評価するポテンシャル関数

第 1 項は目標位置への到達を表す引力項であり，第 2 項は**予測された知覚空間**上で定義される危険度に基づく斥力項である。

### 2.2.2 予測ベース行動生成（Pattern D: Action-Dependent Uncertainty World Model）

本研究の核心は，自由エネルギーが操作指令値 $\boldsymbol{u}[k]$ を通じて予測 SPM に依存する点にある。v5.5 (Pattern D) では VAE は以下の **行動依存エンコーダ構造** を持つ：

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

ここで重要なのは：
- **エンコーダに $\boldsymbol{u}$ が入力される**：潜在分布 $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ は行動に依存して変化する。
- **Haze が行動に依存する**：$\boldsymbol{\sigma}_z^2$ が $\boldsymbol{u}$ に依存するため，「急激な動作は不確実性が高い」といった関係を表現可能となる。

この設計により：
- $\boldsymbol{z}$ = 「状態 $\boldsymbol{y}$ で行動 $\boldsymbol{u}$ をとった時の遷移の符号化」
- $\boldsymbol{\sigma}_z^2$ = 「その遷移の不確実性」（Action-Dependent Haze）
- $\hat{\boldsymbol{y}}$ = 「$\boldsymbol{z}$ の世界で $\boldsymbol{u}$ を実行した結果」

制御入力は，**操作指令値に関する自由エネルギーの偏微分**として生成される：

$$
\boldsymbol{u}^*[k]
=
\arg\min_{\boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k])}
\left[
F\!\left(\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})\right)
\right]
$$

勾配降下による近似解法として：

$$
\boldsymbol{u}[k] \leftarrow \boldsymbol{u}[k] - \eta \frac{\partial F}{\partial \boldsymbol{u}}
$$

> **設計上の利点**：エンコーダ評価は $\boldsymbol{u}$ 探索前に1回で済み，Haze（→ β）は $\boldsymbol{u}$ 探索中に変動しない。これにより計算効率と最適化の安定性が確保される。

### 2.2.3 チェーンルールによる勾配計算

$\boldsymbol{u}$ に関する自由エネルギーの勾配は，以下のチェーンルールにより計算される：

$$
\frac{\partial F}{\partial \boldsymbol{u}} 
= 
\sum_{m,n}
\frac{\partial \phi(\hat{\boldsymbol{y}}_{m,n})}{\partial \hat{\boldsymbol{y}}_{m,n}}
\cdot
\frac{\partial \hat{\boldsymbol{y}}_{m,n}}{\partial \boldsymbol{u}}
$$

ここで $\partial \hat{\boldsymbol{y}}_{m,n} / \partial \boldsymbol{u}$ は VAE を通じた勾配であり，VAE が微分可能に設計されていることが前提となる。この構造により，行動生成は「予測された将来の危険を避けつつ目標へ向かう」計画問題として解釈される。

> Pattern B では，$\partial \hat{\boldsymbol{y}}/\partial \boldsymbol{u}$ は **VAE デコーダ**を通じた勾配として解釈される（エンコーダは $\boldsymbol{u}$ に依存しない）。

---

## 2.3 Precision 概念の整理と役割分離（v5.2）

自由エネルギー原理において Precision は，予測誤差の信頼性を表す重みとして導入される（Feldman & Friston, 2010）。しかし，工学的実装においては，Precision が複数の役割を暗黙的に担ってしまい，理論的混乱を招く場合がある。

本研究では，この問題を回避するため，Precision の役割を以下の 2 つに明確に分離する。

### 2.3.1 推論における Precision（Inference Precision）

推論における Precision は，予測誤差項の信頼性重みとして自由エネルギーに現れる量であり，FEP における本来の定義に対応する。本研究では，この推論 Precision は固定値として扱い，学習や制御の対象とはしない。

### 2.3.2 知覚解像度を制御するパラメータ（Perceptual Resolution Parameter）

一方，本研究で主に扱うのは，知覚表現そのものの鋭さを制御するパラメータである。本研究では，これを **Perceptual Resolution Parameter** と呼び，記号 $\beta$ によって表す。

$\beta$ は，自由エネルギー中の誤差項を直接重み付けする量ではなく，知覚表現（SPM）における soft 集約の鋭さを制御するメタパラメータである。この役割分離により，Precision の二重利用による理論的不整合を回避する。

---

## 2.4 不確実性指標 Haze の定義

本研究では，不確実性を **Haze** と呼ばれる操作的指標として定義する。Haze は，環境そのものの物理的不確実性を直接表す量ではなく，世界モデルに基づく予測の不安定さを反映する内部指標である。

### 2.4.1 不確実性の種類と本研究の立場

機械学習において，不確実性は一般に以下の 2 種類に分類される（Kendall & Gal, 2017）。

- **Aleatoric uncertainty**：観測ノイズや環境の本質的ランダム性に起因する不確実性
- **Epistemic uncertainty**：モデルの知識不足に起因する不確実性

本研究で用いる Haze は，VAE によって推定される潜在分散に基づく量であり，厳密には aleatoric uncertainty の操作的代理量として位置付けられる。本研究では，epistemic uncertainty の厳密な導入（アンサンブル学習や MC Dropout 等）は将来課題とし，まずは工学的に扱いやすい不確実性指標として Haze を定義する。

---

### 2.4.2 Haze の数理定義

世界モデルとして用いる変分オートエンコーダ（VAE）において，潜在変数 $\boldsymbol{z}[k]$ の事後分布は次式で与えられる。

$$
q_\phi(\boldsymbol{z}[k] \mid \boldsymbol{y}[k], \boldsymbol{u}[k])
=
\mathcal{N}
\!\left(
\boldsymbol{\mu}_z[k],
\mathrm{diag}(\boldsymbol{\sigma}_z^2[k])
\right)
$$

本研究では，この行動依存の潜在分散 $\boldsymbol{\sigma}_z^2[k]$ を，現在の状態-行動ペアがどの程度安定して予測可能であるかを示す量と解釈する。そして，Haze を以下のように定義する。

$$
H[k]
=
\frac{1}{D}
\sum_{d=1}^{D}
\sigma_{z,d}^2[k-1]
$$

ここで $D$ は潜在次元数である。重要なのは，Haze が **前時刻 $k-1$ の潜在分散** に基づいて計算される点であり，これにより同一時刻内での循環依存を回避している。

---

## 2.5 循環依存の解消と因果順序

従来の定式化では，知覚表現が不確実性に依存し，不確実性が再び知覚表現から推定されるという循環構造が暗黙的に存在していた。本研究では，以下の因果順序を明示することで，この問題を解消する。

$$
\boldsymbol{y}[k]
\;\rightarrow\;
\boldsymbol{\sigma}_z^2[k]
\;\rightarrow\;
H[k+1]
\;\rightarrow\;
\beta[k+1]
\;\rightarrow\;
\boldsymbol{y}[k+1]
$$

すなわち，時刻 $k$ における知覚表現 $\boldsymbol{y}[k]$ は，時刻 $k+1$ における解像度制御にのみ影響し，同一時刻内での自己参照は生じない。この 1 ステップ遅延により，初期化および収束性に関する問題を回避する。

補足として，2.4.2 の定義
$
H[k]=\frac{1}{D}\sum_{d=1}^{D}\sigma_{z,d}^2[k-1]
$
は，上式の
$
H[k+1]=\mathrm{Agg}(\boldsymbol{\sigma}_z^2[k])
$
と同値な **インデックスの付け替え**である。以降は「**時刻 $k$ の観測 $\boldsymbol{y}[k]$ から得た潜在分散が，次時刻 $k+1$ の $\beta$ を決める**」という因果解釈を一貫して用いる。

初期時刻における Haze $H[0]$ は，事前に設定された定数値，あるいは短時間のウォームアップ期間における平均潜在分散として与えられる。

---

## 2.6 本章のまとめ

本章では，EPH の理論的基盤として，以下を明確化した。

- 行動生成を自由エネルギー最小化問題として定式化した。
- Precision の役割を推論用と知覚解像度制御用に分離した。
- 不確実性指標 Haze を操作的に定義し，循環依存を解消した。

これにより，次章で述べる手法設計において，不確実性・知覚・行動が一貫した因果構造のもとで結び付けられる。



# 3. 手法 (Methodology)

本章では，提案手法 Emergent Perceptual Haze（EPH）の具体的な構成と実装方法について述べる。EPH は，知覚表現，世界モデル，不確実性指標 Haze，および行動生成を一貫した因果構造として統合する点に特徴がある。

---

## 3.1 システム全体構成 (System Overview)

EPH の処理フローは，Pattern B（Action-Conditioned World Model）に基づく以下の構造を持つ。

### 3.1.1 VAE の2段階構造

```
エンコーダ（Action-Dependent）：
  (y[k], u[k]) → q(z | y[k], u[k]) = N(μ_z, σ_z²)

デコーダ（u に条件付け）：
  (z, u[k]) → ŷ[k+1]
```

この変更により，不確実性（Haze）は行動の関数 $H(\boldsymbol{u})$ となる。

### 3.1.2 行動生成経路（Action Generation Path）

$$
(\boldsymbol{y}[k], \boldsymbol{u}_{\text{cand}})
\;\xrightarrow{\text{Encoder}}\;
q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u}_{\text{cand}})
\;\xrightarrow{\text{Sample}}\;
\boldsymbol{z}
\;\xrightarrow[\boldsymbol{u}_{\text{cand}}]{\text{Decoder}}\;
\hat{\boldsymbol{y}}[k+1]
\;\xrightarrow{}\;
F
$$

1. エンコーダは $\boldsymbol{y}[k]$ と候補行動 $\boldsymbol{u}_{\text{cand}}$ から潜在分布を推定
2. 潜在変数 $\boldsymbol{z}$ をサンプリング
3. デコーダは $(\boldsymbol{z}, \boldsymbol{u})$ から将来 SPM を予測（$\boldsymbol{u}$ に条件付け）
4. 自由エネルギー $F$ を $\boldsymbol{u}$ で偏微分し，勾配降下で最適化

### 3.1.3 知覚解像度制御経路（Perceptual Resolution Control Path）

$$
\boldsymbol{\sigma}_z^2[k-1]
\;\xrightarrow{\text{Agg}}\;
H[k]
\;\xrightarrow{1/(H+\epsilon)}\;
\Pi^{\text{perc}}[k]
\;\xrightarrow{}\;
\beta[k]
$$

前時刻の潜在分散から Haze を算出し，知覚解像度パラメータ $\beta$ を変調する。**Haze は $\boldsymbol{u}$ に依存しない**ため，$\boldsymbol{u}$ 探索中に $\beta$ は変動しない。

### 3.1.4 統合されたシステムフロー

1. **知覚**：環境観測から SPM $\boldsymbol{y}[k]$ を構築（$\beta[k]$ により解像度が変調）
2. **符号化**：エンコーダが $\boldsymbol{y}[k]$ から潜在分布 $q(\boldsymbol{z} \mid \boldsymbol{y})$ を推定
3. **サンプリング**：潜在変数 $\boldsymbol{z}$ を取得
4. **予測**：デコーダが $(\boldsymbol{z}, \boldsymbol{u})$ から $\hat{\boldsymbol{y}}[k+1]$ を予測
5. **評価**：予測 SPM に対する自由エネルギー $F$ を計算
6. **最適化**：$\partial F / \partial \boldsymbol{u}$ により最適行動 $\boldsymbol{u}^*[k]$ を導出
7. **更新**：潜在分散 $\boldsymbol{\sigma}_z^2[k]$ から $H[k+1]$ を算出し，次時刻の $\beta[k+1]$ を更新

---

## 3.2 知覚表現：Saliency Polar Map (SPM)

### 3.2.1 SPM の概要

SPM は，ロボットを中心とした極座標系に基づく自己中心的知覚表現であり，距離方向には対数スケール，角度方向には等間隔の分割を用いる。この構造により，近傍の詳細情報と遠方の粗い情報を自然に同一表現内で扱うことが可能となる。

SPM は $M \times N \times 3$ のテンソルとして表現され，各セル $(m,n)$ は以下の 3 チャネルを持つ。

---

### 3.2.2 チャネル1：占有密度 (Occupancy)

セル $(m,n)$ に含まれる他エージェント数に基づき，占有密度を次式で定義する。

$$
\boldsymbol{y}_{m,n,1}[k]
=
\mathrm{clip}
\!\left(
\frac{1}{Z_{m,n}}
\sum_{i \in \mathcal{I}_{m,n}[k]} 1,
\, 0, \, 1
\right)
$$

ここで $\mathcal{I}_{m,n}[k]$ は時刻 $k$ においてセル $(m,n)$ に含まれるエージェント集合，$Z_{m,n}$ は正規化定数である。

---

### 3.2.3 チャネル2：近接顕著性 (Proximity Saliency)

セル内の距離情報は，最短距離に基づく hard-min ではなく，微分可能な soft-min 集約によって表現される。

$$
\bar{r}_{m,n}[k]
=
-\frac{1}{\beta_r[k]}
\log
\sum_{i \in \mathcal{I}_{m,n}[k]}
\exp
\!\left(
-\beta_r[k]
\|\boldsymbol{r}_i[k]\|
\right)
$$

$$
\boldsymbol{y}_{m,n,2}[k]
=
\exp
\!\left(
-\frac{\bar{r}_{m,n}[k]^2}{2\sigma_{\text{safe}}^2}
\right)
$$

ここで $\boldsymbol{r}_i[k]$ はロボットからエージェント $i$ への相対位置ベクトルである。

---

### 3.2.4 チャネル3：動的衝突危険性 (Dynamic Collision Risk)

相対速度を考慮した Time-to-Collision（TTC）に基づき，動的な衝突危険性を評価する。

$$
\nu_{m,n}[k]
=
\frac{1}{\beta_\nu[k]}
\log
\sum_{i \in \mathcal{I}_{m,n}[k]}
\exp
\!\left(
\beta_\nu[k]
\max
\left(
0,
-\frac{\boldsymbol{r}_i[k]^\top \Delta\dot{\boldsymbol{x}}_i[k]}
{\|\boldsymbol{r}_i[k]\|+\epsilon}
\right)
\right)
$$

$$
\boldsymbol{y}_{m,n,3}[k]
=
\sigma
\!\left(
\beta_{\text{ttc}}
\left(
T_{\text{th}}
-
\frac{\bar{r}_{m,n}[k]}{\nu_{m,n}[k]+\epsilon}
\right)
\right)
$$

---

## 3.3 集約演算子 Agg の定義（v5.2 明示）

Haze の算出に用いる集約演算子 $\mathrm{Agg}(\cdot)$ は，本研究では算術平均として定義する。

$$
H[k]
=
\mathrm{Agg}
\!\left(
\boldsymbol{\sigma}_z^2(\boldsymbol{y}[k], \boldsymbol{u}[k])
\right)
=
\frac{1}{D}
\sum_{d=1}^{D}
\sigma_{z,d}^2
$$

算術平均を採用する理由は，以下の点にある。

- 潜在次元全体の平均的予測不確実性を直感的に反映できる。
- 勾配が安定であり，制御入力の急激な変動を抑制できる。
- log-sum-exp や max と比較して，外れ値への過度な感度を回避できる。

他の集約関数（log-sum-exp, max）については，性能比較および感度分析をアブレーションスタディとして評価する。

---

## 3.4 世界モデル：Action-Conditioned VAE による将来 SPM 予測

### 3.4.1 VAE の構造（Pattern D）

本研究では，世界モデルとして **Action-Dependent Uncertainty VAE** を用いる。

| 構成要素 | 入力 | 出力 |
|---------|------|------|
| **エンコーダ** | $(\boldsymbol{y}[k], \boldsymbol{u}[k])$ | $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ |
| **デコーダ** | $(\boldsymbol{z}, \boldsymbol{u}[k])$ | $\hat{\boldsymbol{y}}[k+1]$ |

### 3.4.2 エンコーダ（状態と行動から潜在分布を推定）

エンコーダは **現在の SPM と行動**を入力とし，潜在分布を推定する：

$$
q_\phi(\boldsymbol{z}[k] \mid \boldsymbol{y}[k], \boldsymbol{u}[k])
=
\mathcal{N}
\!\left(
\boldsymbol{\mu}_z[k],
\mathrm{diag}(\boldsymbol{\sigma}_z^2[k])
\right)
$$

**重要**：エンコーダに $\boldsymbol{u}$ が入力される。これにより：
- 潜在分布 $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ は行動に依存する
- 潜在分散 $\boldsymbol{\sigma}_z^2$（Haze）は行動によって変動する（Counterfactual Haze）

### 3.4.3 デコーダ（潜在変数 + 操作指令値から将来予測）
（変更なし：デコーダは引き続き $z$ と $u$ を用いる）

### 3.4.4 VAE の二重の役割
（変更なし）

### 3.4.5 Pattern D の設計根拠（v5.5変更）

Pattern B（行動非依存）では Haze と予測誤差の相関が得られなかったため，Pattern D へ移行した。この構造は以下の利点を持つ：

- **行動依存の不確実性**：「停止していれば安全（低分散）」「急加速すれば危険（高分散）」といった物理的因果を反映できる。
- **負の相関の解消**：予測困難な行動ほど Haze が高くなるため，Haze と予測誤差の正の相関が期待される。
- **Freezing 抑制**：危険な行動に対する Haze ペナルティ（次時刻の解像度低下）が，より適切な回避行動を促す。

---

## 3.5 操作指令値に関する行動生成（Pattern B）

### 3.5.1 行動生成の目的関数

行動生成は，予測された将来 SPM に基づく自由エネルギーを最小化する問題として定式化される：

$$
\boldsymbol{u}^*[k] 
= 
\arg\min_{\boldsymbol{u}} 
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k], \boldsymbol{u})}
\left[ 
F[\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})] 
\right]
$$

**Pattern D の特徴**：期待値を計算する分布 $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ 自身が $\boldsymbol{u}$ に依存する。

自由エネルギー $F$ は以下で定義される：

$$
F[\hat{\boldsymbol{y}}] 
= 
\|\hat{\boldsymbol{x}}[k+1] - \boldsymbol{x}_g\|^2 
+ 
\lambda \sum_{m,n} \phi(\hat{\boldsymbol{y}}_{m,n})
$$

### 3.5.2 勾配降下による最適化（Reparameterization Trick）

Pattern D では $q(\boldsymbol{z} \mid \boldsymbol{y}, \boldsymbol{u})$ が $\boldsymbol{u}$ に依存するため，勾配計算には Reparameterization Trick を用いる：

$$
\boldsymbol{z} = \boldsymbol{\mu}_z(\boldsymbol{y}, \boldsymbol{u}) + \boldsymbol{\sigma}_z(\boldsymbol{y}, \boldsymbol{u}) \odot \boldsymbol{\epsilon}, \quad \boldsymbol{\epsilon} \sim \mathcal{N}(0, I)
$$

これにより，エンコーダを通じた勾配 $\partial \boldsymbol{z} / \partial \boldsymbol{u}$ を計算可能とする。

$$
\frac{\partial \mathcal{L}}{\partial \boldsymbol{u}}
=
\mathbb{E}_{\boldsymbol{\epsilon}}
\left[
\frac{\partial F}{\partial \hat{\boldsymbol{y}}}
\left(
\frac{\partial \hat{\boldsymbol{y}}}{\partial \boldsymbol{u}}
+
\frac{\partial \hat{\boldsymbol{y}}}{\partial \boldsymbol{z}}
\frac{\partial \boldsymbol{z}}{\partial \boldsymbol{u}}
\right)
\right]
$$

勾配はチェーンルールにより計算される：

$$
\frac{\partial F}{\partial \boldsymbol{u}} 
= 
\underbrace{
\frac{\partial F}{\partial \hat{\boldsymbol{y}}}
}_{\text{SPM 勾配}}
\cdot
\underbrace{
\frac{\partial \hat{\boldsymbol{y}}}{\partial \boldsymbol{u}}
}_{\text{デコーダ勾配}}
$$

### 3.5.3 各項の詳細

**SPM 勾配**（$\partial F / \partial \hat{\boldsymbol{y}}$）：

$$
\frac{\partial F}{\partial \hat{\boldsymbol{y}}_{m,n}} 
= 
\lambda \cdot \phi'(\hat{\boldsymbol{y}}_{m,n})
$$

ここで $\phi'(\cdot)$ はポテンシャル関数の導関数である。

**デコーダ勾配**（$\partial \hat{\boldsymbol{y}} / \partial \boldsymbol{u}$）：

$$
\frac{\partial \hat{\boldsymbol{y}}_{m,n}}{\partial \boldsymbol{u}} 
= 
\frac{\partial f_{\text{dec}}(\boldsymbol{z}, \boldsymbol{u})}{\partial \boldsymbol{u}}
$$

**重要**：この勾配はデコーダのみを通過し，エンコーダは関与しない。$\boldsymbol{z}$ は固定されたまま，$\boldsymbol{u}$ の変化が $\hat{\boldsymbol{y}}$ に影響する。

### 3.5.4 期待値の近似

潜在変数 $\boldsymbol{z}$ に関する期待値は，再パラメータ化トリック（reparameterization trick）を用いて近似する：

$$
\boldsymbol{z} = \boldsymbol{\mu}_z(\boldsymbol{y}[k]) + \boldsymbol{\sigma}_z(\boldsymbol{y}[k]) \odot \boldsymbol{\epsilon}, 
\quad 
\boldsymbol{\epsilon} \sim \mathcal{N}(\boldsymbol{0}, \boldsymbol{I})
$$

これにより，$\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y})}[\cdot]$ を Monte Carlo 近似できる。なお Pattern B では $\boldsymbol{z}$ は $\boldsymbol{u}$ に依存しないため，$\boldsymbol{u}$ に関する勾配は **デコーダ経路のみ**を通じて計算される。

---

## 3.6 Haze に基づく知覚解像度制御（β 変調）

Haze $H[k]$ は，前時刻の潜在分散に基づいて算出され，次時刻の知覚解像度制御に用いられる。

$$
\beta[k]
=
\beta^{\min}
+
(\beta^{\max} - \beta^{\min})
\cdot
s
\!\left(
\frac{1}{H[k] + \epsilon}
\right)
$$

ここで $s(\cdot)$ は単調増加な正規化関数であり，本研究では線形写像を基本とする。線形写像は，近似範囲内での解釈性と計算効率の観点から採用されている。非線形写像（指数関数，シグモイド関数）については，感度分析およびアブレーションにより比較評価する。

---

## 3.7 群知能への拡張 (Swarm Intelligence Extension)

EPH は，単体ロボットに限定されない一般的な設計原理として，群知能システムへ自然に拡張可能である。

各エージェント $i$ は，近傍集合 $\mathcal{N}_i[k]$ に基づき，局所的な運動予測誤差から Haze を推定する。

$$
\hat{\boldsymbol{x}}_j[k]
=
\boldsymbol{x}_j[k-1]
+
\dot{\boldsymbol{x}}_j[k-1]
\Delta t
$$

$$
H_i[k]
=
\frac{1}{|\mathcal{N}_i[k]|}
\sum_{j \in \mathcal{N}_i[k]}
\|
\boldsymbol{x}_j[k]
-
\hat{\boldsymbol{x}}_j[k]
\|^2
$$

局所 Haze $H_i[k]$ に基づき，各エージェントは知覚解像度を調整し，分離・整列・結合といった群行動の鋭さを連続的に変調する。このとき，単体ロボットにおける Haze は，群知能における局所 Haze の特別な場合として解釈できる。

---

## 3.8 本章のまとめ

本章では，EPH の具体的な実装方法として以下を示した：

1. **SPM に基づく知覚表現**：3チャネル（占有密度，近接顕著性，動的衝突危険性）による自己中心的知覚
2. **Action-Conditioned VAE（Pattern B）による将来 SPM 予測**：エンコーダは現在の SPM のみから潜在分布を推定し，デコーダは $(\boldsymbol{z}, \boldsymbol{u})$ から将来状態を予測
3. **操作指令値に関する行動生成**：予測 SPM に対する自由エネルギーを $\boldsymbol{u}$ で偏微分し，勾配降下で最適化
4. **Haze に基づく知覚解像度制御**：潜在分散から算出される不確実性指標により $\beta$ を変調
5. **群知能への拡張**：局所 Haze による分散型知覚解像度制御

この構成により，**予測 → 不確実性推定 → 知覚解像度制御 → 行動生成** という一貫した因果構造が実現される。



# 4. 検証戦略 (Verification Strategy)

本章では，提案手法 EPH の有効性を検証するための実験設計，評価指標，および比較対象（Baseline）について述べる。本研究では，単なる性能向上ではなく，不確実性起因の行動破綻，特に Freezing の抑制を主目的とした検証を行う。

---

## 4.1 検証シナリオと前提条件

検証は，2 次元平面上の移動ロボットナビゲーションタスクを対象とする。ロボットは静的障害物および複数の動的エージェントが存在する環境において，目標位置への到達を目指す。

### 4.1.1 シミュレーション環境

- シミュレーション空間：$10 \,\mathrm{m} \times 10 \,\mathrm{m}$ の連続平面
- 時間刻み：$\Delta t = 0.1 \,\mathrm{s}$
- 制御更新周期：$10 \,\mathrm{Hz}$
- 物理モデル：2 次遅れ系（第2章参照）

他エージェントは，後述する Baseline 手法に応じた行動モデルを用いて動作する。これにより，提案手法と既存手法を同一条件下で比較可能とする。

---

### 4.1.2 混雑度の操作的定義

混雑環境は，単位面積あたりのエージェント密度 $\rho$ によって定義する。

$$
\rho
=
\frac{N_{\text{agents}}}{A}
$$

ここで $A$ は環境面積である。本研究では，$\rho > \rho_{\text{th}}$ を満たす状況を混雑環境と定義し，$\rho_{\text{th}}$ は予備実験に基づき設定する。

---

### 4.1.3 学習と評価の分離（再現性・一般化の前提）

本研究は「世界モデル（VAE）の学習」と「行動生成（$\boldsymbol{u}$ 最適化）の評価」を明確に分離し，過学習や評価リークを避けることで学術的信頼性（再現性・一般化可能性）を担保する。

具体的には：

- **学習データ（Train）**：複数の混雑度 $\rho \in \mathcal{R}_{\text{train}}$ と，他者行動モデルの集合 $\mathcal{M}_{\text{train}}$（例：Social Force / ORCA など）を組み合わせて生成したロールアウトから，$(\boldsymbol{y}[k], \boldsymbol{u}[k], \boldsymbol{y}[k+1])$ を収集し，VAE を学習する。
- **評価データ（Test）**：$\rho \in \mathcal{R}_{\text{test}}$ や $\mathcal{M}_{\text{test}}$ を **学習で用いない**範囲（後述の OOD 条件）として設定し，VAE は固定したまま行動生成性能を評価する。

この分離により，「EPH の Freezing 抑制」が **訓練環境への適合ではなく，不確実性下での設計原理として成立している**ことを検証する。

---

### 4.1.4 OOD（未知条件）評価：未知混雑度・未知他者モデル・観測ノイズ

EPH が「不確実性に応じて知覚解像度を変調する」設計原理として有効であることを示すため，以下の OOD（out-of-distribution）条件を設定する。

- **未知混雑度（Density OOD）**：$\mathcal{R}_{\text{test}}$ として学習で用いない高密度領域を含める（例：$\rho_{\text{test}} > \max \mathcal{R}_{\text{train}}$）。
- **未知他者モデル（Behavior OOD）**：学習で用いない他者行動（速度分布，回避規則，停止傾向など）を導入し，行動破綻（Freezing/振動）が増える条件で比較する。
- **観測ノイズ（Noise OOD）**：SPM 構築段階でのノイズ（検出欠落，位置誤差，遅延）を系統的に付与し，Haze→$\beta$ 制御の頑健性を評価する。

---

## 4.2 評価指標 (Evaluation Metrics)

本研究では，評価指標を **Primary Outcome** と **Secondary Outcomes** に明確に分離する。

---

### 4.2.1 Primary Outcome：Freezing Rate

本研究における主要評価指標は **Freezing Rate** である。Freezing は以下の操作的定義に基づいて判定される。

$$
\|\dot{\boldsymbol{x}}[k]\| < \epsilon_v
\quad \text{が}
\quad
T_{\text{freeze}}
\text{ 秒以上継続}
$$

ここで $\epsilon_v$ は速度閾値，$T_{\text{freeze}}$ は時間閾値である。Freezing Rate は，全試行における Freezing 発生割合として算出される。

---

### 4.2.2 Secondary Outcomes

Primary Outcome を補完する指標として，以下を用いる。

- **Success Rate**：目標到達率
- **Collision Rate**：衝突発生率
- **Jerk**：加速度変化率の時間平均
- **最小 TTC**：試行中の最小 Time-to-Collision
- **Throughput**：狭隘領域の通過流量
- **渋滞指標**：局所密度の時間積分
- **群分断率**：連結成分数の変化
- **Haze 妥当性（Calibration/Correlation）**：$H$ と 1-step 予測誤差（例：$\|\hat{\boldsymbol{y}}[k+1]-\boldsymbol{y}[k+1]\|$）の相関，および誤差の校正曲線（Calibration curve）

これらの指標は，Freezing 抑制が他の性能指標に与える影響やトレードオフを評価するために用いられる。

---

## 4.3 比較手法（Baselines）

提案手法 EPH の有効性を検証するため，以下の代表的手法を Baseline として採用する。

### 4.3.1 古典的手法

- **Social Force Model**（Helbing & Molnár, 1995）  
  群集挙動の古典モデルとして広く用いられる。

- **ORCA**（van den Berg et al., 2011）  
  幾何学的衝突回避に基づく代表的手法。

---

### 4.3.2 モデル予測制御系

- **Robust MPC**  
  不確実性を最悪ケースとして扱うロバスト制御。

- **Tube MPC**  
  不確実性集合をチューブとして扱う予測制御。

これらは，不確実性を明示的に考慮する MPC 系手法として，EPH の主張と直接比較可能な Baseline である。

---

### 4.3.3 学習ベース手法

- **SA-CADRL**（Everett et al., 2018）  
  社会ナビゲーションに特化した深層強化学習手法。

- **RL + Entropy Regularization（SAC）**  
  方策エントロピーを自動調整する代表的手法。

これらは，探索・活用バランスを温度パラメータで調整する点で，EPH の知覚解像度制御との概念的差異を検証する対象となる。

---

### 4.3.4 リスク感受・信念空間・不確実性対応の強い比較（推奨 Baselines）

EPH の主張（「不確実性を行動空間の温度や最悪ケース制約ではなく，**知覚解像度**として設計変数化する」）をより厳密に検証するため，以下の近縁で強い比較対象を追加する。

- **Risk-Sensitive MPC（例：CVaR 正則化）**  
  コストの期待値に加え，尾部リスク（最悪側の期待）を最小化することで保守性を制御する。EPH が「知覚表現側の粗視化」で Freezing を抑えるのに対し，こちらは「目的関数側のリスク」で調停する。

- **Belief-Space MPC / POMDP 近似（信念上での計画）**  
  観測ノイズや他者不確実性を信念状態で表現し，信念上で将来コストを最小化する。EPH が「信念推定の厳密化」ではなく「知覚表現の解像度変調」を採る点を明確に比較できる。

- **Sampling-based Planning（MPPI 等）**  
  勾配ではなくサンプリングで行動列を最適化することで，局所的な鋭い勾配による停止・振動を回避できる場合がある。EPH の優位性を「最適化器の違い」から切り分けるために有効である。

- **Uncertainty-aware RL（例：アンサンブル不確実性＋リスク/保守正則化）**  
  方策の不確実性推定を用いて保守性や探索を調整する。EPH の「知覚解像度制御」が，方策側の不確実性制御と異なることを示す比較となる。

> 実装上は，可能な限り「同一の観測（SPM）・同一のシミュレーション条件」を共有し，差分が **不確実性の扱い方（知覚 vs 目的関数 vs 信念推定 vs 最適化器）**に帰着するよう設計する。

---

## 4.4 アブレーションスタディ

提案手法の各構成要素の寄与を明確化するため，以下の条件でアブレーションを行う。

- **A1**：固定 $\beta$（Baseline）
- **A2**：固定 $\beta$ + SPM
- **A3**：適応 $\beta(H)$ + 直交座標
- **A4**：**EPH（提案手法）**

これにより，表現，解像度変調，不確実性指標の各要素が Freezing 抑制に与える影響を分離して評価する。

---

## 4.5 統計的検証

各条件について，$N \ge 30$ 試行を実施し，平均値および分散を算出する。統計的有意性の検定には，多重比較による第 I 種過誤を抑制するため，False Discovery Rate（FDR）補正を用いる。

さらに，学術的信頼性を高めるため，以下を明示する。

- **乱数と初期条件**：乱数シード・初期位置・他者配置の分布を公開し，条件間で可能な限り **同一シードの対応比較（paired design）**を行う。
- **効果量と信頼区間**：Primary Outcome（Freezing Rate）について，差分の効果量（例：Cliff's delta）と，ブートストラップによる 95% 信頼区間を併記する。
- **一般化評価の報告形式**：$\rho$ のスイープに対する Freezing Rate 曲線（Freezing-vs-Density）を提示し，IID（train 相当）と OOD（test 相当）を区別して示す。
- **Haze 妥当性**：$H$ と予測誤差の相関・校正を併せて報告し，「Haze が操作的に不確実性を捉えている」ことを定量化する。

---

## 4.6 本章のまとめ

本章では，EPH の有効性を検証するための実験設計，評価指標，および比較手法を体系的に整理した。特に，Freezing Rate を Primary Outcome として明示することで，本研究の主張と検証設計の対応関係を明確化した。


# 5. 関連研究 (Related Work)

本章では，提案手法 EPH と関連する既存研究を，不確実性表現，知覚表現，行動生成，および群知能の観点から整理し，本研究の位置付けを明確にする。

---

## 5.1 自由エネルギー原理と Active Inference

自由エネルギー原理（Free Energy Principle; FEP）は，生体および人工システムにおける知覚・行動・学習を統一的に説明する理論枠組みとして提案されている（Friston, 2010）。Active Inference は，FEP に基づき，予測誤差を最小化するように行動を生成する制御原理である。

FEP において Precision は，予測誤差の信頼性を表す重みとして導入され，注意や感覚ゲイン制御との関係が議論されてきた（Feldman & Friston, 2010）。一方で，多くの工学的応用では，Precision は固定値として扱われることが多く，環境不確実性に応じた動的制御は十分に検討されていない。

本研究は，FEP の理論的枠組みに着想を得つつ，Precision を **知覚表現の解像度を制御する設計変数**として明示的に導入する点で，既存の Active Inference 応用とは一線を画す。

---

## 5.2 不確実性の分類と推定手法

不確実性は，一般に epistemic uncertainty（モデル不確実性）と aleatoric uncertainty（本質的ランダム性）に分類される（Kendall & Gal, 2017）。

Epistemic uncertainty を扱う代表的手法として，以下が挙げられる。

- ベイズニューラルネットワーク
- モデルアンサンブル
- MC Dropout（Gal & Ghahramani, 2016）

一方，VAE における潜在分散は，主に aleatoric uncertainty を反映する量として解釈される。本研究では，Haze を **予測の不安定さを反映する操作的指標**として定義し，厳密な epistemic uncertainty の推定とは区別する。この点を明示することで，不確実性概念の混同を回避している。

---

## 5.3 ナビゲーションと衝突回避手法

移動ロボットのナビゲーションにおいては，多様な衝突回避手法が提案されてきた。

### 5.3.1 古典的モデル

Social Force Model（Helbing & Molnár, 1995）は，人間群集の運動を力学的相互作用として記述する古典的モデルであり，現在でも Baseline として広く用いられている。

ORCA（van den Berg et al., 2011）は，速度空間における衝突回避制約を用いた幾何学的手法であり，計算効率と安全性に優れる。

---

### 5.3.2 モデル予測制御（MPC）

MPC は，将来状態を予測し最適制御入力を算出する枠組みであり，Robust MPC や Tube MPC では不確実性を考慮した設計が行われている。ただし，これらの手法では，不確実性は制約の拡張や保守性の増大として扱われることが多く，結果として Freezing や過度な回避が生じやすい。

EPH は，不確実性を抑制すべき対象ではなく，**知覚と行動を調停する情報源**として利用する点で，これらの MPC 系手法と根本的に異なる。

---

## 5.4 学習ベース手法と温度パラメータ

深層強化学習に基づく社会ナビゲーション手法として，SA-CADRL（Everett et al., 2018）や，Soft Actor-Critic（SAC）に代表されるエントロピー正則化手法が提案されている。

SAC における温度パラメータは，方策のエントロピーを制御することで探索・活用のバランスを調整する。一方，本研究の $\beta$ 変調は，**行動空間ではなく知覚表現空間の解像度**を直接制御する点に本質的な違いがある。

すなわち，SAC が「どの行動を選ぶか」の多様性を制御するのに対し，EPH は「世界をどの解像度で知覚するか」を制御する。この違いにより，Freezing のような行動生成以前の問題に対処可能となる。

---

## 5.5 知覚表現と極座標表現

対数極座標表現は，移動ロボットや視覚システムにおいて既に利用されている（Burgard et al., 1999）。本研究の SPM は，表現形式そのものの新規性を主張するものではない。

本研究の新規性は，SPM を **Haze によって解像度可変な知覚表現**として位置付け，行動生成と直接結び付けた点にある。この統合により，bounded rationality 下での適応的知覚制御を実装可能とした。

---

## 5.6 本章のまとめ

本章では，EPH と関連する既存研究を整理し，本研究の位置付けを明確にした。EPH は，既存のナビゲーション手法や学習ベース手法とは異なり，不確実性を知覚解像度制御に用いるという設計原理に基づく点に特徴がある。


# 6. 議論と限界 (Discussion and Limitations)

本章では，提案手法 EPH の理論的含意，適用可能性，および限界について議論する。特に，不確実性の扱い方，Freezing 抑制のメカニズム，群知能への拡張可能性について整理し，本研究の射程と今後の課題を明確にする。

---

## 6.1 Freezing 抑制のメカニズムに関する考察

従来のナビゲーション手法における Freezing は，不確実性の増大に伴い，行動生成が過度に保守化することに起因する場合が多い。Robust MPC や幾何学的衝突回避では，不確実性は制約の拡張や安全マージンの増大として反映され，結果として「動かないこと」が最適解として選択されやすい。

EPH では，不確実性を直接行動制約に反映するのではなく，**知覚表現の解像度を調整する変数**として扱う。Haze が高い状況では，知覚が意図的に粗視化され，局所的なノイズや一時的な衝突危険に過剰反応することを防ぐ。一方，Haze が低下すると，知覚解像度が高まり，精緻な回避行動が可能となる。

この機構により，EPH は「不確実だから止まる」のではなく，「不確実だから粗く動く」という行動様式を実現している。

---

## 6.2 不確実性の解釈と理論的位置付け

本研究における Haze は，VAE の潜在分散に基づく操作的指標であり，厳密な epistemic uncertainty の推定を目的としたものではない。Haze は，予測の不安定さや環境の曖昧さを反映する量として定義され，知覚解像度制御のための設計変数として機能する。

この点で，EPH は自由エネルギー原理（FEP）そのものの厳密な実装ではなく，**FEP に着想を得た工学的拡張**として位置付けられる。特に，Precision を予測誤差の重みではなく，知覚表現の解像度制御に用いる点は，FEP の理論的枠組みを設計指針として再解釈したものである。

---

## 6.3 Precision 分離設計の意義

v5.2 では，査読指摘を踏まえ，Precision の役割を明確に分離した。すなわち，

- 推論・学習に関わる不確実性指標（Haze）
- 知覚表現の解像度を制御するパラメータ（$\beta$）

を異なるレイヤで扱うことで，循環依存や理論的不整合を回避している。

この分離設計により，EPH は数理的な厳密性と実装上の安定性を両立し，工学的応用に耐える構造を獲得している。

---

## 6.4 群知能への拡張に関する議論

EPH は，単体ロボットにおける知覚・行動調停原理として設計されているが，局所 Haze の概念を導入することで，群知能システムへ自然に拡張可能である。

群環境では，各エージェントが近傍エージェントの運動予測誤差から局所 Haze を推定し，それに基づいて知覚解像度を調整する。この機構は，群全体の密度や秩序の変化に応じて，行動の鋭さを連続的に変調する役割を果たす。

ただし，本研究では群知能への拡張は概念実証段階に留まっており，大規模群における安定性やスケーラビリティの検証は今後の課題である。

---

## 6.5 限界と失敗モード

EPH には以下の限界が存在する。

1. **Haze の誤推定**  
   VAE の学習が不十分な場合，Haze が過大または過小評価され，知覚解像度の不適切な変調が生じる可能性がある。

2. **極端な混雑環境**  
   極端に高密度な環境では，粗視化された知覚でも衝突回避が困難となる場合がある。

3. **計算コスト**  
   SPM および VAE の計算は，単純な幾何学的手法に比べて計算負荷が高い。

これらの限界に対しては，軽量モデルの導入や，Haze の時間平滑化などが有効な対策として考えられる。

---

## 6.6 今後の展望

今後の研究課題として，以下が挙げられる。

- Epistemic uncertainty を明示的に扱うためのアンサンブルモデルの導入
- 実環境ロボットによる検証
- 群知能における秩序形成や相転移現象との関係解析
- 人間群集データを用いた社会的受容性評価

これらを通じて，EPH を不確実性下での適応的知覚・行動設計の一般原理として発展させることを目指す。

---

## 6.7 本章のまとめ

本章では，EPH の理論的意義，Freezing 抑制のメカニズム，および限界と今後の展望について議論した。EPH は，不確実性を抑制すべき対象ではなく，知覚と行動を調停する情報源として再定義する点に本質的な特徴を持つ。


## 7. 参考文献 (References)

### 7.1 自由エネルギー原理・Active Inference

- Friston, K. (2010).  
  *The free-energy principle: a unified brain theory?*  
  **Nature Reviews Neuroscience**, 11(2), 127–138.  
  → 自由エネルギー原理（FEP）の原典。本研究はこの理論を「知覚解像度制御」という工学的観点で再解釈する。

- Friston, K., FitzGerald, T., Rigoli, F., Schwartenbeck, P., & Pezzulo, G. (2017).  
  *Active inference: a process theory.*  
  **Neural Computation**, 29(1), 1–49.  
  → Active Inference の行動生成理論。本研究は厳密実装ではなく設計思想として参照。

- Feldman, H., & Friston, K. J. (2010).  
  *Attention, uncertainty, and free-energy.*  
  **Frontiers in Human Neuroscience**, 4, 215.  
  → Precision を注意の重みとして解釈する神経科学的基盤。

---

### 7.2 不確実性推定・深層学習

- Kingma, D. P., & Welling, M. (2014).  
  *Auto-Encoding Variational Bayes.*  
  **ICLR**.  
  → 本研究で用いる VAE 世界モデルの基礎。

- Kendall, A., & Gal, Y. (2017).  
  *What uncertainties do we need in Bayesian deep learning for computer vision?*  
  **NeurIPS**, 5574–5584.  
  → epistemic / aleatoric uncertainty の整理。本研究では VAE 分散を操作的指標として使用。

- Gal, Y., & Ghahramani, Z. (2016).  
  *Dropout as a Bayesian approximation: Representing model uncertainty in deep learning.*  
  **ICML**.  
  → 本研究が採用しなかった epistemic uncertainty 推定手法との対比。

---

### 7.3 社会ナビゲーション・衝突回避

- Helbing, D., & Molnár, P. (1995).  
  *Social force model for pedestrian dynamics.*  
  **Physical Review E**, 51(5), 4282–4286.  
  → 社会ナビゲーションの古典的ベースライン。

- van den Berg, J., Lin, M., & Manocha, D. (2011).  
  *Reciprocal velocity obstacles for real-time multi-agent navigation.*  
  **IJRR**, 30(1), 3–23.  
  → ORCA。幾何学的衝突回避の代表手法。

- Everett, M., Chen, Y. F., & How, J. P. (2018).  
  *Motion planning among dynamic, decision-making agents with deep reinforcement learning.*  
  **IROS**.  
  → RL ベース社会ナビゲーション（SA-CADRL）。

---

### 7.4 Freezing 問題・群集挙動

- Trautman, P., et al. (2015).  
  *Robot navigation in dense human crowds.*  
  **IJRR**, 34(3), 335–356.  
  → Freezing Robot Problem の実証的報告。

- Helbing, D. (2001).  
  *Traffic and related self-driven many-particle systems.*  
  **Reviews of Modern Physics**, 73(4), 1067–1141.  
  → 群集における渋滞・停止現象の理論的背景。

---

### 7.5 知覚表現・注意モデル

- Itti, L., & Koch, C. (2001).  
  *Computational modelling of visual attention.*  
  **Nature Reviews Neuroscience**, 2(3), 194–203.  
  → Saliency Map の計算論的基礎。

- Burgard, W., et al. (1999).  
  *Experiences with an interactive museum tour-guide robot.*  
  **Artificial Intelligence**, 114(1–2), 3–55.  
  → 対数極座標・空間圧縮表現の先行例。

- Wolfe, J. M., & Horowitz, T. S. (2017).  
  *Five factors that guide attention in visual search.*  
  **Nature Human Behaviour**, 1(3), 0058.  
  → 人間の注意分散戦略と本研究の知覚粗視化との対応。

---

### 7.6 制御理論・ロバスト性

- Zames, G., & Francis, B. A. (1983).  
  *Feedback, minimax sensitivity, and optimal robustness.*  
  **IEEE Transactions on Automatic Control**, 28(5), 585–601.  
  → 固定最悪ケース設計の限界。本研究の動機付け。

---

### 7.7 本研究との位置づけまとめ

本研究 **EPH** は，

- FEP / Active Inference を **設計思想として採用**
- 不確実性を **知覚解像度制御に写像**
- Freezing を **知覚と不確実性のミスマッチ現象**として説明

する点で，上記研究群と明確に差別化される。

---

### 7.8 追加ベースライン（リスク感受・POMDP・サンプリング計画・分布RL）

- **[Kaelbling et al., 1998]** Planning and acting in partially observable stochastic domains, *Artificial Intelligence*. [`https://people.csail.mit.edu/lpk/papers/aij98.pdf`](https://people.csail.mit.edu/lpk/papers/aij98.pdf)

- **[Williams et al., 2017]** Information theoretic MPC for model-based reinforcement learning, *ICRA*. [`https://arxiv.org/abs/1707.02342`](https://arxiv.org/abs/1707.02342)

- **[Bellemare et al., 2017]** A distributional perspective on reinforcement learning, *ICML*. [`https://arxiv.org/abs/1707.06887`](https://arxiv.org/abs/1707.06887)

- **[Rockafellar & Uryasev, 2000]** Optimization of Conditional Value-at-Risk, *Journal of Risk*. [URL不明](不明)

# Appendix A. Precision 分離ルートAの数理補遺  

（Mathematical Appendix for Precision Decoupling: Route A）

## A.1 背景と目的

本補遺では、本文で採用した **Precision 分離ルートA** の数理的妥当性を明示する。  
特に、以下の査読指摘に対応することを目的とする。

1. Precision が  
   - 自由エネルギー中の誤差重み  
   - 知覚表現（SPM）の解像度制御  
   の **二重の役割**を担っている点の不整合
2. Haze → Precision → β → SPM → VAE → Haze  
   という **循環依存構造**
3. FEP における Precision 概念との理論的関係の曖昧さ

本研究ではこれらを回避するため、Precision を **機能的に分離された2種類の変数**として再定義する。

---

## A.2 Precision の機能分離

本研究では Precision を以下の2種類に分離する。

### A.2.1 推論 Precision（Inference Precision）

$$
\Pi^{\text{inf}}[k]
$$

- 自由エネルギー汎関数 $F$ における **予測誤差項の信頼性重み**
- FEP / Active Inference における **本来の Precision 概念**
- 本研究では **固定値**または **事前に調整された定数**として扱う

> 重要：  
> 本研究では $\Pi^{\text{inf}}$ を **学習・適応させない**。  
> これにより、FEP の理論的一貫性を保持する。

---

### A.2.2 知覚 Precision（Perceptual Precision）

$$
\Pi^{\text{perc}}[k]
$$

- 本研究で新たに導入する **工学的設計変数**
- 不確実性指標 Haze に基づき更新される
- **自由エネルギー汎関数には直接現れない**
- SPM における soft 集約パラメータ $\beta$ を制御する

---

## A.3 自由エネルギーの定式化（Precision 分離版）

本補遺では，Precision 分離の観点から，本文 2.2 における工学的自由エネルギーの定義と整合する形で，自由エネルギー $F$ を再掲する。

$$
F[k]
=
\underbrace{
\|\hat{\boldsymbol{x}}[k+1] - \boldsymbol{x}_g\|^2
}_{\text{Goal Attraction}}
+
\lambda
\sum_{m,n}
\phi\!\left(
\hat{\boldsymbol{y}}_{m,n}[k+1]
\right)
$$

ここで：

- $\hat{\boldsymbol{x}}[k+1]$ : 予測された将来位置
- $\boldsymbol{x}_g$ : 目標位置
- $\hat{\boldsymbol{y}}_{m,n}[k+1]$ : 予測 SPM のセル値
- $\phi(\cdot)$ : 危険性ポテンシャル関数

Pattern B（本文 2.2.2）では，予測は
$\hat{\boldsymbol{y}}[k+1]=f_{\text{dec}}(\boldsymbol{z},\boldsymbol{u}[k])$
で与えられ，行動生成は以下で定義される。

$$
\boldsymbol{u}^*[k]
=
\arg\min_{\boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k])}
\left[
F\!\left(\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})\right)
\right]
$$

勾配降下で解く場合は：

$$
\boldsymbol{u}[k]
\leftarrow
\boldsymbol{u}[k]
-
\eta
\frac{\partial}{\partial \boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k])}
\left[
F\!\left(\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})\right)
\right]
$$

> **重要な点**  
> 本研究では，知覚解像度制御に用いる $\Pi^{\text{perc}}$（→ $\beta$）は **自由エネルギー汎関数に直接現れない**。  
> 推論 Precision $\Pi^{\text{inf}}$ は固定値として扱い，工学的実装では学習率 $\eta$ 等に吸収される（したがって設計変数としての $\Pi^{\text{perc}}$ と混同されない）。

これにより Precision の二重使用は完全に回避される。

---

## A.4 Haze と知覚 Precision の関係

### A.4.1 Haze の定義（再掲）

Haze は世界モデル（VAE）から得られる **操作的な不確実性指標**として定義される。

$$
H[k] = \mathrm{Agg}\!\left(\boldsymbol{\sigma}_z^2[k-1]\right)
$$

ここで：

- $\boldsymbol{\sigma}_z^2[k-1]$ : 前時刻の VAE 潜在分散（本定義で用いる量）
- $\mathrm{Agg}(\cdot)$ : 算術平均による集約

---

### A.4.2 知覚 Precision の更新則

知覚 Precision は Haze の単調減少関数として定義される。

$$
\Pi^{\text{perc}}[k]
=
\frac{1}{H[k] + \epsilon}
$$

この定義により：

- 高不確実性（$H$ 大）→ 低解像度知覚
- 低不確実性（$H$ 小）→ 高解像度知覚

が保証される。

---

## A.5 β 変調と知覚解像度

SPM における soft 集約パラメータ $\beta$ は、知覚 Precision によって制御される。

$$
\beta[k]
=
\beta^{\min}
+
(\beta^{\max} - \beta^{\min})
\, s\!\left(\Pi^{\text{perc}}[k]\right)
$$

ここで $s(\cdot)$ は $[0,1]$ に正規化する単調関数である  
（本文では線形写像を採用）。

> **解釈**  
> - $\beta \to \infty$ : hard-min / hard-max（鋭い注意）
> - $\beta \to 0$ : 平均化された知覚（粗視化）

---

## A.6 循環依存の解消（1ステップ遅延）

循環構造を避けるため、以下の **時間遅延構造**を導入する。

$$
\boldsymbol{y}[k]
\;\rightarrow\;
\boldsymbol{\sigma}_z^2[k]
\;\rightarrow\;
H[k+1]
\;\xrightarrow{}\;
\Pi^{\text{perc}}[k+1]
\;\xrightarrow{}\;
\beta[k+1]
\;\xrightarrow{}\;
\boldsymbol{y}[k+1]
$$

すなわち：

- VAE は **前時刻の SPM** を入力とする
- Haze は **次時刻の知覚解像度**を制御する

これにより：

- 同時刻内の代数的循環は存在しない
- 初期条件 $\beta[0]$ を与えれば逐次計算が可能

---

## A.7 FEP との関係整理（査読対応要約）

| 項目 | 本研究の扱い |
|---|---|
| Precision（FEP） | $\Pi^{\text{inf}}$ として固定 |
| Precision（知覚） | $\Pi^{\text{perc}}$ として新規導入 |
| FEP との関係 | **厳密実装ではなく設計インスピレーション** |
| 理論的一貫性 | Precision の役割分離により保持 |

---

## A.8 本補遺の結論

- Precision の二重役割は **明示的分離**により解消された
- 循環依存は **1ステップ遅延構造**により排除された
- 本研究は FEP の厳密実装ではなく、  
  **不確実性適応型知覚設計の工学的原理**を提示する

この位置づけにより、理論的過剰主張を避けつつ、  
ロボット工学・群知能設計における再現性と実装可能性を確保する。

---

# Appendix B. 操作指令値に関する行動生成の数理補遺（Pattern B）

（Mathematical Appendix for Action Generation via Control Input Derivatives）

## B.1 背景と目的

本補遺では，v5.4 で採用した **Pattern B（Action-Conditioned World Model）** に基づく行動生成の数理的詳細を記述する。

Pattern B の核心は：
- **エンコーダには $\boldsymbol{u}$ を入力しない**：潜在分布は現在の観測のみに依存
- **デコーダには $\boldsymbol{u}$ を入力する**：将来予測は行動に条件付けられる

この設計により：
1. 潜在分布（および Haze）は $\boldsymbol{u}$ 探索前に確定
2. $\boldsymbol{u}$ 探索中に Haze / β は変動しない
3. 計算効率と最適化の安定性が確保される

---

## B.2 Action-Conditioned VAE の構造（Pattern B）

### B.2.1 エンコーダとデコーダの入出力

| 構成要素 | 入力 | 出力 |
|---------|------|------|
| **エンコーダ** | $\boldsymbol{y}[k]$ のみ | $q(\boldsymbol{z} \mid \boldsymbol{y})$ |
| **デコーダ** | $(\boldsymbol{z}, \boldsymbol{u}[k])$ | $\hat{\boldsymbol{y}}[k+1]$ |

### B.2.2 エンコーダ（u に依存しない）

$$
q_\phi(\boldsymbol{z} \mid \boldsymbol{y}[k])
=
\mathcal{N}(\boldsymbol{\mu}_z, \mathrm{diag}(\boldsymbol{\sigma}_z^2))
$$

**重要**：エンコーダには $\boldsymbol{u}$ は入力されない。潜在分布は $\boldsymbol{y}[k]$ のみに依存する。

### B.2.3 デコーダ（u に条件付け）

$$
\hat{\boldsymbol{y}}[k+1] = f_{\text{dec}}(\boldsymbol{z}, \boldsymbol{u}[k])
$$

デコーダは「$\boldsymbol{z}$ で符号化された世界状態で $\boldsymbol{u}$ を実行したらどうなるか」を予測する。

---

## B.3 行動生成の最適化問題（Pattern B）

### B.3.1 目的関数

$$
\boldsymbol{u}^*[k]
=
\arg\min_{\boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y}[k])}
\left[
F[\hat{\boldsymbol{y}}[k+1](\boldsymbol{z}, \boldsymbol{u})]
\right]
$$

**Pattern B の重要な特徴**：期待値は $q(\boldsymbol{z} \mid \boldsymbol{y}[k])$ に関して取られ，$\boldsymbol{u}$ には依存しない。

自由エネルギー $F$ は：

$$
F[\hat{\boldsymbol{y}}]
=
\|\hat{\boldsymbol{x}}[k+1] - \boldsymbol{x}_g\|^2
+
\lambda \sum_{m,n} \phi(\hat{\boldsymbol{y}}_{m,n})
$$

### B.3.2 勾配降下による解法

$$
\boldsymbol{u}[k]
\leftarrow
\boldsymbol{u}[k]
-
\eta
\frac{\partial}{\partial \boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y})}[F]
$$

Pattern B では $q(\boldsymbol{z} \mid \boldsymbol{y})$ が $\boldsymbol{u}$ に依存しないため：

$$
\frac{\partial}{\partial \boldsymbol{u}}
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y})}[F]
=
\mathbb{E}_{q(\boldsymbol{z}|\boldsymbol{y})}
\left[
\frac{\partial F}{\partial \boldsymbol{u}}
\right]
$$

期待値と微分の順序を交換できる点が，Pattern B の計算上の利点である。

---

## B.4 チェーンルールによる勾配計算

### B.4.1 勾配の分解

$$
\frac{\partial F}{\partial \boldsymbol{u}}
=
\sum_{m,n}
\frac{\partial \phi(\hat{\boldsymbol{y}}_{m,n})}{\partial \hat{\boldsymbol{y}}_{m,n}}
\cdot
\frac{\partial \hat{\boldsymbol{y}}_{m,n}}{\partial \boldsymbol{u}}
$$

### B.4.2 SPM 勾配

$$
\frac{\partial \phi(\hat{\boldsymbol{y}}_{m,n})}{\partial \hat{\boldsymbol{y}}_{m,n}}
=
\phi'(\hat{\boldsymbol{y}}_{m,n})
$$

ポテンシャル関数 $\phi$ として，例えば以下を用いる：

$$
\phi(y) = \exp(\alpha y) - 1
$$

この場合：

$$
\phi'(y) = \alpha \exp(\alpha y)
$$

### B.4.3 デコーダ勾配（Pattern B）

$$
\frac{\partial \hat{\boldsymbol{y}}_{m,n}}{\partial \boldsymbol{u}}
=
\frac{\partial f_{\text{dec}}(\boldsymbol{z}, \boldsymbol{u})}{\partial \boldsymbol{u}}
$$

**Pattern B の重要な特徴**：この勾配は**デコーダのみ**を通過する。エンコーダは $\boldsymbol{u}$ に依存しないため，エンコーダを通じた勾配は存在しない。

これにより，勾配計算が簡潔かつ安定になる。

---

## B.5 再パラメータ化トリック（Pattern B）

潜在変数 $\boldsymbol{z}$ のサンプリングを通じて勾配を伝播させるため，再パラメータ化を用いる：

$$
\boldsymbol{z}
=
\boldsymbol{\mu}_z(\boldsymbol{y})
+
\boldsymbol{\sigma}_z(\boldsymbol{y}) \odot \boldsymbol{\epsilon},
\quad
\boldsymbol{\epsilon} \sim \mathcal{N}(\boldsymbol{0}, \boldsymbol{I})
$$

**Pattern B の重要な特徴**：$\boldsymbol{\mu}_z$ と $\boldsymbol{\sigma}_z$ は $\boldsymbol{y}$ のみに依存し，$\boldsymbol{u}$ には依存しない。

したがって：

$$
\frac{\partial \boldsymbol{z}}{\partial \boldsymbol{u}} = \boldsymbol{0}
$$

これにより，$\boldsymbol{u}$ に関する勾配はデコーダ経路のみを通過し，計算が大幅に簡潔化される。

---

## B.6 アルゴリズム（Pattern B）

```
Algorithm: EPH Action Generation (Pattern B)
Input: y[k], u_init, η, N_iter
Output: u*[k]

1. // エンコーダ評価（1回のみ，u に依存しない）
2. (μ_z, σ_z) ← Encoder(y[k])
3. z ← μ_z + σ_z ⊙ ε, where ε ~ N(0, I)  // Reparameterization
4. 
5. // u の最適化ループ
6. u ← u_init
7. for i = 1 to N_iter do
8.     ŷ[k+1] ← Decoder(z, u)  // z は固定
9.     F ← ||x̂[k+1] - x_g||² + λ Σ φ(ŷ_{m,n})
10.    ∂F/∂u ← backprop(F, u)  // デコーダ経路のみ
11.    u ← u - η · ∂F/∂u
12. end for
13. return u
```

**Pattern B の利点**：
- エンコーダ評価はループ外で1回のみ
- z は u 探索中に固定
- 勾配計算はデコーダのみを通過

---

## B.7 本補遺の結論

- **Pattern B** では，エンコーダへの $\boldsymbol{u}$ 入力を排除し，デコーダのみが $\boldsymbol{u}$ に条件付けられる
- 行動生成は **デコーダを通じた予測 SPM に対する自由エネルギーの $\boldsymbol{u}$ 偏微分**で実現
- 潜在分布（および Haze）は $\boldsymbol{u}$ 探索前に確定し，安定した最適化が可能
- この構造は Dreamer, PlaNet 等の検証済みアーキテクチャと整合する
