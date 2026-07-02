import 'package:flutter/foundation.dart' show ChangeNotifier;
import '../models/app_settings.dart';
import '../models/sensor_device_mapping.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';

/// アプリ設定を管理する Provider。
///
/// [SettingsService] を介して SharedPreferences に永続化する。
class SettingsProvider with ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  AppSettings _settings = AppSettings();

  AppSettings get settings => _settings;
  ViewMode get viewMode => _settings.viewMode;
  AppTheme get theme => _settings.theme;
  ThemePreference get themePreference => _settings.themePreference;
  bool get notificationEnabled => _settings.notificationEnabled;
  LogTypeColors get logTypeColors => _settings.logTypeColors;
  PlantSortOrder get plantSortOrder => _settings.plantSortOrder;
  List<String> get customSortOrder => _settings.customSortOrder;

  /// 保存済み設定を読み込む。
  /// 通知が有効な場合はアプリ起動時に再スケジュールする。
  Future<void> loadSettings() async {
    _settings = await _settingsService.loadSettings();
    notifyListeners();
    // アプリ起動時に通知設定が有効ならスマートスケジュールを実行する
    // （OSが再起動するとスケジュール済み通知が消えるため）
    if (_settings.notificationEnabled) {
      await NotificationService.scheduleSmartWateringReminder(
        hour: _settings.notificationHour,
        minute: _settings.notificationMinute,
      );
    }
  }

  /// 表示モードを変更する。
  Future<void> setViewMode(ViewMode mode) async {
    _settings = _settings.copyWith(viewMode: mode);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// アプリテーマを変更する。
  Future<void> setTheme(AppTheme theme) async {
    _settings = _settings.copyWith(theme: theme);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// ライト/ダーク/システムのテーマ設定を変更する。
  Future<void> setThemePreference(ThemePreference pref) async {
    _settings = _settings.copyWith(themePreference: pref);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// 通知時刻を変更し、通知が有効なら再スケジュールする。
  Future<void> setNotificationTime(int hour, int minute) async {
    _settings = _settings.copyWith(
      notificationHour: hour,
      notificationMinute: minute,
    );
    await _settingsService.saveSettings(_settings);
    notifyListeners();
    // 通知が有効なら再スケジュール
    if (_settings.notificationEnabled) {
      await NotificationService.scheduleSmartWateringReminder(
        hour: hour,
        minute: minute,
      );
    }
  }

  /// 通知の有効/無効を切り替える。
  /// 有効化時はパーミッションを確認し、完全に拒否された場合は設定を戻す。
  Future<void> setNotificationEnabled(bool enabled) async {
    _settings = _settings.copyWith(notificationEnabled: enabled);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
    if (enabled) {
      // パーミッション確認してからスケジュール
      final granted = await NotificationService().requestPermission();
      if (granted) {
        await NotificationService.scheduleSmartWateringReminder(
          hour: _settings.notificationHour,
          minute: _settings.notificationMinute,
        );
      } else {
        // パーミッション拒否時は設定を元に戻す
        _settings = _settings.copyWith(notificationEnabled: false);
        await _settingsService.saveSettings(_settings);
        notifyListeners();
      }
    } else {
      await NotificationService().cancelDailyWateringReminder();
    }
  }

  /// ログ種別の表示色を変更する。
  Future<void> setLogTypeColors(LogTypeColors colors) async {
    _settings = _settings.copyWith(logTypeColors: colors);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// 植物の並び順を変更する。
  Future<void> setPlantSortOrder(PlantSortOrder order) async {
    _settings = _settings.copyWith(plantSortOrder: order);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// カスタム並び順（ユーザー指定）を変更する。
  Future<void> setCustomSortOrder(List<String> order) async {
    _settings = _settings.copyWith(customSortOrder: order);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// IoT連携のAPIキーを更新する。
  Future<void> updateIotSettings({
    required String natureRemoToken,
    required String switchBotToken,
    required String switchBotSecret,
  }) async {
    _settings = _settings.copyWith(
      natureRemoToken: natureRemoToken,
      switchBotToken: switchBotToken,
      switchBotSecret: switchBotSecret,
    );
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// デバイス-植物マッピングを更新する。
  Future<void> updateDeviceMappings(
      List<SensorDeviceMapping> mappings) async {
    _settings = _settings.copyWith(sensorDeviceMappings: mappings);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// センサー自動取得間隔（時間）を更新する。0 は無効。
  Future<void> updateSensorFetchInterval(int hours) async {
    _settings = _settings.copyWith(sensorFetchIntervalHours: hours);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// センサー最終自動取得日時を更新する。null でクリアする。
  Future<void> updateLastSensorFetchAt(DateTime? time) async {
    _settings = _settings.copyWith(
      lastSensorFetchAt: time?.toIso8601String(),
    );
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  /// AI診断・同定機能用のAPIキーを更新する（Issue #177/#178）。
  Future<void> updateAiApiKey(String apiKey) async {
    _settings = _settings.copyWith(aiApiKey: apiKey);
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

}
