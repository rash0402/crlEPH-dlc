# EPH (Emergent Perceptual Haze) プロジェクト

自由エネルギー原理（Free Energy Principle）に基づく、混雑環境における社会的ロボットナビゲーションの研究実装です。

## プロジェクト概要

**EPH（Emergent Perceptual Haze）** は、不確実性を**知覚解像度（Perceptual Precision）**の可変設計として扱うActive Inferenceの工学的拡張アーキテクチャです。予測信頼性に応じて知覚・注意の鋭さを連続的に変調することで、単体ロボットおよび群知能システムにおける停止（Freezing）・振動・分断といった不確実性起因の行動破綻を構造的に抑制します。

### 主要概念
- **SPM (Saliency Polar Map)**: 霊長類V1野を模倣した対数極座標の生体模倣的知覚表現
- **Haze**: 不確実性を定量化し、知覚解像度の制御に写像する操作的指標 $H(y,u)$
- **Pattern D Integration**: 行動依存の不確実性（Counterfactual Haze）を推定するVAEモデル
- **4群スクランブル交差**: 標準的なテストシナリオ（N/S/E/W群が中央で交差）

## プロジェクト構造

```
crlEPH-dlc/
├── doc/                          # ドキュメントと研究提案書
├── src/                          # Juliaメイン実装
│   ├── config.jl                 # システム設定
│   ├── spm.jl                    # SPM生成（16x16x3ch: 占有・顕著性・リスク）
│   ├── dynamics.jl               # エージェント物理演算
│   ├── controller.jl             # FEPベースコントローラ
│   ├── action_vae.jl             # Action-Dependent VAE (Pattern D)
│   ├── communication.jl          # ZMQ通信
│   ├── metrics.jl                # 評価指標・Freezing判定
│   └── logger.jl                 # HDF5ロギング
├── scripts/                      # 実行スクリプト
│   ├── run_all.sh                # [推奨] 一括起動ランチャー
│   ├── run_simulation.jl         # メインシミュレーション
│   ├── train_action_vae.jl       # VAE学習スクリプト
│   ├── validate_haze.jl          # Haze妥当性検証
│   ├── evaluate_metrics.jl       # 評価指標計算
│   └── archive/                  # 旧スクリプトの退避場所
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

### 2. シミュレーション実行

**推奨: 一括起動 (Mac/Linux)**
```bash
./scripts/run_all.sh
```
これにより、JuliaバックエンドとPythonビューアが起動します。

**手動起動**
```bash
# Terminal 1: Simulation
julia --project=. scripts/run_simulation.jl

# Terminal 2: Viewer
~/local/venv/bin/python viewer/detail_viewer.py
```

### 3. VAE学習と検証

**学習**
```bash
julia --project=. scripts/train_action_vae.jl
```

**Haze 妥当性検証 (Pattern D)**
```bash
julia --project=. scripts/validate_haze.jl
```

## アーキテクチャ (v5.5 Pattern D)

本実装は **Action-Dependent Uncertainty (Pattern D)** を採用しています。

### Juliaバックエンド (`src/`)
- **action_vae.jl**: $(y_t, u_t)$ を入力とするエンコーダを持ち、反事実的な不確実性（Counterfactual Haze）を推定します。
- **controller.jl**: 推定された Haze を用いて、自由エネルギー最小化における知覚解像度 $\beta$ を適応的に変調します。

### データ出力
- **Simulation Logs**: `data/logs/` (HDF5形式)
- **VAE Training Data**: `data/vae_training/`
- **Validation Results**: `results/haze_validation/`

## 機能

### Phase 1.5: Pattern D 実装 (完了) ✅
- **アーキテクチャ**: Action-Dependent Encoder ($q(z|y, u)$)
- **Haze定義**: $H(y, u) = \text{Agg}(\sigma_z^2(y, u))$
- **検証**: 行動による不確実性の変化を確認済み

### Phase 2: 評価指標 (進行中) 🚧
- **Freezing Rate**: 停止状態の定量的検出
- **Collision Rate**: 衝突頻度の測定
- **Jerk**: 動作の滑らかさの評価

## ライセンス

このプロジェクトは研究目的で開発されています。

## 著者

五十嵐 洋（Hiroshi Igarashi）
東京電機大学
