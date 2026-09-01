import 'package:flutter/foundation.dart' show debugPrint;
import 'package:workmanager/workmanager.dart';
import '../models/app_settings.dart';
import 'iot_fetch_service.dart';
import 'settings_service.dart';

/// センサーデータの自動取得（バックグラウンド定期実行）を管理するサービス。
///
/// フォアグラウンド（アプリ起動時）とバックグラウンド（Workmanagerの
/// 別Isolate）の両方から呼び出される共通ロジックを提供する。
class SensorAutoFetchService {
  /// Workmanagerに登録するバックグラウンドタスク名
  static const String taskName = 'sensor_fetch_task';

  /// 現在の設定に応じてバックグラウンド定期タスクを登録・解除する。
  ///
  /// 取得間隔が0（無効）またはデバイスマッピングが空の場合はタスクを解除する。
  static Future<void> reschedule(AppSettings settings) async {
    final enabled =
        settings.sensorFetchIntervalHours > 0 &&
        settings.sensorDeviceMappings.isNotEmpty;

    if (!enabled) {
      await Workmanager().cancelByUniqueName(taskName);
      return;
    }

    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: Duration(hours: settings.sensorFetchIntervalHours),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// センサーデータの取得を実行し、成功したら最終取得日時を更新する。
  ///
  /// [forceRun] が false の場合、前回取得からの経過時間が
  /// [AppSettings.sensorFetchIntervalHours] 未満ならスキップする
  /// （アプリ起動のたびに毎回取得しないようにするため）。
  /// バックグラウンドタスクからは間隔をWorkmanager自体が管理しているため
  /// [forceRun] を true にして呼び出す。
  ///
  /// 戻り値: 保存できたログ件数。スキップ時は 0。
  /// エラー時は [debugPrint] でログを残した上で例外を再スローする。
  static Future<int> run(AppSettings settings, {bool forceRun = false}) async {
    if (settings.sensorDeviceMappings.isEmpty) return 0;

    if (!forceRun) {
      final lastFetchStr = settings.lastSensorFetchAt;
      if (lastFetchStr != null) {
        final lastFetch = DateTime.tryParse(lastFetchStr);
        if (lastFetch != null) {
          final elapsed = DateTime.now().difference(lastFetch);
          if (elapsed.inHours < settings.sensorFetchIntervalHours) return 0;
        }
      }
    }

    try {
      final count = await IotFetchService().fetchAndSaveWithMappings(settings);
      final settingsService = SettingsService();
      await settingsService.saveSettings(
        settings.copyWith(lastSensorFetchAt: DateTime.now().toIso8601String()),
      );
      return count;
    } catch (e) {
      debugPrint('センサー自動取得エラー: $e');
      rethrow;
    }
  }
}
