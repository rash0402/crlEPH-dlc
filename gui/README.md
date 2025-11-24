# EPH Dashboard - GUI Application

PySide6ベースの統合実験制御GUI

## 起動方法

### 1. PySide6インストール

```bash
# venv環境の場合
source ~/local/venv/bin/activate
pip install -r requirements.txt

# conda環境の場合
conda activate your-env
pip install PySide6>=6.6.0
```

### 2. Dashboard起動

```bash
python eph_dashboard.py
```

または：

```bash
./eph_dashboard.py
```

## 機能

### ✅ Validation タブ（実装済み）

**機能:**
- Phase 1/2/compat/all の検証実行
- リアルタイムログ表示（色付き出力）
- 進捗インジケーター
- 実行中のプロセス停止

**使い方:**
1. Phase選択（all/1/2/compat）
2. "Run Validation" ボタンをクリック
3. 出力ログを確認
4. 結果確認（✅ Pass / ❌ Fail）

---

### 🧠 GRU Training タブ（未実装）

**予定機能:**
- GRUトレーニングデータ収集
- ハイパーパラメータ設定
- 学習実行・進捗表示
- 学習曲線プロット

---

### 🧪 Experiments タブ（未実装）

**予定機能:**
- 実験タイプ選択（Baseline, Shepherding）
- パラメータ編集
- 実験実行・リアルタイム可視化
- 実験停止・再実行

---

### 📊 Analysis タブ（未実装）

**予定機能:**
- ログファイル選択（.jld2）
- 自動解析実行
- グラフ表示（EFE, haze, entropy, surprise）
- レポート生成（PDF/Markdown）

---

## ステータスバー

画面下部に常時表示されるシステム状態インジケーター：

- **🖥️ Julia**: Julia インストール状態（✅/❌）
- **📁 Data**: データディレクトリ（logs, training）の存在確認
- **📜 Scripts**: 重要なスクリプトの存在確認
- **📦 Project**: Julia Project.toml/Manifest.toml 確認

各インジケーターにマウスホバーで詳細情報表示

---

## ディレクトリ構造

```
gui/
├── main_window.py           # メインウィンドウ
├── tabs/
│   ├── validation_tab.py    # Phase検証タブ
│   └── placeholder_tab.py   # 未実装タブプレースホルダー
├── widgets/
│   └── system_status.py     # システム状態ウィジェット
├── utils/
│   └── system_checker.py    # システム要件チェッカー
└── styles/
    └── material_dark.qss    # Material Designテーマ
```

---

## 次のステップ

未実装タブの実装順序：

1. **GRU Training タブ**
   - データ収集UI
   - 学習実行・監視

2. **Experiments タブ**
   - パラメータ編集パネル
   - 実験実行制御

3. **Analysis タブ**
   - JLD2ファイル解析
   - matplotlib統合
   - レポート生成

---

## トラブルシューティング

### Q1: GUIが起動しない

**A:** PySide6がインストールされているか確認
```bash
python -c "import PySide6; print(PySide6.__version__)"
```

### Q2: Julia not found エラー

**A:** Julia インストール確認
```bash
~/.juliaup/bin/julia --version
```

### Q3: Validation実行時にエラー

**A:** スクリプトの実行権限確認
```bash
chmod +x scripts/run_basic_validation.sh
```

---

## 開発者向け

### 新しいタブの追加方法

1. `gui/tabs/` に新しいタブクラスを作成
2. `main_window.py` でタブを追加
3. 必要に応じて `utils/` にヘルパーを追加

### スタイルカスタマイズ

`gui/styles/material_dark.qss` を編集してQtスタイルシートを変更

### システムチェック項目の追加

`gui/utils/system_checker.py` の `check_all()` メソッドを拡張
