---
issue: 176
title: 天気連動ケアアラート
status: approved
---

## 概要
登録した緯度・経度の天気予報（Open-Meteo、APIキー不要）を確認し、猛暑日・低温・大雨・強UVが予想される場合に屋外植物のケアを促す通知を出す。

## スコープ・設計判断
- GPS自動取得は行わず、既存のIoT連携（APIキーを設定画面で手入力する方式）と同様に、緯度・経度を設定画面で手入力する方式にする。位置情報パーミッションの追加取得フローを避け、実装・審査リスクを抑える
- 植物の屋内/屋外属性は `Plant.isOutdoor` として追加する（Issue #180 で追加した `Location.isOutdoor` と概念が重複するが、#180のPRは未マージのため本Issueは独立して完結させる。将来的に両者をマージ後に統合可能）

## 変更対象ファイル
- `lib/models/plant.dart`: `isOutdoor` フィールド追加
- `lib/models/app_settings.dart`: `weatherAlertsEnabled`/`weatherLatitude`/`weatherLongitude` を追加
- `lib/services/database_service.dart`: `plants.isOutdoor` カラム追加（DB v5→6）
- `lib/services/weather_service.dart`（新規）: Open-Meteo APIクライアント、閾値判定
- `lib/services/notification_service.dart`: `scheduleWeatherAlert()` を追加
- `lib/providers/settings_provider.dart`: `updateWeatherAlertSettings()` を追加
- `lib/main.dart`: バックグラウンドタスクで `scheduleWeatherAlert()` も呼び出す
- `lib/screens/add_plant_screen.dart`: 「屋外の植物」トグルを追加
- `lib/screens/settings_screen.dart`: 天気連動アラートの設定UIを追加

## データモデル変更
- `Plant.isOutdoor`（`bool`, デフォルト `false`、非nullableのため sentinel 不要）
- `AppSettings.weatherAlertsEnabled`（`bool`, デフォルト `false`）
- `AppSettings.weatherLatitude` / `weatherLongitude`（`double?`、sentinelパターンでnullクリア可能）

## DB変更
- 現在のバージョン: 5 → 新バージョン: 6
- `plants` テーブルに `isOutdoor INTEGER NOT NULL DEFAULT 0` を ALTER TABLE で追加（try/catchでべき等化）

## UI/UX設計
- `add_plant_screen.dart`: 水やり間隔セクション付近に `SwitchListTile`「屋外の植物」を追加
- `settings_screen.dart`: 新セクション「天気連動アラート」
  - `SwitchListTile` で有効/無効
  - 有効時のみ緯度・経度の `TextFormField`（数値入力）を表示。ヒントテキストで「Googleマップの座標をコピーして入力してください」と案内
  - 保存ボタンで設定を確定し、`SettingsProvider.updateWeatherAlertSettings()` を呼び出す

## エラーハンドリング
- Open-Meteo APIの通信失敗・タイムアウト（10秒）はログのみで通知をスキャンセルせず既存通知を維持する（サイレント失敗、アプリ動作への影響なし）
- 緯度・経度が未設定、または屋外植物が1件もない場合は通知をスケジュールしない（`cancel`のみ実行）

## 影響範囲
- 既存の水やり通知（`_dailyWateringNotificationId`）とは別の通知ID（`_weatherAlertNotificationId`）を使うため、既存のスマート水やり通知には影響しない
- エクスポート/インポート: `Plant.toMap/fromMap`、`AppSettings.toMap/fromMap` に追加するだけで自動対応
- IoTセンサー連携（屋内環境）とは独立した機能で、既存コードへの変更はなし

## テスト観点
- [ ] 植物編集画面で「屋外」を設定できる
- [ ] 設定画面で天気連動アラートを有効化し、緯度・経度を入力できる
- [ ] 緯度経度が不正な値の場合はエラー表示され保存されない
- [ ] 猛暑日・低温・大雨・強UVの閾値を超える予報がある場合、通知がスケジュールされる（手動でAPIレスポンスを確認）
- [ ] 屋外植物が0件の場合は通知がスケジュールされない
- [ ] アラート無効化時に既存の天気通知がキャンセルされる
- [ ] 既存DB（バージョン5以前）からのアップグレードでエラーが出ない
- [ ] Web/Windowsビルドで例外が発生しない

## 実装上の注意点
- `NotificationService.scheduleWeatherAlert()` はバックグラウンドIsolateから呼ばれるため、Providerを使わずSharedPreferences/DatabaseServiceに直接アクセスする既存パターン（`scheduleSmartWateringReminder`）を踏襲する
- Open-Meteo APIはAPIキー不要の無料エンドポイント（`https://api.open-meteo.com/v1/forecast`）を使用し、追加の認証情報管理は不要
