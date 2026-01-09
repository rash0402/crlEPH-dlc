# EPH (Emergent Perceptual Haze) プロジェクト

自由エネルギー原理（Free Energy Principle）に基づく、混雑環境における社会的ロボットナビゲーションの研究実装です。

## プロジェクト概要

**EPH（Emergent Perceptual Haze）** は、不確実性を**知覚解像度（Perceptual Precision）**の可変設計として扱うActive Inferenceの工学的拡張アーキテクチャです。予測信頼性に応じて知覚・注意の鋭さを連続的に変調することで、単体ロボットおよび群知能システムにおける停止（Freezing）・振動・分断といった不確実性起因の行動破綻を構造的に抑制します。

### 主要概念

- **SPM (Saliency Polar Map)**: 霊長類V1野を模倣した対数極座標の生体模倣的知覚表現
- **Haze**: 不確実性を定量化し、知覚解像度の制御に写像する操作的指標
- **Precision Modulation**: 確信度に応じた知覚表現の適応的変形
- **Toroidal World**: トーラス境界を持つ世界（エージェントは境界で折り返し）
- **自己中心座標系**: SPMはエージェントの速度方向を基準に生成
- **4群スクランブル交差**: 標準的なテストシナリオ（N/S/E/W群が中央で交差）

## プロジェクト構造

```
crlEPH-dlc/
├── doc/                          # ドキュメントと研究提案書
│   ├── EPH-proposal_all_v5.2.md # 最新の研究提案書
│   └── ...
├── src_julia/                    # Juliaメイン実装
│   ├── config.jl                 # システム設定
│   ├── spm.jl                    # SPM生成（16x16x3ch: 占有・顕著性・リスク）
│   ├── dynamics.jl               # エージェント物理演算
│   ├── controller.jl             # FEPベースコントローラ
│   ├── prediction.jl             # 予測モデル（VAE）
│   ├── communication.jl          # ZMQ通信
│   └── logger.jl                 # HDF5ロギング
├── scripts/                      # 実行スクリプト
│   ├── run_simulation.jl         # メインシミュレーション
│   ├── start_backend.fish        # バックエンド起動スクリプト
│   ├── start_main_viewer.fish    # メインビューア起動
│   ├── start_detail_viewer.fish  # 詳細ビューア起動
│   └── start_all.fish            # 全コンポーネント一括起動（macOS）
├── viewer/                       # Python可視化
│   ├── zmq_client.py             # ZMQサブスクライバ
│   ├── main_viewer.py            # 4群表示
│   └── detail_viewer.py          # SPM詳細ビュー
├── Project.toml                  # Julia依存関係
├── requirements.txt              # Python依存関係
└── CLAUDE.md                     # Claude Code向け開発ガイド
```

## クイックスタート

### 1. 依存関係のインストール

**Julia** (1.10+):
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

**Python** (3.10+):
```bash
~/local/venv/bin/pip install -r requirements.txt
```

### 2. シミュレーション実行

**方法A: 起動スクリプトを使用（推奨）**

ターミナル1 - Juliaバックエンド起動:
```bash
./scripts/start_backend.fish
```

ターミナル2 - メインビューア起動:
```bash
./scripts/start_main_viewer.fish
```

ターミナル3 - 詳細ビューア起動（オプション）:
```bash
./scripts/start_detail_viewer.fish
```

**方法B: 一括起動（macOS）**
```bash
./scripts/start_all.fish
```
全3コンポーネントを個別のターミナルウィンドウで起動します。

**方法C: 手動起動**

ターミナル1:
```bash
julia --project=. scripts/run_simulation.jl
```

ターミナル2:
```bash
~/local/venv/bin/python viewer/main_viewer.py
```

ターミナル3:
```bash
~/local/venv/bin/python viewer/detail_viewer.py
```

### 3. ポート管理

ZMQポート（5555）が使用中の場合:
```bash
lsof -i :5555                    # ポート使用状況の確認
lsof -ti :5555 | xargs kill -9   # プロセスの強制終了
```

## アーキテクチャ

### Juliaバックエンド (`src_julia/`)
コアシミュレーションロジックを実装。

- **config.jl** - システムパラメータ（SPM、世界、エージェント、制御、通信）
- **spm.jl** - Saliency Polar Map生成（16×16×3ch: 占有、顕著性、リスク）
- **dynamics.jl** - トーラス境界を持つエージェント物理
- **controller.jl** - 自由エネルギー最小化に基づくコントローラ
- **prediction.jl** - VAE世界モデル（Haze推定）
- **communication.jl** - リアルタイム配信用ZMQ PUBソケット
- **logger.jl** - HDF5データロギング

### Pythonビューア (`viewer/`)
リアルタイム可視化を担当。

- **main_viewer.py** - 4群スクランブル交差の表示
- **detail_viewer.py** - SPM 3チャンネル可視化とメトリクス
- **zmq_client.py** - ZMQ SUBソケットクライアント

### 通信
- Juliaが `tcp://127.0.0.1:5555` でZMQ経由で配信
- Pythonビューアがサブスクライブして可視化

## 機能

### M1-M2: ベースライン実装 ✅
- **4群スクランブル交差**: トーラス世界でN/S/E/W群が交差
- **SPM表現**: 16×16×3ch（占有、顕著性、リスク）
- **FEPコントローラ**: 自由エネルギー最小化
- **VAE世界モデル**: SPMからHaze推定
- **適応的β(H)変調**: Precision（精度）に基づく知覚解像度制御
- **リアルタイム可視化**: ZMQベースのストリーミング
- **HDF5ロギング**: 完全なシミュレーションデータの記録

### M3: 検証フレームワーク ✅
- **Freezing検出**: 操作的定義に基づくアルゴリズム
- **評価メトリクス**: 成功率、衝突率、ジャーク、最小TTC
- **アブレーション研究**: A1-A4条件切り替え
- **統計分析**: ターゲットに対する自動検証
- **テスト結果**: Freezing 36%削減、ジャーク23%改善

### M4: 予測的衝突回避 🎯 _(進行中)_
- [ ] Expected Free Energy（EFE）最小化
- [ ] 候補行動からの予測的SPM生成
- [ ] Ch3集中評価（動的衝突リスク）
- [ ] 自動微分ベースの最適化
- [ ] 実験実行と論文投稿

**設計ドキュメント**:
- `doc/predictive_collision_avoidance_discussion.md`
- `doc/ch3_focused_evaluation.md`

## 設定

パラメータは `src_julia/config.jl` で構造体として定義されています：
- `SPMParams` - 解像度、視野、センシング距離、βパラメータ
- `WorldParams` - 世界サイズ、タイムステップ、最大ステップ数
- `AgentParams` - 質量、減衰、半径、グループサイズ
- `ControlParams` - 学習率、安全距離、TTCしきい値
- `CommParams` - ZMQエンドポイントとトピック名

## データ出力

- ログは `log/data_YYYYMMDD_HHMMSS.h5` (HDF5形式) に保存
- 各タイムステップのSPMテンソル、行動、位置、速度を含む

## 参考文献

完全な研究提案書については `doc/EPH-proposal_all_v5.2.md` を参照してください。

## 開発者向け情報

Claude Codeを使用して開発する際は、`CLAUDE.md` を参照してください。プロジェクト構造、主要概念、よく使うコマンドなどが記載されています。

## ライセンス

このプロジェクトは研究目的で開発されています。

## 著者

五十嵐 洋（Hiroshi Igarashi）
東京電機大学
