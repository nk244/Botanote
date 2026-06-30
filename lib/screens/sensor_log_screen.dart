import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sensor_log.dart';
import '../providers/plant_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/iot_service.dart';
import 'iot_settings_screen.dart';

/// センサーデータの取得・閲覧画面
class SensorLogScreen extends StatefulWidget {
  const SensorLogScreen({super.key});

  @override
  State<SensorLogScreen> createState() => _SensorLogScreenState();
}

class _SensorLogScreenState extends State<SensorLogScreen> {
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SensorLogProvider>().loadLogs();
    });
  }

  /// SensorSource の表示名を返す。
  String _sourceName(SensorSource source) {
    switch (source) {
      case SensorSource.natureRemo:
        return 'Nature Remo';
      case SensorSource.switchBot:
        return 'SwitchBot';
      case SensorSource.manual:
        return '手動';
    }
  }

  /// センサーデータ取得と記録のフローを開始する。
  Future<void> _startFetchFlow(SensorSource source) async {
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _isFetching = true);

    try {
      final List<SensorData> data;
      if (source == SensorSource.natureRemo) {
        data = await context
            .read<SensorLogProvider>()
            .fetchNatureRemoData(settings.natureRemoToken);
      } else {
        data = await context.read<SensorLogProvider>().fetchSwitchBotData(
              settings.switchBotToken,
              settings.switchBotSecret,
            );
      }

      if (!mounted) return;

      if (data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('センサーデータが見つかりませんでした')),
        );
        return;
      }

      // デバイスが複数ある場合はユーザーに選択させる
      final SensorData selected;
      if (data.length == 1) {
        selected = data.first;
      } else {
        final picked = await _showDevicePickerDialog(data);
        if (!mounted || picked == null) return;
        selected = picked;
      }

      // 取得結果確認と記録ダイアログを表示
      await _showRecordDialog(selected, source);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// 複数デバイスがある場合のデバイス選択ダイアログ
  Future<SensorData?> _showDevicePickerDialog(List<SensorData> devices) {
    return showDialog<SensorData>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('デバイスを選択'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (ctx, i) {
              final d = devices[i];
              return ListTile(
                leading: const Icon(Icons.sensors),
                title: Text(d.deviceName),
                subtitle: Text(_formatSensorValues(d.temperature, d.humidity)),
                onTap: () => Navigator.of(ctx).pop(d),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  /// センサーデータ確認と記録ダイアログ
  Future<void> _showRecordDialog(SensorData data, SensorSource source) async {
    final plants = context.read<PlantProvider>().plants;
    String? selectedPlantId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(data.deviceName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // センサー値の表示
              _buildSensorValueRow(
                Icons.thermostat,
                '温度',
                data.temperature != null
                    ? '${data.temperature!.toStringAsFixed(1)} ℃'
                    : '--',
              ),
              const SizedBox(height: 8),
              _buildSensorValueRow(
                Icons.water_drop,
                '湿度',
                data.humidity != null
                    ? '${data.humidity!.toStringAsFixed(1)} %'
                    : '--',
              ),
              const SizedBox(height: 16),
              // 植物への紐付け選択
              DropdownButtonFormField<String?>(
                initialValue: selectedPlantId,
                decoration: const InputDecoration(
                  labelText: '植物に紐付け（任意）',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('紐付けなし'),
                  ),
                  ...plants.map((p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name),
                      )),
                ],
                onChanged: (v) =>
                    setDialogState(() => selectedPlantId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('記録する'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<SensorLogProvider>().saveSensorLog(
            data: data,
            source: source,
            plantId: selectedPlantId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('センサーログを記録しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記録に失敗しました: $e')),
      );
    }
  }

  Widget _buildSensorValueRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  String _formatSensorValues(double? temperature, double? humidity) {
    final parts = <String>[];
    if (temperature != null) parts.add('${temperature.toStringAsFixed(1)}℃');
    if (humidity != null) parts.add('${humidity.toStringAsFixed(1)}%');
    return parts.isEmpty ? '温湿度データなし' : parts.join(' / ');
  }

  Future<void> _deleteSensorLog(SensorLog log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログを削除'),
        content: const Text('このセンサーログを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<SensorLogProvider>().deleteSensorLog(log.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('センサーログ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'IoT設定',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const IotSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFetchButtons(),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildFetchButtons() {
    final settings = context.watch<SettingsProvider>().settings;
    final hasNatureRemo = settings.natureRemoToken.isNotEmpty;
    final hasSwitchBot = settings.switchBotToken.isNotEmpty &&
        settings.switchBotSecret.isNotEmpty;

    if (!hasNatureRemo && !hasSwitchBot) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.sensors_off,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'IoTデバイスが連携されていません',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const IotSettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.settings),
              label: const Text('IoT設定を開く'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasNatureRemo)
            _buildFetchButton(
              label: 'Nature Remo からデータ取得',
              icon: Icons.sensors,
              source: SensorSource.natureRemo,
            ),
          if (hasNatureRemo && hasSwitchBot) const SizedBox(height: 8),
          if (hasSwitchBot)
            _buildFetchButton(
              label: 'SwitchBot からデータ取得',
              icon: Icons.sensors,
              source: SensorSource.switchBot,
            ),
        ],
      ),
    );
  }

  Widget _buildFetchButton({
    required String label,
    required IconData icon,
    required SensorSource source,
  }) {
    return FilledButton.icon(
      onPressed: _isFetching ? null : () => _startFetchFlow(source),
      icon: _isFetching
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildLogList() {
    return Consumer2<SensorLogProvider, PlantProvider>(
      builder: (context, sensorProvider, plantProvider, _) {
        if (sensorProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = sensorProvider.logs;
        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sensors,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'センサーログがありません',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '上のボタンからIoTデバイスのデータを取得・記録できます',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // 植物ID→名前の変換マップを生成
        final plantMap = {
          for (final p in plantProvider.plants) p.id: p.name,
        };

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: logs.length,
          itemBuilder: (context, index) =>
              _buildLogCard(logs[index], plantMap),
        );
      },
    );
  }

  Widget _buildLogCard(SensorLog log, Map<String, String> plantMap) {
    final plantName = log.plantId != null
        ? (plantMap[log.plantId!] ?? '削除済み')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: const Icon(Icons.thermostat),
        title: Text(
          _formatSensorValues(log.temperature, log.humidity),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_sourceName(log.source)} / ${log.deviceName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              DateFormat('yyyy年MM月dd日 HH:mm').format(log.recordedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (plantName != null)
              Text(
                '植物: $plantName',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '削除',
          onPressed: () => _deleteSensorLog(log),
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Consumer2 ウィジェット（2種類の Provider を同時に購読する）
class Consumer2<A extends ChangeNotifier, B extends ChangeNotifier>
    extends StatelessWidget {
  final Widget Function(BuildContext context, A a, B b, Widget? child) builder;
  final Widget? child;

  const Consumer2({super.key, required this.builder, this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<A>(
      builder: (context, a, _) => Consumer<B>(
        builder: (context, b, _) => builder(context, a, b, child),
      ),
    );
  }
}
