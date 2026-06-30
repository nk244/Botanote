---
issue: 169
title: IoTセンサーのデバイス-植物マッピングとアプリ起動時自動取得
status: implemented
---

## 概要

センサーデバイスと複数の植物を事前にマッピングしておき、取得時に自動で全植物に SensorLog を生成する機能と、設定した時間間隔が経過していたらアプリ起動時に自動取得する機能を追加する。マッピングは SharedPreferences に保存し、DB 変更は不要。

## 変更対象ファイル

| ファイル | 種別 | 変更概要 |
|---|---|---|
| `lib/models/sensor_device_mapping.dart` | 新規 | デバイス-植物マッピングデータモデル |
| `lib/models/app_settings.dart` | 変更 | `sensorDeviceMappings` / `sensorFetchIntervalHours` / `lastSensorFetchAt` を追加 |
| `lib/providers/settings_provider.dart` | 変更 | マッピング・間隔・最終取得日時の更新メソッドを追加 |
| `lib/providers/sensor_log_provider.dart` | 変更 | マッピングを使った一括保存メソッドを追加 |
| `lib/screens/iot_settings_screen.dart` | 変更 | デバイス設定（植物マッピング）セクションと自動取得間隔設定を追加 |
| `lib/screens/plant_detail_screen.dart` | 変更 | `_startFetchFlow` でマッピング先の全植物に保存するよう変更 |
| `lib/screens/home_screen.dart` | 変更 | 起動時自動取得チェックを追加 |

## データモデル変更

### 新規: `lib/models/sensor_device_mapping.dart`

```dart
import 'sensor_log.dart';

/// センサーデバイスと植物の紐づけ設定
class SensorDeviceMapping {
  final String deviceId;
  final String deviceName;
  final SensorSource source;
  final List<String> plantIds; // 紐づける植物IDリスト

  const SensorDeviceMapping({
    required this.deviceId,
    required this.deviceName,
    required this.source,
    required this.plantIds,
  });

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'source': source.name,
    'plantIds': plantIds,
  };

  factory SensorDeviceMapping.fromMap(Map<String, dynamic> map) =>
    SensorDeviceMapping(
      deviceId: map['deviceId'] as String,
      deviceName: map['deviceName'] as String,
      source: SensorSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => SensorSource.manual,
      ),
      plantIds: List<String>.from(map['plantIds'] as List? ?? []),
    );
}
```

### 変更: `lib/models/app_settings.dart`

`AppSettings` に以下フィールドを追加する:

```dart
/// デバイス-植物マッピング設定
final List<SensorDeviceMapping> sensorDeviceMappings;

/// センサー自動取得間隔（時間）。0 = 無効
final int sensorFetchIntervalHours;

/// 最後にセンサーを自動取得した日時（ISO8601文字列、未取得は null）
final String? lastSensorFetchAt;
```

デフォルト値: `sensorDeviceMappings = const []`, `sensorFetchIntervalHours = 0`, `lastSensorFetchAt = null`

**`copyWith` の sentinel パターン**:

`lastSensorFetchAt` は null クリアが必要なため sentinel パターンを適用する:

```dart
const Object _sentinel = Object();

AppSettings copyWith({
  // ... 既存フィールド ...
  List<SensorDeviceMapping>? sensorDeviceMappings,
  int? sensorFetchIntervalHours,
  Object? lastSensorFetchAt = _sentinel,
}) {
  return AppSettings(
    // ... 既存フィールド ...
    sensorDeviceMappings: sensorDeviceMappings ?? this.sensorDeviceMappings,
    sensorFetchIntervalHours: sensorFetchIntervalHours ?? this.sensorFetchIntervalHours,
    lastSensorFetchAt: lastSensorFetchAt == _sentinel
        ? this.lastSensorFetchAt
        : lastSensorFetchAt as String?,
  );
}
```

**`toMap()` / `fromMap()`**:

```dart
// toMap に追加
'sensorDeviceMappings': sensorDeviceMappings.map((m) => m.toMap()).toList(),
'sensorFetchIntervalHours': sensorFetchIntervalHours,
'lastSensorFetchAt': lastSensorFetchAt,

// fromMap に追加
sensorDeviceMappings: (map['sensorDeviceMappings'] as List<dynamic>? ?? [])
    .map((m) => SensorDeviceMapping.fromMap(Map<String, dynamic>.from(m as Map)))
    .toList(),
sensorFetchIntervalHours: map['sensorFetchIntervalHours'] as int? ?? 0,
lastSensorFetchAt: map['lastSensorFetchAt'] as String?,
```

## DB変更

なし。マッピング・間隔・最終取得日時はすべて SharedPreferences に保存する。

## UI/UX設計

### 1. IoT設定画面のデバイス設定（`iot_settings_screen.dart`）

接続テストの「接続成功」SnackBar に加え、**接続成功時にデバイス一覧をステート変数に保持**して設定画面内に「デバイス設定」セクションを表示する。

```
── Nature Remo ──
  [既存: APIトークン入力・接続テスト]
  
  // 接続成功後に表示
  ── デバイス設定 ──
  [デバイス名 A]  紐づけ: 植物1・植物2  [設定する >]
  [デバイス名 B]  紐づけなし            [設定する >]

── SwitchBot ──
  [既存: トークン・シークレット入力・接続テスト]
  
  // 接続成功後に表示
  ── デバイス設定 ──
  [デバイス名 C]  紐づけ: 植物3         [設定する >]

── 自動取得間隔 ──
  DropdownButton: 無効 / 1時間 / 3時間 / 6時間 / 12時間 / 24時間
```

「設定する >」タップ → `_showPlantMappingDialog()` でチェックリストダイアログを表示:

```
[ダイアログ] デバイス名A の紐づけ植物
  ☑ 植物1
  ☐ 植物2  
  ☑ 植物3
  [キャンセル] [保存]
```

保存時は `SettingsProvider.updateDeviceMappings()` を呼ぶ。

**自動取得間隔**は `DropdownButton<int>` で実装:
- 選択肢: `{0: '無効', 1: '1時間', 3: '3時間', 6: '6時間', 12: '12時間', 24: '24時間'}`
- 変更時は即座に `SettingsProvider.updateSensorFetchInterval()` を呼ぶ（「保存」ボタン不要）

**ステート変数の追加**:
```dart
List<SensorData>? _natureRemoDevices;  // 接続テスト成功後に格納
List<SensorData>? _switchBotDevices;
```

### 2. plant_detail_screen.dart の `_startFetchFlow()` 変更

現在: 選択デバイス → `plantId: widget.plant.id` で1件保存

変更後: 選択デバイスのマッピングを参照 → **マッピングされた全植物 + 現在の植物** に保存

```dart
Future<void> _startFetchFlow(SensorSource source) async {
  // ... 既存のデバイス取得・選択ロジック ...

  // マッピングから紐づけ植物IDを取得し、現在の植物を含む一意リストを作成
  final mappings = settingsProvider.settings.sensorDeviceMappings;
  final mapping = mappings.firstWhere(
    (m) => m.deviceId == selected.deviceId && m.source == source,
    orElse: () => SensorDeviceMapping(
      deviceId: selected.deviceId,
      deviceName: selected.deviceName,
      source: source,
      plantIds: [],
    ),
  );
  final plantIds = {...mapping.plantIds, widget.plant.id}.toList();

  await sensorProvider.saveSensorLogsForPlants(
    data: selected,
    source: source,
    plantIds: plantIds,
  );
  // ...
}
```

### 3. HomeScreen の起動時自動取得

`initState()` の `addPostFrameCallback` に自動取得チェックを追加:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  // ... 既存のコールバック設定 ...
  await _checkAndAutoFetch();
});

Future<void> _checkAndAutoFetch() async {
  final settings = context.read<SettingsProvider>().settings;
  final intervalHours = settings.sensorFetchIntervalHours;
  if (intervalHours <= 0) return;

  // APIキーが未設定なら何もしない
  final hasNatureRemo = settings.natureRemoToken.isNotEmpty;
  final hasSwitchBot = settings.switchBotToken.isNotEmpty
      && settings.switchBotSecret.isNotEmpty;
  if (!hasNatureRemo && !hasSwitchBot) return;

  // 前回取得から設定間隔が経過しているか確認
  final lastFetch = settings.lastSensorFetchAt != null
      ? DateTime.tryParse(settings.lastSensorFetchAt!)
      : null;
  final now = DateTime.now();
  if (lastFetch != null &&
      now.difference(lastFetch).inHours < intervalHours) return;

  // 自動取得を実行
  try {
    final count = await context.read<SensorLogProvider>()
        .fetchAndSaveWithMappings(settings);
    if (!mounted) return;
    await context.read<SettingsProvider>()
        .updateLastSensorFetchAt(now);
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('センサーデータを自動取得しました（$count件）')),
      );
    }
  } catch (_) {
    // 自動取得エラーはサイレントに無視する（起動時に通知しない）
  }
}
```

### 4. SensorLogProvider の追加メソッド

```dart
/// 複数の植物にセンサーログを一括保存する。
Future<void> saveSensorLogsForPlants({
  required SensorData data,
  required SensorSource source,
  required List<String> plantIds,
}) async {
  final now = DateTime.now();
  for (final plantId in plantIds) {
    final log = SensorLog(
      id: const Uuid().v4(),
      plantId: plantId,
      source: source,
      deviceId: data.deviceId,
      deviceName: data.deviceName,
      temperature: data.temperature,
      humidity: data.humidity,
      recordedAt: now,
      createdAt: now,
    );
    await _db.insertSensorLog(log);
  }
  await loadLogs();
}

/// マッピング設定に基づき全デバイスからデータを取得して保存する。
///
/// 戻り値: 保存した SensorLog の総件数
Future<int> fetchAndSaveWithMappings(AppSettings settings) async {
  int count = 0;
  final mappings = settings.sensorDeviceMappings;

  if (settings.natureRemoToken.isNotEmpty) {
    final devices = await _iot.fetchNatureRemoData(settings.natureRemoToken);
    for (final device in devices) {
      final mapping = mappings.firstWhere(
        (m) => m.deviceId == device.deviceId && m.source == SensorSource.natureRemo,
        orElse: () => SensorDeviceMapping(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          source: SensorSource.natureRemo,
          plantIds: [],
        ),
      );
      if (mapping.plantIds.isEmpty) continue;
      await saveSensorLogsForPlants(
        data: device,
        source: SensorSource.natureRemo,
        plantIds: mapping.plantIds,
      );
      count += mapping.plantIds.length;
    }
  }

  if (settings.switchBotToken.isNotEmpty && settings.switchBotSecret.isNotEmpty) {
    final devices = await _iot.fetchSwitchBotData(
        settings.switchBotToken, settings.switchBotSecret);
    for (final device in devices) {
      final mapping = mappings.firstWhere(
        (m) => m.deviceId == device.deviceId && m.source == SensorSource.switchBot,
        orElse: () => SensorDeviceMapping(
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          source: SensorSource.switchBot,
          plantIds: [],
        ),
      );
      if (mapping.plantIds.isEmpty) continue;
      await saveSensorLogsForPlants(
        data: device,
        source: SensorSource.switchBot,
        plantIds: mapping.plantIds,
      );
      count += mapping.plantIds.length;
    }
  }

  return count;
}
```

## エラーハンドリング

| 異常系 | 対処方針 |
|---|---|
| デバイス取得失敗（ネットワーク不通など） | `_startFetchFlow` では SnackBar 表示、`fetchAndSaveWithMappings` では呼び出し元に再スローせずサイレントに無視（起動時は通知しない） |
| マッピングに存在しないデバイスを取得 | plantIds が空のマッピングとして扱い、保存しない |
| マッピング先の植物がすでに削除済み | DB の sensor_logs に外部キー制約なしのため孤立レコードとして保存（既存挙動と同じ） |
| plantIds が空のまま自動取得実行 | count = 0 で SnackBar を表示しない |
| 接続テスト後にデバイス一覧取得失敗 | SnackBar でエラー表示、デバイス設定セクションは非表示のまま |

## 影響範囲

- **バックアップ/エクスポート**: `AppSettings` に追加したフィールドは SharedPreferences の JSON として保存されるため、バックアップ対象ではない（設定は端末固有のため影響なし）
- **センサーログのバックアップ**: 変更なし（SensorLog モデルに変更なし）
- **plant_detail_screen の環境タブ**: `_startFetchFlow()` の動作変更により、マッピング設定済みの場合は複数植物に保存される（UXは同一）
- **sensor_log_screen**: 変更なし

## テスト観点

### 正常系
- [ ] IoT設定画面で接続テスト成功後にデバイス一覧（デバイス設定セクション）が表示される
- [ ] 「設定する」タップでチェックリストダイアログが開き、植物を複数選択して保存できる
- [ ] マッピング設定後に植物詳細の「取得」ボタンを押すと、マッピング先の全植物に SensorLog が保存される（現在の植物も含む）
- [ ] 自動取得間隔を「1時間」に設定した後、アプリを再起動すると自動取得が実行される
- [ ] 自動取得成功時にSnackBarが表示される
- [ ] 設定間隔内での再起動では自動取得が実行されない（lastSensorFetchAt が更新されている）
- [ ] 自動取得間隔「無効」では起動時に取得が走らない

### 異常系
- [ ] マッピングなしのデバイスがある場合、そのデバイスは自動取得でスキップされる
- [ ] APIキー未設定の場合、自動取得が走らない
- [ ] デバイス設定セクションで全植物のチェックを外して保存すると plantIds が空になり、自動取得でスキップされる

### 境界値・その他
- [ ] 同一デバイスに3植物以上マッピングしても全植物に保存される
- [ ] Nature Remo と SwitchBot 両方設定済みの場合、両方のデバイスから自動取得が実行される
- [ ] 自動取得で複数デバイス・複数植物のすべての組み合わせで SensorLog が生成される
- [ ] `flutter analyze` でエラーがない

## 実装上の注意点

- `SensorDeviceMapping` は `lib/models/sensor_device_mapping.dart` に単独ファイルで定義する（1ファイル1クラス原則）
- `AppSettings.copyWith` の `lastSensorFetchAt` は null クリアが必要なため sentinel パターン必須（`app_settings.dart` ファイル末尾に `const Object _sentinel = Object();` を定義）
- `fetchAndSaveWithMappings` は `SensorLogProvider` 内に置き、screens から services を直接呼ばないアーキテクチャ規約を守る
- `HomeScreen._checkAndAutoFetch()` は `addPostFrameCallback` 内で実行し、`initState` 内で直接 `context.read` しない（Flutter のライフサイクル規約）
- 自動取得エラーは起動体験を損なわないためサイレントに無視する（ログ出力 `debugPrint` のみ）
- IoT設定画面の `_natureRemoDevices` / `_switchBotDevices` は接続テスト成功後に `setState` で更新し、画面を再ビルドしてデバイス設定セクションを表示する
- マッピングダイアログで使う植物一覧は `context.read<PlantProvider>().plants` から取得し、IoT設定画面の import に `PlantProvider` を追加する
- `fetchAndSaveWithMappings` の Nature Remo / SwitchBot 各フェッチを個別の `try/catch` で包み、片方が失敗しても他方を試みるようにする
- `_checkAndAutoFetch` の冒頭で `if (!mounted) return;` を入れてライフサイクル安全を確保する
- IoT設定画面のデバイス設定セクションは `_buildNatureRemoDeviceSettings()` / `_buildSwitchBotDeviceSettings()` / `_buildAutoFetchSection()` に分割する（100行超対策）

## レビュー結果
- レビュー日: 2026-06-30
- 結果: 承認
- コメント: アーキテクチャ・規約・エラーハンドリング・DB安全性に問題なし。実装上の注意点に軽微な補足（各ソースの個別try/catch、mountedチェック、ウィジェット分割方針）を追記済み。
