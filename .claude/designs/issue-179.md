---
issue: 179
title: 植物ごとの成長写真タイムライン
status: approved
---

## 概要
植物詳細画面から、その植物に紐付くノート画像（＋登録時の植物写真）を時系列に並べた成長タイムラインを表示する。既存データ（ノートの `imagePaths`/`plantIds`、植物の `imagePath`）のみを使用し、新規テーブルは追加しない。

## 変更対象ファイル
- `lib/screens/plant_growth_timeline_screen.dart`（新規）: タイムライン表示画面
- `lib/screens/plant_detail_screen.dart`: AppBarアクションにタイムラインへの導線を追加

## データモデル変更
なし。

## DB変更
なし。既存の `Note.imagePaths`/`Note.plantIds`、`Plant.imagePath`/`Plant.purchaseDate` のみを使用する。

## UI/UX設計
- `plant_detail_screen.dart` のSliverAppBar `actions` に `Icons.auto_awesome_motion`（タイムライン）アイコンボタンを追加し、`PlantGrowthTimelineScreen` へ遷移する
- `PlantGrowthTimelineScreen`:
  - `Consumer<NoteProvider>` でその植物に紐付くノートを取得し、各ノートの `imagePaths` を `note.createdAt` とともにフラット化する
  - 植物の `imagePath`（登録時の写真）があれば `purchaseDate ?? createdAt` を日付として先頭候補に加える
  - 日付昇順でソートし、`GridView`（正方形サムネイル、日付キャプション付き）で表示する
  - 写真が2枚以上ある場合、AppBarに「比較」ボタンを表示し、最初の写真と最新の写真を左右に並べた「ビフォーアフター」ビューをダイアログで表示する
  - 写真が0枚の場合は空状態（アイコン＋「まだ成長記録がありません。ノートに写真を追加すると、ここに時系列で表示されます」）を表示する
  - サムネイルタップで既存の画像ビューア相当の拡大表示（`InteractiveViewer` を使ったシンプルなダイアログ）を行う

## エラーハンドリング
- 画像ファイルが存在しない/読み込みに失敗した場合は `PlantImageWidget` 側の既存エラーハンドリングに委譲する（新規のエラーハンドリングは不要）

## 影響範囲
- 既存のノート・植物データの読み取りのみで、書き込み処理は行わないためバックアップ・エクスポート・通知には影響しない
- `plant_detail_screen.dart` への変更はAppBarアクション追加のみで、既存の4タブ構成（情報/ログ/ノート/環境）は変更しない

## テスト観点
- [ ] ノートに画像がある植物でタイムライン画面を開くと、時系列順に写真が表示される
- [ ] 植物の登録時写真がタイムラインの先頭（購入日 or 登録日基準）に含まれる
- [ ] 写真が1枚以下の場合、「比較」ボタンが表示されない
- [ ] 写真が2枚以上の場合、「比較」ボタンで最初と最新の写真が並んで表示される
- [ ] 写真が1枚もない植物では空状態メッセージが表示される
- [ ] サムネイルタップで拡大表示できる

## 実装上の注意点
- CLAUDE.mdの依存方向規約（screens→providers→models）に従い、DB直接アクセスは行わずNoteProvider/Plantモデル経由でデータ取得する
- 画像表示は既存の `PlantImageWidget`（Web/ネイティブ両対応）を再利用し、パス形式の差異を意識しない
