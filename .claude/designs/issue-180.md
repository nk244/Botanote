---
issue: 180
title: 置き場所（部屋・屋内外）単位の植物グループ管理
status: approved
---

## 概要
リビング・ベランダ等の「置き場所」を登録し、植物を紐付けてグルーピングできるようにする。植物一覧をフィルタできる。

## スコープ外
- IoTデバイス-植物マッピングを「デバイス-場所」に発展させる連携（環境ダッシュボードとの統合）は、既存の安定したIoT機能への影響範囲が大きいため本Issueのスコープ外とし、将来のフォローアップ課題とする。本Issueでは「場所」を植物のグルーピング・一覧フィルタ用途に限定する。

## 変更対象ファイル
- `lib/models/location.dart`（新規）
- `lib/models/plant.dart`: `locationId` フィールド追加
- `lib/services/database_service.dart`: `locations` テーブル追加、`plants.locationId` カラム追加、Location CRUD追加
- `lib/providers/location_provider.dart`（新規）
- `lib/main.dart`: `LocationProvider` を MultiProvider に登録
- `lib/screens/location_list_screen.dart`（新規）: 場所の追加・編集・削除
- `lib/screens/settings_screen.dart`: 「置き場所管理」への導線を追加
- `lib/screens/add_plant_screen.dart`: 場所選択ドロップダウンを追加
- `lib/screens/plant_list_screen.dart`: 場所フィルタチップを追加

## データモデル変更
- `Location`: `id`, `name`, `isOutdoor`（bool）, `createdAt`, `updatedAt`
- `Plant.locationId`（`String?`、sentinelパターンでnullクリア可能）を追加

## DB変更
- 現在のバージョン: 5 → 新バージョン: 6
- `locations` テーブルを新規作成
- `plants` テーブルに `locationId TEXT` カラムを追加（ALTER TABLE、try/catchでべき等化）
- 場所削除時は該当植物の `locationId` を `NULL` にクリアする（DB制約ではなくアプリ側処理、既存の `_removePlantIdFromNotes` と同様のパターン）

## UI/UX設計
- 設定画面に「置き場所管理」のListTileを追加し、`LocationListScreen` へ遷移する
- `LocationListScreen`: 場所一覧（名称＋屋内/屋外アイコン）、右下FABで追加、タップで編集、スワイプまたは長押しで削除（既存画面の削除UXパターンに合わせる）
- `add_plant_screen.dart`: 購入先の下に「置き場所」の `DropdownButtonFormField<String?>` を追加（未設定＝null許容）
- `plant_list_screen.dart`: AppBar下に横スクロールの `FilterChip` 行（「すべて」＋登録済み場所一覧）を追加し、選択中の場所でリスト/グリッドをフィルタする

## エラーハンドリング
- 場所名が空の場合はバリデーションエラーを表示し保存させない
- 場所削除時の植物側 `locationId` クリアはトランザクション的に確実に行う（削除失敗時は植物側を更新しない）

## 影響範囲
- エクスポート/インポート: `Plant.toMap/fromMap` に `locationId` を含めるだけで自動対応。`locations` テーブル自体は本Issueのスコープでは export_service に含めない（植物名で十分識別可能な軽量グルーピングのため、バックアップ非対応は許容 — 大きな支障がある場合は別Issueで対応）
- 既存の水やりスケジュール・通知ロジックには影響しない

## テスト観点
- [ ] 置き場所を追加・編集・削除できる
- [ ] 植物登録・編集時に場所を選択できる（未選択も可能）
- [ ] 植物一覧の場所フィルタで対象植物のみ表示される
- [ ] 場所を削除すると、その場所が設定されていた植物の場所が「未設定」に戻る
- [ ] 既存DB（バージョン5以前）からのアップグレードでエラーが出ない
- [ ] 場所を1件も登録していない状態でアプリが問題なく動作する（フィルタチップは「すべて」のみ表示）

## 実装上の注意点
- CLAUDE.mdの依存方向規約に従い、`LocationListScreen`/`plant_list_screen.dart` は `LocationProvider` 経由でデータアクセスする
- `Plant.copyWith` の `locationId` は他のnullableフィールドと同様にsentinelパターンを使用する
