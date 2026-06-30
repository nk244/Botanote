import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
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
    });
  }

  /// 自動取得間隔が経過していた場合にセンサーデータを一括取得して保存する
  Future<void> _checkAndAutoFetch() async {
    final settingsProvider = context.read<SettingsProvider>();
    final settings = settingsProvider.settings;

    final intervalHours = settings.sensorFetchIntervalHours;
    // 間隔が0（無効）またはマッピングが空の場合はスキップ
    if (intervalHours <= 0 || settings.sensorDeviceMappings.isEmpty) return;

    // 前回取得時刻を確認して間隔が経過しているか判定
    final lastFetchStr = settings.lastSensorFetchAt;
    if (lastFetchStr != null) {
      final lastFetch = DateTime.tryParse(lastFetchStr);
      if (lastFetch != null) {
        final elapsed = DateTime.now().difference(lastFetch);
        if (elapsed.inHours < intervalHours) return;
      }
    }

    // 間隔が経過しているので取得を実行する
    try {
      final sensorProvider = context.read<SensorLogProvider>();
      final count = await sensorProvider.fetchAndSaveWithMappings(settings);
      // 最終取得日時を更新
      await settingsProvider.updateLastSensorFetchAt(DateTime.now());

      if (!mounted || count == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('センサーデータを自動取得しました（$count件）')),
      );
    } catch (_) {
      // 起動時の自動取得エラーはサイレントに無視する
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
