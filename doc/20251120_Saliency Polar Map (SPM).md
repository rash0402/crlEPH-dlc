---
title: "Saliency Polar Map: A Bio-inspired, Scalable Perceptual Framework for Swarm Intelligence via Active Inference"
type: research_proposal
status: draft
status_icon: 🟡
version: 1.1.0
date_created: 2025-11-20
date_modified: 2025-11-20
author: Hiroshi Igarashi
institution: Tokyo Denki University
tags:
  - Research/Proposal
  - Topic/FEP
  - Topic/SwarmIntelligence
  - Status/Draft
keywords:
  - Saliency Polar Map
  - Active Inference
  - Swarm Robotics
  - Log-polar Mapping
  - Bio-inspired Vision
  - Swarm Heterogeneity
bibliography: references.bib
csl: ieee.csl
---

# Research Proposal: Saliency Polar Map (SPM) : 能動推論に基づく群知能のための生物模倣型スケーラブル知覚フレームワーク

> [!ABSTRACT] **Purpose**: 本ドキュメントは、群知能エージェントのための新規環境知覚フレームワーク「Saliency Polar Map (SPM)」に関する研究プロポーザル（Ver 1.1）である。SPMを将来的な動作生成研究（別プロジェクト）のコア技術として位置づけ、その知覚モデルとしての学術的妥当性と優位性を確立することを目的とする。

## 0. Abstract

> [!INFO] 🎯 AI-DLC Review Guidance **Focus**: 背景（群知能のスケーラビリティ問題）→ 目的（SPMの提案）→ 方法（個性×FEP×対数極座標）→ 結果（圧倒的な計算効率と群の多様性効果）

### Writing Template

**Background**: 大規模な群ロボットシステム（Swarm Robotics）において、各エージェントが環境を効率的に認識することは極めて重要である。しかし、従来の占有格子地図（Occupancy Grid Maps）[[1]](https://www.google.com/search?q=%23ref1 "null") は、環境サイズに対して計算コストが二次関数的（$O(L^2)$）に増大するため、リソース制約の厳しい群エージェントへの実装には限界があった。

**Objective**: 本研究は、生物の視覚システムと自由エネルギー原理（Free Energy Principle: FEP）[[4]](https://www.google.com/search?q=%23ref4 "null") を統合し、計算コストを劇的に削減しつつ、生存に必要な顕著性（Saliency）を保持する「Saliency Polar Map (SPM)」を提案する。

**Methods**: 我々は、(1) 任意の解像度（$N_r \times N_\theta$）にスケーラブルな対数極座標マッピング、(2) 社会心理学的「個性（Personal Space）」[[5]](https://www.google.com/search?q=%23ref5 "null") をFEPの生成モデルにおける事前分布（Prior）として数理的に定義する新規アルゴリズム、(3) 上丘のLooming検出特性を模倣した注意機構を導入する。

**Results**: 比較評価の結果、SPMは従来のグリッドマップと比較してデータ次元を90%以上削減（$O(1)$相当）しつつ、衝突回避に必要な局所情報を保持することを示す。さらに、個性パラメータの分散（ノイズ）を導入した群は、均質な群と比較して局所的なデッドロックの解消率が有意に向上することを示唆する。

**Conclusion**: SPMは、計算資源の限られたエージェント群に「個性的かつ適応的な知覚」を与える基盤技術となり、次世代の群知能アルゴリズムの標準的な知覚表現となる可能性を持つ。

**Keywords**: Saliency Polar Map, Active Inference, Swarm Robotics, Log-polar Mapping, Bio-inspired Vision

## 1. Academic Core Identity (学術的核)

### 1.1 Academic Novelty (学術的新規性)

**既存手法との決定的な差分（Delta）**: 従来の環境表現手法は、「幾何学的正確さ」を追求するか（例: Occupancy Grid）、あるいは「ブラックボックスな圧縮」を行うか（例: VAE/Latent Vector）の二極化状態にある。本研究の最大の新規性は、**「生物学的・社会心理学的意味（Personality/Saliency）」を明示的に組み込んだ幾何学的圧縮表現**を提案する点にある。

#### Concept Novelty: Personality-driven FEP Integration

従来、FEP（自由エネルギー原理）は抽象的な脳理論として扱われることが多かった。本研究では、社会心理学における「パーソナルスペース ($ps$)」を、FEPの数式における**「感覚精度の変調項（Precision Modulation）」**として具体的に定式化した点が独創的である。

- **従来**: $ps$ は単なるIF文の閾値（If distance < ps then avoid）。
    
- **提案**: $ps$ は生成モデルの事前分布を規定するハイパーパラメータであり、予測誤差の重みを動的に制御する。
    

#### Technical Novelty: Scalable Log-Polar Tensor

従来の対数極座標画像 [[2]](https://www.google.com/search?q=%23ref2 "null") が「画素（輝度）」を扱うのに対し、SPMは「意味（占有・速度・脅威度）」を扱う**テンソル表現**へと拡張した。また、マップサイズを固定せず $N_r \times N_\theta$ で抽象化することで、タスクに応じたスケーラビリティを保証する。

### 1.2 Academic Reliability (学術的信頼性)

**理論的・生理学的裏付け**: 本手法は、単なるヒューリスティックではなく、以下の確立された知見に基づき設計されている。

1. **網膜皮質変換**: 霊長類のV1野における対数的な空間圧縮 [[6]](https://www.google.com/search?q=%23ref6 "null")。
    
2. **Looming Detection**: 脊椎動物の上丘（Superior Colliculus）における、接近速度/距離（$\tau^{-1}$）に基づく脅威検出 [[12]](https://www.google.com/search?q=%23ref12 "null")。
    
3. **Weber-Fechner則**: 知覚強度が刺激の対数に比例するという心理物理法則。
    

### 1.3 Academic Significance (学術的意義)

**群知能分野への貢献**: 数千台規模のエージェント群シミュレーションあるいは実機実装において、個々のエージェントがリッチなSLAM（Simultaneous Localization and Mapping）を実行することは現実的ではない。SPMは、**「必要最低限の計算資源で、生存に必要な知覚を得る」**ためのミニマリズム的解法を提供し、大規模群システムの実現可能性を飛躍的に高める。

## 2. Theoretical Foundation (理論的枠組み)

### 2.1 Abstract Polar Grid Definition

SPMは、エージェントを中心とした局所座標系において、径方向ビン $N_r$ と角度ビン $N_\theta$ により定義される抽象テンソル空間 $\mathcal{S}$ を形成する。

$$
\mathcal{S} \in \mathbb{R}^{N_r \times N_\theta \times N_c}
$$

ここで $N_c$ はチャネル数（占有、径方向速度、接線方向速度）である。

**径方向ビン（Radial Bins）**

1. **Intimate Zone (Bin 0)**: $d \in [0, ps]$ — パーソナルスペース内を高解像度で表現。
2. **Ambient Zone (Bin $1 \dots N_r-1$)**: $d \in (ps, d_{\max}]$ — Weber-Fechner則に従って対数的に解像度を落とす。

距離 $d$ は個性パラメータ $ps$ を境に非線形マッピングされるため、近距離の脅威を強調しつつ遠距離情報を圧縮できる。

**スケーラビリティ**

$N_r, N_\theta$ は固定値ではなく、計算資源 $C_{comp}$ と要求精度 $A_{req}$ に基づいて設計者が選択する。

$$
(N_r, N_\theta) = f(C_{comp}, A_{req})
$$

### 2.2 FEP Integration: Personality as Precision

自由エネルギー原理の枠組みでは、エージェントは変分自由エネルギー $\mathcal{F}$ を最小化するように知覚・行動する。SPMでは、個性パラメータ $ps_i$ が予測誤差 $\epsilon$ の重み付けを担う精度行列 $\boldsymbol{\Pi}$ を変調する。

$$
\mathcal{F} \approx \frac{1}{2} \epsilon^T \boldsymbol{\Pi}(d, ps_i) \epsilon + \dots
$$

$$
\boldsymbol{\Pi}(d, ps_i) \propto \sigma\left( \frac{ps_i - d}{\tau} \right) \cdot \mathbf{I}
$$

ここで $\sigma(\cdot)$ はシグモイド関数である。パーソナルスペースへの侵入が生じると $\boldsymbol{\Pi}$ の値が急増し、Active Inference に基づく回避行動が誘発される。これは「自分のパーソナルスペースには侵入者が存在しない」という強い事前信念を持つことと同値であり、個性に応じた回避挙動を数理的に保証する。

## 3. Positioning & Related Work (関連研究との比較)

### 3.1 Landscape Comparison

SPMの立ち位置を明確にするため、代表的な3つの環境表現アプローチと比較する。

| Approach           | Core Concept            | Scalability             | Biological Basis | Example                     |
|--------------------|-------------------------|-------------------------|------------------|-----------------------------|
| **Metric Maps**    | 正確な幾何学配置        | Low ($O(L^2)$)          | None             | Occupancy Grid [[1]](#ref1) |
| **Feature Maps**   | 視覚特徴の対数変換      | Medium ($O(N \log N)$) | High (Retina)    | Log-Polar Image [[2]](#ref2) |
| **Latent Maps**    | NNによる圧縮表現        | High ($O(1)$)           | Low (Blackbox)   | World Models [[3]](#ref3)   |
| **SPM (Proposed)** | **意味論的サリエンス** | **High ($O(N_r N_\theta)$)** | **Very High** | **This Work**               |

### 3.2 Detailed Analysis

**vs. Occupancy Grid Maps (Elfes, 1989)** [[1]](#ref1)  
OGMは静的な環境地図作成には最適だが、群ロボットのような動的かつ多数のエージェントが存在する環境では、情報の更新コストと通信コストがボトルネックとなる。SPMは、情報をエージェント中心の相対座標かつ低次元テンソルに圧縮することで、この問題を解決する。

**vs. Log-Polar Mapping (Schwartz, 1977)** [[2]](#ref2)  
従来の対数極座標マッピングは画像処理（ピクセル操作）に主眼を置いており、ロボットの物理的な「回避」や「追従」に必要な意味情報（距離、相対速度、脅威度）への変換が含まれていない。SPMは、物理量（$m, m/s$）を直接マッピングする点で異なる。

**vs. World Models (Ha & Schmidhuber, 2018)** [[3]](#ref3)  
World ModelsはVAEを用いて環境を潜在ベクトル $z$ に圧縮する手法だが、$z$ の各次元が何を表すか（解釈可能性）は低い。SPMは各セルが物理的な空間方向に対応しており、デバッグや行動ルールの記述（明示的な安全性の保証など）が容易である。

## 4. Methodology (実装手法)

### 4.1 Soft-Mapping Mechanism (Differentiability)

SPMの生成プロセスは、微分可能な Gaussian Kernel を用いたソフトマッピングとして実装される。これにより、将来的にSPMをニューラルネットワークの一部として組み込み、End-to-End で学習させることが可能となる。

あるオブジェクト $k$ の位置 $(d_k, \\theta_k)$ が与えられたとき、SPM上のセル $(i, j)$ への寄与 $w_{ijk}$ は以下で計算される。

$$
w_{ijk} = \\alpha_k \\, \\exp\\left(-\\frac{(r_i - \\ln d_k)^2}{2\\sigma_r^2} - \\frac{(\\phi_j - \\theta_k)^2}{2\\sigma_\\theta^2}\\right)
$$

ここで $\\alpha_k$ は対象の脅威度（Looming係数）であり、上丘の特性に基づき接近速度に応じて動的に増幅される。

### 4.2 Tensor Architecture

実装上、SPMは PyTorch テンソルとして扱われる。

- **Shape**: `(Batch_Size, Channels, Nr, Ntheta)`
- **Channels**:
  1. **Occupancy** — 物体の存在確率（密度）
  2. **Radial Velocity** — 接近/離反速度（脅威度に直結）
  3. **Tangential Velocity** — 横切る動き（オプティカルフロー相当）

## 5. Experimental Design (検証計画)

> [!NOTE]
> 本プロポーザルでは、SPMを用いた「動作生成」ではなく、SPM自体の「知覚表現としての妥当性」を検証することに焦点を当てる。

### 5.1 Objective

SPMが、従来のグリッドマップと比較して、**「圧倒的に少ない情報量で、同等の脅威検出能力を持つか」**を検証する。

### 5.2 Evaluation Metrics

1. **Compression Ratio (圧縮率)**  
   $$
   CR = 1 - \frac{\text{SPM Size}}{\text{OGM Size}}
   $$
2. **Reconstruction Accuracy (再構成精度)**  
   元の環境情報を再構成した際の誤差（近傍領域と遠方領域で重みを変えて評価）。
3. **Threat Detection Latency (脅威検出遅延)**  
   高速で接近する物体を「脅威」として認識するまでのタイムラグ。

### 5.3 Simulation Setup

- **Environment**: Pythonベースの2D群シミュレータ。
- **Scenarios**:
  1. 静的障害物環境でのナビゲーション。
  2. 100体規模のランダムウォーク・エージェント群における相互回避。
- **Comparison**:
  - Baseline: $50 \\times 50$ Local Occupancy Grid
  - SPM: $N_r = 6, N_\\theta = 12$（パラメータ可変）

### 5.4 Swarm Heterogeneity Experiment (群の多様性実験)

> [!IMPORTANT] Adopted from AI-DLC Review
> 個性パラメータの分散が、群全体のパフォーマンスに与える影響を検証する。

**Hypothesis**: 均質な（Homogeneous）パーソナルスペースを持つ群よりも、多様な（Heterogeneous）パーソナルスペースを持つ群の方が、狭路でのすれ違いや密集状態におけるデッドロックを効率的に解消できる。

**Method**: エージェント群の個性パラメータ $ps_i$ に正規分布ノイズを加える。

$$
ps_i \sim \mathcal{N}(\mu_{ps}, \sigma_{ps}^2)
$$

分散 $\sigma_{ps}^2$ を変化させ、群の流動性（平均移動速度、停止時間）を比較する。

**Significance**: SPMが単なる知覚圧縮モデルではなく、**「個体差（ノイズ）を設計パラメータとして組み込むことで、群の創発的秩序を制御できる」**ことを示唆する。

## 6. References

<a id="ref1"></a> [1] A. Elfes, "Using occupancy grids for mobile robot perception and navigation," _Computer_, vol. 22, no. 6, pp. 46-57, 1989. [doi: 10.1109/2.30720](https://doi.org/10.1109/2.30720 "null")

<a id="ref2"></a> [2] E. L. Schwartz, "Spatial mapping in the primate sensory projection: Analytic structure and relevance to perception," _Biological Cybernetics_, vol. 25, no. 4, pp. 181-194, 1977. [doi: 10.1007/BF00337256](https://doi.org/10.1007/BF00337256 "null")

<a id="ref3"></a> [3] D. Ha and J. Schmidhuber, "World Models," _NeurIPS_, 2018. [doi: 10.5281/zenodo.1207631](https://doi.org/10.5281/zenodo.1207631 "null") [URL](https://worldmodels.github.io/ "null")

<a id="ref4"></a> [4] K. J. Friston, "The free-energy principle: a unified brain theory?," _Nature Reviews Neuroscience_, vol. 11, no. 2, pp. 127-138, 2010. [doi: 10.1038/nrn2787](https://doi.org/10.1038/nrn2787 "null")

<a id="ref5"></a> [5] E. T. Hall, _The Hidden Dimension_. Doubleday, 1966. [URL](https://archive.org/details/hiddendimension00hall "null")

<a id="ref6"></a> [6] J. C. Horton and W. F. Hoyt, "The representation of the visual field in human striate cortex," _Archives of Ophthalmology_, vol. 109, no. 6, pp. 816-824, 1991. [doi: 10.1001/archopht.1991.01080060080030](https://doi.org/10.1001/archopht.1991.01080060080030 "null")

<a id="ref7"></a> [7] L. Itti and C. Koch, "Computational Modelling of Visual Attention," _Nature Reviews Neuroscience_, vol. 2, no. 3, pp. 194–203, 2001. [doi: 10.1038/35058500](https://doi.org/10.1038/35058500 "null")

<a id="ref8"></a> [8] C. W. Reynolds, "Flocks, herds and schools: A distributed behavioral model," _ACM SIGGRAPH Computer Graphics_, vol. 21, no. 4, pp. 25-32, 1987. [doi: 10.1145/37401.37406](https://doi.org/10.1145/37401.37406 "null")

<a id="ref9"></a> [9] J. Kennedy and R. Eberhart, "Particle swarm optimization," in _Proceedings of ICNN'95 - International Conference on Neural Networks_, vol. 4, pp. 1942-1948, 1995. [doi: 10.1109/ICNN.1995.488968](https://doi.org/10.1109/ICNN.1995.488968 "null")

<a id="ref10"></a> [10] J. H. R. Maunsell and D. C. Van Essen, "Functional properties of neurons in middle temporal visual area of the macaque monkey," _Journal of Neurophysiology_, vol. 49, no. 5, pp. 1127–1147, 1983. [doi: 10.1152/jn.1983.49.5.1127](https://journals.physiology.org/doi/10.1152/jn.1983.49.5.1127 "null")

<a id="ref11"></a> [11] C. C. Pack and R. T. Born, "Temporal dynamics of a neural solution to the aperture problem in visual area MT of macaque monkey," _Nature_, vol. 409, no. 6823, pp. 1040–1042, 2001. [doi: 10.1038/35059085](https://doi.org/10.1038/35059085 "null")

<a id="ref12"></a> [12] C. J. Duffy and R. H. Wurtz, "Sensitivity of MST neurons to optic flow stimuli," _Journal of Neurophysiology_, vol. 65, no. 6, pp. 1329–1345, 1991. [doi: 10.1152/jn.1991.65.6.1329](https://journals.physiology.org/doi/10.1152/jn.1991.65.6.1329 "null")

## Document Metadata

**Version History**:

- v0.9: Initial draft based on SPM Technical Note v4.2
    
- v1.0: Refined for Research Proposal (Scalability & Comparative Analysis added)
    
- v1.1: Added Generative Model & Heterogeneity Hypothesis (AI-DLC Review Feedback)
    

**Export Commands**:

```
pandoc Research_Proposal_SPM.md \
--bibliography=references.bib \
--csl=ieee.csl \
-o proposal.pdf
```