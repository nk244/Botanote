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

  /// マッピングを使って一括取得・保存する（メインフロー）
  Future<void> _fetchWithMappings() async {
    final settingsProvider = context.read<SettingsProvider>();
    final settings = settingsProvider.settings;
    setState(() => _isFetching = true);
    try {
      final count = await context
          .read<SensorLogProvider>()
          .fetchAndSaveWithMappings(settings);
      await settingsProvider.updateLastSensorFetchAt(DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? '$count件のセンサーログを記録しました'
                : 'データを取得しましたが記録できたログはありませんでした',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  /// マッピング未設定時の手動取得フロー（フォールバック）
  Future<void> _startManualFetchFlow(SensorSource source) async {
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
          const SnackBar(content: Text('センサーデバイスが見つかりませんでした')),
        );
        return;
      }

      // 複数デバイスがある場合はユーザーに選択させる
      final SensorData selected;
      if (data.length == 1) {
        selected = data.first;
      } else {
        final picked = await _showDevicePickerDialog(data);
        if (!mounted || picked == null) return;
        selected = picked;
      }

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
                onChanged: (v) => setDialogState(() => selectedPlantId = v),
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
    if (humidity != null) parts.add('${humidity.toStringAsFixed(0)}%');
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
        title: const Text('センサー'),
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
          _buildFetchArea(),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildFetchArea() {
    final settings = context.watch<SettingsProvider>().settings;
    final hasNatureRemo = settings.natureRemoToken.isNotEmpty;
    final hasSwitchBot = settings.switchBotToken.isNotEmpty &&
        settings.switchBotSecret.isNotEmpty;
    final hasMappings = settings.sensorDeviceMappings.isNotEmpty;

    // APIトークン未設定
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
              'センサーが設定されていません',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
              ),
              icon: const Icon(Icons.settings),
              label: const Text('IoT設定を開く'),
            ),
          ],
        ),
      );
    }

    // マッピングが設定済み → 1タップ取得ボタン
    if (hasMappings) {
      return _buildMappingFetchArea(settings.sensorDeviceMappings.length);
    }

    // マッピング未設定 → 手動取得ボタン + マッピング設定へのヒント
    return _buildManualFetchArea(hasNatureRemo, hasSwitchBot);
  }

  /// マッピング設定済みのときに表示する取得エリア
  Widget _buildMappingFetchArea(int deviceCount) {
    final settings = context.read<SettingsProvider>().settings;
    final lastFetchStr = settings.lastSensorFetchAt;
    String lastFetchLabel = '未取得';
    if (lastFetchStr != null) {
      final dt = DateTime.tryParse(lastFetchStr);
      if (dt != null) {
        lastFetchLabel =
            '前回: ${DateFormat('MM/dd HH:mm').format(dt.toLocal())}';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _isFetching ? null : _fetchWithMappings,
            icon: _isFetching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sensors),
            label: const Text('今すぐ取得'),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$deviceCount台のデバイスから取得して紐づけ済み植物に記録します',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                lastFetchLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// マッピング未設定のときに表示する手動取得エリア
  Widget _buildManualFetchArea(bool hasNatureRemo, bool hasSwitchBot) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // マッピング設定を促すバナー
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'IoT設定でデバイスと植物を紐づけると、1タップで全デバイスのデータを取得・記録できます。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const IotSettingsScreen()),
                    ),
                    child: const Text('設定'),
                  ),
                ],
              ),
            ),
          ),
          // 手動取得ボタン
          if (hasNatureRemo)
            _buildManualFetchButton(
              label: 'Nature Remo からデータ取得',
              source: SensorSource.natureRemo,
            ),
          if (hasNatureRemo && hasSwitchBot) const SizedBox(height: 8),
          if (hasSwitchBot)
            _buildManualFetchButton(
              label: 'SwitchBot からデータ取得',
              source: SensorSource.switchBot,
            ),
        ],
      ),
    );
  }

  Widget _buildManualFetchButton({
    required String label,
    required SensorSource source,
  }) {
    return FilledButton.tonal(
      onPressed:
          _isFetching ? null : () => _startManualFetchFlow(source),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isFetching)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.sensors),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
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
