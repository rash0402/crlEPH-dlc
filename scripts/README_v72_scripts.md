# V7.2 Shell Scripts

**v7.2データ収集と可視化のための便利スクリプト集**

## 概要

v7.2実装（5D状態空間 + Heading Alignment）のデータ収集と可視化を簡単に実行するためのシェルスクリプトです。

---

## 📊 1. データ可視化スクリプト

### `view_v72_data.sh`

**v7.2軌跡データのインタラクティブビューワーを起動**

#### 機能
- Python仮想環境（`~/local/venv`）を自動アクティベート
- 依存パッケージ（h5py, numpy, matplotlib）の自動チェック
- データディレクトリの存在確認
- **GUIファイル選択ダイアログ**（デフォルト）
- **ターミナルメニュー**（`--menu`オプション）
- エラーハンドリングとユーザーフレンドリーなメッセージ

#### 使用方法

**基本的な起動（GUIダイアログ - デフォルト）:**
```bash
./scripts/view_v72_data.sh
```

実行すると、グラフィカルなファイル選択ダイアログが表示されます（Tkinter）。
- ファイルブラウザーでナビゲート
- プレビュー機能
- ファイル名でソート

**ターミナルメニューモード:**
```bash
./scripts/view_v72_data.sh --menu
```

実行すると、ターミナル内でファイル一覧が表示されます：
```
========================================
Select a file to visualize:
========================================

  1) v72_corridor_d10_s1_20260114_182900.h5
  2) v72_corridor_d10_s2_20260114_182900.h5
  3) v72_corridor_d10_s3_20260114_182900.h5
  ...
 48) v72_scramble_d20_s3_20260114_182838.h5

Enter file number (1-48), or press Enter for most recent:
```

- **数字を入力**: 指定したファイルを開く
- **Enterのみ**: 最新のファイルを自動選択

**ファイルを直接指定:**
```bash
# Scramble Crossing
./scripts/view_v72_data.sh data/vae_training/raw_v72/v72_scramble_d10_s1_*.h5

# Corridor
./scripts/view_v72_data.sh data/vae_training/raw_v72/v72_corridor_d15_s2_*.h5

# Random Obstacles
./scripts/view_v72_data.sh data/vae_training/raw_v72/v72_random_d20_n50_s3_*.h5
```

#### 必要な準備

**Python仮想環境の作成（初回のみ）:**
```bash
python3 -m venv ~/local/venv
~/local/venv/bin/pip install h5py numpy matplotlib
```

#### 出力例

```
========================================
V7.2 Raw Trajectory Viewer
========================================

Checking Python dependencies...
✓ All dependencies found

Found 45 HDF5 file(s) in data/vae_training/raw_v72

Usage:
  1. File selection dialog will appear (default)
  2. Or specify file as argument:
     ./scripts/view_v72_data.sh path/to/file.h5

Launching V7.2 Trajectory Viewer...
```

---

## 🔬 2. データ収集スクリプト

### `collect_v72_data.sh`

**3つのシナリオ（Scramble, Corridor, Random Obstacles）のデータ収集を一括実行**

#### 機能
- 全3シナリオの自動実行
- シナリオ選択オプション（個別実行可能）
- クイックテストモード（100ステップ）
- ログファイル自動保存（`logs/v72_*.log`）
- 進捗状況のリアルタイム表示

#### 使用方法

**全シナリオ実行（フルデータ収集）:**
```bash
./scripts/collect_v72_data.sh
```

**個別シナリオのみ実行:**
```bash
# Scramble Crossingのみ
./scripts/collect_v72_data.sh --scramble-only

# Corridorのみ
./scripts/collect_v72_data.sh --corridor-only

# Random Obstaclesのみ
./scripts/collect_v72_data.sh --random-only
```

**クイックテストモード（動作確認用）:**
```bash
./scripts/collect_v72_data.sh --quick
```
- 100ステップのみ
- 密度=10, シード=1のみ
- 障害物=30のみ

**ヘルプ表示:**
```bash
./scripts/collect_v72_data.sh --help
```

#### デフォルト設定

```yaml
Densities: 10, 15, 20
Seeds: 1, 2, 3
Steps: 1500
Obstacle counts (Random): 30, 50, 70
```

**生成ファイル数:**
- Scramble: 9ファイル（3密度 × 3シード）
- Corridor: 9ファイル（3密度 × 3シード）
- Random Obstacles: 27ファイル（3密度 × 3障害物数 × 3シード）
- **合計: 45ファイル**

#### 出力例

```
================================================================================
V7.2 Data Collection: 5D State Space with Heading Alignment
================================================================================

Configuration:
  Densities: 10,15,20
  Seeds: 1,2,3
  Steps: 1500
  Obstacle counts: 30,50,70

Scenarios to run:
  ✓ Scramble Crossing (4-group intersection)
  ✓ Corridor (2-group bidirectional)
  ✓ Random Obstacles (4-group + obstacles)

Start data collection? [y/N]: y

Starting data collection...

========================================
1. Scramble Crossing
========================================
...
✓ Scramble Crossing completed

========================================
2. Corridor
========================================
...
✓ Corridor completed

========================================
3. Random Obstacles
========================================
...
✓ Random Obstacles completed

================================================================================
Data Collection Complete
================================================================================

Generated files: 45
Total size: 203M

Next steps:
  1. View data: scripts/view_v72_data.sh
  2. Train VAE: julia --project=. scripts/train_action_vae_v72.jl
  3. Test EPH: julia --project=. scripts/test_eph_v72.jl
```

---

## 📁 ディレクトリ構造

```
scripts/
├── view_v72_data.sh              # データ可視化スクリプト
├── collect_v72_data.sh           # データ収集スクリプト
├── raw_v72_viewer.py             # Pythonビューワー本体
├── README_v72_scripts.md         # このファイル
├── README_raw_v72_viewer.md      # ビューワー詳細ドキュメント
├── create_dataset_v72_scramble.jl
├── create_dataset_v72_corridor.jl
└── create_dataset_v72_random_obstacles.jl

data/vae_training/raw_v72/        # 生成データ（.gitignore）
logs/                             # 実行ログ（.gitignore推奨）
```

---

## 🛠️ トラブルシューティング

### Python仮想環境が見つからない

**エラー:**
```
ERROR: Python venv not found at ~/local/venv
```

**解決策:**
```bash
python3 -m venv ~/local/venv
~/local/venv/bin/pip install h5py numpy matplotlib
```

### Juliaが見つからない

**エラー:**
```
ERROR: Julia not found in PATH
```

**解決策:**
```bash
# Juliaのインストールを確認
which julia

# PATHに追加（~/.bashrc または ~/.zshrc）
export PATH="/Applications/Julia-1.X.app/Contents/Resources/julia/bin:$PATH"
```

### データファイルが見つからない

**警告:**
```
WARNING: No HDF5 files found in data/vae_training/raw_v72
```

**解決策:**
```bash
# データ収集を実行
./scripts/collect_v72_data.sh
```

### 依存パッケージが不足

**エラー:**
```
ERROR: Missing Python packages: h5py numpy matplotlib
```

**解決策:**
```bash
~/local/venv/bin/pip install h5py numpy matplotlib
```

---

## 🔄 ワークフロー例

### 1. 初回セットアップ

```bash
# 1. Python仮想環境を作成
python3 -m venv ~/local/venv
~/local/venv/bin/pip install h5py numpy matplotlib

# 2. Juliaプロジェクトを初期化
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 2. クイックテスト

```bash
# 動作確認（100ステップ）
./scripts/collect_v72_data.sh --quick

# 可視化
./scripts/view_v72_data.sh
```

### 3. フルデータ収集

```bash
# 全シナリオ実行（約10-15分）
./scripts/collect_v72_data.sh

# 結果確認
ls -lh data/vae_training/raw_v72/*.h5 | wc -l
# → 45

# データ確認
./scripts/view_v72_data.sh
```

---

## 📊 ログファイル

データ収集の実行ログは `logs/` ディレクトリに保存されます：

```
logs/
├── v72_scramble_20260114_182837.log
├── v72_corridor_20260114_182900.log
└── v72_random_20260114_182923.log
```

ログ内容:
- 各ステップの進捗状況
- 衝突率の推移
- エラーメッセージ
- 最終統計

---

## 🎯 次のステップ

データ収集と可視化が完了したら：

1. **VAE学習**: `scripts/train_action_vae_v72.jl` を作成・実行
2. **EPHコントローラーテスト**: `scripts/test_eph_v72.jl` を作成・実行
3. **評価**: 衝突率、Freezing率、進捗速度などのメトリクス評価

---

## 📝 補足

### スクリプトの特徴

- **エラーハンドリング**: `set -e` で実行時エラーを即座に検出
- **カラー出力**: 視認性向上のためのカラーコード使用
- **自動確認**: データ収集前にユーザー確認プロンプト
- **ログ保存**: 全出力を自動的にログファイルに保存
- **依存チェック**: 実行前に必要な環境を自動検証

### Gitignore推奨

```
# .gitignore に追加推奨
logs/*.log
data/vae_training/raw_v72/
```

---

**便利なスクリプトで効率的にv7.2データ収集と可視化を実施してください！** 🚀
