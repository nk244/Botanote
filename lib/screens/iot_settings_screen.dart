import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor_device_mapping.dart';
import '../providers/location_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../services/iot_service.dart';
import '../services/sensor_auto_fetch_service.dart';
import '../utils/error_utils.dart';

/// IoT連携APIキー・デバイスマッピング・自動取得間隔の設定画面
class IotSettingsScreen extends StatefulWidget {
  const IotSettingsScreen({super.key});

  @override
  State<IotSettingsScreen> createState() => _IotSettingsScreenState();
}

class _IotSettingsScreenState extends State<IotSettingsScreen> {
  late final TextEditingController _natureRemoController;
  late final TextEditingController _switchBotTokenController;
  late final TextEditingController _switchBotSecretController;

  bool _isSaving = false;
  bool _isTestingNatureRemo = false;
  bool _isTestingSwitchBot = false;
  bool _isFetchingDevices = false;

  bool _obscureNatureRemo = true;
  bool _obscureSwitchBotToken = true;
  bool _obscureSwitchBotSecret = true;

  /// 現在の編集中マッピング（deviceId → plantIdリスト）
  late List<SensorDeviceMapping> _mappings;

  /// 自動取得間隔（時間）
  late int _fetchIntervalHours;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _natureRemoController =
        TextEditingController(text: settings.natureRemoToken);
    _switchBotTokenController =
        TextEditingController(text: settings.switchBotToken);
    _switchBotSecretController =
        TextEditingController(text: settings.switchBotSecret);
    _mappings = List.from(settings.sensorDeviceMappings);
    _fetchIntervalHours = settings.sensorFetchIntervalHours;
  }

  @override
  void dispose() {
    _natureRemoController.dispose();
    _switchBotTokenController.dispose();
    _switchBotSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final provider = context.read<SettingsProvider>();
      await provider.updateIotSettings(
        natureRemoToken: _natureRemoController.text.trim(),
        switchBotToken: _switchBotTokenController.text.trim(),
        switchBotSecret: _switchBotSecretController.text.trim(),
      );
      await provider.updateDeviceMappings(_mappings);
      await provider.updateSensorFetchInterval(_fetchIntervalHours);
      // 間隔・マッピング変更をバックグラウンド定期タスクへ即座に反映する
      await SensorAutoFetchService.reschedule(provider.settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定を保存しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: ${describeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testNatureRemo() async {
    final token = _natureRemoController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('APIトークンを入力してください')),
      );
      return;
    }
    setState(() => _isTestingNatureRemo = true);
    try {
      final devices = await IotService().fetchNatureRemoData(token);
      if (!mounted) return;
      final names = devices.map((d) => d.deviceName).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(devices.isEmpty
              ? '接続しました（温湿度センサーが見つかりません）'
              : '接続成功: $names'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接続失敗: ${describeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isTestingNatureRemo = false);
    }
  }

  Future<void> _testSwitchBot() async {
    final token = _switchBotTokenController.text.trim();
    final secret = _switchBotSecretController.text.trim();
    if (token.isEmpty || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('トークンとシークレットを入力してください')),
      );
      return;
    }
    setState(() => _isTestingSwitchBot = true);
    try {
      final devices = await IotService().fetchSwitchBotData(token, secret);
      if (!mounted) return;
      final names = devices.map((d) => d.deviceName).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(devices.isEmpty
              ? '接続しました（温湿度センサーが見つかりません）'
              : '接続成功: $names'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接続失敗: ${describeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isTestingSwitchBot = false);
    }
  }

  /// 設定済み API からデバイスを一括取得してリストに表示する
  Future<void> _fetchDevices() async {
    final natureRemoToken = _natureRemoController.text.trim();
    final switchBotToken = _switchBotTokenController.text.trim();
    final switchBotSecret = _switchBotSecretController.text.trim();

    if (natureRemoToken.isEmpty && switchBotToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('APIトークンを入力してから取得してください')),
      );
      return;
    }

    setState(() => _isFetchingDevices = true);
    try {
      final iot = IotService();
      final allDevices = <SensorData>[];
      // 各サービスの取得失敗理由を収集する。片方が失敗しても続行するが、
      // エラーをサイレントに握り潰さず、後でユーザーに提示する。
      final errors = <String>[];

      if (natureRemoToken.isNotEmpty) {
        try {
          final devices = await iot.fetchNatureRemoData(natureRemoToken);
          allDevices.addAll(devices);
        } catch (e) {
          errors.add(describeError(e));
        }
      }
      if (switchBotToken.isNotEmpty && switchBotSecret.isNotEmpty) {
        try {
          final devices =
              await iot.fetchSwitchBotData(switchBotToken, switchBotSecret);
          allDevices.addAll(devices);
        } catch (e) {
          errors.add(describeError(e));
        }
      }

      if (!mounted) return;

      if (allDevices.isEmpty) {
        // 取得0件でも、エラーがあれば「見つからない」ではなく実際の原因を出す。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errors.isEmpty
                ? 'デバイスが見つかりませんでした'
                : '取得に失敗しました: ${errors.join(' / ')}'),
          ),
        );
        return;
      }

      // 一部のサービスだけ成功した場合は、成功分を反映しつつ失敗も知らせる。
      if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('一部の取得に失敗しました: ${errors.join(' / ')}'),
          ),
        );
      }

      setState(() {
        // 取得できたデバイスのうちマッピングに存在しないものを初期登録
        for (final device in allDevices) {
          final exists = _mappings.any((m) => m.deviceId == device.deviceId);
          if (!exists) {
            _mappings.add(SensorDeviceMapping(
              deviceId: device.deviceId,
              deviceName: device.deviceName,
              source: device.source,
              plantIds: [],
            ));
          }
        }
      });
    } finally {
      if (mounted) setState(() => _isFetchingDevices = false);
    }
  }

  /// 管理場所に連動しているデバイスの連動解除を確認するダイアログを表示する
  Future<void> _showLocationUnlinkDialog(SensorDeviceMapping mapping) async {
    final locationName =
        context.read<LocationProvider>().getLocationName(mapping.locationId) ??
            '不明な場所';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('場所との連動を解除しますか？'),
        content: Text(
          '「${mapping.deviceName}」は現在「$locationName」に連動しており、'
          'この場所に属する植物全員へ自動的にデータが紐づいています。\n'
          '解除すると植物を個別に選択できるようになります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('連動を解除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      final idx = _mappings.indexWhere((m) => m.deviceId == mapping.deviceId);
      if (idx >= 0) {
        _mappings[idx] = _mappings[idx].copyWith(locationId: null);
      }
    });
  }

  /// デバイスに紐づける植物を複数選択するダイアログを表示する
  Future<void> _showPlantPickerDialog(SensorDeviceMapping mapping) async {
    final plantProvider = context.read<PlantProvider>();
    final plants = plantProvider.plants;

    if (plants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('植物が登録されていません')),
      );
      return;
    }

    // 現在選択中の植物IDセット（ダイアログ内で変更する）
    final selectedIds = Set<String>.from(mapping.plantIds);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${mapping.deviceName}の植物を設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: plants.length,
              itemBuilder: (_, i) {
                final plant = plants[i];
                final isSelected = selectedIds.contains(plant.id);
                return CheckboxListTile(
                  title: Text(plant.name),
                  subtitle: plant.variety != null
                      ? Text(plant.variety!)
                      : null,
                  value: isSelected,
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selectedIds.add(plant.id);
                      } else {
                        selectedIds.remove(plant.id);
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

    if (confirmed != true || !mounted) return;

    setState(() {
      final idx = _mappings.indexWhere((m) => m.deviceId == mapping.deviceId);
      if (idx >= 0) {
        _mappings[idx] = _mappings[idx].copyWith(plantIds: selectedIds.toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IoTセンサー設定'),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildNatureRemoSection(),
          const SizedBox(height: 24),
          _buildSwitchBotSection(),
          const SizedBox(height: 24),
          _buildDeviceMappingSection(),
          const SizedBox(height: 24),
          _buildAutoFetchSection(),
          const SizedBox(height: 24),
          _buildNoteCard(),
        ],
      ),
    );
  }

  Widget _buildNatureRemoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nature Remo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _natureRemoController,
              obscureText: _obscureNatureRemo,
              decoration: InputDecoration(
                labelText: 'APIトークン',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNatureRemo
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () => setState(
                      () => _obscureNatureRemo = !_obscureNatureRemo),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isTestingNatureRemo ? null : _testNatureRemo,
              icon: _isTestingNatureRemo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: const Text('接続テスト'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchBotSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SwitchBot',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _switchBotTokenController,
              obscureText: _obscureSwitchBotToken,
              decoration: InputDecoration(
                labelText: 'APIトークン',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureSwitchBotToken
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () => setState(() =>
                      _obscureSwitchBotToken = !_obscureSwitchBotToken),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _switchBotSecretController,
              obscureText: _obscureSwitchBotSecret,
              decoration: InputDecoration(
                labelText: 'シークレット',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureSwitchBotSecret
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () => setState(() =>
                      _obscureSwitchBotSecret = !_obscureSwitchBotSecret),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isTestingSwitchBot ? null : _testSwitchBot,
              icon: _isTestingSwitchBot
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: const Text('接続テスト'),
            ),
          ],
        ),
      ),
    );
  }

  /// デバイス-植物マッピングカード
  Widget _buildDeviceMappingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'デバイスと植物の紐づけ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'センサーを取得してから、各デバイスに植物を紐づけます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isFetchingDevices ? null : _fetchDevices,
              icon: _isFetchingDevices
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sensors),
              label: const Text('センサーを取得'),
            ),
            if (_mappings.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              ..._mappings.map((mapping) => _buildMappingTile(mapping)),
            ],
          ],
        ),
      ),
    );
  }

  /// デバイス1件のマッピング行
  Widget _buildMappingTile(SensorDeviceMapping mapping) {
    // 管理場所に連動している場合は場所名バッジを表示し、タップで連動解除ダイアログを開く
    if (mapping.locationId != null) {
      final locationName =
          context.read<LocationProvider>().getLocationName(mapping.locationId) ??
              '不明な場所';
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.device_hub),
        title: Text(mapping.deviceName),
        subtitle: Text('「$locationName」に連動中（植物は自動追従）'),
        trailing: const Icon(Icons.link),
        onTap: () => _showLocationUnlinkDialog(mapping),
      );
    }

    final plantProvider = context.read<PlantProvider>();
    final plants = plantProvider.plants;

    // 紐づけ済み植物名の一覧を作成
    final linkedNames = mapping.plantIds
        .map((id) {
          try {
            return plants.firstWhere((p) => p.id == id).name;
          } catch (_) {
            return null;
          }
        })
        .where((n) => n != null)
        .cast<String>()
        .toList();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.device_hub),
      title: Text(mapping.deviceName),
      subtitle: linkedNames.isEmpty
          ? const Text('植物が未設定')
          : Text(linkedNames.join('、')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPlantPickerDialog(mapping),
    );
  }

  /// 自動取得間隔カード
  Widget _buildAutoFetchSection() {
    const intervalOptions = [
      (label: '無効', hours: 0),
      (label: '3時間ごと', hours: 3),
      (label: '6時間ごと', hours: 6),
      (label: '12時間ごと', hours: 12),
      (label: '24時間ごと', hours: 24),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '自動取得',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'アプリを開いていなくても、指定した間隔でバックグラウンドで自動取得します。'
              '（OSの省電力設定により実行タイミングが多少ずれる場合があります）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _fetchIntervalHours,
              decoration: const InputDecoration(
                labelText: '取得間隔',
                border: OutlineInputBorder(),
              ),
              items: intervalOptions
                  .map((opt) => DropdownMenuItem<int>(
                        value: opt.hours,
                        child: Text(opt.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _fetchIntervalHours = v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'APIキーの取得方法',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• Nature Remo: home.nature.global にログインし「アカウント」→「APIキーの発行」から取得\n'
              '• SwitchBot: SwitchBotアプリの「プロフィール」→「設定」→「開発者向けオプション」から取得',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

