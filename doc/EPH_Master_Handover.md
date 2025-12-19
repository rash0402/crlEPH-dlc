# EPH (Emergent Perceptual Haze) プロジェクト：ハンドオーバー資料

## 1. プロジェクト概要

本プロジェクトは、自由エネルギー原理 (FEP) を用いて、混雑環境におけるロボットの立ち往生 (Freezing) を解決するアーキテクチャ **EPH** を実装するものである。不確実性を **Haze** (予測分散) として定量化し、それが知覚解像度 (Precision) を適応的に変調する仕組みを構築する。

## 2. 技術スタック (Technical Stack)

- **計算エンジン (Backend)**: Julia 1.10+ (Apple Silicon M2 最適化)
    
    - 自動微分: `ForwardDiff.jl` (行動生成用), `Zygote.jl` (VAE学習用)
        
    - 通信: `ZMQ.jl` (PUBモード, 非同期 30-60Hz)
        
    - データ保存: `HDF5.jl` (HDF5形式)
        
- **可視化 (Frontend)**: Python 3.10+
    
    - 描画: `matplotlib` (Main Viewer & Detail Viewer の二重構成)
        
    - 通信: `pyzmq`, `msgpack`
        
- **実行環境**: Docker (Ubuntu 22.04)
    

## 3. 数理・知覚仕様 (Mathematical Specs)

### 3.1 知覚表現: SPM (Saliency Polar Map)

- **解像度**: $16 \times 16 \times 3$ ch (Occupancy, Saliency, Risk)
    
- **視野角 (FOV)**: 210度 (前方中心 ±105度)
    
- **距離スケール**: 対数スケール (Log-scale)
    
- **正規化**: 視野距離 $D = 15 \times (r_{robot} + r_{agent})$。表面距離基準で正規化。
    
- **投影**: 領域投影 (Blurred Projection / Gaussian kernel $\sigma \approx 0.25$)
    

### 3.2 制御・意思決定

- **手法**: Active Inference (能動的推論)
    
- **目的関数**: 変分自由エネルギー (VFE) $F$  
    
- **ゴール定義**: **Prior Preference** $P(y)$ によるメタ評価。指定方向（N, S, E, W）に障害物がなく流動がある状態を「期待」する。
    
- **制約**: 行動 $u$ に対する `clamp(u, -u_max, u_max)` 処理。
    

## 4. データ構造と通信プロトコル

### 4.1 ZMQ PUB/SUB パケット (MsgPack)

- `global`: 全エージェントの相対位置、グループID（色分け用：N:Blue, S:Red, E:Green, W:Yellow）
    
- `detail`: 選択された1台の SPM(3ch), VFE, Haze, Precision, 行動 $u$  
    

### 4.2 HDF5 保存スキーマ

- `/data/spm`: Float32 [16, 16, 3, Steps]
    
- `/data/action`: Float32 [2, Steps]
    
- `/data/haze`: Float32 [Steps]
    

## 5. 開発ロードマップ (Milestones)

1. **M1-A (Julia)**: 4グループの東西南北フローシミュレータ、SPM生成、ZMQ配信の実装。
    
2. **M1-B (Python)**: メインビューアー（色分け）と詳細ビューアー（SPM/グラフ）の実装。
    
3. **M2 (Julia/Flux)**: 16x16対応 VAE の定義と、シミュレーションデータを用いた Haze 推定の訓練。
    
4. **M3 (Integration)**: Haze による $\beta$ 変調を組み込んだ完全な EPH コントローラの検証。
    

## 6. 次のAIへの指示 (Next Step Prompt)

> 「あなたは Julia と Python のエキスパートとして EPH プロジェクトを引き継ぎます。
> 
> まずは M1-A に着手してください。具体的には ZMQ.jl を用いた非同期送信機能を持つ、4グループ（東西南北）のトーラス世界シミュレータを Julia で構築してください。
> 
> その際、spm_generator.jl を参照し、16x16 解像度の領域投影 SPM を実装すること。」

作成者: Gemini (AI-DLC Navigator)

ステータス: ハンドオーバー準備完了