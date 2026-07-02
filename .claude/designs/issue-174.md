---
issue: 174
title: ホーム画面ウィジェット（今日の水やり予定表示）
status: approved
---

## 概要
Androidのホーム画面ウィジェットで、今日水やりが必要な植物の件数・名前をアプリを開かずに確認できるようにする。`home_widget` パッケージ（RemoteViewsベースの `HomeWidgetProvider` API、Glance/Compose不使用）を用いる。

## 変更対象ファイル
- `pubspec.yaml`: `home_widget` 依存追加
- `lib/services/home_widget_service.dart`（新規）: ウィジェットへのデータ書き込み
- `lib/providers/plant_provider.dart`: `getPlantsNeedingWateringToday()` 追加、`loadPlants()` 完了時にウィジェット更新を呼び出す
- `android/app/src/main/kotlin/com/example/bota_note/TodayWateringWidgetProvider.kt`（新規）
- `android/app/src/main/res/layout/today_watering_widget.xml`（新規）
- `android/app/src/main/res/xml/today_watering_widget_info.xml`（新規）
- `android/app/src/main/res/drawable/widget_background.xml`（新規）
- `android/app/src/main/AndroidManifest.xml`: receiver 登録

## データモデル変更
なし。

## DB変更
なし。

## UI/UX設計
- ウィジェットサイズ: 最小 110dp×40dp（2×1セル相当）、リサイズ可
- 表示内容: タイトル「今日の水やり」＋件数（例: 「3件」）＋対象植物名（先頭3件、超過分は「他N件」）
- タップでアプリを起動する（`HomeWidgetLaunchIntent`）
- 表示更新契機: `PlantProvider.loadPlants()` が完了するたびに `HomeWidgetService.updateTodayWateringWidget()` を呼び出す（起動時・ログ記録後・植物追加編集削除後など、既存のデータ更新フローに自動的に乗る）。加えてOS標準の `updatePeriodMillis`（6時間）でも更新
- 対象プラットフォーム: Android のみ（iOSはWidgetKit Extensionの追加にXcodeでのターゲット作成が必要で、Windows環境でのスクリプト的な追加は不可能なため本Issueのスコープ外とし、フォローアップ課題とする）

## エラーハンドリング
- `HomeWidgetService` 内で例外を握りつぶし、ウィジェット未配置・プラットフォーム未対応（Web/Windows/iOS）でもアプリ本体の動作に影響しないようにする

## 影響範囲
- 既存の水やりスケジュール計算ロジックには変更を加えない（`getPlantsNeedingWateringToday()` は `hasAnyWateringScheduledForToday()` と同じ判定条件を流用する読み取り専用メソッド）
- `loadPlants()` は既に高頻度で呼ばれるため、ウィジェット更新の失敗がアプリの他機能をブロックしないよう try/catch で確実に握りつぶす

## テスト観点
- [ ] `flutter build apk --debug` が成功する
- [ ] Androidエミュレーターでホーム画面にウィジェットを追加できる
- [ ] 水やり予定がある状態でウィジェットに件数・植物名が表示される
- [ ] ウィジェットタップでアプリが起動する
- [ ] アプリ内で水やりを記録するとウィジェットの件数が更新される（アプリ再起動時の反映を含む）
- [ ] 水やり予定がない場合に「今日の水やりはありません」等の表示になる
- [ ] Web/Windowsビルドで例外が発生しない

## 実装上の注意点
- `home_widget` 0.9.x はデフォルトでJetpack Glance/Composeベースのサンプルが主流だが、依存の複雑化・ビルドリスクを避けるため、パッケージが後方互換で提供している **RemoteViewsベースの `HomeWidgetProvider`** を使用する（Composeツールチェーンの追加設定が不要で本プロジェクトの既存Android構成に対する変更が最小限で済むため）
- ネイティブコードはAndroidのみ追加し、iOS/Web/Windowsは変更しない
- CLAUDE.mdの依存方向規約に従い、Provider から Service を呼び出す形で実装する
