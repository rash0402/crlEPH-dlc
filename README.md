# EPH (Emergent Perceptual Haze) プロジェクト

自由エネルギー原理（Free Energy Principle）に基づく、混雑環境における社会的ロボットナビゲーションの研究実装です。

## プロジェクト概要

**EPH（Emergent Perceptual Haze）** は、不確実性を**知覚解像度（Perceptual Precision）**の可変設計として扱うActive Inferenceの工学的拡張アーキテクチャです。予測信頼性に応じて知覚・注意の鋭さを連続的に変調することで、単体ロボットおよび群知能システムにおける停止（Freezing）・振動・分断といった不確実性起因の行動破綻を構造的に抑制します。

### 主要概念
- **SPM (Saliency Polar Map)**: 霊長類V1野を模倣した対数極座標の生体模倣的知覚表現
- **Haze**: 不確実性を定量化し、知覚解像度の制御に写像する操作的指標 $H(y,u)$
- **Pattern D Integration**: 行動依存の不確実性（Counterfactual Haze）を推定するVAEモデル
- **5D State Space (v7.2)**: 位置・速度・方向角を統合した動力学モデル $(x, y, v_x, v_y, \theta)$

## プロジェクト構造

```
crlEPH-dlc/
├── doc/                          # ドキュメントと研究提案書
│   ├── proposal_v7.3.md          # v7.3研究提案書
│   ├── implementation_plan_v7.2.md # v7.2実装計画
│   └── remote_simulation_guide.md  # リモートGPU実行ガイド
├── src/                          # Juliaメイン実装
│   ├── config.jl                 # システム設定
│   ├── spm.jl                    # SPM生成（12×12×3ch: 占有・顕著性・リスク）
│   ├── scenarios.jl              # シナリオ定義（Scramble/Corridor/Random Obstacles）
│   ├── dynamics.jl               # 5D動力学エンジン（RK4 + heading alignment）
│   ├── controller.jl             # FEPベース + Random walkコントローラ
│   ├── action_vae.jl             # Action-Dependent VAE (Pattern D)
│   ├── communication.jl          # ZMQ通信
│   ├── metrics.jl                # 評価指標・Freezing判定
│   └── logger.jl                 # HDF5ロギング
├── scripts/                      # 実行スクリプト
│   ├── create_dataset_v72_scramble.jl          # Scramble Crossingデータ収集
│   ├── create_dataset_v72_corridor.jl          # Corridorデータ収集
│   ├── create_dataset_v72_random_obstacles.jl  # Random Obstaclesデータ収集
│   ├── train_action_vae_v72.jl                 # VAE学習スクリプト（v7.2）
│   ├── run_simulation_eph.jl                   # EPHコントローラシミュレーション
│   ├── run_viewer_v72.sh                       # データビューア起動
│   ├── remote/                                 # リモート実行スクリプト
│   └── archive/                                # 旧スクリプトの退避場所
├── viewer/                       # Python可視化
│   ├── raw_viewer_v72.py         # v7.2生軌跡データビューア
│   ├── spm_reconstructor.py      # Python SPM生成器
│   └── detail_viewer.py          # SPM詳細ビュー
├── Project.toml                  # Julia依存関係
├── requirements.txt              # Python依存関係
└── CLAUDE.md                     # Claude Code向け開発ガイド
```

## クイックスタート

### 1. 依存関係のインストール

**自動セットアップ（推奨）**:
```bash
./scripts/setup.sh
```
このスクリプトが自動的に Julia と Python の依存関係をインストールします（初回は5-10分）。

**手動セットアップ**:
```bash
# Julia (1.10+)
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Python (3.10+)
~/local/venv/bin/pip install -r requirements.txt
```

詳細は [SETUP.md](SETUP.md) を参照してください。

### 2. データ収集 (v7.2)

**3シナリオのデータ収集（完了済み）**:
```bash
# Scramble Crossing（4群交差）
julia --project=. scripts/create_dataset_v72_scramble.jl \
  --densities 10 --seeds 1,2,3 --steps 1500

# Corridor（狭通路）
julia --project=. scripts/create_dataset_v72_corridor.jl \
  --densities 10 --seeds 1,2,3 --steps 1500

# Random Obstacles（障害物環境）
julia --project=. scripts/create_dataset_v72_random_obstacles.jl \
  --densities 10 --obstacle-counts 30 --seeds 1,2,3 --steps 1500
```

**データセット構成**:
- 3 scenarios × 3 seeds = **9 files (25MB)**
- Total: **450,000 samples** (5D state space)

### 3. データ可視化

```bash
# v7.2データビューア（SPM再構成機能付き）
./scripts/run_viewer_v72.sh data/vae_training/raw_v72/*.h5
```

### 4. VAE学習（次のステップ）

```bash
# Pattern D VAE学習
julia --project=. scripts/train_action_vae_v72.jl
```

## アーキテクチャ (v7.2 Current)

### v7.2の主要革新

**5D State Space + Heading Alignment**:
- 状態空間: $(x, y, v_x, v_y, \theta)$ - 位置・速度・方向角
- 動力学: RK4積分 + heading alignment ($d\theta/dt = k_{align} \cdot \Delta\theta$)
- 物理モデル: $m=70$kg, $F_{max}=150$N（歩行者モデル）

**Circular Obstacles**:
- 真の円形障害物（中心 + 半径）
- 点群近似から脱却→正確な衝突回避
- Random Obstaclesシナリオで検証済み

**Controller-Bias-Free Data Collection**:
- ランダムウォーク + 幾何学的衝突回避
- FEPコントローラの事前バイアスを排除
- 多様な状態-行動カバレッジを実現

**3つのシナリオ** (各3シード):
1. **Scramble Crossing**: 4群スクランブル交差（40エージェント、衝突率6.78%）
2. **Corridor**: 狭通路での対面流動（20エージェント、衝突率1.91%）
3. **Random Obstacles**: ランダム配置の円形障害物環境（40エージェント+30障害物、衝突率2.16%）

**Raw Trajectory Architecture**:
- SPMを保存せず、生軌跡データ（pos, vel, heading, u, d_goal）のみ保存
- 学習時にオンザフライでSPM再構成
- ストレージ効率: v6.3と同様（25MB/9 files）

### データ構造 (HDF5 v7.2)
```
trajectory/
  ├── pos        [T, N, 2]  # 位置 (x, y)
  ├── vel        [T, N, 2]  # 速度 (vx, vy)
  ├── heading    [T, N]     # 方向角 θ (NEW in v7.2)
  ├── u          [T, N, 2]  # 制御入力 (Fx, Fy)
  ├── d_goal     [N, 2]     # ゴール方向ベクトル (NEW in v7.2)
  └── group      [N]        # グループID

obstacles/
  └── data       [M, 3]     # 円形障害物 (cx, cy, radius) (NEW in v7.2)

events/
  ├── collision       [T, N]  # 衝突フラグ
  └── near_collision  [T, N]  # ニアミスフラグ

metadata/
  ├── scenario, version, density, seed, max_steps, dt, ...
  ├── collision_rate, near_collision_rate, freezing_rate
  └── n_agents

v72_params/  (NEW)
  ├── mass         # m = 70kg
  ├── k_align      # k_align = 4.0 rad/s
  └── u_max        # F_max = 150N

spm_params/
  ├── n_rho, n_theta  # 12×12 grid
  ├── sensing_ratio   # 9.0 (D_max=18.0m for 100×100m world)
  └── r_robot, fov_deg
```

## 開発マイルストーン

### Phase 1: Data Collection ✅ **完了 (2026-01-18)**
- [x] 5D動力学エンジン実装（RK4 + heading alignment）
- [x] 円形障害物システム（center + radius）
- [x] 3シナリオデータ収集スクリプト
- [x] データ収集完了（9 files, 25MB, 450k samples）
- [x] データビューア検証（SPM再構成機能確認）

### Phase 2: VAE Training 🎯 **次のステップ**
- [ ] Pattern D VAE学習（v7.2データ）
- [ ] 学習曲線の収束確認
- [ ] VAE予測精度の評価

### Phase 3: EPH Controller & Evaluation
- [ ] EPHコントローラ実装（Haze変調 + Free Energy最小化）
- [ ] 3シナリオでの評価実験
- [ ] Haze効果の定量評価

## 機能

### v7.2 (開発中) 🚧
- ✅ **5D Dynamics**: RK4積分 + heading alignment
- ✅ **Circular Obstacles**: 真の円形障害物システム
- ✅ **Data Collection**: 3シナリオ × 3シード（450k samples）
- ✅ **Data Viewer**: SPM再構成機能付きビューア
- 🎯 **VAE Training**: Pattern D学習（次のステップ）
- ⏳ **EPH Controller**: Haze変調コントローラ（未実装）

### v6.3 (完了) ✅
- **Controller-Bias-Free Data**: ランダムウォークによるバイアスフリーデータ収集
- **Random Obstacles**: 再現可能な障害物生成（obstacle_seed）
- **Raw Trajectory Viewer**: リアルタイムSPM再構成機能
- **3シナリオ × 3シード**: 合計9データセット（10MB）

## リモートGPU実行

GPU搭載サーバーでのVAE学習用スクリプトを提供:

```bash
# リモートサーバーでのデータ収集
./scripts/remote/sync_up.sh
./scripts/remote/run.sh "julia --project=. scripts/create_dataset_v72_scramble.jl"

# リモートGPUでのVAE学習
./scripts/remote/run.sh "julia --project=. scripts/train_action_vae_v72.jl"

# 結果の取得
./scripts/remote/sync_down.sh
```

詳細は [doc/remote_simulation_guide.md](doc/remote_simulation_guide.md) を参照。

## ライセンス

このプロジェクトは研究目的で開発されています。

## 著者

五十嵐 洋（Hiroshi Igarashi）
東京電機大学
