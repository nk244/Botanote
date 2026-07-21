import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sensor_device_mapping.dart';
import '../models/sensor_log.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import 'iot_settings_screen.dart';
import '../utils/error_utils.dart';

/// センサー環境ダッシュボード画面
///
/// デバイス単位で最新の温湿度データを一覧表示する。
/// ログの時系列履歴は植物詳細画面の「環境」タブで確認できる。
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

  /// マッピングを使って全デバイスのデータを一括取得・保存する
  Future<void> _fetchNow() async {
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
            count > 0 ? '$count件のセンサーログを記録しました' : 'データを取得しましたが記録できたログはありませんでした',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得に失敗しました: ${describeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
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
              MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<SensorLogProvider>(
        builder: (context, sensorProvider, _) {
          return _buildBody(sensorProvider);
        },
      ),
    );
  }

  Widget _buildBody(SensorLogProvider sensorProvider) {
    final settings = context.watch<SettingsProvider>().settings;
    final mappings = settings.sensorDeviceMappings;
    final hasToken = settings.natureRemoToken.isNotEmpty ||
        (settings.switchBotToken.isNotEmpty &&
            settings.switchBotSecret.isNotEmpty);

    // APIトークン未設定
    if (!hasToken) {
      return _buildEmptyState(
        icon: Icons.sensors_off,
        message: 'センサーが設定されていません',
        action: _buildIotSettingsButton(),
      );
    }

    // マッピング未設定
    if (mappings.isEmpty) {
      return _buildEmptyState(
        icon: Icons.device_hub,
        message: 'デバイスと植物が紐づけされていません',
        subMessage: 'IoT設定でデバイスを取得し、植物を割り当ててください。',
        action: _buildIotSettingsButton(),
      );
    }

    // ダッシュボード表示
    final latestLogs = sensorProvider.latestLogPerDevice;
    final linked = mappings.where((m) => m.plantIds.isNotEmpty).toList();
    final unlinked = mappings.where((m) => m.plantIds.isEmpty).toList();

    return Column(
      children: [
        _buildFetchBar(settings.lastSensorFetchAt, mappings.length),
        const Divider(height: 1),
        if (sensorProvider.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...linked.map((m) => _buildDeviceCard(m, latestLogs[m.deviceId])),
                if (unlinked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSectionLabel('植物が未設定のデバイス'),
                  ...unlinked.map((m) => _buildDeviceCard(m, null)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 取得ボタンと前回取得日時のバー
  Widget _buildFetchBar(String? lastFetchAt, int deviceCount) {
    String lastLabel = '未取得';
    if (lastFetchAt != null) {
      final dt = DateTime.tryParse(lastFetchAt);
      if (dt != null) {
        lastLabel = DateFormat('MM/dd HH:mm').format(dt.toLocal());
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _isFetching ? null : _fetchNow,
              icon: _isFetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sensors),
              label: const Text('今すぐ取得'),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '前回',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              Text(
                lastLabel,
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

  /// デバイス1台分のカード
  Widget _buildDeviceCard(SensorDeviceMapping mapping, SensorLog? latest) {
    final hasData = latest != null;
    final tempText = hasData && latest.temperature != null
        ? '${latest.temperature!.toStringAsFixed(1)}℃'
        : '--';
    final humidText = hasData && latest.humidity != null
        ? '${latest.humidity!.toStringAsFixed(0)}%'
        : '--';
    final plantCount = mapping.plantIds.length;
    final updatedText = hasData
        ? DateFormat('MM/dd HH:mm').format(latest.recordedAt.toLocal())
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // デバイス名と取得元
            Row(
              children: [
                Icon(
                  Icons.sensors,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mapping.deviceName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (updatedText != null)
                  Text(
                    updatedText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 温湿度の大きな数値表示
            Row(
              children: [
                _buildValueChip(Icons.thermostat, tempText, hasData),
                const SizedBox(width: 12),
                _buildValueChip(Icons.water_drop, humidText, hasData),
              ],
            ),
            const SizedBox(height: 10),
            // フッター: ソース名と植物数（または設定ボタン）
            Row(
              children: [
                Text(
                  _sourceName(mapping.source),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                if (plantCount > 0) ...[
                  Text(
                    '  ·  ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  Text(
                    '植物 $plantCount株',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ] else ...[
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const IotSettingsScreen()),
                    ),
                    child: const Text('植物を設定'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 温度・湿度の数値チップ
  Widget _buildValueChip(IconData icon, String value, bool hasData) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: hasData
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: hasData
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }

  Widget _buildIotSettingsButton() {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
      ),
      icon: const Icon(Icons.settings),
      label: const Text('IoT設定を開く'),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? subMessage,
    required Widget action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                subMessage,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}
