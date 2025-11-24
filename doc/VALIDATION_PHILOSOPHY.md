# Validation の目的と意義

## 📋 目次
1. [Validation とは何か](#validation-とは何か)
2. [なぜ Validation が必要なのか](#なぜ-validation-が必要なのか)
3. [Validation vs Experiments の違い](#validation-vs-experiments-の違い)
4. [成功基準：何を持って良しとするか](#成功基準何を持って良しとするか)
5. [開発ワークフローにおける位置づけ](#開発ワークフローにおける位置づけ)
6. [各Phase Validation の具体的意義](#各phase-validation-の具体的意義)

---

## Validation とは何か

**Validation（検証）** は、EPH システムの **基礎機能が正しく動作するか** を確認する、**単体テスト相当** のプロセスです。

### Validation の特徴

| 観点 | Validation |
|-----|-----------|
| **目的** | システムの基礎機能が壊れていないことを確認 |
| **対象** | 個別モジュール・コンポーネント（単体） |
| **実行時間** | 短時間（数秒〜数十秒） |
| **データ生成** | なし（または最小限） |
| **出力** | Pass/Fail の判定のみ |
| **実行タイミング** | コード変更後、毎回実行すべき |

### 具体例

```bash
# Phase 2 Validation の一部
Test 2.1: SPM module import                     ✅ PASS
Test 2.2: SPMParams instantiation              ✅ PASS
Test 2.3: SPM tensor creation                   ✅ PASS
```

これらは「SPMモジュールが正しくロードできるか」「パラメータが作成できるか」といった、**システムの基本的な健全性** を確認しています。

---

## なぜ Validation が必要なのか

### 1. **破壊的変更の早期検出**

コードを修正した際に、**意図しない副作用** で他の機能が壊れることがあります。

**例：**
```julia
# FullTensorHaze.jl を修正
# → うっかり Statistics を import し忘れた
# → mean() が使えなくなり、Test 4.4 が失敗
```

Validation があれば、**コミット前に気づける** ため、バグの混入を防げます。

### 2. **リファクタリングの安全性確保**

コードをリファクタリング（構造改善）する際、**機能が変わらないこと** を保証する必要があります。

**例：**
```julia
# EPH.jl のアルゴリズムを最適化
# → Validation を実行して、結果が変わらないことを確認
```

Validation がないと、「最適化したつもりが、実は機能が壊れていた」というリスクがあります。

### 3. **依存関係の問題を早期発見**

Julia パッケージのバージョンアップや、他のモジュールの変更により、**依存関係が壊れる** ことがあります。

**例：**
```bash
# Julia を 1.10 → 1.11 にアップデート
# → Zygote の挙動が変わり、gradient計算が失敗
# → Phase 1 Validation が失敗して気づける
```

### 4. **新しいメンバーの安心感**

新しく参加した開発者が、「このコードベースは健全か？」を簡単に確認できます。

```bash
# 初めてプロジェクトをclone
./scripts/run_basic_validation.sh all
# → 全てPass → 「環境構築が正しく完了した」と確認
```

---

## Validation vs Experiments の違い

この2つは **目的が全く異なります**。混同しないことが重要です。

| 観点 | Validation | Experiments |
|-----|-----------|------------|
| **目的** | システムが壊れていないか確認 | 研究仮説を検証・データを収集 |
| **対象** | 個別モジュールの機能 | システム全体の挙動 |
| **判定基準** | Pass/Fail（二値） | 定量的指標（連続値） |
| **実行時間** | 短時間（秒単位） | 長時間（分〜時間単位） |
| **データ生成** | なし（最小限） | あり（大量の実験データ） |
| **実行頻度** | コード変更の度に毎回 | 研究の節目で実施 |
| **失敗時の対応** | コードを修正して再実行 | 仮説を修正して再設計 |

### 具体例で比較

#### Validation の例（Phase 2 Test 2.3）

```julia
# Test 2.3: SPM tensor creation
spm = create_spm(agent, env, params)
if size(spm) == (3, 8, 16) && all(0.0 .<= spm .<= 1.0)
    println("✅ PASS")
else
    println("❌ FAIL")
end
```

**判定:** SPMが正しいサイズで、値が[0,1]の範囲内か？ → **Pass/Fail**

#### Experiments の例

```julia
# Shepherding experiment
n_trials = 100
success_rate = run_shepherding_experiment(n_trials)
avg_task_time = compute_average_task_time()

println("Success rate: $(success_rate)%")
println("Avg task time: $(avg_task_time)s")
```

**判定:** 成功率は何%か？平均タスク時間は何秒か？ → **定量的指標**

### Validation と Experiments の関係

```
┌─────────────────────────────────────────┐
│  開発サイクル                            │
├─────────────────────────────────────────┤
│  1. コード修正                           │
│     ↓                                   │
│  2. Validation 実行 ← 基礎機能確認      │
│     ↓ (Pass)                            │
│  3. Git commit                          │
│     ↓                                   │
│  4. Experiments 実行 ← 研究仮説検証     │
│     ↓                                   │
│  5. 論文執筆・分析                       │
└─────────────────────────────────────────┘
```

**Validation は Experiments の前提条件** です。Validation が Pass しないと、Experiments の結果が信頼できません。

---

## 成功基準：何を持って良しとするか

### Validation の成功基準

**全テストが Pass すること** が唯一の成功基準です。

```bash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Validation Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Total tests: 24
  Passed: 24
  Failed: 0

✅ All validation tests passed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

これが「良し」です。**1つでも Fail があれば、システムに問題があります。**

### Phase 毎の成功基準

| Phase | 成功基準 | 意味 |
|-------|---------|-----|
| **Phase 1** | 6 tests Pass | Scalar Self-Haze の基礎機能が動作 |
| **Phase 2** | 6 tests Pass | Environmental Haze の基礎機能が動作 |
| **Phase 3** | 6 tests Pass | GRU/Shepherding モジュールがロード可能 |
| **Phase 4** | 6 tests Pass | Full Tensor Haze の基礎機能が動作 |
| **compat** | 1 test Pass | 既存コードが互換性を保っている |

### Validation が失敗した場合

**即座にコードを修正する必要があります。** Validation が失敗している状態で Experiments を実行しても、結果が信頼できません。

**対応手順:**

1. 失敗したテストを確認
2. エラーメッセージから原因を特定
3. コードを修正
4. Validation を再実行
5. Pass するまで繰り返す

**例:**
```bash
❌ FAIL: Per-channel precision computation
ERROR: UndefVarError: `mean` not defined

# 原因: Statistics module の import 忘れ
# 修正: using Statistics を追加
# 再実行: ./scripts/run_basic_validation.sh 4
# → ✅ PASS
```

---

## 開発ワークフローにおける位置づけ

### Git Commit 前のチェックリスト

```
□ コードを修正した
□ Validation を実行した（./scripts/run_basic_validation.sh all）
□ 全テストが Pass した
□ Git commit を実行
```

**Validation が Pass しないコードは commit すべきではありません。**

### CI/CD パイプライン（将来的な拡張）

```
┌─────────────────────────────────────────┐
│  GitHub Actions / CI Pipeline           │
├─────────────────────────────────────────┤
│  1. git push                            │
│     ↓                                   │
│  2. Validation 自動実行                 │
│     ↓ (Pass)                            │
│  3. Pull Request を自動承認可能に       │
│     ↓ (Fail)                            │
│  4. ❌ PR をブロック                     │
└─────────────────────────────────────────┘
```

将来的には、GitHub Actions 等で Validation を自動実行し、**失敗したコードがマージされないようにする** ことが理想です。

---

## 各Phase Validation の具体的意義

### Phase 1: Scalar Self-Haze Validation

**意義:** EPH の最もシンプルな実装が動作するかを確認

**検証内容:**
- エージェントが self-haze 値を持てるか
- Haze が時間経過で減衰するか
- シミュレーションが最後まで実行できるか

**なぜ重要か:**
- Phase 1 は全ての基礎。これが壊れると、Phase 2/3/4 も動かない
- 最もシンプルなため、**デバッグの起点** として重要

### Phase 2: Environmental Haze Validation

**意義:** 2D ヘイズグリッドの実装が動作するかを確認

**検証内容:**
- SPM テンソルが正しいサイズで生成されるか
- ヘイズグリッドが初期化できるか
- SPM-based EPH コントローラーが動作するか

**なぜ重要か:**
- Phase 2 は研究の中心機能。Shepherding 実験はこれに依存
- SPM は複雑な構造のため、**壊れやすい**

### Phase 3: Advanced Integration Validation

**意義:** GRU 予測器と Shepherding 機能がロードできるかを確認

**検証内容:**
- SPMPredictor モジュールが import できるか
- ShepherdingEPH モジュールが import できるか
- GRU モデルファイルが存在すれば読み込めるか

**なぜ重要か:**
- Phase 3 は複数のモジュールに依存。**依存関係の問題** が起きやすい
- GRU モデルは optional（まだ訓練していない場合もある）ため、柔軟に検証

### Phase 4: Full 3D Tensor Haze Validation

**意義:** 最も高度なヘイズ機構が動作するかを確認

**検証内容:**
- 3D ヘイズテンソルが計算できるか
- チャネル毎の精度制御が動作するか
- チャネルマスクが正しく適用されるか

**なぜ重要か:**
- Phase 4 は最新実装。**最も壊れやすい**
- 将来の研究拡張の基盤となる

### compat: Backward Compatibility Validation

**意義:** 既存の実験スクリプトが新しいコードで動作するかを確認

**検証内容:**
- `baseline_comparison.jl` が syntax error なく読み込めるか

**なぜ重要か:**
- 既存の研究結果を **再現可能** に保つため
- API 変更による破壊的変更を早期検出

---

## まとめ

### Validation の本質

**Validation は「システムの健全性を保証する安全網」です。**

| 質問 | 答え |
|-----|-----|
| **なぜ必要か？** | コード変更による破壊的変更を早期検出するため |
| **何を確認するか？** | 個別モジュールが正しく動作するか（単体テスト） |
| **何を持って良しとするか？** | 全テストが Pass すること |
| **いつ実行するか？** | コード変更の度に、commit 前に毎回 |
| **Experiments との違いは？** | Validation は動作確認、Experiments は仮説検証 |

### Validation なしの開発は危険

```
Validation なし
  ↓
コード修正
  ↓
気づかずに機能が壊れる
  ↓
Experiments を実行
  ↓
おかしな結果が出る
  ↓
原因がコードのバグか、仮説の問題か、判別できない
  ↓
デバッグに膨大な時間を消費
```

```
Validation あり
  ↓
コード修正
  ↓
Validation 実行 → ❌ FAIL
  ↓
すぐに修正
  ↓
Validation 実行 → ✅ PASS
  ↓
安心して Experiments を実行
```

### 開発者の心構え

**「Validation が全て Pass している = システムは健全」**

この状態を常に維持することが、研究の信頼性と開発効率の両方を高めます。

---

## 参考：Validation の設計思想

### Test Pyramid

```
        ┌─────────────┐
        │   E2E Tests │  ← Experiments (少数、高コスト)
        │             │
        ├─────────────┤
        │ Integration │  ← Phase compat (中程度)
        │    Tests    │
        ├─────────────┤
        │   Unit      │  ← Phase 1/2/3/4 (多数、低コスト)
        │   Tests     │
        └─────────────┘
```

EPH Validation は、このピラミッドの **Unit Tests 層** に相当します。

### Validation の原則

1. **Fast（高速）**: 数秒〜数十秒で完了すべき
2. **Independent（独立）**: テスト同士が依存しないべき
3. **Repeatable（再現可能）**: 何度実行しても同じ結果
4. **Self-validating（自己検証）**: Pass/Fail を自動判定
5. **Timely（適時）**: コード変更の直後に実行

これらの原則を守ることで、Validation が開発の邪魔ではなく、**強力な味方** になります。

---

**次のステップ:**
- Validation を習慣化する
- CI/CD パイプラインに統合する（将来）
- テストカバレッジを増やす（必要に応じて）
