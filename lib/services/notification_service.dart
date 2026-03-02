import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

/// 水やり予定をチェックするためのコールバック型
typedef HasWateringScheduleCallback = Future<bool> Function();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _dailyWateringNotificationId = 1;

  bool _initialized = false;
  /// 水やり予定チェック用のコールバック
  HasWateringScheduleCallback? _hasWateringScheduleCallback;

  /// 初期化。main() で await して呼ぶ。
  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    tz.initializeTimeZones();
    // デバイスのタイムゾーンを取得してtzに設定（未設定だとUTCになる）
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
      debugPrint('NotificationService: timezone set to ${tzInfo.identifier}');
    } catch (e) {
      debugPrint('NotificationService: failed to get timezone, using UTC: $e');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// 水やり予定チェック用のコールバックを設定する
  /// SettingsProvider から呼ぶ
  void setWateringScheduleCallback(HasWateringScheduleCallback callback) {
    _hasWateringScheduleCallback = callback;
  }

  /// 通知パーミッションをリクエストする。
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    // Android 13+
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      // 通知権限（Android 13+）
      final granted = await androidImpl.requestNotificationsPermission();
      // Exact alarm権限（Android 12+で正確な時刻指定に必要）
      await androidImpl.requestExactAlarmsPermission();
      return granted ?? false;
    }

    // iOS / macOS
    final darwinImpl = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (darwinImpl != null) {
      final granted = await darwinImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// 毎日 [hour]:[minute] に水やり通知をスケジュールする。
  /// 通知時に水やり予定があるかをチェックして、ある場合のみ表示する。
  Future<void> scheduleDailyWateringReminder({
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();

    await cancelDailyWateringReminder();

    // デバイスのローカルタイムゾーンを使用
    final location = tz.local;
    final now = tz.TZDateTime.now(location);
    var scheduledDate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // 今日の指定時刻が既に過ぎていたら翌日にする
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'watering_reminder',
      '水やりリマインダー',
      channelDescription: '水やりが必要な植物をお知らせします',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'watering',
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // exact alarm権限がある場合はexactAllowWhileIdle、ない場合はinexactにフォールバック
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.inexact;
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final hasExact = await androidImpl.canScheduleExactNotifications();
      if (hasExact ?? false) {
        scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    }

    await _plugin.zonedSchedule(
      id: _dailyWateringNotificationId,
      title: '💧 水やりの時間です',
      body: '水やりが必要な植物を確認しましょう',
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time, // 毎日繰り返し
    );

    debugPrint(
        'NotificationService: scheduled daily at $hour:${minute.toString().padLeft(2, '0')} (mode: $scheduleMode)');
  }

  /// 水やり予定があるかをチェックする
  /// SettingsProviderから通知有効化時に呼ばれ、予定がない場合は通知をキャンセル
  Future<bool> checkHasWateringScheduled() async {
    if (_hasWateringScheduleCallback == null) {
      // コールバックが設定されていないなら、予定があると仮定して通知を続行
      debugPrint('NotificationService: No callback set, assuming watering scheduled');
      return true;
    }
    final hasSchedule = await _hasWateringScheduleCallback!();
    debugPrint('NotificationService: watering scheduled today = $hasSchedule');
    return hasSchedule;
  }

  /// 水やり通知をキャンセルする。
  Future<void> cancelDailyWateringReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _dailyWateringNotificationId);
  }
}
