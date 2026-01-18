---
title: "{{Project_Title}}"
type: Research_Proposal
status: 🟡 Draft
target_journal: "{{Target_Journal_Name}}"
target_conference: "{{Target_Conference_Name}}"
version: 3.0.0
date_created: "{ date }"
date_modified: "{ date }"
author: "{{Your_Name}}"
tags:
  - Research/Proposal
  - Status/Draft
---

# {{Project_Title}}

## 0. 戦略的ポジショニング (Strategic Positioning)

> [!TIP] 🧠 Phase 0: 執筆前の戦略策定 (The War Room)
> 本文を書き始める前に、この研究の「勝ち筋」を定義します。ここは自分と共著者のための戦略メモであり、論文にはそのまま載りませんが、最も重要な指針です。

### 0.1 ターゲットと採択要件
* **Target Journal/Conf**: (例: IEEE T-RO, NeurIPS, Nature Human Behaviour)
* **主な評価基準 (Acceptance Criteria)**: 
    * (例: アルゴリズムの新規性よりも、実機での堅牢性が重視される)
    * (例: 数理的な証明（Convergence Proof）が必須)
* **想定されるReject理由 (Pre-mortem)**: 
    * (例: 「既存手法Xとの差分が小さい」と言われそう)
    * **対策**: (例: 手法Xとの直接対決実験（Ablation study）をExp-2に組み込む)

### 0.2 SOTAとの差分 (The Delta Matrix)
> [!WARNING] 👮‍♂️ D-1 Check: 競合優位性の明確化
> 「何ができるか」ではなく「他と何が違うか」を記述してください。

| 比較軸 (Dimensions) | SOTA (既存技術/ベースライン) | 本研究 (Proposed) | なぜ勝てるか (Rationale) |
| :--- | :--- | :--- | :--- |
| **理論/原理** | (例: ヒューリスティック、線形近似) | (例: 凸最適化、非線形ダイナミクス) | 大域的最適解が保証されるため |
| **機能/性能** | (例: 静的環境のみ対応) | (例: 動的・未知環境に対応) | オンライン適応則の実装により |
| **実装/コスト** | (例: GPUクラスタ必須) | (例: エッジデバイスで動作) | 計算量 $O(N^2) \to O(N)$ |
| **信頼性/保証** | (例: 実験的確認のみ) | (例: Lyapunov安定性証明あり) | 理論的な安全性保証があるため |

### 0.3 コア・コントリビューション (3 Bullet Points)
1. **理論**: ...
2. **手法**: ...
3. **実証**: ...

---

## 1. 序論 (Introduction)

> [!NOTE] 📖 Phase 1: Story Arc
> 読者を「なぜ今、これをやる必要があるのか？(Why Now?)」と「それがどんな意味を持つのか？(So What?)」で惹きつけます。

### 1.1 背景と未解決問題 (Context & Problem)
* **広範な背景**: [社会課題や技術トレンド (例: 自動運転の普及に伴うHMIの重要性)]
* **具体的なボトルネック**: [既存アプローチが共通して抱える、本質的な限界点 (例: 予測不可能な人間行動に対する応答遅延)]

### 1.2 リサーチ・ギャップ (The Research Gap)
* **SOTAの限界**: [最新技術でも解決できていない具体的な欠点]
* **本質的な欠落**: [なぜ解決できていないのか？ (例: そもそもモデル化の前提が間違っている、計算量が爆発する等)]

### 1.3 本研究の目的 (Objective)
* **提案の核心**: 本研究は、[Core Concept] に基づく [Project_Name] を提案する。
* **解決のアプローチ**: [ギャップを埋めるための具体的なアプローチの概要]

---

## 2. 理論的枠組み (Theoretical Framework)

> [!WARNING] 📐 Phase 2: Math & Logic
> 特定の理論に依存せず、本研究が依拠する「公理」「仮定」「モデル」を定義します。曖昧な自然言語を排し、数式で定義してください。

### 2.1 問題の定式化 (Problem Formulation)
* **システム定義**: 
  $$x_{t+1} = f(x_t, u_t, w_t)$$
  (ここで $x$: 状態, $u$: 入力, $w$: 外乱)
* **目的関数/評価指標**:
  $$J = \sum_{t=0}^{T} c(x_t, u_t)$$

### 2.2 採用するコア理論/モデル (Core Theory / Model)
* **名称**: [採用する理論体系 (例: ベイズ推論, MPC, ゲーム理論)]
* **重要概念の定義**: [本研究で鍵となる概念 (例: Free Energy, Nash Equilibrium)]
* **仮定 (Assumptions)**:
    1. [仮定1 (例: システムは可観測である)]
    2. [仮定2 (例: ノイズはガウス分布に従う)]

---

## 3. 提案手法 (Proposed Methodology)

> [!IMPORTANT] ⚙️ Phase 3: Implementation Spec
> **「実験コード (C++/Python/Julia)」の仕様書**として機能するよう記述してください。エンジニアがこれを読めば実装できるレベルを目指します。

### 3.1 システム/実験構成 (Architecture)
> [!TIP] ここにシステム構成図（Mermaid等）が入る想定

* **入力 (Inputs)**:
    * データソース: [例: LiDAR点群, 為替ティックデータ]
    * 次元/型: [例: $\mathbb{R}^{3 \times N}$, Float32]
    * 頻度: [例: 30Hz]
* **処理ブロック (Process)**:
    * [前処理] $\to$ [メインアルゴリズム] $\to$ [後処理/安全装置]
* **出力 (Outputs)**:
    * 制御信号/予測値: [例: トルク指令 $\tau \in \mathbb{R}^6$]
    * 形式: [例: UDPパケット, CSVログ]

### 3.2 アルゴリズム詳細 (Algorithm Details)
* **アルゴリズム名**: `{{Algorithm_Name}}`

1. **初期化 (Initialization)**:
   * パラメータ $\theta$ を $\theta_0$ に設定。
2. **メインループ (Main Loop)**:
   * **Step 1 (観測)**: $y_t$ を取得。
   * **Step 2 (推定/学習)**: 以下の式で内部状態を更新。
     $$\hat{x}_t = \dots$$
   * **Step 3 (決定/制御)**: 最適化問題を解く。
     $$u^*_t = \arg\min_u \dots$$
3. **終了条件 (Termination)**: [例: エラー収束 or タイムアウト]

### 3.3 実装要件 (Implementation Requirements)
* **言語/フレームワーク**: (例: C++17, Python 3.10 / ROS2 Humble, PyTorch 2.0)
* **計算制約 (Constraints)**:
    * レイテンシ: [例: < 10ms per step]
    * メモリ: [例: < 4GB VRAM]
* **主要ライブラリ**: (例: Eigen, SciPy, OpenCV)

---

## 4. 検証計画 (Verification Plan)

> [!TIP] 📊 Phase 4: Validation Strategy
> 学術的信頼性を担保するための「客観的な物差し」を定義します。

### 4.1 検証シナリオ (Scenarios)
* **Exp-1: 概念実証 (Proof of Concept)**
    * **目的**: 提案手法が基本的な条件下で意図通り動作することの確認。
    * **環境**: [例: 1次元シミュレーション, Toy Problem]
* **Exp-2: 比較検証 (Benchmark Comparison)**
    * **目的**: SOTA (Section 0.2で定義) に対する定量的優位性の証明。
    * **環境**: [例: 標準ベンチマークデータセット, 実機実験]
* **Exp-3: アブレーション研究 (Ablation Study)**
    * **目的**: 提案手法の各構成要素（モジュール）の貢献度分析。
    * **方法**: [例: 適応機構をOFFにした場合との比較]

### 4.2 評価指標 (Metrics)
* **主要指標 (Primary Metric)**: [論文の主張を支える最も重要な数字 (例: 成功率, RMSE)]
    * **目標値**: SOTA比 +XX% / 誤差 < YY
* **副次指標 (Secondary Metrics)**:
    * 計算コスト (実行時間/メモリ)
    * 安定性 (分散, 最悪ケース)
    * 人間工学指標 (主観評価, 生理負荷) ※HRI等の場合

---

## 5. 関連研究 (Related Work)

### 5.1 カテゴリA: [理論的基盤]
* **文献**: [Author, Year]
* **本研究との位置関係**: [この理論を拡張・応用する]

### 5.2 カテゴリB: [競合手法/SOTA]
* **文献**: [Author, Year]
* **本研究との位置関係**: [本研究はこの手法の課題（XX）を解決する]

---

## 6. 予想される結果と意義 (Expected Results & Impact)

### 6.1 学術的意義 (Academic Significance)
* [この研究が通ることで、学術界の何が変わるか？新しいスタンダードになるか？]
* [「現象レベル」「機構レベル」「設計原理レベル」のどの階層で貢献するか？]

### 6.2 産業・社会への応用 (Broader Impact)
* [具体的なユースケース、経済的・社会的メリット]
* [実用化に向けたTRL (Technology Readiness Level) の向上]

---

## 7. 議論と結論 (Discussion & Conclusion)

### 7.1 限界点 (Limitations)
* [正直に記述する (例: 計算コストが高く、組み込みには向かない)]
* [将来の解決策の展望]

### 7.2 結論 (Conclusion)
* [全体サマリー]

---

## 8. 要旨 (Abstract) - *To be written last*

> [!INFO] 📝 Phase 5: Finalize
> ここまでの内容（背景、目的、手法、結果、意義）が固まってから、全体を300-500語で凝縮します。

* **Context**: [背景]
* **Gap**: [課題]
* **Objective**: [目的]
* **Method**: [手法（キーワード含む）]
* **Result (Expected)**: [主要な成果・数値]
* **Impact**: [意義]

**Keywords**: [Keyword1], [Keyword2], [Keyword3]

---

## 🛡️ AI-DLC Self-Correction Checklist

### 👮‍♂️ D-1: The "So What?" Test (新規性)
- [ ] 既存手法との差分（Delta）は、Section 0.2 で明確化されているか？
- [ ] 「弱いベースライン」とだけ比較して勝った気になっていないか？

### 👨‍🏫 B-2: The Rigor Test (厳密性)
- [ ] 数式中の記号（$x, u, \theta$）は全て Section 2 で定義されているか？
- [ ] 「収束する」「最適である」等の主張に対し、証明または強い経験的証拠があるか？

### 👷‍♂️ C-1: The Reality Test (実装・制御)
- [ ] Section 3.3 の計算制約（レイテンシ等）は、物理法則やハードウェア限界と矛盾していないか？
- [ ] シミュレーションだけでなく、実環境のノイズや不確実性を考慮しているか？

### 👩‍🔬 B-1: The Human Test (生理・倫理) ※該当する場合
- [ ] 人間の反応速度（約200ms）や認知限界を無視した設計になっていないか？
- [ ] 倫理的配慮（IRB等）についての記述はあるか？