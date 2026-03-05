import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';
import 'providers/plant_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/note_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_themes.dart';
import 'models/app_settings.dart';
import 'services/notification_service.dart';

/// バックグラウンドタスクのタスク名
const _kSmartNotifyTask = 'smart_notify_task';

/// workmanager から呼び出されるバックグラウンドエントリポイント。
/// 別Isolateで動くため、Providerは使用不可。DatabaseServiceを直接使う。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == _kSmartNotifyTask ||
        taskName == Workmanager.iOSBackgroundTask) {
      // 翌日の水やり予定をDBから確認し、予定があれば翌日に通知をスケジュール
      await NotificationService.scheduleSmartWateringReminder();
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');

  if (!kIsWeb) {
    // 通知サービスを初期化
    await NotificationService().initialize();

    // workmanager を初期化し、毎日バックグラウンドで翌日の予定チェックを行う
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _kSmartNotifyTask,
      _kSmartNotifyTask,
      // 毎日実行（WorkManagerの最短は15分だが、ユーザーのバッテリー節約を優先しOSが最適化する）
      frequency: const Duration(hours: 24),
      // 制約: ネットワーク不要・バッテリー節約モードでも実行
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
      ),
      // 既存タスクがあれば上書き
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlantProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          // ThemePreference → Flutter ThemeMode に変換
          ThemeMode mode;
          switch (settingsProvider.themePreference) {
            case ThemePreference.light:
              mode = ThemeMode.light;
              break;
            case ThemePreference.dark:
              mode = ThemeMode.dark;
              break;
            case ThemePreference.system:
              mode = ThemeMode.system;
              break;
          }

          return MaterialApp(
            title: 'Botanote',
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ja')],
            locale: const Locale('ja'),
            theme: AppThemes.getLightTheme(settingsProvider.theme),
            darkTheme: AppThemes.getDarkTheme(settingsProvider.theme),
            themeMode: mode,
            home: const HomeScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
