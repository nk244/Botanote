import 'sensor_log.dart';

/// センサーデバイスと植物の紐づけ設定
class SensorDeviceMapping {
  /// デバイスID
  final String deviceId;

  /// デバイス名
  final String deviceName;

  /// データ取得元
  final SensorSource source;

  /// 紐づける植物IDリスト（[locationId] が設定されている場合は無視される）
  final List<String> plantIds;

  /// 紐づける管理場所ID（設定されている場合、この場所に属する植物全員に自動追従する）
  final String? locationId;

  const SensorDeviceMapping({
    required this.deviceId,
    required this.deviceName,
    required this.source,
    required this.plantIds,
    this.locationId,
  });

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'source': source.name,
    'plantIds': plantIds,
    'locationId': locationId,
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
        locationId: map['locationId'] as String?,
      );

  /// フィールドを部分的に更新した新しい SensorDeviceMapping を返す。
  /// [locationId] を明示的に null にしたい場合は sentinel パターンを使用する。
  SensorDeviceMapping copyWith({
    List<String>? plantIds,
    Object? locationId = _sentinel,
  }) {
    return SensorDeviceMapping(
      deviceId: deviceId,
      deviceName: deviceName,
      source: source,
      plantIds: plantIds ?? this.plantIds,
      locationId: locationId == _sentinel
          ? this.locationId
          : locationId as String?,
    );
  }
}

/// copyWith で locationId を null クリアするための sentinel 値
const Object _sentinel = Object();
