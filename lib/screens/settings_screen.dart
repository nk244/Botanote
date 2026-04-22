import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../models/app_settings.dart';
import '../services/export_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          
          // Theme settings
          _buildSectionHeader(context, 'テーマ'),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return Column(
                children: [
                  // Theme mode (system/light/dark)
                  RadioListTile<ThemePreference>(
                    title: const Text('システムに従う'),
                    value: ThemePreference.system,
                    groupValue: settings.themePreference,
                    onChanged: (v) => settings.setThemePreference(v!),
                  ),
                  RadioListTile<ThemePreference>(
                    title: const Text('ライトモード'),
                    value: ThemePreference.light,
                    groupValue: settings.themePreference,
                    onChanged: (v) => settings.setThemePreference(v!),
                  ),
                  RadioListTile<ThemePreference>(
                    title: const Text('ダークモード'),
                    value: ThemePreference.dark,
                    groupValue: settings.themePreference,
                    onChanged: (v) => settings.setThemePreference(v!),
                  ),
                  const Divider(),
                  // Color theme selection
                  ...AppTheme.values.map((theme) {
                    return RadioListTile<AppTheme>(
                      title: Text(_getThemeName(theme)),
                      value: theme,
                      groupValue: settings.theme,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setTheme(value);
                        }
                      },
                      secondary: Icon(
                        Icons.palette,
                        color: _getThemeColor(theme),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          const Divider(),

          // Notification settings
          _buildSectionHeader(context, '通知設定'),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications),
                    title: const Text('水やりリマインダー'),
                    subtitle: const Text('水やり予定がある日のみ通知します'),
                    value: settings.notificationEnabled,
                    onChanged: (v) => settings.setNotificationEnabled(v),
                  ),
                  if (settings.notificationEnabled)
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: const Text('通知時刻'),
                      subtitle: Text(
                        '${settings.settings.notificationHour.toString().padLeft(2, '0')}:${settings.settings.notificationMinute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: settings.settings.notificationHour,
                            minute: settings.settings.notificationMinute,
                          ),
                        );
                        if (time != null) {
                          settings.setNotificationTime(time.hour, time.minute);
                        }
                      },
                    ),
                ],
              );
            },
          ),
          const Divider(),

          // Watering interval bulk settings
          _buildSectionHeader(context, '水やり間隔'),
          ListTile(
            leading: const Icon(Icons.water_drop),
            title: const Text('水やり間隔を一括設定'),
            subtitle: const Text('すべての植物の間隔を同じ日数に変更'),
            onTap: () => _showBulkSetIntervalDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('水やり間隔を一括調整'),
            subtitle: const Text('設定済みの植物の間隔を一定日数ずつ増減'),
            onTap: () => _showBulkAdjustIntervalDialog(context),
          ),
          const Divider(),

          // Data management
          _buildSectionHeader(context, 'データ管理'),
          ListTile(
            leading: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            title: const Text('データをエクスポート'),
            subtitle: const Text('植物・ログ・画像を ZIP ファイルに保存'),
            onTap: _isExporting ? null : () => _handleExport(context),
          ),
          ListTile(
            leading: _isImporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            title: const Text('データをインポート'),
            subtitle: const Text('ZIP または JSON ファイルからデータを復元'),
            onTap: _isImporting ? null : () => _handleImport(context),
          ),
          // AI機能設定
          _buildSectionHeader(context, 'AI機能'),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return _AiApiKeyTile(
                initialValue: settings.geminiApiKey,
                onSaved: (key) => settings.setGeminiApiKey(key),
              );
            },
          ),
          const Divider(),

          // About
          _buildSectionHeader(context, 'アプリについて'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('バージョン'),
            subtitle: Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('開発情報'),
            subtitle: const Text('Flutter製の水やり管理アプリ'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Botanote',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.eco, size: 48),
                children: const [
                  Text('植物の水やりを管理するためのアプリです。'),
                  SizedBox(height: 8),
                  Text('水やりの記録、リマインダー、日記機能を提供します。'),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 水やり間隔を一括設定するダイアログ
  Future<void> _showBulkSetIntervalDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('水やり間隔を一括設定'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('すべての植物の水やり間隔を指定した日数に変更します。'),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '日数',
                  suffixText: '日',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1) return '1以上の整数を入力してください';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('設定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final days = int.parse(controller.text);
    if (!mounted) return;
    try {
      await context.read<PlantProvider>().bulkUpdateWateringInterval(days);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('すべての植物の水やり間隔を $days 日に設定しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新に失敗しました: $e')),
      );
    }
  }

  /// 水やり間隔を一括調整するダイアログ（増減）
  Future<void> _showBulkAdjustIntervalDialog(BuildContext context) async {
    int delta = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('水やり間隔を一括調整'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('水やり間隔が設定されている植物の\n間隔を一定日数ずつ増減します。'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove),
                    onPressed: () => setDialogState(() => delta--),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${delta > 0 ? '+' : ''}$delta 日',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    onPressed: () => setDialogState(() => delta++),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: delta == 0 ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('適用'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await context.read<PlantProvider>().bulkAdjustWateringInterval(delta);
      if (!mounted) return;
      final label = delta > 0 ? '+$delta' : '$delta';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('水やり間隔を $label 日調整しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新に失敗しました: $e')),
      );
    }
  }

  /// エクスポート処理
  Future<void> _handleExport(BuildContext context) async {
    if (kIsWeb) {
      // Web 環境: JSON テキストをダイアログで表示（コピー可）
      setState(() => _isExporting = true);
      try {
        final json = await ExportService().exportToJson();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('エクスポートJSON'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: SingleChildScrollView(
                child: SelectableText(json,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポートに失敗しました: $e')),
        );
      } finally {
        if (mounted) setState(() => _isExporting = false);
      }
      return;
    }

    // モバイル環境: ファイルに保存
    setState(() => _isExporting = true);
    try {
      final path = await ExportService().exportToFile();
      if (!mounted) return;
      if (path == null) {
        // ユーザーがキャンセル
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('バックアップファイルを共有しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポートに失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// インポート処理
  Future<void> _handleImport(BuildContext context) async {
    // 上書き警告
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('データのインポート'),
        content: const Text(
          'バックアップファイル（.zip または .json）を選択してください。\n'
          '既存のデータは保持され、インポートしたデータが追加・上書きされます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ファイルを選択'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isImporting = true);
    try {
      final result = await ExportService().importFromFilePicker();
      if (!mounted) return;
      if (result == null) {
        // キャンセル
        return;
      }
      // PlantProvider・NoteProvider を再読み込みして反映
      await context.read<PlantProvider>().loadPlants();
      await context.read<NoteProvider>().loadNotes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポートしました（$result）')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポートに失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getThemeName(AppTheme theme) {
    switch (theme) {
      case AppTheme.green:
        return 'グリーン';
      case AppTheme.blue:
        return 'ブルー';
      case AppTheme.purple:
        return 'パープル';
      case AppTheme.orange:
        return 'オレンジ';
    }
  }

  Color _getThemeColor(AppTheme theme) {
    switch (theme) {
      case AppTheme.green:
        return Colors.green;
      case AppTheme.blue:
        return Colors.blue;
      case AppTheme.purple:
        return Colors.purple;
      case AppTheme.orange:
        return Colors.orange;
    }
  }
}

/// APIキーの入力・保存を行う独立ウィジェット。
class _AiApiKeyTile extends StatefulWidget {
  final String initialValue;
  final Future<void> Function(String) onSaved;

  const _AiApiKeyTile({required this.initialValue, required this.onSaved});

  @override
  State<_AiApiKeyTile> createState() => _AiApiKeyTileState();
}

class _AiApiKeyTileState extends State<_AiApiKeyTile> {
  late final TextEditingController _controller;
  bool _obscure = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSaved(_controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('APIキーを保存しました')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 説明文
          Text(
            'Gemini APIキーを入力すると、植物の自動識別・健康診断・パーソナルコーチ機能が利用できます。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Gemini APIキー',
                    hintText: 'AIza...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _isSaving
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          // Google AI Studioへのヒント
          Text(
            'APIキーは Google AI Studio (aistudio.google.com) で取得できます。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
