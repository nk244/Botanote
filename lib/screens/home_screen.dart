import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/sensor_auto_fetch_service.dart';
import 'today_watering_screen.dart';
import 'plant_list_screen.dart';
import 'notes_list_screen.dart';
import 'sensor_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const TodayWateringScreen(),
    const PlantListScreen(),
    const NotesListScreen(),
    const SensorLogScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // アプリ起動時にセンサー自動取得が必要か確認する
      _checkAndAutoFetch();
      // 水やりリマインダーが有効なのに OS 通知権限が未許可の場合は権限をリクエストする
      _ensureNotificationPermission();
    });
  }

  /// 水やりリマインダーが有効なのに OS の通知権限が未許可の場合、権限をリクエストする。
  ///
  /// リマインダーは初期状態で有効だが、ユーザーが設定画面でトグルを操作しない限り
  /// 権限リクエストが発火せず、通知が一度も届かない不具合への対応（Issue #201）。
  /// 権限が付与された場合はリマインダーを再スケジュールする。
  Future<void> _ensureNotificationPermission() async {
    final settings = context.read<SettingsProvider>().settings;
    if (!settings.notificationEnabled) return;

    try {
      final service = NotificationService();
      // 既に許可済みなら何もしない（毎回ダイアログを出さない）
      if (await service.areNotificationsEnabled()) return;

      final granted = await service.requestPermission();
      if (granted) {
        await NotificationService.scheduleSmartWateringReminder(
          hour: settings.notificationHour,
          minute: settings.notificationMinute,
        );
      }
    } catch (e) {
      // 権限リクエストの失敗はサイレントに無視せずログに残す
      debugPrint('通知権限リクエストエラー: $e');
    }
  }

  /// 自動取得間隔が経過していた場合にセンサーデータを一括取得して保存する。
  ///
  /// 実際の取得・間隔判定は [SensorAutoFetchService] に委譲する
  /// （バックグラウンドタスクと共通のロジックを使用するため）。
  Future<void> _checkAndAutoFetch() async {
    final settingsProvider = context.read<SettingsProvider>();

    try {
      final count = await SensorAutoFetchService.run(settingsProvider.settings);
      if (!mounted) return;
      // SensorAutoFetchService は SharedPreferences に直接保存するため、
      // フォアグラウンドの Provider 状態にも最終取得日時等を反映させる
      await settingsProvider.loadSettings();

      if (!mounted || count == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('センサーデータを自動取得しました（$count件）')),
      );
    } catch (e) {
      // エラーはサイレントに無視せずログに残す
      debugPrint('起動時センサー自動取得エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) async {
          setState(() {
            _selectedIndex = index;
          });
          // タブ切替時にデータを再読み込みする
          if (!context.mounted) return;
          await context.read<PlantProvider>().loadPlants();
          // ノートタブ（index=2）切替時はノートも再読み込みする
          if (index == 2) {
            if (!context.mounted) return;
            await context.read<NoteProvider>().loadNotes();
          }
          // センサータブ（index=3）切替時はセンサーログも再読み込みする
          if (index == 3) {
            if (!context.mounted) return;
            await context.read<SensorLogProvider>().loadLogs();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: '水やりログ',
          ),
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco),
            label: '植物一覧',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: 'ノート',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'センサー',
          ),
        ],
      ),
    );
  }
}
