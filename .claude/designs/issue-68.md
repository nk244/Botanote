---
issue: 68
title: IoTセンサー連携
status: implemented
---

## 概要

Nature Remo・SwitchBot などのスマートホームデバイスの REST API を呼び出し、温度・湿度を取得してローカル DB に保存する機能を追加する。MVP として**手動取得**（ボタン押下でオンデマンド取得）に絞り、バックグラウンド自動取得はスコープ外とする。設定画面で API キーを入力し、新設する「センサーログ画面」でデータ取得・記録・閲覧を行う。

## 変更対象ファイル

| ファイル | 種別 | 変更概要 |
|---|---|---|
| `lib/models/sensor_log.dart` | 新規 | センサーログデータモデル |
| `lib/services/iot_service.dart` | 新規 | Nature Remo / SwitchBot API 通信 |
| `lib/providers/sensor_log_provider.dart` | 新規 | センサーログの状態管理 |
| `lib/screens/sensor_log_screen.dart` | 新規 | センサーデータ取得・閲覧画面 |
| `lib/screens/iot_settings_screen.dart` | 新規 | IoT APIキー設定画面 |
| `lib/services/database_service.dart` | 変更 | `sensor_logs` テーブル追加・CRUD メソッド追加 |
| `lib/models/app_settings.dart` | 変更 | IoT APIキーフィールド追加 |
| `lib/services/export_service.dart` | 変更 | センサーログをバックアップ対象に追加 |
| `lib/screens/settings_screen.dart` | 変更 | 「IoTセンサー連携」セクション追加 |
| `lib/screens/home_screen.dart` | 変更 | ナビゲーションにセンサーログ画面を追加 |
| `lib/main.dart` | 変更 | `SensorLogProvider` を MultiProvider に登録 |
| `pubspec.yaml` | 変更 | `http: ^1.2.0`、`crypto: ^3.0.3` を追加 |

## データモデル変更

### 新規: `lib/models/sensor_log.dart`

```dart
enum SensorSource { natureRemo, switchBot, manual }

class SensorLog {
  final String id;           // UUID v4
  final String? plantId;     // nullable（植物に紐付けない場合も可）
  final SensorSource source; // 取得元
  final String deviceId;     // デバイスID
  final String deviceName;   // デバイス名
  final double? temperature; // 気温（℃）
  final double? humidity;    // 湿度（%）
  final DateTime recordedAt; // センサー計測時刻
  final DateTime createdAt;  // DB 登録時刻
}
```

sentinel パターン不要（全フィールドが immutable で、変更は再取得・再挿入で対応）。

### 変更: `lib/models/app_settings.dart`

`AppSettings` に以下フィールドを追加する（SharedPreferences の JSON で永続化）:

```dart
final String natureRemoToken;   // Nature Remo APIトークン
final String switchBotToken;    // SwitchBot APIトークン
final String switchBotSecret;   // SwitchBot HMAC署名シークレット
```

デフォルトは空文字列。`copyWith`・`toMap`・`fromMap` も更新する。

## DB変更

- **現バージョン**: 4
- **新バージョン**: 5

### 新規テーブル `sensor_logs`

```sql
CREATE TABLE sensor_logs(
  id TEXT PRIMARY KEY,
  plantId TEXT,
  source TEXT NOT NULL,
  deviceId TEXT NOT NULL,
  deviceName TEXT NOT NULL,
  temperature REAL,
  humidity REAL,
  recordedAt TEXT NOT NULL,
  createdAt TEXT NOT NULL
)
```

plantId への外部キー制約は設けない（植物削除後もセンサーログは保持する方針）。

### マイグレーション (`onUpgrade` 追記)

```dart
if (oldVersion < 5) {
  await db.execute('''CREATE TABLE sensor_logs(...)''');
}
```

### DatabaseService に追加するメソッド

- `insertSensorLog(SensorLog log)`
- `getAllSensorLogs()` — `recordedAt DESC` 順
- `getSensorLogsByPlant(String plantId)`
- `deleteSensorLog(String id)`

## UI/UX 設計

### 1. ナビゲーション変更（`home_screen.dart`）

ボトムナビゲーションに「センサー」タブを追加（4タブ構成に変更）:

```
水やりログ | 植物一覧 | ノート | センサー
```

### 2. センサーログ画面（`sensor_log_screen.dart`）

```
AppBar: "センサーログ"  [設定アイコン → IotSettingsScreen へ]

── デバイス選択チップ（ Nature Remo / SwitchBot、連携済みのみ表示） ──
── 「センサーデータを取得」ボタン ──
     ↓ 取得成功
[ダイアログ] デバイス名、温度 XX.X℃、湿度 XX.X%
             植物に紐付け: (ドロップダウン / 「なし」)
             [記録する] [キャンセル]
             
── 取得履歴リスト（日付降順） ──
[カード]  日時 / デバイス名 / 温度・湿度 / 紐付け植物名
          長押し or スワイプで削除
```

既存の `_buildGroupedLogRow`（`plant_detail_screen.dart`）の Card スタイルを参考にする。

### 3. IoT 設定画面（`iot_settings_screen.dart`）

```
AppBar: "IoTセンサー設定"

── Nature Remo ──
  APIトークン: [TextField (obscureText)]
  [接続テスト] → 成功: デバイス名 SnackBar / 失敗: エラーメッセージ

── SwitchBot ──
  APIトークン: [TextField (obscureText)]
  シークレット: [TextField (obscureText)]
  [接続テスト]

[保存]
```

### 4. 設定画面へのエントリ（`settings_screen.dart`）

既存の「データ管理」セクションの下に「IoTセンサー連携」セクションを追加:

```dart
_buildSectionHeader(context, 'IoTセンサー連携'),
ListTile(
  leading: const Icon(Icons.sensors),
  title: const Text('センサー連携の設定'),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.push(...IotSettingsScreen()),
),
```

## エラーハンドリング

| 異常系 | 対処方針 |
|---|---|
| APIキー未設定 | 取得ボタン押下時に「APIキーが未設定」SnackBar |
| ネットワーク不通 | `SocketException` / `TimeoutException` をキャッチし SnackBar 表示 |
| APIレスポンス異常 (4xx/5xx) | ステータスコードをメッセージに含めて SnackBar 表示 |
| デバイスに温湿度センサーなし | 該当フィールドが null のまま表示（"--" 表記） |
| DB 挿入失敗 | `try/catch` でキャッチし SnackBar 表示（データは破棄しない） |

## 影響範囲

- **バックアップ/エクスポート**: `export_service.dart` の `_buildZipBytes` と `_importData` を拡張し、`sensor_logs` テーブルを `data.json` の `sensorLogs` キーに含める。バックアップ version を `3` に上げる（`version > 3` は未対応エラー）。
- **通知**: 影響なし（センサー取得は手動のみ）
- **植物削除**: `plantId` に外部キー制約なしのため、孤立レコードが残る（表示時は植物名「削除済み」として扱う）
- **他画面**: 植物詳細の「情報」タブに最新センサー値（温度・湿度）を任意表示する（設計段階では省略可能、実装の余裕があれば追加）

## テスト観点

### 正常系
- [ ] Nature Remo の API トークンを設定し「接続テスト」が成功する
- [ ] SwitchBot のトークン・シークレットを設定し「接続テスト」が成功する
- [ ] Nature Remo からセンサーデータ（温度・湿度）が取得できる
- [ ] SwitchBot からセンサーデータが取得できる
- [ ] 取得したデータを植物に紐付けて保存できる
- [ ] 植物に紐付けずに保存できる（`plantId = null`）
- [ ] センサーログ画面に履歴が日付降順で表示される
- [ ] センサーログを削除できる
- [ ] エクスポート ZIP に `sensorLogs` が含まれる
- [ ] インポートでセンサーログが復元される

### 異常系
- [ ] APIキー未設定時に適切なエラーメッセージが表示される
- [ ] 不正なAPIキーで「接続テスト」するとエラーメッセージが表示される
- [ ] オフライン時に取得ボタンを押すとエラーメッセージが表示される
- [ ] センサーが温湿度を持たないデバイスでも UI がクラッシュしない

### 境界値・その他
- [ ] センサーログが 0 件の場合にセンサーログ画面が空状態を表示する
- [ ] 植物を削除した後も、紐付いていたセンサーログが残る（孤立レコードで表示「削除済み」）
- [ ] DB v4 → v5 へのマイグレーションが正常に完了する（旧端末シミュレート）
- [ ] `flutter analyze` でエラーがない

## 実装上の注意点

### API 仕様
- **Nature Remo**: `GET https://api.nature.global/1/devices` を `Authorization: Bearer <token>` ヘッダーで呼び出す。レスポンスのデバイスオブジェクト内 `newest_events.te.val`（温度）・`newest_events.hu.val`（湿度）を使う。
- **SwitchBot**: `GET https://api.switch-bot.com/v1.1/devices` → `GET https://api.switch-bot.com/v1.1/devices/{deviceId}/status`。リクエストヘッダーに `Authorization: <token>`、`sign: HMAC-SHA256(token+timestamp+uuid, secret)`、`t: <timestamp_ms>`、`nonce: <uuid>` を付与する（`crypto` パッケージで署名）。

### アーキテクチャ
- `IotService` は `PlantProvider` に依存せず、取得したデータは raw な `Map` を返す。`SensorLogProvider` 側で `SensorLog` への変換を行う。
- HTTP 通信は `dart:io` の `HttpClient` ではなく `http` パッケージを使用し、タイムアウトは `client.get(...).timeout(const Duration(seconds: 10))` で設定する。
- APIキーは `AppSettings` 経由で `SharedPreferences` に保存する（Botanote は既存の機密データも SharedPreferences を使用している点と統一するため）。

### コーディング規約
- `SensorLog.copyWith` は不要（ログは記録後に変更しない設計）
- `SensorSource` の表示名は `IotService` 内でなく UI 層（`sensor_log_screen.dart`）で定義する
- 既存の `_buildSectionHeader` ウィジェット（`settings_screen.dart`）を再利用する
- DB マイグレーションの `CREATE TABLE` は `CREATE TABLE IF NOT EXISTS` とすることでべき等性を確保する
- センサーデータ取得中は `_isFetching` フラグで `CircularProgressIndicator` を表示する（`settings_screen.dart` の `_isExporting` パターンと同様）
- `IotSettingsScreen` での設定保存は `SettingsProvider.updateIotSettings(...)` 経由とし、`SettingsService` を直接呼ばない

## レビュー結果
- レビュー日: 2026-06-30
- 結果: 承認
- コメント: アーキテクチャ・コーディング規約・DB 安全性・エラーハンドリングに問題なし。実装上の注意点に軽微な補足（IF NOT EXISTS、ローディング状態、SettingsProvider 経由の保存）を追記済み。
