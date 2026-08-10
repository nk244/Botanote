import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/log_entry.dart';
import 'database_service.dart';
import 'weather_service.dart';

/// 通知アクション「水やり完了」をバックグラウンドIsolateで受け取るエントリポイント。
///
/// アプリが起動していない状態でも呼ばれるため、トップレベル関数かつ
/// `@pragma('vm:entry-point')` が必須（Issue #276）。
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId != NotificationService.wateringDoneActionId) return;
  // await できない同期エントリポイントのため、Future はそのまま流す
  NotificationService.recordWateringForDuePlants();
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _dailyWateringNotificationId = 1;
  static const int _weatherAlertNotificationId = 2;

  /// 通知アクション「水やり完了」の識別子（Issue #276）。
  static const String wateringDoneActionId = 'watering_done';

  bool _initialized = false;

  /// 初期化。main() で await して呼ぶ。
  Future<void> initialize() async {
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
        AndroidInitializationSettings('@drawable/ic_notification');
    // iOS/macOS では通知カテゴリにアクションを登録する（Issue #276）
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          'watering',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              wateringDoneActionId,
              '水やり完了',
            ),
          ],
        ),
      ],
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _initialized = true;
  }

  /// フォアグラウンド（アプリ起動中）で通知アクションを受け取ったときの処理。
  static void _handleNotificationResponse(NotificationResponse response) {
    if (response.actionId != wateringDoneActionId) return;
    recordWateringForDuePlants();
  }

  /// 今日時点で水やり予定を迎えている（予定超過を含む）植物すべてに、
  /// 今日の日付で水やりログを記録する（Issue #276）。
  ///
  /// 同じ日に既に水やりログがある植物は二重記録しない。
  /// 通知アクションから呼ばれ、アプリ未起動のバックグラウンドIsolateでも動作する。
  static Future<void> recordWateringForDuePlants() async {
    try {
      final db = DatabaseService();
      final now = DateTime.now();
      final duePlants = await db.getPlantsDueOn(now);
      if (duePlants.isEmpty) return;

      const uuid = Uuid();
      for (final plant in duePlants) {
        final existing =
            await db.getLogsByPlantAndType(plant.id, LogType.watering);
        final alreadyLogged = existing.any((log) =>
            log.date.year == now.year &&
            log.date.month == now.month &&
            log.date.day == now.day);
        if (alreadyLogged) continue;

        await db.insertLog(LogEntry(
          id: uuid.v4(),
          plantId: plant.id,
          type: LogType.watering,
          date: now,
          createdAt: now,
          updatedAt: now,
        ));
      }

      debugPrint(
          'NotificationService: recorded watering from notification action '
          '(${duePlants.length} plants checked)');

      // 記録内容が変わったので次回のリマインダーを組み直す
      await scheduleSmartWateringReminder();
    } catch (e) {
      debugPrint('NotificationService: watering action failed: $e');
    }
  }

  /// 通知パーミッションをリクエストする。
  Future<bool> requestPermission() async {
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

  /// OS レベルで通知が許可されているかを返す（Android 13+ の POST_NOTIFICATIONS）。
  ///
  /// 判定できないプラットフォーム（iOS/macOS 等）や不明な場合は true を返し、
  /// 権限リクエストの要否判定を過剰に発火させない。
  Future<bool> areNotificationsEnabled() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final enabled = await androidImpl.areNotificationsEnabled();
      return enabled ?? true;
    }
    return true;
  }

  /// 水やりリマインダーの本文を組み立てる。
  ///
  /// 対象植物が分かっている場合は名前を載せる。多い場合は先頭の名前＋残り件数に
  /// 丸めて、通知本文が長くなりすぎないようにする（Issue #245）。
  /// [duePlantNames] が空の場合は従来どおりの汎用文言を返す。
  static String buildWateringReminderBody(List<String> duePlantNames) {
    if (duePlantNames.isEmpty) return '水やりが必要な植物を確認しましょう';
    if (duePlantNames.length == 1) {
      return '${duePlantNames.first}に水やりをしましょう';
    }
    if (duePlantNames.length == 2) {
      return '${duePlantNames[0]}と${duePlantNames[1]}に水やりをしましょう';
    }
    return '${duePlantNames.first} ほか${duePlantNames.length - 1}件に水やりをしましょう';
  }

  /// 翌日の水やり予定をDBから直接確認し、予定がある場合のみ通知を1件登録する。
  ///
  /// バックグラウンドIsolateとアプリ起動時の両方から呼び出す共通ロジック。
  /// [hour] と [minute] が null の場合は SharedPreferences から読み込む。
  static Future<void> scheduleSmartWateringReminder({
    int? hour,
    int? minute,
  }) async {
    // 通知時刻が未指定の場合は SharedPreferences から取得
    int notifHour = hour ?? 9;
    int notifMinute = minute ?? 0;
    bool notifEnabled = true;
    if (hour == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final settingsJson = prefs.getString('app_settings');
        if (settingsJson != null) {
          final map = json.decode(settingsJson) as Map<String, dynamic>;
          notifEnabled = map['notificationEnabled'] as bool? ?? true;
          notifHour = map['notificationHour'] as int? ?? 9;
          notifMinute = map['notificationMinute'] as int? ?? 0;
        }
      } catch (e) {
        debugPrint('NotificationService: failed to read prefs: $e');
      }
    }

    if (!notifEnabled) {
      debugPrint('NotificationService: notifications disabled, skipping smart schedule');
      return;
    }

    // 通知対象日を決める（Issue #281）。
    // 当日の通知時刻がまだ来ていなければ「今日」を対象にする。
    // 「翌日だけ」を見ていると、予定日当日にスケジューリングが走った場合に
    // その日の通知が登録されず、通知が丸1日遅れてしまう。
    final now = DateTime.now();
    final todayNotifyTime =
        DateTime(now.year, now.month, now.day, notifHour, notifMinute);
    final bool targetIsToday = now.isBefore(todayNotifyTime);
    final targetDate =
        targetIsToday ? now : now.add(const Duration(days: 1));

    bool hasDuePlants = false;
    // 通知本文に載せる対象植物名（DBエラー時は空のまま汎用文言にフォールバック）
    var duePlantNames = <String>[];
    try {
      final db = DatabaseService();
      // getPlantsDueOn は「予定日が対象日以前」の植物を返すため、予定超過分も含まれる
      final duePlants = await db.getPlantsDueOn(targetDate);
      hasDuePlants = duePlants.isNotEmpty;
      duePlantNames = duePlants.map((p) => p.name).toList();
      debugPrint('NotificationService: plants due on '
          '${targetIsToday ? "today" : "tomorrow"} = ${duePlants.length}');
    } catch (e) {
      debugPrint('NotificationService: DB check failed, scheduling anyway: $e');
      // DBエラー時は安全側として通知を登録する
      hasDuePlants = true;
    }

    final plugin = FlutterLocalNotificationsPlugin();

    // タイムゾーン初期化
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {}

    // 初期化（バックグラウンドIsolate用）
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
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
    await plugin.initialize(settings: initSettings);

    // 既存の通知をキャンセル
    await plugin.cancel(id: _dailyWateringNotificationId);

    if (!hasDuePlants) {
      debugPrint(
          'NotificationService: no plants due on target day, notification cancelled');
      return;
    }

    // 対象日の指定時刻に1回限りの通知を登録
    final location = tz.local;
    final tzNow = tz.TZDateTime.now(location);
    final scheduledDate = tz.TZDateTime(
      location,
      tzNow.year,
      tzNow.month,
      targetIsToday ? tzNow.day : tzNow.day + 1,
      notifHour,
      notifMinute,
    );

    const androidDetails = AndroidNotificationDetails(
      'watering_reminder',
      '水やりリマインダー',
      channelDescription: '水やりが必要な植物をお知らせします',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      // 通知から直接その日の水やりを記録できるようにする（Issue #276）
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          wateringDoneActionId,
          '水やり完了',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'watering',
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // exact alarm権限チェック
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.inexact;
    final androidImpl = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final hasExact = await androidImpl.canScheduleExactNotifications();
      if (hasExact ?? false) {
        scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    }

    // matchDateTimeComponents を指定しない = 1回限りの通知
    await plugin.zonedSchedule(
      id: _dailyWateringNotificationId,
      title: '💧 水やりの時間です',
      body: buildWateringReminderBody(duePlantNames),
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
    );

    debugPrint(
        'NotificationService: smart scheduled for tomorrow at $notifHour:${notifMinute.toString().padLeft(2, '0')}');
  }

  /// 水やり通知をキャンセルする。
  Future<void> cancelDailyWateringReminder() async {
    await _plugin.cancel(id: _dailyWateringNotificationId);
  }

  /// 翌日の天気予報を確認し、屋外植物のケアアラートが必要な場合に通知を1件登録する
  /// （Issue #176）。バックグラウンドIsolateとアプリ起動時の両方から呼び出す。
  ///
  /// 引数が null の場合は SharedPreferences から読み込む。
  static Future<void> scheduleWeatherAlert({
    bool? enabled,
    double? latitude,
    double? longitude,
    int? hour,
    int? minute,
  }) async {
    bool weatherEnabled = enabled ?? false;
    double? lat = latitude;
    double? lon = longitude;
    int notifHour = hour ?? 9;
    int notifMinute = minute ?? 0;

    if (enabled == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final settingsJson = prefs.getString('app_settings');
        if (settingsJson != null) {
          final map = json.decode(settingsJson) as Map<String, dynamic>;
          weatherEnabled = map['weatherAlertsEnabled'] as bool? ?? false;
          lat = (map['weatherLatitude'] as num?)?.toDouble();
          lon = (map['weatherLongitude'] as num?)?.toDouble();
          notifHour = map['notificationHour'] as int? ?? 9;
          notifMinute = map['notificationMinute'] as int? ?? 0;
        }
      } catch (e) {
        debugPrint('NotificationService: failed to read weather prefs: $e');
      }
    }

    final plugin = FlutterLocalNotificationsPlugin();
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {}

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
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
    await plugin.initialize(settings: initSettings);

    // 無効・座標未設定の場合は既存通知をキャンセルして終了
    if (!weatherEnabled || lat == null || lon == null) {
      await plugin.cancel(id: _weatherAlertNotificationId);
      return;
    }

    // 屋外植物が1件もない場合はキャンセルして終了
    List<String> alerts = [];
    try {
      final db = DatabaseService();
      final plants = await db.getAllPlants();
      final hasOutdoorPlants = plants.any((p) => p.isOutdoor);
      if (!hasOutdoorPlants) {
        await plugin.cancel(id: _weatherAlertNotificationId);
        return;
      }

      alerts = await WeatherService.checkTomorrowAlerts(
        latitude: lat,
        longitude: lon,
      );
    } catch (e) {
      debugPrint('NotificationService: weather alert check failed: $e');
      // 通信・DBエラー時は通知を変更せず既存の状態を維持する
      return;
    }

    if (alerts.isEmpty) {
      await plugin.cancel(id: _weatherAlertNotificationId);
      return;
    }

    final location = tz.local;
    final now = tz.TZDateTime.now(location);
    final scheduledDate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      notifHour,
      notifMinute,
    );

    const androidDetails = AndroidNotificationDetails(
      'weather_alert',
      '天気連動ケアアラート',
      channelDescription: '屋外植物のケアに関わる天気の注意喚起を通知します',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'weather_alert',
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    AndroidScheduleMode scheduleMode = AndroidScheduleMode.inexact;
    final androidImpl = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final hasExact = await androidImpl.canScheduleExactNotifications();
      if (hasExact ?? false) {
        scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    }

    await plugin.zonedSchedule(
      id: _weatherAlertNotificationId,
      title: '🌤 明日の天気に注意',
      body: alerts.join(' '),
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
    );

    debugPrint('NotificationService: weather alert scheduled (${alerts.length}件)');
  }

  /// 天気連動ケアアラート通知をキャンセルする。
  Future<void> cancelWeatherAlert() async {
    await _plugin.cancel(id: _weatherAlertNotificationId);
  }
}
