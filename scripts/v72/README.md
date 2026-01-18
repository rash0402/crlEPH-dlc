# V7.2 Scripts

**v7.2データ収集、学習、可視化のためのバージョン固有スクリプト**

---

## 概要

v7.2実装（5D状態空間 + Heading Alignment）を扱うスクリプト群です。

汎用エントリポイント（`scripts/*.sh`, `scripts/*.jl`）から自動的に呼び出されます。

---

## 📊 1. データ可視化

### `viewer.sh`

v7.2軌跡データのインタラクティブビューワーを起動

#### 使用方法

```bash
# 汎用エントリポイント経由（推奨）
./scripts/view_data.sh

# 直接実行
./scripts/v72/viewer.sh data/vae_training/raw_v72/v72_scramble_d10_s1_*.h5
```

詳細: `viewer/v72/README.md`

---

## 🔬 2. データ収集

### `dataset/all.sh`

3つのシナリオ（Scramble, Corridor, Random Obstacles）のデータ収集を一括実行

#### 使用方法

```bash
# 汎用エントリポイント経由（推奨）
./scripts/collect_data.sh

# 直接実行
./scripts/v72/dataset/all.sh

# 個別シナリオ
julia --project=. scripts/v72/dataset/scramble.jl
julia --project=. scripts/v72/dataset/corridor.jl
julia --project=. scripts/v72/dataset/random_obstacles.jl
```

#### 出力

- **Scramble**: 3ファイル（3シード）
- **Corridor**: 3ファイル（3シード）
- **Random Obstacles**: 3ファイル（3シード）
- **合計**: 9ファイル、25MB、450,000サンプル

---

## 🤖 3. VAE学習

### `train_vae.jl`

Action-Conditioned VAEの学習スクリプト

#### 使用方法

```bash
# 汎用エントリポイント経由（推奨）
./scripts/train_vae.jl

# 直接実行
julia --project=. scripts/v72/train_vae.jl
```

#### 出力

- **モデル**: `models/action_vae_v72_best.bson`
- **学習ログ**: `results/v72/vae_tuning/v72_training_*.h5`

---

## 🎮 4. EPHシミュレーション

### `simulate_eph.jl`

v7.2物理モデルでEPHコントローラーをテスト

#### 使用方法

```bash
# 汎用エントリポイント経由（推奨）
./scripts/run_simulation.jl

# 直接実行
julia --project=. scripts/v72/simulate_eph.jl
```

---

## 📁 ディレクトリ構造

```
scripts/
├── collect_data.sh               # 汎用データ収集エントリポイント
├── train_vae.jl                  # 汎用VAE学習エントリポイント
├── run_simulation.jl             # 汎用シミュレーションエントリポイント
├── view_data.sh                  # 汎用ビューワーエントリポイント
└── v72/                          # v7.2固有スクリプト
    ├── README.md                 # このファイル
    ├── dataset/
    │   ├── all.sh                # 一括データ収集
    │   ├── scramble.jl
    │   ├── corridor.jl
    │   └── random_obstacles.jl
    ├── train_vae.jl              # v7.2 VAE学習
    ├── simulate_eph.jl           # v7.2 EPHシミュレーション
    └── viewer.sh                 # v7.2ビューワー起動
```

---

## 🔄 ワークフロー例

### 1. 初回セットアップ

```bash
# Python仮想環境
python3 -m venv ~/local/venv
~/local/venv/bin/pip install h5py numpy matplotlib

# Juliaプロジェクト
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 2. データ収集

```bash
# 汎用エントリポイント使用
./scripts/collect_data.sh

# 結果確認
ls -lh data/vae_training/raw_v72/*.h5 | wc -l
# → 9 (Scramble×3, Corridor×3, Random×3)

# データ可視化
./scripts/view_data.sh
```

### 3. VAE学習

```bash
# 汎用エントリポイント使用
./scripts/train_vae.jl

# 結果確認
ls -lh models/action_vae_v72_best.bson
ls -lh results/v72/vae_tuning/
```

### 4. EPHシミュレーション

```bash
# 汎用エントリポイント使用
./scripts/run_simulation.jl

# 結果可視化
./scripts/view_data.sh data/logs/eph_sim_*.h5
```

---

## 💡 バージョン管理のメリット

### 汎用エントリポイント

ユーザーはバージョンを意識せずに実行:

```bash
./scripts/collect_data.sh   # 自動的にv7.2を使用
./scripts/train_vae.jl      # 自動的にv7.2を使用
```

環境変数で切り替え可能:

```bash
EPH_VERSION=v73 ./scripts/collect_data.sh  # 将来のv7.3を使用
```

### バージョン固有スクリプト

開発者はバージョン固有の実装に集中:

```bash
scripts/v72/dataset/scramble.jl    # v7.2固有のScramble実装
scripts/v73/dataset/scramble.jl    # v7.3固有のScramble実装
```

---

## 🎯 現在のステータス (v7.2 Phase 2)

**完了:**
- ✅ Phase 1: Controller-bias-free data collection (9 files, 25MB)

**進行中:**
- 🎯 Phase 2: VAE Training
- 🎯 Phase 3: Haze Effect Evaluation

---

**汎用エントリポイントで効率的にv7.2開発を進めてください！** 🚀
