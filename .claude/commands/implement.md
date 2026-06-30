承認済み設計書に従って機能を実装し、PR を作成する。

## 前提

- 引数（$ARGUMENTS）にIssue番号を指定する。例: `/implement 156`
- `.claude/designs/issue-<N>.md` の status が `approved` であること
- status が `approved` でない場合は「先に `/design-review <N>` で承認を受けてください」と案内して停止する

## 手順

### ステップ1: 設計書の確認

`.claude/designs/issue-<N>.md` を読み込み、以下を把握する:
- 変更対象ファイルと変更概要
- データモデル変更・DB変更の内容
- UI/UX設計
- 実装上の注意点

### ステップ2: mainの最新化とブランチの作成

まず `main` ブランチを最新化してからブランチを作成する:
```
git checkout main
git pull origin main
```

設計書タイトルから kebab-case のブランチ名を生成してチェックアウトする:
```
feat/<機能名-kebab-case>-<N>
```
例: Issue #156「その他の植物に水やりのときも複数選択したい」→ `feat/unscheduled-multi-select-156`

### ステップ3: 実装

設計書に従って実装する。実装時は CLAUDE.md の規約を厳守する:

- **コメント**: すべて日本語で記述する（`//` インラインコメント、`///` ドキュメントコメント）
- **不変性**: `final` を積極的に使用する
- **非同期**: `async`/`await` を使用し、`.then()` チェーンは避ける
- **ウィジェット**: build() が長くなる場合は `_buildXxx()` プライベートメソッドに分割する
- **DB変更**: 累積マイグレーション方式、ALTER TABLE は try/catch でラップする
- **依存方向**: screens→providers→services→models を守り、screens から services を直接呼ばない

### ステップ4: 静的解析

```bash
flutter analyze
```

**エラーが1件でもある場合は必ず修正してから次のステップに進む。**
警告も可能な限り解消する。

### ステップ5: テスト実行

```bash
flutter test
```

既存テストが失敗した場合は原因を調査して実装を修正する。

### ステップ6: コミット

変更ファイルをステージングし、Conventional Commits 形式でコミットする:
```
feat: <変更内容の要約（日本語可）> (#<N>)
```

### ステップ7: PR 作成

PR作成前に `main` の最新をブランチに取り込む:
```
git fetch origin main
git rebase origin/main
```

コンフリクトが発生した場合は解消してから進む。

ブランチをリモートにプッシュし、PR を作成する。
**プッシュ前にユーザーに確認を求める。**

PR 本文に含めるもの:
- 変更内容の箇条書き（日本語）
- 設計書パス: `.claude/designs/issue-<N>.md`
- テスト手順（設計書の「テスト観点」を転記）
- UI変更がある場合は「スクリーンショット: 要添付」と明記

### ステップ8: 完了報告

PR の URL をユーザーに報告する。
設計書のフロントマターを `status: implemented` に更新する。
ユーザーに `/test <N>` でテスト確認観点を確認するよう案内する。
