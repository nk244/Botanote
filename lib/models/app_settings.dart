import 'sensor_device_mapping.dart';

enum ViewMode { list, card }

enum AppTheme { green, blue, purple, orange }

enum ThemePreference { system, light, dark }

enum PlantSortOrder {
  nameAsc, // 名前昇順
  nameDesc, // 名前降順
  purchaseDateDesc, // 購入日が新しい順
  purchaseDateAsc, // 購入日が古い順
  createdAtDesc, // 登録日が新しい順
  createdAtAsc, // 登録日が古い順
  custom, // ユーザー指定
  varietyAsc, // 品種名昇順
  varietyDesc, // 品種名降順
  nextWateringAsc, // 次の水やり予定が近い順（予定超過を先頭に、Issue #271）
}

class LogTypeColors {
  final int wateringBg;
  final int wateringFg;
  final int fertilizerBg;
  final int fertilizerFg;
  final int vitalizerBg;
  final int vitalizerFg;

  LogTypeColors({
    this.wateringBg = 0xFFBBDEFB, // Colors.blue.shade100
    this.wateringFg = 0xFF0D47A1, // Colors.blue.shade900
    this.fertilizerBg = 0xFFC8E6C9, // Colors.green.shade100
    this.fertilizerFg = 0xFF1B5E20, // Colors.green.shade900
    this.vitalizerBg = 0xFFFFECB3, // Colors.amber.shade100
    this.vitalizerFg = 0xFFFF6F00, // Colors.amber.shade900
  });

  Map<String, dynamic> toMap() {
    return {
      'wateringBg': wateringBg,
      'wateringFg': wateringFg,
      'fertilizerBg': fertilizerBg,
      'fertilizerFg': fertilizerFg,
      'vitalizerBg': vitalizerBg,
      'vitalizerFg': vitalizerFg,
    };
  }

  factory LogTypeColors.fromMap(Map<String, dynamic> map) {
    return LogTypeColors(
      wateringBg: map['wateringBg'] ?? 0xFFBBDEFB,
      wateringFg: map['wateringFg'] ?? 0xFF0D47A1,
      fertilizerBg: map['fertilizerBg'] ?? 0xFFC8E6C9,
      fertilizerFg: map['fertilizerFg'] ?? 0xFF1B5E20,
      vitalizerBg: map['vitalizerBg'] ?? 0xFFFFECB3,
      vitalizerFg: map['vitalizerFg'] ?? 0xFFFF6F00,
    );
  }

  LogTypeColors copyWith({
    int? wateringBg,
    int? wateringFg,
    int? fertilizerBg,
    int? fertilizerFg,
    int? vitalizerBg,
    int? vitalizerFg,
  }) {
    return LogTypeColors(
      wateringBg: wateringBg ?? this.wateringBg,
      wateringFg: wateringFg ?? this.wateringFg,
      fertilizerBg: fertilizerBg ?? this.fertilizerBg,
      fertilizerFg: fertilizerFg ?? this.fertilizerFg,
      vitalizerBg: vitalizerBg ?? this.vitalizerBg,
      vitalizerFg: vitalizerFg ?? this.vitalizerFg,
    );
  }
}

class AppSettings {
  final ViewMode viewMode;
  final AppTheme theme;
  final ThemePreference themePreference;
  final bool notificationEnabled;
  final int notificationHour;
  final int notificationMinute;
  final LogTypeColors logTypeColors;
  final PlantSortOrder plantSortOrder;
  final List<String> customSortOrder;

  /// Nature Remo APIトークン
  final String natureRemoToken;

  /// SwitchBot APIトークン
  final String switchBotToken;

  /// SwitchBot HMAC署名シークレット
  final String switchBotSecret;

  /// デバイス-植物マッピング設定
  final List<SensorDeviceMapping> sensorDeviceMappings;

  /// センサー自動取得間隔（時間）。0 = 無効
  final int sensorFetchIntervalHours;

  /// 最後にセンサーを自動取得した日時（ISO8601文字列、未取得は null）
  final String? lastSensorFetchAt;

  /// 天気連動ケアアラートの有効/無効（Issue #176）
  final bool weatherAlertsEnabled;

  /// 天気予報取得地点の緯度
  final double? weatherLatitude;

  /// 天気予報取得地点の経度
  final double? weatherLongitude;

  /// 初回起動時のオンボーディングを完了したか（Issue #277）
  final bool onboardingCompleted;

  AppSettings({
    this.viewMode = ViewMode.card,
    this.theme = AppTheme.green,
    this.themePreference = ThemePreference.system,
    this.notificationEnabled = true,
    this.notificationHour = 9,
    this.notificationMinute = 0,
    LogTypeColors? logTypeColors,
    this.plantSortOrder = PlantSortOrder.createdAtAsc,
    this.customSortOrder = const [],
    this.natureRemoToken = '',
    this.switchBotToken = '',
    this.switchBotSecret = '',
    this.sensorDeviceMappings = const [],
    this.sensorFetchIntervalHours = 0,
    this.lastSensorFetchAt,
    this.weatherAlertsEnabled = false,
    this.weatherLatitude,
    this.weatherLongitude,
    this.onboardingCompleted = false,
  }) : logTypeColors = logTypeColors ?? LogTypeColors();

  Map<String, dynamic> toMap() {
    return {
      'viewMode': viewMode.name,
      'theme': theme.name,
      'themePreference': themePreference.name,
      'notificationEnabled': notificationEnabled,
      'notificationHour': notificationHour,
      'notificationMinute': notificationMinute,
      'logTypeColors': logTypeColors.toMap(),
      'plantSortOrder': plantSortOrder.name,
      'customSortOrder': customSortOrder,
      'natureRemoToken': natureRemoToken,
      'switchBotToken': switchBotToken,
      'switchBotSecret': switchBotSecret,
      'sensorDeviceMappings': sensorDeviceMappings
          .map((m) => m.toMap())
          .toList(),
      'sensorFetchIntervalHours': sensorFetchIntervalHours,
      'lastSensorFetchAt': lastSensorFetchAt,
      'weatherAlertsEnabled': weatherAlertsEnabled,
      'weatherLatitude': weatherLatitude,
      'weatherLongitude': weatherLongitude,
      'onboardingCompleted': onboardingCompleted,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      viewMode: ViewMode.values.firstWhere(
        (e) => e.name == map['viewMode'],
        orElse: () => ViewMode.card,
      ),
      theme: AppTheme.values.firstWhere(
        (e) => e.name == map['theme'],
        orElse: () => AppTheme.green,
      ),
      themePreference: map['themePreference'] != null
          ? ThemePreference.values.firstWhere(
              (e) => e.name == map['themePreference'],
              orElse: () => ThemePreference.system,
            )
          : ThemePreference.system,
      notificationEnabled: map['notificationEnabled'] ?? true,
      notificationHour: map['notificationHour'] ?? 9,
      notificationMinute: map['notificationMinute'] ?? 0,
      logTypeColors: map['logTypeColors'] != null
          ? LogTypeColors.fromMap(map['logTypeColors'])
          : LogTypeColors(),
      plantSortOrder: PlantSortOrder.values.firstWhere(
        (e) => e.name == map['plantSortOrder'],
        orElse: () => PlantSortOrder.createdAtAsc,
      ),
      customSortOrder: map['customSortOrder'] != null
          ? List<String>.from(map['customSortOrder'])
          : [],
      natureRemoToken: map['natureRemoToken'] as String? ?? '',
      switchBotToken: map['switchBotToken'] as String? ?? '',
      switchBotSecret: map['switchBotSecret'] as String? ?? '',
      sensorDeviceMappings:
          (map['sensorDeviceMappings'] as List<dynamic>? ?? [])
              .map(
                (m) => SensorDeviceMapping.fromMap(
                  Map<String, dynamic>.from(m as Map),
                ),
              )
              .toList(),
      sensorFetchIntervalHours: map['sensorFetchIntervalHours'] as int? ?? 0,
      lastSensorFetchAt: map['lastSensorFetchAt'] as String?,
      weatherAlertsEnabled: map['weatherAlertsEnabled'] as bool? ?? false,
      weatherLatitude: (map['weatherLatitude'] as num?)?.toDouble(),
      weatherLongitude: (map['weatherLongitude'] as num?)?.toDouble(),
      onboardingCompleted: map['onboardingCompleted'] as bool? ?? false,
    );
  }

  AppSettings copyWith({
    ViewMode? viewMode,
    AppTheme? theme,
    ThemePreference? themePreference,
    bool? notificationEnabled,
    int? notificationHour,
    int? notificationMinute,
    LogTypeColors? logTypeColors,
    PlantSortOrder? plantSortOrder,
    List<String>? customSortOrder,
    String? natureRemoToken,
    String? switchBotToken,
    String? switchBotSecret,
    List<SensorDeviceMapping>? sensorDeviceMappings,
    int? sensorFetchIntervalHours,
    Object? lastSensorFetchAt = _sentinel,
    bool? weatherAlertsEnabled,
    Object? weatherLatitude = _sentinel,
    Object? weatherLongitude = _sentinel,
    bool? onboardingCompleted,
  }) {
    return AppSettings(
      viewMode: viewMode ?? this.viewMode,
      theme: theme ?? this.theme,
      themePreference: themePreference ?? this.themePreference,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationMinute: notificationMinute ?? this.notificationMinute,
      logTypeColors: logTypeColors ?? this.logTypeColors,
      plantSortOrder: plantSortOrder ?? this.plantSortOrder,
      customSortOrder: customSortOrder ?? this.customSortOrder,
      natureRemoToken: natureRemoToken ?? this.natureRemoToken,
      switchBotToken: switchBotToken ?? this.switchBotToken,
      switchBotSecret: switchBotSecret ?? this.switchBotSecret,
      sensorDeviceMappings: sensorDeviceMappings ?? this.sensorDeviceMappings,
      sensorFetchIntervalHours:
          sensorFetchIntervalHours ?? this.sensorFetchIntervalHours,
      lastSensorFetchAt: lastSensorFetchAt == _sentinel
          ? this.lastSensorFetchAt
          : lastSensorFetchAt as String?,
      weatherAlertsEnabled: weatherAlertsEnabled ?? this.weatherAlertsEnabled,
      weatherLatitude: weatherLatitude == _sentinel
          ? this.weatherLatitude
          : weatherLatitude as double?,
      weatherLongitude: weatherLongitude == _sentinel
          ? this.weatherLongitude
          : weatherLongitude as double?,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}

/// sentinel: copyWith で lastSensorFetchAt を null クリアするために使用
const Object _sentinel = Object();
