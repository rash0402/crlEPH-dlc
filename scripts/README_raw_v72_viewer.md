# V7.2 Raw Trajectory Viewer

**5D状態空間（x, y, vx, vy, θ）対応のインタラクティブ軌跡ビューワー**

## 概要

v7.2データ収集で生成されたHDF5ファイルを可視化するためのツールです。Heading情報を含む5D状態空間、方向ベクトル目標、全方向力制御に対応しています。

## v7.2の新機能

- **5D状態空間**: 位置（x, y）、速度（vx, vy）、姿勢（θ）
- **Heading矢印**: エージェントの向き（黒矢印）を表示
- **目標方向ベクトル**: d_goal（紫の破線矢印）
- **Heading vs 速度方向**: 時系列プロット
- **全方向力制御**: [Fx, Fy]の履歴表示
- **v7.2物理パラメータ**: m=70kg, u_max=150N, k_align=4.0 rad/s

## 使用方法

### 基本的な起動（ファイル選択ダイアログ）

```bash
python scripts/raw_v72_viewer.py
```

ファイル選択ダイアログが表示され、`data/vae_training/raw_v72/`から任意のHDF5ファイルを選択できます。

### ファイル指定での起動

```bash
# Scramble Crossing
python scripts/raw_v72_viewer.py data/vae_training/raw_v72/v72_scramble_d10_s1_*.h5

# Corridor
python scripts/raw_v72_viewer.py data/vae_training/raw_v72/v72_corridor_d15_s2_*.h5

# Random Obstacles
python scripts/raw_v72_viewer.py data/vae_training/raw_v72/v72_random_d20_n50_s3_*.h5
```

### 仮想環境での実行

```bash
~/local/venv/bin/python scripts/raw_v72_viewer.py
```

## 画面構成

### 1. **Global View** (左上・メイン)
- 全エージェントの位置と軌跡
- **黒矢印**: Heading（エージェントの向き）
- **紫破線矢印**: 目標方向ベクトル（選択エージェント）
- **円**: エージェント本体（色=グループ）
- **赤破線円**: 衝突イベント
- **クリック**: エージェント選択

### 2. **Agent Detail** (右上)
- 選択エージェントの詳細情報
  - 位置、速度（大きさ・方向）
  - **Heading θ**: 姿勢角度
  - **Heading Error**: 速度方向との差
  - 制御力、目標方向
  - **Progress**: v·d_goal（進捗速度）

### 3. **Heading vs Velocity Direction** (右中央)
- **青線**: Heading θ（姿勢）
- **赤破線**: 速度方向
- Heading alignment dynamics（k_align=4.0 rad/s）の効果を確認

### 4. **Statistics** (左下)
- シナリオ情報
- **v7.2物理モデル**: mass, u_max, k_align
- エージェント数、密度
- 衝突統計

### 5. **Control Forces** (中央下)
- 選択エージェントの制御力履歴
- **青線**: Fx（X方向力）
- **赤線**: Fy（Y方向力）
- **黒線**: |F|（力の大きさ）
- **灰破線**: u_max上限

### 6. **Collision Events** (右下)
- 全エージェントの衝突イベント
- 赤点 = 衝突発生

## 操作方法

### マウス操作
- **左クリック（Global View）**: エージェント選択
  - 最も近いエージェント（2m以内）を選択
  - 選択されたエージェントは太枠＋矢印で強調表示

### スライダー
- **Time Step**: タイムステップを変更（0 ～ max_steps-1）

### ボタン
- **Play/Pause**: 自動再生の開始/停止
  - 再生速度: リアルタイム（dt=0.01s）

## v7.2データ構造

ビューワーが読み込むHDF5構造：

```
/trajectory/
  ├─ pos      [T, N, 2]  # Position (x, y)
  ├─ vel      [T, N, 2]  # Velocity (vx, vy)
  ├─ heading  [T, N]     # ★ v7.2 NEW: Heading θ
  ├─ u        [T, N, 2]  # Control (Fx, Fy)
  ├─ d_goal   [N, 2]     # ★ v7.2 NEW: Direction vectors
  └─ group    [N]        # Group ID

/events/
  ├─ collision        [T, N]  # Collision flags
  └─ near_collision   [T, N]  # Near-collision flags

/metadata/
  ├─ scenario         str     # "scramble", "corridor", "random_obstacles"
  ├─ version          str     # "v7.2"
  ├─ density          int
  ├─ seed             int
  ├─ max_steps        int
  ├─ dt               float
  ├─ n_agents         int
  └─ collision_rate   float

/v72_params/          # ★ v7.2 NEW
  ├─ mass             float   # 70.0 kg
  ├─ k_align          float   # 4.0 rad/s
  └─ u_max            float   # 150.0 N
```

## 確認ポイント

### 1. Heading Alignment（姿勢追従）
- **Heading vs Velocity Direction**プロットで確認
- 青線（Heading）が赤破線（速度方向）に追従
- 時定数 τ = 1/k_align ≈ 0.25s

### 2. 目標方向への進捗
- Agent Detailの**Progress**値
- P = v·d_goal > 0 なら目標方向に進行中
- Global Viewの紫矢印が目標方向

### 3. 衝突パターン
- Collision Eventsで時空間分布
- Global Viewで赤破線円が衝突位置

### 4. 制御力の特性
- Control Forcesで全方向性を確認
- Fx, Fyが独立に変化（Unicycle [v, ω]とは異なる）

## トラブルシューティング

### エラー: `KeyError: 'trajectory/heading'`
- v7.2以前のファイルを開いている
- `data/vae_training/raw_v72/`のファイルを使用

### エラー: `ModuleNotFoundError: No module named 'h5py'`
```bash
pip install h5py numpy matplotlib
```

### ウィンドウが表示されない
- バックエンドの問題の可能性
```python
# raw_v72_viewer.py の先頭で確認
matplotlib.use('TkAgg')  # または 'Qt5Agg'
```

## 関連ファイル

- **データ収集スクリプト**:
  - `scripts/create_dataset_v72_scramble.jl`
  - `scripts/create_dataset_v72_corridor.jl`
  - `scripts/create_dataset_v72_random_obstacles.jl`

- **データディレクトリ**: `data/vae_training/raw_v72/` (gitignore)

- **v7.2実装**:
  - `src/dynamics.jl` - dynamics_rk4(), step_v72!()
  - `src/config.jl` - v7.2物理パラメータ
  - `src/controller.jl` - v7.2コントローラー

## バージョン履歴

**v7.2** (2026-01-14)
- 5D状態空間対応（heading表示）
- Direction vector goals（d_goal）
- Omnidirectional force control表示
- v7.2物理パラメータ表示

---

**ビューワーを使って、v7.2のHeading Alignment Dynamicsの効果を確認してください！** 🎯
