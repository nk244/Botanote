import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../models/sensor_device_mapping.dart';
import '../providers/location_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/plant_picker_dialog.dart';
import 'iot_settings_screen.dart';
import 'plant_detail_screen.dart';

/// 管理場所（Location）の詳細画面。
///
/// この場所に属する植物・センサーを表示し、一括での紐づけ設定を行う。
class LocationDetailScreen extends StatelessWidget {
  const LocationDetailScreen({super.key, required this.location});

  final Location location;

  /// この場所に属する植物を一括選択するダイアログを表示する
  Future<void> _showPlantPickerDialog(BuildContext context) async {
    final plantProvider = context.read<PlantProvider>();
    final locationProvider = context.read<LocationProvider>();
    final plants = plantProvider.plants;

    if (plants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('植物が登録されていません')),
      );
      return;
    }

    // 共通ダイアログに寄せることで、並び順がアプリ設定に揃い、
    // 検索と全選択も使えるようになる（Issue #293）
    final selectedIds = await PlantPickerDialog.show(
      context,
      title: 'この場所の植物を設定',
      confirmLabel: '確定',
      initialSelectedIds: plants
          .where((p) => p.locationId == location.id)
          .map((p) => p.id)
          .toSet(),
      subtitleBuilder: (plant) {
        if (plant.locationId == null || plant.locationId == location.id) {
          return null;
        }
        final name = locationProvider.getLocationName(plant.locationId);
        return '現在「$name」に設定中';
      },
    );

    if (selectedIds == null || !context.mounted) return;
    await plantProvider.assignPlantsToLocation(location.id, selectedIds);
  }

  /// この場所に紐づけるセンサーデバイスを一括選択するダイアログを表示する
  Future<void> _showSensorPickerDialog(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final mappings = settingsProvider.settings.sensorDeviceMappings;

    if (mappings.isEmpty) {
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('センサーが未登録です'),
          content: const Text('IoTセンサー設定でデバイスを先に登録してください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('閉じる'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('設定画面へ'),
            ),
          ],
        ),
      );
      if (goToSettings == true && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
        );
      }
      return;
    }

    final selectedIds = Set<String>.from(
      mappings.where((m) => m.locationId == location.id).map((m) => m.deviceId),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('この場所のセンサーを設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: mappings.length,
              itemBuilder: (_, i) {
                final mapping = mappings[i];
                final isSelected = selectedIds.contains(mapping.deviceId);
                final otherLocationName = mapping.locationId != null &&
                        mapping.locationId != location.id
                    ? ctx
                        .read<LocationProvider>()
                        .getLocationName(mapping.locationId)
                    : null;
                return CheckboxListTile(
                  title: Text(mapping.deviceName),
                  subtitle: otherLocationName != null
                      ? Text('現在「$otherLocationName」に連動中（付け替わります）')
                      : null,
                  value: isSelected,
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selectedIds.add(mapping.deviceId);
                      } else {
                        selectedIds.remove(mapping.deviceId);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await settingsProvider.assignSensorsToLocation(location.id, selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(location.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(context),
          const SizedBox(height: 16),
          _buildPlantsCard(context),
          const SizedBox(height: 16),
          _buildSensorsCard(context),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(location.isOutdoor ? Icons.deck : Icons.home),
        title: Text(location.name),
        subtitle: Text(location.isOutdoor ? '屋外' : '屋内'),
      ),
    );
  }

  Widget _buildPlantsCard(BuildContext context) {
    return Consumer<PlantProvider>(
      builder: (context, plantProvider, _) {
        final plants =
            plantProvider.plants.where((p) => p.locationId == location.id).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'この場所の植物',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showPlantPickerDialog(context),
                      icon: const Icon(Icons.edit),
                      label: const Text('植物を設定'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (plants.isEmpty)
                  Text(
                    'この場所に設定された植物はありません',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  // 行から植物詳細へ入れるようにする（Issue #292）
                  ...plants.map((plant) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.eco_outlined),
                        title: Text(plant.name),
                        subtitle: plant.variety != null ? Text(plant.variety!) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlantDetailScreen(plant: plant),
                          ),
                        ),
                      )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSensorsCard(BuildContext context) {
    return Consumer2<SettingsProvider, SensorLogProvider>(
      builder: (context, settingsProvider, sensorLogProvider, _) {
        final List<SensorDeviceMapping> mappings = settingsProvider
            .settings.sensorDeviceMappings
            .where((m) => m.locationId == location.id)
            .toList();
        final latestByDevice = sensorLogProvider.latestLogPerDevice;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'この場所のセンサー',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showSensorPickerDialog(context),
                      icon: const Icon(Icons.sensors),
                      label: const Text('センサーを設定'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (mappings.isEmpty)
                  Text(
                    'この場所に紐づくセンサーはありません',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...mappings.map((mapping) {
                    final latest = latestByDevice[mapping.deviceId];
                    final reading = latest == null
                        ? '未取得'
                        : [
                            if (latest.temperature != null)
                              '${latest.temperature!.toStringAsFixed(1)}℃',
                            if (latest.humidity != null)
                              '${latest.humidity!.toStringAsFixed(0)}%',
                          ].join(' / ');
                    // センサー行も反応しなかったため、デバイス設定へ入れるようにする
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.device_hub),
                      title: Text(mapping.deviceName),
                      subtitle: Text(reading),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const IotSettingsScreen(),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
