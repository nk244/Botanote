/// IoTセンサーのデータ取得元を表す列挙型
enum SensorSource {
  /// Nature Remo
  natureRemo,

  /// SwitchBot
  switchBot,

  /// 手動入力
  manual,
}

/// IoTセンサーから取得した環境ログデータモデル
class SensorLog {
  /// ログの一意識別子（UUID v4）
  final String id;

  /// 紐付け先の植物ID（植物に紐付けない場合は null）
  final String? plantId;

  /// データ取得元
  final SensorSource source;

  /// デバイスID
  final String deviceId;

  /// デバイス名
  final String deviceName;

  /// 温度（℃）。センサーが対応していない場合は null
  final double? temperature;

  /// 湿度（%）。センサーが対応していない場合は null
  final double? humidity;

  /// センサー計測時刻
  final DateTime recordedAt;

  /// DB 登録時刻
  final DateTime createdAt;

  const SensorLog({
    required this.id,
    this.plantId,
    required this.source,
    required this.deviceId,
    required this.deviceName,
    this.temperature,
    this.humidity,
    required this.recordedAt,
    required this.createdAt,
  });

  /// DB へ保存する Map に変換する。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plantId': plantId,
      'source': source.name,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'temperature': temperature,
      'humidity': humidity,
      'recordedAt': recordedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// DB から取得した Map を SensorLog に変換する。
  factory SensorLog.fromMap(Map<String, dynamic> map) {
    return SensorLog(
      id: map['id'] as String,
      plantId: map['plantId'] as String?,
      source: SensorSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => SensorSource.manual,
      ),
      deviceId: map['deviceId'] as String,
      deviceName: map['deviceName'] as String,
      temperature: map['temperature'] as double?,
      humidity: map['humidity'] as double?,
      // UTC 表記（末尾 Z）でも日付がずれないようローカル時刻へ揃える（Issue #338）
      recordedAt: DateTime.parse(map['recordedAt'] as String).toLocal(),
      createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
    );
  }
}
