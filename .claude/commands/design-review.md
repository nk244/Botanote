設計書をレビューし、承認または修正依頼を行う。

## 前提

- 引数（$ARGUMENTS）にIssue番号を指定する。例: `/design-review 156`
- `.claude/designs/issue-<N>.md` が存在すること。なければ「先に `/feature-design <N>` を実行してください」と案内して停止する
- status が `approved` または `implemented` の場合はその旨を伝え、再レビューするか確認する

## 手順

### ステップ1: 設計書と関連コードの読み込み

1. `.claude/designs/issue-<N>.md` を読み込む
2. 設計書の「変更対象ファイル」に列挙されたファイルをすべて読み込み、
   設計の実現可能性と既存コードとの整合性を確認する

### ステップ2: レビューチェック

以下の観点でチェックし、問題点を列挙する:

**アーキテクチャ規約（CLAUDE.md準拠）**
- 依存方向が正しいか（screens→providers→services→models）
- screens から services を直接呼んでいないか
- models が services や providers に依存していないか

**コーディング規約（Effective Dart）**
- ファイル名は snake_case か
- クラス名は UpperCamelCase か
- nullable フィールドの copyWith に sentinel パターンが使われているか
- DB の toMap/fromMap のキー名はフィールド名・カラム名と一致しているか

**DB変更の安全性**
- マイグレーションは累積方式（oldVersion < N の連鎖）になっているか
- ALTER TABLE は try/catch でべき等にラップされているか
- バックアップ/エクスポートへの影響が設計書に記載されているか

**エッジケース・堅牢性**
- 空リスト・null・DB失敗などの異常系が考慮されているか
- 非同期処理に適切な try/catch があるか
- unawaited な Future が放置されていないか

**UI/UX の一貫性**
- Material3 のコンポーネント（FilledButton、ActionChip 等）と統一されているか
- ローディング状態・エラー状態の表示が考慮されているか
- 100行超のウィジェットは _buildXxx() に分割する方針が示されているか

### ステップ3: 判定と設計書の更新

**問題なし → 承認**

設計書のフロントマターを `status: approved` に更新し、末尾に以下を追記する:

```
## レビュー結果
- レビュー日: <YYYY-MM-DD>
- 結果: 承認
- コメント: <特記事項があれば記載、なければ「問題なし」>
```

ユーザーに結果を伝え、次のコマンドを案内する:
```
/implement <N>
```

**問題あり → 修正依頼**

設計書の status は `draft` のままにし、末尾に以下を追記する:

```
## レビュー結果
- レビュー日: <YYYY-MM-DD>
- 結果: 修正依頼
- 指摘事項:
  1. <問題点と具体的な修正方針>
  2. ...
```

ユーザーに指摘事項を説明し、設計書を修正して `/design-review <N>` を再実行するよう案内する。
