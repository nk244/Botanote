import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/sensor_device_mapping.dart';
import '../models/sensor_log.dart';
import '../services/database_service.dart';
import '../services/iot_service.dart';

/// センサーログの状態管理を担う Provider。
///
/// [IotService] でセンサーデータを取得し、[DatabaseService] に永続化する。
class SensorLogProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final IotService _iot = IotService();

  List<SensorLog> _logs = [];
  bool _isLoading = false;

  List<SensorLog> get logs => _logs;
  bool get isLoading => _isLoading;

  /// deviceId をキーに、そのデバイスの最新ログ1件を返すマップ。
  ///
  /// _logs は recordedAt DESC 順なので先頭の1件が最新になる。
  Map<String, SensorLog> get latestLogPerDevice {
    final result = <String, SensorLog>{};
    for (final log in _logs) {
      result.putIfAbsent(log.deviceId, () => log);
    }
    return result;
  }

  /// DB からすべてのセンサーログを読み込む。
  Future<void> loadLogs() async {
    _isLoading = true;
    notifyListeners();
    try {
      _logs = await _db.getAllSensorLogs();
    } catch (e) {
      debugPrint('センサーログ読み込みエラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Nature Remo からセンサーデータを取得して返す。
  ///
  /// DBへの保存は行わない（取得のみ）。
  /// エラー時は例外をそのままスローする。
  Future<List<SensorData>> fetchNatureRemoData(String token) async {
    return _iot.fetchNatureRemoData(token);
  }

  /// SwitchBot からセンサーデータを取得して返す。
  ///
  /// DBへの保存は行わない（取得のみ）。
  /// エラー時は例外をそのままスローする。
  Future<List<SensorData>> fetchSwitchBotData(
    String token,
    String secret,
  ) async {
    return _iot.fetchSwitchBotData(token, secret);
  }

  /// センサーデータをDBに保存する。
  ///
  /// [source] はデータ取得元の種別。[plantId] は紐付ける植物のID（省略可）。
  Future<void> saveSensorLog({
    required SensorData data,
    required SensorSource source,
    String? plantId,
  }) async {
    final now = DateTime.now();
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
    await loadLogs();
  }

  /// 指定植物のセンサーログを取得して返す（DB から直接クエリ）。
  Future<List<SensorLog>> getLogsForPlant(String plantId) async {
    return _db.getSensorLogsByPlant(plantId);
  }

  /// 指定IDのセンサーログを削除する。
  Future<void> deleteSensorLog(String id) async {
    try {
      await _db.deleteSensorLog(id);
      await loadLogs();
    } catch (e) {
      debugPrint('センサーログ削除エラー: $e');
      rethrow;
    }
  }

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
          orElse: () => throw StateError(
              'デバイスが見つかりません: ${mapping.deviceName}'),
        );

        // 紐づく植物ごとにセンサーログを保存（loadLogs は後でまとめて実行）
        for (final plantId in mapping.plantIds) {
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

    if (savedCount > 0) {
      await loadLogs();
    }
    return savedCount;
  }
}
