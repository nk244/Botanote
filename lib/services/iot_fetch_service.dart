import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/sensor_device_mapping.dart';
import '../models/sensor_log.dart';
import 'database_service.dart';
import 'iot_service.dart';

/// センサーデバイス-植物マッピング設定を使って一括取得・保存する処理を担うサービス。
///
/// [SensorLogProvider] とバックグラウンドタスクの両方から共通利用できるよう、
/// Provider（状態管理層）に依存せず [DatabaseService] と [IotService] のみで完結させる。
class IotFetchService {
  final DatabaseService _db = DatabaseService();
  final IotService _iot = IotService();

  /// マッピング設定を使って全デバイスのセンサーデータを取得し、
  /// 紐づく植物すべてにセンサーログを保存する。
  ///
  /// [settings] に API トークンと [SensorDeviceMapping] リストを含める。
  /// 戻り値: 保存に成功したログ件数。
  Future<int> fetchAndSaveWithMappings(AppSettings settings) async {
    final mappings = settings.sensorDeviceMappings;
    if (mappings.isEmpty) return 0;

    int savedCount = 0;

    // ソース別にデバイス一覧を取得（API呼び出しを最小化）
    List<SensorData>? natureRemoDevices;
    List<SensorData>? switchBotDevices;

    // locationId が設定されたマッピングを解決するため、全植物を1回だけ取得
    final allPlants = await _db.getAllPlants();

    for (final mapping in mappings) {
      try {
        final List<SensorData> devices;
        if (mapping.source == SensorSource.natureRemo) {
          natureRemoDevices ??=
              await _iot.fetchNatureRemoData(settings.natureRemoToken);
          devices = natureRemoDevices;
        } else {
          switchBotDevices ??= await _iot.fetchSwitchBotData(
              settings.switchBotToken, settings.switchBotSecret);
          devices = switchBotDevices;
        }

        // マッピングのデバイスIDに一致するデバイスを探す
        final device = devices.firstWhere(
          (d) => d.deviceId == mapping.deviceId,
          orElse: () =>
              throw StateError('デバイスが見つかりません: ${mapping.deviceName}'),
        );

        // locationId が設定されている場合はその場所に属する植物全員に自動追従、
        // 未設定の場合は個別に選択された plantIds を使用する
        final targetPlantIds = mapping.locationId != null
            ? allPlants
                .where((p) => p.locationId == mapping.locationId)
                .map((p) => p.id)
            : mapping.plantIds;

        // 紐づく植物ごとにセンサーログを保存
        for (final plantId in targetPlantIds) {
          final now = DateTime.now();
          final log = SensorLog(
            id: const Uuid().v4(),
            plantId: plantId,
            source: mapping.source,
            deviceId: device.deviceId,
            deviceName: device.deviceName,
            temperature: device.temperature,
            humidity: device.humidity,
            recordedAt: now,
            createdAt: now,
          );
          await _db.insertSensorLog(log);
          savedCount++;
        }
      } catch (e) {
        // 1デバイスのエラーで全体を止めない
        debugPrint('マッピング取得エラー (${mapping.deviceName}): $e');
      }
    }

    return savedCount;
  }
}
