import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../providers/location_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/location_edit_dialog.dart';
import 'location_detail_screen.dart';

/// 置き場所（Location）の一覧・追加・編集・削除画面（Issue #180）。
class LocationListScreen extends StatelessWidget {
  const LocationListScreen({super.key});

  /// 置き場所の追加・編集ダイアログを表示して保存する。
  ///
  /// ダイアログと TextEditingController の所有権は [LocationEditDialog] にある
  /// （Issue #341 で植物追加画面と共通化）。
  Future<void> _showEditDialog(
    BuildContext context, {
    Location? location,
  }) async {
    final result = await LocationEditDialog.show(
      context,
      title: location == null ? '置き場所を追加' : '置き場所を編集',
      initialName: location?.name ?? '',
      initialIsOutdoor: location?.isOutdoor ?? false,
    );
    if (result == null || !context.mounted) return;

    final locationProvider = context.read<LocationProvider>();
    if (location == null) {
      await locationProvider.addLocation(result.name, result.isOutdoor);
    } else {
      await locationProvider.updateLocation(
        location.copyWith(name: result.name, isOutdoor: result.isOutdoor),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Location location) async {
    final locationProvider = context.read<LocationProvider>();
    final plantProvider = context.read<PlantProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text(
          '「${location.name}」を削除してもよろしいですか？\nこの場所が設定されている植物は「未設定」に戻ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await locationProvider.deleteLocation(location.id);
      await plantProvider.loadPlants();
      await settingsProvider.clearLocationFromSensorMappings(location.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('置き場所管理')),
      body: Consumer<LocationProvider>(
        builder: (context, locationProvider, _) {
          if (locationProvider.isLoading &&
              locationProvider.locations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (locationProvider.locations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '置き場所が登録されていません',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '右下のボタンから「リビング」「ベランダ」等を登録できます',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }

          // 置き場所ごとの鉢数を一覧でも把握できるようにする（Issue #336）。
          // 植物一覧のフィルタチップには件数が出ているのに、置き場所を
          // 管理するこの画面には出ていなかった。
          final plants = context.watch<PlantProvider>().plants;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: locationProvider.locations.length,
            itemBuilder: (context, index) {
              final location = locationProvider.locations[index];
              final plantCount = plants
                  .where((p) => p.locationId == location.id)
                  .length;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ListTile(
                  leading: Icon(location.isOutdoor ? Icons.deck : Icons.home),
                  title: Text(location.name),
                  subtitle: Text(
                    '${location.isOutdoor ? '屋外' : '屋内'}・$plantCount鉢',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocationDetailScreen(location: location),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditDialog(context, location: location);
                      } else if (value == 'delete') {
                        _confirmDelete(context, location);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('編集')),
                      PopupMenuItem(value: 'delete', child: Text('削除')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '置き場所を追加',
        onPressed: () => _showEditDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
