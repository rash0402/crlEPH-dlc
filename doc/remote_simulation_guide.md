# 遠隔GPUシミュレーション 実行ガイド

## 1. 必要な環境

### A. リモートサーバー (Linux + GPU)
*   **Docker Engine**: 必須
*   **NVIDIA Container Toolkit**: GPU利用に必須 (GPUドライバ含む)

### B. ローカルPC (あなたのMacBook Air)
**特別なソフトのインストールは基本的に不要です。** macOS標準の機能を使います。

*   **SSH / Rsync**: 標準搭載されています。
*   **Docker Desktop**: **不要です**。（すべての処理はサーバー側で行われます）
*   **Python環境**: 結果の可視化(`viewer`スクリプト)を動かすために必要です。
    *   `pip install matplotlib numpy pyzmq h5py PyQt5` など

---

## 2. セットアップ手順

### Step 1: SSH鍵の設定 (重要)
サーバーに「合鍵」を渡すことで、パスワードなしで安全に接続できるようにします。

**手順 1: 鍵があるか確認**
ターミナルで以下を実行します。
```bash
ls ~/.ssh/id_ed25519.pub
```
*   ファイルが表示されたら → **既存の鍵を使います**（手順3へ）。
*   `No such file...` と出たら → **新しい鍵を作ります**（手順2へ）。

**手順 2: 鍵の作成** (必要な場合のみ)
```bash
ssh-keygen -t ed25519
```
*   "Enter file in which to save..." → **Enter** (そのまま)
*   "Enter passphrase..." → **Enter** (パスワードなしでOK、ここで設定すると毎回聞かれます)
*   "Enter same passphrase again" → **Enter**

**手順 3: 鍵をサーバーに渡す**
ローカルPCから、以下のコマンドを実行します（`<REMOTE_USER>` と `<REMOTE_HOST>` は**リモートのLinuxサーバーの情報**に置き換えてください）。

**[方法A: ssh-copy-id]** (推奨)
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub <REMOTE_USER>@<REMOTE_HOST>
```

**[方法B: 代替コマンド]** (方法Aで `command not found` となる場合)
以下のコマンドを1行で実行してください。
```bash
cat ~/.ssh/id_ed25519.pub | ssh <REMOTE_USER>@<REMOTE_HOST> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**手順 4: 接続テスト**
```bash
ssh <REMOTE_USER>@<REMOTE_HOST>
```
パスワードを聞かれずにログインできれば成功です！

---

### Step 2: プロジェクト設定 (.env)
1.  テンプレートをコピーして設定ファイルを作成します。
    ```bash
    cp scripts/remote/.env.template scripts/remote/.env
    nano scripts/remote/.env
    ```
2.  中身を書き換えます。
    *   `REMOTE_HOST`: サーバーのIPアドレス
    *   `REMOTE_USER`: サーバーのユーザー名
    *   `REMOTE_DIR`: サーバー上の作業フォルダ (例: `/home/user/work/crlEPH-dlc`)
    *   `EXECUTION_MODE`: `docker` (推奨)

---

## 3. 実行ワークフロー

1.  **コード同期 (Local → Remote)**
    ```bash
    ./scripts/remote/sync_up.sh
    ```
2.  **Dockerビルド (初回のみ/更新時)**
    ```bash
    ./scripts/remote/build_docker.sh
    ```
3.  **シミュレーション/学習実行**
    ```bash
    # データ生成
    ./scripts/remote/run.sh "julia scripts/create_dataset_v72_corridor.jl ..."
    
    # 学習
    ./scripts/remote/run.sh "julia scripts/train_action_vae_v72.jl"
    ```
4.  **結果取得 (Remote → Local)**
    ```bash
    ./scripts/remote/sync_down.sh
    ```
