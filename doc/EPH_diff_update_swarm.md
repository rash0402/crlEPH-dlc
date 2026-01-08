# EPH 更新差分ドキュメント（群知能拡張）

## 目的
本ドキュメントは、最初に提示された **EPH（Emergent Perceptual Haze）研究提案書** を基準とし、
その後の議論を通じて追加・更新された内容を **差分（diff）** として整理するものである。
本差分を反映することで、元ドキュメントを **最新の研究構想（特に群知能文脈）** に更新可能とする。

---

## 1. 研究の位置づけの更新

### Before
- 主応用：混雑環境における単体ロボットの Freezing Robot Problem
- EPHの役割：不確実性下での行動停滞（Freezing）回避

### After（更新）
- 主位置づけ：
  - **Active Inference の工学的拡張**
  - 不確実性に応じて「知覚解像度（perceptual geometry）」を変調する設計原理
- Freezing は **代表的な破綻モードの一例** に再定義
- 群知能・人間操作支援・AI Safety などへの一般化可能な基盤原理として再フレーミング

**追記推奨セクション**：
- Introduction
- Academic Novelty
- Discussion（Design Principle レベル）

---

## 2. 新たに明確化された設計原理（コア差分）

### 追加された中核命題
> 不確実性に応じて知覚の有効分解能を変形し，
> 意思決定勾配の条件数を制御することで，
> 不確実性起因の閉ループ破綻（停止・振動・分断）を抑制する。

### 用語整理（追記）
- Precision：
  - 誤差項の重みではなく **知覚表現・注意鋭さを制御するメタ変数**
- Haze：
  - 世界モデル（または簡易予測）に基づく **epistemic uncertainty の操作的指標**

---

## 3. 群知能（Swarm Intelligence）文脈の新規追加

### 3.1 応用領域の拡張（新規）

**追加応用**：
- 群ロボット制御
- 群の相転移制御（拡散 ↔ 収束）
- 渋滞・分断・振動の抑制
- 局所不確実性に基づく適応的群行動

---

### 3.2 群知能版 EPH の最小構成（MVP）

#### 新規定義：局所Haze
各エージェント i に対し：

- 近傍エージェントの **運動予測誤差** を用いた Haze 定義

\[
\hat{x}_j[k] = x_j[k-1] + v_j[k-1]\Delta t
\]

\[
H_i[k] = \mathrm{Agg}\left( \{\|x_j[k] - \hat{x}_j[k]\|^2\}_{j \in \mathcal{N}_i} \right)
\]

（※ VAE 導入前の MVP 設計として明示）

---

### 3.3 Precision → 群行動パラメータ変調（新規）

\[
\Pi_i[k] = \frac{1}{H_i[k] + \epsilon}
\]

- Precision を **BOIDs 行動の鋭さ（softmax 温度 β）** に写像

\[
\beta_i[k] = \beta^{min} + (\beta^{max} - \beta^{min}) \cdot s(\Pi_i[k])
\]

---

### 3.4 Soft Attention 化された BOIDs（新規）

#### 分離行動（Separation）の更新

- 従来：最近傍への強い反応（不連続・振動しやすい）
- 更新：softmax による注意重み付き集約

\[
\alpha_{ij}[k] =
\frac{\exp(\beta_i[k] s_{ij}[k])}
{\sum_{\ell}\exp(\beta_i[k] s_{i\ell}[k])}
\]

\[
a_{sep,i}[k] = \sum_j \alpha_{ij}[k] \frac{-r_{ij}[k]}{\|r_{ij}[k]\| + \epsilon}
\]

→ 不確実性が高いほど「平均化された穏やかな反応」を実現

---

## 4. 評価指標の拡張（群知能向け）

### Before
- Freezing Rate
- Collision Rate
- Jerk

### After（追加）
- Throughput（狭隘通過流量）
- 局所密度の時間積分（渋滞指標）
- 群分断率（connected components）
- 速度・加速度の高周波成分（振動）

---

## 5. アブレーション設計の更新

### 追加された比較条件
- A1：通常 BOIDs（固定）
- A2：Soft Attention のみ（β固定）
- A3：β(H) 変調のみ
- A4：**EPH（Haze → Precision → β変調 + Soft Attention）**

→ 群知能における因果検証が可能に

---

## 6. 将来拡張の整理（位置づけ更新）

### 明確化されたロードマップ
1. MVP：予測誤差ベース Haze（学習なし）
2. 拡張：VAE / 世界モデル由来 Haze
3. 発展：
   - 群内 Haze 伝播
   - 個性・模倣強度の Haze 依存変調
   - Active Inference 群制御への統合

---

## 7. 元ドキュメントへの反映ガイド

**必須更新セクション**
- Abstract（応用の一般化）
- Academic Novelty（Precision = perceptual geometry 制御）
- Methodology（群知能MVPの追加サブセクション）
- Verification Strategy（群知能タスク・指標）
- Discussion（設計原理の抽象化）

---

## 8. まとめ（差分の本質）

- Freezing 問題 → **不確実性起因の行動破綻一般**
- 単体ロボット → **群知能・分散系**
- Precision 重み付け → **知覚解像度・注意鋭さの設計**
- EPH → **Active Inference の工学的拡張原理**

本差分を反映することで、EPH は
「特定タスクの手法」から
**不確実性適応型知覚設計という汎用工学原理**
として再定義される。
