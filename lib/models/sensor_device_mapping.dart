import 'sensor_log.dart';

/// センサーデバイスと植物の紐づけ設定
class SensorDeviceMapping {
  /// デバイスID
  final String deviceId;

  /// デバイス名
  final String deviceName;

  /// データ取得元
  final SensorSource source;

  /// 紐づける植物IDリスト
  final List<String> plantIds;

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
