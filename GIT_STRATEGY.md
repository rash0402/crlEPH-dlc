# Git Management Strategy - EPH v5.6

**Document**: Git管理戦略ガイド
**Date**: 2026-01-11
**Purpose**: 学術研究プロジェクトの再現性を最大化するGit運用方針

---

## 基本方針

### ✅ COMMIT すべきもの (Git管理対象)

#### 1. **ソースコード** (必須)
```
src/*.jl          # 全コアモジュール
├── config.jl
├── config_v56.jl
├── spm.jl
├── surprise.jl
├── action_vae.jl
└── ... (全て)
```
**理由**: 研究の根幹、バージョン管理必須

#### 2. **実行スクリプト** (必須)
```
scripts/
├── run_simulation_eph.jl          # メインシミュレーション ★
├── run_haze_comparison_v56.jl     # Phase 5バッチ実験 ★
├── analyze_phase5_results.jl      # Phase 5分析 ★
├── compare_formulations.jl        # 理論検証 (260,777x) ★
├── train_vae_v56.jl               # VAEトレーニング
├── tune_vae_v56.jl                # VAEチューニング
├── validate_vae_v56.jl            # VAE検証
├── create_dataset_v56.jl          # データセット作成
├── collect_vae_data_v56.jl        # データ収集
├── compare_baseline_eph.jl        # ベースライン比較
├── visualize_comparison.jl        # 可視化
├── analyze_spm_spatial_distribution.py  # SPM分析
├── run_all_eph.sh                 # ランチャー
├── run_all.sh
└── setup.sh
```
**理由**: 全実験が再現可能、論文のMethods sectionの根拠

#### 3. **ドキュメント** (必須)
```
doc/proposal_v5.6.md               # 理論仕様書 ★★★
CLAUDE.md                          # プロジェクトガイド
README.md                          # プロジェクト概要
GIT_STRATEGY.md (this file)        # Git運用方針
```
**理由**: 理論的根拠、学術的整合性の証明

#### 4. **検証レポート** (学術的に重要)
```
results/
├── haze_mechanism_validation_conclusion.md       # 最終検証結論 ★★★
├── theory_implementation_validation_report.md    # 理論実装検証 ★★
├── root_cause_technical_analysis.md              # 技術分析 ★★
└── README.md
```
**理由**: 260,777x改善の学術的エビデンス、論文執筆に必須

#### 5. **小容量分析結果** (再現に時間がかかる成果物)
```
results/
├── spm_analysis/                  # 232KB (レポート+図)
│   ├── mechanism_analysis_report.md
│   └── spm_spatial_comparison.png
├── vae_tuning/                    # 24KB (ハイパーパラメータログ)
│   ├── tuning_analysis_interim.md
│   └── config_*/training_log.csv
├── vae_training/                  # 8KB (トレーニングログ)
│   └── training_log.csv
└── vae_validation/                # 4KB (検証レポート)
    └── validation_report.md
```
**理由**: 小容量かつ学術的価値あり、再現に数時間〜数日かかる

#### 6. **設定ファイル** (必須)
```
Project.toml                       # Julia依存関係
requirements.txt (viewer用)        # Python依存関係 (if exists)
.gitignore                         # Git戦略定義
```
**理由**: 環境再現に必須

---

### ❌ IGNORE すべきもの (Git管理対象外)

#### 1. **大容量トレーニングデータ** (13.1GB)
```
data/vae_training/raw/             # 6.6GB
data/vae_training/exploratory/     # 6.5GB
data/vae_training/exploratory_test/  # 59MB
data/vae_training/*.h5
```
**理由**:
- スクリプトで再生成可能 (`scripts/create_dataset_v56.jl`)
- Gitリポジトリが肥大化
- クラウドストレージやローカル保存で十分

#### 2. **シミュレーションログ** (一時ファイル)
```
data/logs/*.h5
data/logs/comparison/
data/logs/control_integration/
... (all subdirectories)
```
**理由**:
- 各実験で上書きされる一時ファイル
- スクリプトで再実行可能

#### 3. **モデルファイル** (~30MB)
```
models/*.bson                      # 全てのVAEモデル
models/action_vae_v56_checkpoints/
models/vae_tuning/
```
**理由**:
- `scripts/train_vae_v56.jl`で再トレーニング可能 (~2時間)
- 1ファイル1.4MB × 20個以上 = 無駄な容量

**例外**: 将来的にGit LFSで"published model"を1つだけバージョン管理する可能性あり

#### 4. **大容量実験結果** (13.4GB)
```
results/phase5/                    # 13GB (160実験の生データ)
results/theory_comparison_*/       # 449MB (比較実験データ)
```
**理由**:
- スクリプトで再実行可能
  - `scripts/run_haze_comparison_v56.jl` (Phase 5, ~8時間)
  - `scripts/compare_formulations.jl` (理論比較, ~6分)
- 生データは研究者のローカル環境で保管
- 最終論文には集計結果のみ使用

#### 5. **OS・ツール固有ファイル**
```
.DS_Store, .vscode/, __pycache__/, Manifest.toml, etc.
```
**理由**: 環境依存、不要

---

## Commit戦略

### Phase 1: 現在の変更をcommit

```bash
# 1. ソースコード (理論整合版への修正)
git add src/*.jl

# 2. スクリプト (新規v5.6 + 削除された旧版)
git add scripts/*.jl scripts/*.sh scripts/*.py

# 3. ドキュメント
git add doc/proposal_v5.6.md
git add .gitignore
git add GIT_STRATEGY.md

# 4. 検証レポート (学術的エビデンス)
git add results/*.md
git add results/spm_analysis/
git add results/vae_tuning/
git add results/vae_training/
git add results/vae_validation/

# 5. Commit (学術的整合性を記録)
git commit -m "feat: Implement theory-correct EPH v5.6 with validation

- Replace simplified formulations with theory-correct implementations
  - F_safety: Σ φ(Ch2, Ch3) instead of mean(Ch1)
  - Surprise: reconstruction error instead of latent variance
- Remove all simplified versions per academic integrity requirement
- Add comprehensive validation reports (260,777x improvement evidence)
- Clean up obsolete test/diagnostic scripts (32 files removed)
- Optimize git management strategy for reproducibility

Academic Validation:
- Theory-implementation correspondence verified
- Haze sensitivity: ΔF = -12.68% (vs 0.08% in simplified version)
- All changes aligned with proposal_v5.6.md specification

Refs: results/haze_mechanism_validation_conclusion.md"
```

### Phase 2: models/ディレクトリの扱い

**現状**: `models/action_vae_best.bson`がシンボリックリンクに変更されている

**問題**: リンク先がignoreされているため、checkout後に動作しない

**解決策**:
```bash
# Option A: typechangeを無視 (推奨)
git restore models/action_vae_best.bson

# Option B: models/READMEを追加してモデル不在を説明
echo "# Models Directory

All model files (*.bson) are git-ignored.

## Reproducing Models

Train VAE model:
\`\`\`bash
julia --project=. scripts/train_vae_v56.jl
\`\`\`

Expected output: \`models/action_vae_v56_best.bson\`
Training time: ~2 hours on M1 Mac
" > models/README.md

git add models/README.md
```

**推奨**: Option A (modelsは完全にローカル管理)

---

## 再現性確保のワークフロー

### 新しい環境でのセットアップ

```bash
# 1. Clone repository
git clone <repo-url>
cd crlEPH-dlc

# 2. Install dependencies
./scripts/setup.sh

# 3. Train VAE model (~2 hours)
julia --project=. scripts/train_vae_v56.jl

# 4. Run experiments
julia --project=. scripts/run_simulation_eph.jl --visualize
```

### Phase 5実験の再現

```bash
# Full Phase 5 experiments (160 runs, ~8 hours)
julia --project=. scripts/run_haze_comparison_v56.jl

# Results will be saved to: results/phase5/haze_comparison_YYYYMMDD_HHMMSS/
```

### 理論検証の再現

```bash
# 260,777x improvement validation (~6 minutes)
julia --project=. scripts/compare_formulations.jl

# Results will be saved to: results/theory_comparison_YYYYMMDD_HHMMSS/
```

---

## データ保管戦略

### Git管理 (このリポジトリ)
- ✅ ソースコード、スクリプト、ドキュメント
- ✅ 検証レポート、小容量分析結果
- ✅ 再現手順、設定ファイル

### ローカル保管 (研究者の環境)
- 💾 モデルファイル (`models/*.bson`)
- 💾 大容量データ (`data/vae_training/raw/`)
- 💾 実験結果 (`results/phase5/`, `results/theory_comparison_*/`)

### クラウドバックアップ (オプション)
- ☁️ 重要な実験結果の圧縮版
- ☁️ 論文用の最終データセット
- ☁️ Published modelのアーカイブ

---

## Git LFS検討 (将来的)

もし特定のモデルを"published version"としてバージョン管理したい場合:

```bash
# Install Git LFS
git lfs install

# Track specific model
git lfs track "models/action_vae_v56_published.bson"
git add .gitattributes
git add models/action_vae_v56_published.bson
git commit -m "Add published VAE model v5.6.1"
```

**現時点では不要**: モデルは再トレーニング可能なため

---

## まとめ

### 🎯 この戦略の目的

1. **学術的再現性**: 全実験がスクリプトから再現可能
2. **リポジトリ軽量化**: コードとドキュメントのみ管理 (大容量データ除外)
3. **バージョン管理**: 理論実装の変更履歴を完全記録
4. **協業容易性**: 新しいメンバーが即座に環境構築可能

### 📊 管理対象のサイズ目安

- **Git管理**: ~5MB (コード、スクリプト、レポート、小容量分析結果)
- **Gitignore**: ~26GB (データ、モデル、大容量実験結果)

### ✅ 次のアクション

```bash
# 推奨コミット手順は上記 "Commit戦略" を参照
```

---

**Status**: ✅ Ready for commit
**Next**: Phase 5完了後、最終分析結果を追加commit
