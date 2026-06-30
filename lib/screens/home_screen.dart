import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sensor_log_provider.dart';
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
    // NotificationService のコールバックを設定（水やり予定チェック用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plantProvider = context.read<PlantProvider>();
      final settingsProvider = context.read<SettingsProvider>();
      settingsProvider.setupNotificationCallback(plantProvider);
    });
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
          if (!mounted) return;
          await context.read<PlantProvider>().loadPlants();
          // ノートタブ（index=2）切替時はノートも再読み込みする
          if (index == 2) {
            if (!mounted) return;
            await context.read<NoteProvider>().loadNotes();
          }
          // センサータブ（index=3）切替時はセンサーログも再読み込みする
          if (index == 3) {
            if (!mounted) return;
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
