import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/iot_service.dart';

/// IoT連携APIキーの設定画面
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

  /// Nature Remoのトークン入力フィールドの表示/非表示
  bool _obscureNatureRemo = true;

  /// SwitchBotのトークン入力フィールドの表示/非表示
  bool _obscureSwitchBotToken = true;

  /// SwitchBotのシークレット入力フィールドの表示/非表示
  bool _obscureSwitchBotSecret = true;

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
      await context.read<SettingsProvider>().updateIotSettings(
            natureRemoToken: _natureRemoController.text.trim(),
            switchBotToken: _switchBotTokenController.text.trim(),
            switchBotSecret: _switchBotSecretController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定を保存しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
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
              ? '接続成功（デバイスなし）'
              : '接続成功: $names'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接続失敗: $e')),
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
              ? '接続成功（温湿度センサーなし）'
              : '接続成功: $names'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接続失敗: $e')),
      );
    } finally {
      if (mounted) setState(() => _isTestingSwitchBot = false);
    }
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
          const SizedBox(height: 32),
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
                  : const Icon(Icons.wifi_tethering),
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
                  : const Icon(Icons.wifi_tethering),
              label: const Text('接続テスト'),
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
