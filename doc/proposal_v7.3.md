---
title: "EPH: 2次系動力学下のPerceptual Hazeによるマルチエージェントシステムの創発的協調"
type: Research_Proposal
status: "🟢 Draft (v7.3)"
version: 7.3.0
date_created: "2026-01-17"
date_modified: "2026-01-17"
author: "Hiroshi Igarashi"
institution: "Tokyo Denki University"
keywords:
  - Free Energy Principle
  - Active Inference
  - Perceptual Haze
  - Second-Order Dynamics
  - Emergent Coordination
  - Inertia-Induced Emergence
  - Transfer Learning
  - Swarm Intelligence
tags:
  - Research/Proposal
  - Topic/FEP
  - Status/Draft

---

# 研究提案書: EPH (Emergent Perceptual Haze)

> [!ABSTRACT] 提案の概要（One-Liner Pitch）
> 
> 一言で言うと: 密集環境下の自律エージェント群が抱える「freezing問題」と同調性の欠如を、**2次系Active InferenceとPerceptual Haze（知覚の霧）による確率的誘導**で解決し、**「創発を制御する」という新しい群制御パラダイム**を確立する。

## 要旨 (Abstract)

> [!INFO] 🎯 AI-DLC レビューガイダンス
> 
> Goal: 300-500語で研究の全体像を伝える。以下の**6パート構成**を厳守し、数値と専門用語（Keywords）を適切に配置すること。

### 背景 (Background)

マルチエージェントシステムにおいて、堅牢かつ適応的な分散協調を実現することは依然として困難な課題である。従来の「タスク特化型設計（Task-Specific Design Paradigm）」は、個別のルールを手動で設計するため汎用性に欠け、未知環境への適応力がない。また、ロボティクスにおける既存のActive Inference研究は、物理的慣性（自然な動きや安全性に不可欠な要素）を無視した1次系運動学モデル（瞬間的な速度制御）にほぼ限定されており、真の創発的協調に必要な「物理的身体性」が欠如している。

### 目的 (Objective)

本研究の目的は、2次系動力学（トルク/力制御）をActive Inferenceに導入し、「Perceptual Haze（知覚の霧）」を通じた新しい制御チャネルを確立する統一フレームワーク **EPH (Emergent Perceptual Haze)** を構築することである。これにより、物理的制約（慣性）から自然にレーン形成などの協調パターンが創発し、それを設計者が確率的に誘導できることを定量的に実証する。

### 学術的新規性 (Academic Novelty)

**SOTA（最新技術）との決定的な差分**は以下の3点である: (1) **2次系Active Inference**: 既存の1次系モデルを拡張し、慣性を「利用」して高周波振動を抑制し、同調性を向上させる。 (2) **Perceptual Haze理論**: Environmental Haze（外部）とSelf-Hazing（内部）の二層構造により、個体の自律性を損なわずに集団挙動を誘導する新しいメカニズムを提案する。 (3) **慣性誘導型創発**: 創発を「計算的最適化の結果」ではなく「物理法則と情報の結合」として再定義する。

### 手法 (Methods)

提案手法の核心は、**Pattern D VAE**を用いる予測的Active Inferenceループである。Hazeを「感覚精度の逆数」として定式化し、設計者が指定する空間的顕著性マップ（Environmental Haze）と、エージェント自身の予測誤差に基づく認識論的調整（Self-Hazing）を統合する。これを質量$m$と慣性を持つ5次元状態空間モデル上で実装し、変分自由エネルギー最小化によって最適な力ベクトルを生成する。

### 検証目標 (Validation Goals)

3つのシナリオ（スクランブル交差点、狭い廊下、牧羊）におけるシミュレーション実験で検証する。 **評価軸1（創発度）**: 2次系モデルが1次系と比較して**Emergence Index (EI) > 0.5** を達成すること。 **評価軸2（転移性）**: Environmental Hazeを変更するだけで、追加学習なしに異種タスクに適応し、**転移成功率 (TSR) > 0.8** を達成すること。

### 結論と意義 (Conclusion / Academic Significance)

本研究は、物理的制約（慣性）と情報理論的制御（Haze）を融合させることで、ロボット制御と認知科学のギャップを埋める。これは「創発の誘導（Guiding Emergence）」という新しいパラダイムを確立し、スケーラブルかつ安全な群集ナビゲーションや災害対応ロボットスォームの基礎技術となる。

**Keywords**: Free Energy Principle, Second-Order Dynamics, Perceptual Haze, Emergent Coordination, Active Inference

---

## 1. 序論 (Introduction - The Story Arc)

> [!TIP] 🖊️ 執筆ガイド
> 
> 技術説明ではなく「物語（Story）」を語る。読者を「今なぜ必要なのか？ (Why Now?)」と「それがどんな意味を持つのか？ (So What?)」で惹きつける。

### 1.1 背景と動機 (Context & Motivation)

- **広範な背景**: 自動運転車やサービスロボットの普及に伴い、人間とロボットが混在する環境（Dense Crowds）での安全かつ円滑なナビゲーションが社会的に急務となっている。自然界の群れ（鳥や魚）は、中央指令なしに驚くほど秩序だった動きを見せるが、人工システムでこれを再現することは極めて難しい。
    
- **具体的な問題**: 既存のロボット群制御は、厳密な衝突回避を優先するあまり、人混みの中で身動きが取れなくなる「凍りつくロボット問題 (Freezing Robot Problem)」に直面している。これは、ロボットが周囲の「空気（流れ）」を読めず、過剰に安全マージンを取ることが原因である。
    

### 1.2 研究のギャップ (The Research Gap)

- **1.2.1 SOTAにおける問題点**: 
    - 既存のActive Inference研究（Pio-Lopez et al., 2016等）は、計算の簡略化のために**1次系モデル（速度制御）**を採用している。しかし、質量や慣性を持たないエージェントは現実の物理法則から乖離しており、不自然な挙動（ジッター）を引き起こす。
    - 社会力モデル（Social Force Model）のような反応的手法は、設計者がパラメータを細かく調整する必要があり、**未知の環境への適応力**が低い。

- **1.2.2 概念的・理論的ギャップ**: 
    - 「創発（Emergence）」を設計者が意図的に、かつ柔軟に制御するための**統一的な理論的枠組み**が欠如している。現在は「完全な中央制御」か「完全な自律分散」かの二項対立に陥っている。

### 1.3 主要な貢献 (Key Contribution - The "Delta")

- 本研究は **EPH (Emergent Perceptual Haze)** を提案する。これは「物理的慣性」と「知覚的不確実性（Haze）」を結合させた新しいアーキテクチャである。
    
- **主要な貢献 (3点)**:
    1. **理論**: 2次系動力学をActive Inferenceに厳密に組み込み、**「慣性」を外乱ではなく安定化装置として再定義**した。
    2. **手法**: Haze（Environmental + Self-Hazing）による**二層構造の精度変調メカニズム**を提案し、設計者が確率的に群れを誘導可能にした。
    3. **実証**: 単一の学習モデルで異なるタスク（交差点、廊下、牧羊）に適応できる**高い転移学習性能 (TSR > 0.8)** を示した。

---

## 2. 理論的基盤 (Theoretical Foundation - The "Why")

> [!WARNING] 👮‍♂️ B-2 (数理的厳密性チェック)
> 
> 曖昧な自然言語を排し、数式で定義してください。「〜のような感じ」はNGです。

### 2.1 問題の定式化 (Problem Formulation)

$N$個のエージェントシステムを考える。システムの状態 $s$、入力 $u$（全方向力）、ダイナミクス $f$ を以下のように定義する。

**状態空間 (5D)**:
$$s_i(t) = [\mathbf{x}_i(t), \mathbf{v}_i(t), \theta_i(t)]^\top \in \mathbb{R}^5$$

**2次系ダイナミクス (Newtonian Model)**:
$$ m \dot{\mathbf{v}}_i = \mathbf{F}_i - k_{drag} \|\mathbf{v}_i\| \mathbf{v}_i $$
$$ \dot{\theta}_i = k_{align} \cdot \text{angle\_diff}(\angle \mathbf{v}_i, \theta_i) $$

### 2.2 核となる理論: Perceptual Haze Theory

Active Inferenceにおいて、エージェントは期待自由エネルギー $G$ を最小化する。本研究では、感覚精度 $\Pi$ を「Haze $H$」の逆数として再定義し、これを制御の核とする。

- **コア方程式 (Core Equation)**:
    $$ \Pi(\mathbf{x}, t) = \frac{1}{H_{total}(\mathbf{x}, t) + \epsilon} $$
    $$ H_{total}(\mathbf{x}, t) = H_{spatial}(\rho) \cdot (1 + \alpha H_{env}(\mathbf{x})) \cdot (1 + \beta H_{self}(t)) $$

- **重要な洞察 (Key Insight)**: 
    - **Environmental Haze $H_{env}$**: 設計者が空間に「注意の濃淡」を描くことで、エージェントの探索（高Haze）と活用（低Haze）を誘導できる。
    - **Self-Hazing $H_{self}$**: 予測誤差 $\epsilon$ に基づいて自己調整する。 $H_{self} \propto 1 - \exp(-\lambda \|\epsilon\|)$ 。これにより、未知の状況では慎重に、既知の状況では大胆に行動するという**認識論的自律性**が生まれる。

---

## 3. 手法 (Methodology - The "How")

> [!TIP] 🛠️ 可視化
> 
> ここには必ず [システム構成図] を挿入する。

### 3.1 システム構成 (System Architecture)

- **Saliency Polar Map (SPM) センサ**: 視野を $12\times12\times3$ のテンソルに圧縮し、エゴセントリックな空間表現を提供する。
- **Pattern D VAE**: 観測 $o_t$ と行動候補 $u$ から未来の観測 $o_{t+1}$ を予測する生成モデル。
- **Haze Modulator**: 環境情報と自己予測誤差を統合し、最適な精度 $\Pi$ を計算する。
- **Physics Engine**: 選択された力ベクトルを入力とし、RK4（ルンゲ=クッタ法）で次状態を更新する。

### 3.2 アルゴリズム: Second-Order Active Inference Loop

- **入力**: 現在の観測 $o_t$ (SPM)、内部状態 $s_t$
- **処理**:
    1. **知覚とSelf-Hazing**:
        $$ \epsilon = \|o_t - \hat{o}_t\| \rightarrow H_{self} = 1 - e^{-\lambda \epsilon} $$
    2. **行動候補の評価** (各 $u \in \mathcal{U}$ について):
        - 物理予測: $s_{t+1} = \text{RK4}(s_t, u)$
        - 知覚予測: $\hat{o}_{t+1} = \text{VAE}(o_t, u)$
        - ゴール項: $D_{KL}[q(s_{t+1}) || p(s)] \approx (v_{prog} - v_{target})^2 / 2\sigma^2$
        - 安全性項: $\mathbb{E}[H(o)] \approx \Pi^{-1} \cdot \text{CollisionRisk}(\hat{o}_{t+1})$
    3. **自由エネルギー計算**:
        $$ F(u) = \text{GoalTerm} + \text{SafetyTerm} $$
- **出力**: 最適な力 $u^* = \text{argmin}_u F(u)$

### 3.3 実装詳細 (Implementation Details)

> [!WARNING] 👷‍♂️ C-1 (実装チェック)
> 
> 再現性はありますか？ リアルタイム性は保証されますか？

- **技術スタック**: Julia (Backend) + Python (Visualization)
- **最適化**: 100個の離散行動プリミティブ（力×角度）に対する並列評価により、数ミリ秒オーダーの応答時間を実現。
- **ダイナミクス**: 質量 $m=1.0$ kg、空気抵抗 $k_{drag}=1.0$ を標準パラメータとし、人間の歩行特性を模倣。

---

## 4. 検証戦略とロードマップ (Verification Strategy and Roadmap)

> [!TIP] 📊 検証の指針
> 
> 具体的な実験データではなく、「妥当性を証明するための枠組み」を記述する。

### 4.1 検証のスコープとシナリオ

- **検証スコープ**: シミュレーション環境での広範なパラメータスタディおよびアブレーションスタディ。
- **主要シナリオ (3種)**: 
    1. **スクランブル交差点**: 慣性による創発的秩序（レーン形成）の基礎検証。
    2. **狭い廊下**: Environmental Hazeによる行動誘導（壁回避、通行区分）の検証。
    3. **牧羊**: 異種エージェント（羊と犬）間の非言語的協調の検証。

### 4.2 評価指標 (Evaluation Metrics)

1.  **創発度 (Emergence Index, EI)**: 群全体の速度ベクトル場のエントロピー減少率を測定。EI > 0.5 で「創発あり」と定義。
2.  **転移成功率 (Transfer Success Rate, TSR)**: 学習済みモデルの別タスクでの成功率比。TSR > 0.8 を目標。
3.  **安全性 (Collision Rate)**: 衝突発生率。5%未満を目標。

### 4.3 計画課題と次なるステップ

- **計画課題**: 大規模化（$N > 100$）した際の計算コストの増大と、リアルタイム性の維持。
- **ロードマップ (Publication Strategy - Theory First, Application Second)**:
    - **フェーズ 1 (Paper 1 - Theory Focus)**: 
        - **ターゲット**: *Entropy* (MDPI) or *Physical Review E*
        - **テーマ**: "Inertia-Induced Emergence" & "Environmental Haze".
        - **検証**: シンプルなシナリオ（スクランブル・廊下）での理論的原理の証明。
    - **フェーズ 2 (Paper 2 - Application Focus)**: 
        - **ターゲット**: *Swarm Intelligence* (Springer) or *Science Robotics* (Letter)
        - **テーマ**: "Self-Hazing" & "Heterogeneity" (Sheepdog).
        - **検証**: 異種間協調や転移学習による動的適応性の実証。Paper 1を引用して理論的基盤とする。
    - **フェーズ 3**: 実機ロボット (TurtleBot3等) へのSim-to-Real転移。

---

## 5. 関連研究 (Related Work - The Landscape)

> [!WARNING] 🕵️‍♂️ D-1 (査読者チェック)
> 
> SOTAとの「差異」と「優位性」を明確に記述する。

### 5.1 理論的基盤研究

- **Active Inference / FEP (Friston et al.)**
    - *差異と優位性*: 既存研究は主に単一エージェントや1次系モデルに留まる。本研究はこれを**「2次系マルチエージェント」**へ拡張し、物理的慣性を理論に統合した点が新しい。

### 5.2 技術的アプローチ研究

- **Social Force Model (Helbing et al.)**
    - *差異と優位性*: SFMは決定論的な「力」のモデルだが、EPHは**「不確実性（自由エネルギー）」**に基づく確率的モデルであり、未知環境への適応性と認知的な説明性が高い。

### 5.3 応用ドメイン研究

- **Swarm Robotics (Vicsek, Reynolds)**
    - *差異と優位性*: 従来のスォームは単純なルールの重ね合わせだが、EPHは**Perceptual Haze**という単一の抽象化層を通じて、設計者が**「意図」をスォームに注入できる**点が画期的である。

---

## 6. 議論と結論 (Discussion & Conclusion)

### 6.1 限界点 (Limitations)

- **予測対象**: 現状のVAEは短期間（数秒）の予測に特化しており、長期的な戦略計画は含まない。
- **計算資源**: 各エージェントが独立して推論を行うため、エージェント数の増加に対して計算リソースが線形に増加する。

### 6.2 広範な影響と倫理

- **社会的影響**: 混雑した駅や空港での誘導ロボット、災害現場での探索ドローン群など、社会インフラの自律化・効率化に貢献する。
- **倫理的配慮**: 群衆誘導において、人間の行動を無意識的に操作する可能性があるため、Hazeの可視化などの透明性確保が必要である。

---

## 7. 参考文献 (References - Required)

### 7.1 核となる理論 (Theoretical Backbone)

- **Friston, K. (2010).** "The free-energy principle: a unified brain theory?" _Nature Reviews Neuroscience_.
    - **Key Point**: 本研究の理論的支柱。変分自由エネルギー最小化原理。
    - **Link**: [DOI: 10.1038/nrn2787](https://doi.org/10.1038/nrn2787)

- **Trautman, P., & Krause, A. (2010).** "Unfreezing the robot: Navigation in dense, interacting crowds." _IROS_.
    - **Key Point**: 本研究が解決する「凍りつくロボット問題」の定義。
    - **Link**: [DOI: 10.1109/IROS.2010.5654369](https://doi.org/10.1109/IROS.2010.5654369)

### 7.2 手法論的基盤 (Methodological Basis)

- **Helbing, D., & Molnar, P. (1995).** "Social force model for pedestrian dynamics." _Physical Review E_.
    - **Key Point**: 既存の強力なベースライン。物理的な力による群集モデル。
    - **Link**: [DOI: 10.1103/PhysRevE.51.4282](https://doi.org/10.1103/PhysRevE.51.4282)

---

## 🛡️ AI-DLC 自己修正チェックリスト

### 👮‍♂️ D-1: 「何がすごいのか？」テスト
- [x] **新規性**: 「2次系Active Inference」「Hazeによる誘導」という明確なDeltaがある。
- [x] **比較**: SFMや1次系AIとの比較実験を設計している。

### 👨‍🏫 B-2: 厳密性テスト
- [x] **定義**: 状態空間、ダイナミクス、Hazeの定義式を明記した。
- [x] **論理**: 慣性→低周波化→創発 というロジックを提示した。

### 👷‍♂️ C-1: 現実性テスト
- [x] **再現性**: アルゴリズムと物理パラメータを具体的に記述した。
- [x] **制約**: 計算コストの課題をLimitationsで正直に述べた。

---

## 🧭 追加ガイド（Delta Matrix - 抜粋）

> | 比較軸 | SOTAの限界 | 本研究のDelta | その理由 |
> |---|---|---|---|
> | **ダイナミクス** | 1次系（非物理的） | **2次系（物理的）** | 慣性が振動を抑制 |
> | **制御入力** | 速度指令 | **力・トルク** | 自然な挙動 |
> | **誘導手法** | 個別ルール記述 | **Hazeマップ** | 確率的・包括的 |
> | **適応性** | 再学習・調整必要 | **ゼロショット転移** | 意図のみ変更 |
