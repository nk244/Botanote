import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
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
}
