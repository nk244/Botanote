import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../providers/location_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import 'location_detail_screen.dart';

/// 置き場所（Location）の一覧・追加・編集・削除画面（Issue #180）。
class LocationListScreen extends StatelessWidget {
  const LocationListScreen({super.key});

  Future<void> _showEditDialog(
    BuildContext context, {
    Location? location,
  }) async {
    final nameController = TextEditingController(text: location?.name ?? '');
    bool isOutdoor = location?.isOutdoor ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(location == null ? '置き場所を追加' : '置き場所を編集'),
          // 名前欄を自動フォーカスするとIMEのフローティングツールバーが「屋外」
          // スイッチに重なり、タップしても切り替わらなくなる（Issue #268）。
          // 自動フォーカスをやめ、内容もスクロール可能にして退避できるようにする。
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '場所名',
                    border: OutlineInputBorder(),
                    hintText: '例: リビング、ベランダ',
                  ),
                  // 保存ボタンの活性状態を即座に反映するため、入力のたびに再描画する
                  onChanged: (_) => setState(() {}),
                  // 入力確定でキーボードを閉じ、下のスイッチを操作できるようにする
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('屋外'),
                  subtitle: const Text('天気連動ケアアラートの対象になります'),
                  value: isOutdoor,
                  onChanged: (value) {
                    // スイッチ操作時にキーボードが出ていれば閉じる
                    FocusScope.of(context).unfocus();
                    setState(() => isOutdoor = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !context.mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final locationProvider = context.read<LocationProvider>();
    if (location == null) {
      await locationProvider.addLocation(name, isOutdoor);
    } else {
      await locationProvider.updateLocation(
        location.copyWith(name: name, isOutdoor: isOutdoor),
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

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: locationProvider.locations.length,
            itemBuilder: (context, index) {
              final location = locationProvider.locations[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ListTile(
                  leading: Icon(location.isOutdoor ? Icons.deck : Icons.home),
                  title: Text(location.name),
                  subtitle: Text(location.isOutdoor ? '屋外' : '屋内'),
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
