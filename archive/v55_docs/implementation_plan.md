# EPH v5.5 実装プラン

v5.5 提案書に基づく今後の実装ロードマップ

---

## 📋 現状分析

### ✅ 完了済み

- Pattern B（Action-Conditioned VAE）の基本実装
- VAE エンコーダ/デコーダの分離構造
- Haze 計算と β 変調の基本ロジック
- SPM（Saliency Polar Map）の3チャネル実装
- 基本的なシミュレーション環境（4グループスクランブル交差）

### 🔧 現在の課題

1. **ForwardDiff 互換性**: 解決済み（controller.jl の修正完了）
2. **VAE 学習の安定性**: 訓練データの多様性と品質
3. **評価指標の実装**: Freezing Rate などの Primary/Secondary Outcomes
4. **Baseline 手法**: 比較対象の実装が未完

---

## 🎯 Phase 1: VAE 学習の完成と検証（優先度：高）

### 目標
Action-Conditioned VAE の学習を完了し、予測精度と Haze 妥当性を検証する

### タスク

#### 1.1 訓練データの拡充
- [ ] 複数の混雑度 ρ でデータ収集（低・中・高密度）
- [ ] 異なる他者行動モデル（Social Force, ORCA）でのロールアウト
- [ ] データ拡張：ノイズ付加、回転、スケール変換
- [ ] データセット分割：Train/Val/Test（IID + OOD 条件）

#### 1.2 VAE アーキテクチャの最適化
- [ ] エンコーダ/デコーダの層数・次元数のチューニング
- [ ] 潜在次元 D の最適化（現在の設定を評価）
- [ ] 正則化項（KL divergence weight β_kl）の調整
- [ ] 学習率スケジューリングの導入

#### 1.3 Haze 妥当性の検証
- [ ] Haze と1-step予測誤差の相関分析
- [ ] Calibration curve の作成（予測不確実性の校正）
- [ ] OOD 条件での Haze 挙動の確認
- [ ] 可視化ツールの作成（Haze の時系列プロット）

- `models/vae_v55_best.bson`（最適化された VAE モデル）
- `results/haze_validation_report.md`（Haze 妥当性レポート）

---

## 🎯 Phase 1.5: Action-Dependent Uncertainty (Pattern D)（優先度：最高）

### 目標
Phase 1 で判明した「負の相関」問題を解決するため、Action-Conditioned VAE のアーキテクチャを刷新し、行動依存の不確実性（Counterfactual Haze）を実現する。

### タスク

#### 1.5.1 アーキテクチャ変更 (Pattern B → Pattern D)
- [x] **Action-Dependent Encoder**:
  - 入力を $y_t$ から $(y_t, u_t)$ に変更
  - 「この行動をとった場合の不確実性」を推定可能にする
- [x] **Haze 定義の更新**:
  - $H(y_t, u_t) = \text{Agg}(\sigma_z^2(y_t, u_t))$
  - 因果フローの維持: $u_t$ 決定 $\rightarrow$ $H_t$ 算出 $\rightarrow$ $\beta_{t+1}$ 更新

#### 1.5.2 VAE 再学習
- [x] **データセット拡張**:
  - 既存の $(y_t, u_t, y_{t+1})$ データセットはそのまま利用可能
  - 必要に応じて $u_t$ の多様性を確保するための追加収集
- [/] **Loss 関数の調整**:
  - [x] $\beta_{KL}$ の増大（0.01 $\rightarrow$ 0.1）
  - [x] 潜在空間の正規化を強化し、分散が不確実性を反映するようにする

#### 1.5.3 検証プロセス (Counterfactual Validation)
- [x] **検証スクリプト更新**:
  - [x] 同一 $y_t$ に対して異なる $u$ を入力し、Haze が変動することを確認する
  - [x] 「危険な行動 $\rightarrow$ 高 Haze」「安全な行動 $\rightarrow$ 低 Haze」の対応関係を検証

**成果物**:
- `src/action_vae_pattern_d.jl` (または既存ファイルの改修)
- `models/action_vae_pattern_d_best.bson`
- `results/haze_validation_pattern_d.md`

---

## 🎯 Phase 2: 評価指標の実装（優先度：高）

### 目標
v5.5 提案書で定義された評価指標を実装し、定量評価を可能にする

### タスク

#### 2.1 Primary Outcome: Freezing Rate
- [x] Freezing 判定ロジックの実装
  - 速度閾値 ε_v の設定 (0.1 m/s)
  - 継続時間閾値 T_freeze の設定 (2.0 s)
- [x] Freezing イベントの記録と集計
- [/] 混雑度 ρ に対する Freezing Rate 曲線の生成

#### 2.2 Secondary Outcomes
- [x] **Success Rate**: 目標到達率
- [x] **Collision Rate**: 衝突発生率
- [x] **Jerk**: 加速度変化率の時間平均
- [x] **最小 TTC**: Time-to-Collision の最小値
- [ ] **Throughput**: 狭隘領域の通過流量
- [ ] **渋滞指標**: 局所密度の時間積分
- [ ] **群分断率**: 連結成分数の変化（群知能拡張用）

#### 2.3 評価スクリプトの作成
- [x] `scripts/evaluate_metrics.jl`（全指標の自動計算）
  - バッチ処理及び密度分析機能を追加
- [ ] 統計的検定（FDR 補正、効果量計算）
- [x] 結果の可視化（グラフ、テーブル生成）

**成果物**:
- `src/metrics.jl`（評価指標モジュール）
- `scripts/evaluate_metrics.jl`（評価スクリプト）
- `scripts/run_batch_experiments.jl`（バッチ実験スクリプト）

---

## 🎯 Phase 2.5: シナリオ拡張 (Corridor)（優先度：高）

### 目標
スクランブル交差点に加え、狭路（Corridor/Hallway）シナリオを実装し、ボトルネック環境での通過性能（Throughput）を評価する。

### タスク

#### 2.5.1 環境構築
- [ ] **Corridor 環境の実装**:
  - `src/dynamics.jl` に `init_corridor_obstacles` を追加
  - **双方向対面通行 (Bidirectional Flow)**:
    - Group 1 (East → West) vs Group 2 (West → East)
    - 幅 3.0m〜5.0m の通路で正面衝突・すれ違いを誘発
  - 通路を構成する壁障害物の配置
- [ ] **シナリオ切替機能**:
  - `run_simulation.jl` に `--scenario` 引数を追加（`scramble` vs `corridor`）

#### 2.5.2 評価指標拡張
- [ ] **Throughput 計算**:
  - 単位時間あたりに通路中心を通過したエージェント数
- [ ] **Lane Formation**:
  - レーン形成の秩序パラメータ（群知能評価の前段階）

#### 2.5.3 比較実験
- [ ] Corridor シナリオでのバッチ実験実行
- [ ] 密度別の Throughput vs Density 曲線の作成

**成果物**:
- `src/scenarios.jl`（または `src/dynamics.jl` 拡張）
- `results/corridor_evaluation_report.md`

---

## 🎯 Phase 3: Baseline 手法の実装（優先度：中）

### 目標
v5.5 提案書で定義された比較手法を実装し、EPH との性能比較を可能にする

### タスク

#### 3.1 古典的手法
- [ ] **Social Force Model** の実装
- [ ] **ORCA** の実装

#### 3.2 モデル予測制御系
- [ ] **Robust MPC** の実装（最悪ケース設計）
- [ ] **Tube MPC** の実装（不確実性集合）

#### 3.3 学習ベース手法（オプション）
- [ ] **SA-CADRL** の実装または既存実装の統合
- [ ] **SAC**（Soft Actor-Critic）の実装

#### 3.4 強化比較対象（推奨）
- [ ] **Risk-Sensitive MPC**（CVaR 正則化）
- [ ] **Belief-Space MPC / POMDP 近似**
- [ ] **Sampling-based Planning**（MPPI 等）
- [ ] **Uncertainty-aware RL**（アンサンブル不確実性）

#### 3.5 統一インターフェース
- [ ] 全手法で同一の SPM 観測を使用
- [ ] 同一シミュレーション条件での評価
- [ ] 公平な比較のためのハイパーパラメータ調整

**成果物**:
- `src/baselines/`（Baseline 手法のモジュール）
- `scripts/run_baseline_comparison.jl`（比較実験スクリプト）

---

## 🎯 Phase 4: アブレーションスタディ（優先度：中）

### 目標
EPH の各構成要素の寄与を明確化する

### タスク

#### 4.1 条件設定
- [ ] **A1**: 固定 β（Baseline）
- [ ] **A2**: 固定 β + SPM
- [ ] **A3**: 適応 β(H) + 直交座標
- [ ] **A4**: **EPH（提案手法）**

#### 4.2 集約関数の比較
- [ ] 算術平均（現在の実装）
- [ ] log-sum-exp
- [ ] max

#### 4.3 β 変調関数の比較
- [ ] 線形写像（現在の実装）
- [ ] 指数関数
- [ ] シグモイド関数

**成果物**:
- `results/ablation_study.md`（アブレーション結果レポート）

---

## 🎯 Phase 5: OOD 評価と一般化性能（優先度：中）

### 目標
未知条件での EPH の頑健性を検証する

### タスク

#### 5.1 未知混雑度（Density OOD）
- [ ] 学習時より高密度な環境での評価
- [ ] Freezing Rate vs Density 曲線の作成
- [ ] IID vs OOD の明確な区別

#### 5.2 未知他者モデル（Behavior OOD）
- [ ] 学習で用いない他者行動パターンの導入
- [ ] 速度分布、回避規則、停止傾向の変更
- [ ] 行動破綻の増加条件での比較

#### 5.3 観測ノイズ（Noise OOD）
- [ ] SPM 構築段階でのノイズ付加
- [ ] 検出欠落、位置誤差、遅延の系統的導入
- [ ] Haze → β 制御の頑健性評価

**成果物**:
- `results/ood_evaluation_report.md`（OOD 評価レポート）

---

## 🎯 Phase 6: 群知能への拡張（優先度：低）

### 目標
EPH を群知能システムへ拡張し、分散型知覚解像度制御を実装する

### タスク

#### 6.1 局所 Haze の実装
- [ ] 近傍エージェント集合 N_i[k] の定義
- [ ] 局所運動予測誤差からの Haze 推定
- [ ] 各エージェントの独立した β 変調

#### 6.2 群行動の評価
- [ ] 分離・整列・結合の鋭さ変調
- [ ] 群分断率の測定
- [ ] 秩序形成・相転移現象の解析

**成果物**:
- `src/swarm_extension.jl`（群知能拡張モジュール）
- `results/swarm_experiments.md`（群実験レポート）

---

## 🎯 Phase 7: 論文執筆と投稿準備（優先度：中）

### 目標
学術論文として成果をまとめ、投稿準備を行う

### タスク

#### 7.1 実験結果の整理
- [ ] 全実験データの統計的検定
- [ ] 効果量と信頼区間の計算
- [ ] 図表の作成（高品質な可視化）

#### 7.2 論文執筆
- [ ] Abstract の洗練
- [ ] Introduction の強化（Freezing 問題の動機付け）
- [ ] Related Work の拡充
- [ ] Results セクションの執筆
- [ ] Discussion の深化

#### 7.3 再現性の確保
- [ ] 乱数シード・初期条件の公開
- [ ] コードの整理とドキュメント化
- [ ] README の充実
- [ ] データセットの公開準備

#### 7.4 投稿先の選定
- **推奨ジャーナル**:
  - IEEE Transactions on Robotics
  - Autonomous Robots
  - Robotics and Autonomous Systems
- **推奨カンファレンス**:
  - ICRA（IEEE International Conference on Robotics and Automation）
  - IROS（IEEE/RSJ International Conference on Intelligent Robots and Systems）
  - RSS（Robotics: Science and Systems）

**成果物**:
- `paper/eph_v55_manuscript.tex`（論文原稿）
- `paper/supplementary_materials.pdf`（補足資料）

---

## 📅 推奨スケジュール

| Phase                   | 期間    | 優先度 |
| ----------------------- | ------- | ------ |
| Phase 1: VAE 学習の完成 | 2-3週間 | 🔴 高   |
| Phase 2: 評価指標の実装 | 1-2週間 | 🔴 高   |
| Phase 3: Baseline 実装  | 3-4週間 | 🟡 中   |
| Phase 4: アブレーション | 1-2週間 | 🟡 中   |
| Phase 5: OOD 評価       | 2週間   | 🟡 中   |
| Phase 6: 群知能拡張     | 2-3週間 | 🟢 低   |
| Phase 7: 論文執筆       | 4-6週間 | 🟡 中   |

**総期間**: 約3-4ヶ月（並行作業を含む）

---

## 🎓 学術的貢献の明確化

### 新規性

1. **知覚解像度制御**: 不確実性を知覚表現の解像度として設計変数化
2. **Precision 分離**: 推論用と知覚制御用の明確な役割分離
3. **Pattern B アーキテクチャ**: エンコーダ/デコーダの u 依存性の分離
4. **Freezing 抑制メカニズム**: 「不確実だから止まる」→「不確実だから粗く動く」

### 理論的位置付け

- FEP の厳密実装ではなく、**工学的設計原理としての再解釈**
- 既存の MPC/RL とは異なる不確実性の扱い方
- 群知能への自然な拡張可能性

---

## ⚠️ リスクと対策

### リスク

1. **VAE 学習の失敗**: 予測精度が不十分
   - **対策**: データ拡充、アーキテクチャ調整、事前学習
2. **Baseline との性能差が小さい**: 新規性の主張が弱まる
   - **対策**: OOD 条件での評価強化、Freezing Rate に焦点
3. **計算コストが高い**: リアルタイム性の問題
   - **対策**: 軽量モデルの導入、GPU 最適化
4. **査読での理論的批判**: FEP との関係が曖昧
   - **対策**: Appendix A/B での数理的厳密化、工学的立場の明示

---

## 🚀 次のステップ（即座に着手可能）

1. **VAE 訓練データの多様化**
   - `scripts/collect_action_vae_data.jl` を拡張
   - 複数の ρ, 他者モデルでデータ収集

2. **Freezing Rate 実装**
   - `src/metrics.jl` に Freezing 判定ロジックを追加
   - `scripts/evaluate_freezing.jl` を作成

3. **Social Force Baseline**
   - `src/baselines/social_force.jl` を実装
   - 同一 SPM 観測での比較実験

4. **Haze 妥当性の可視化**
   - `scripts/visualize_haze_correlation.jl` を作成
   - Haze vs 予測誤差のプロット

---

## 📚 参考実装リソース

- **ORCA**: [RVO2 Library](https://gamma.cs.unc.edu/RVO2/)
- **Social Force**: [PedSim](https://github.com/srl-freiburg/pedsim_ros)
- **MPPI**: [MPPI-Generic](https://github.com/AutoRally/autorally)
- **Belief-Space MPC**: [POMCP.jl](https://github.com/JuliaPOMDP/POMCP.jl)

---

## 💡 追加の検討事項

### 実環境実験の可能性

- シミュレーション検証後、実ロボットでの検証を検討
- ROS 統合、LiDAR/カメラからの SPM 構築
- 人間群集データでの社会的受容性評価

---

#### 1.6 プロジェクト構造の整理
- [x] **スクリプトの整理**:
  - 不要ファイルのアーカイブ化 (`scripts/archive`)
  - `run_all.sh` への一元化
- [x] **ドキュメント更新**:
  - `README.md`, `CLAUDE.md`, `GEMINI.md` の v5.5 対応
- [x] **`.gitignore` 最適化**:
  - ログ・一時ファイルの適切な除外
