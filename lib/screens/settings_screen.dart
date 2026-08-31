import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/settings_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/location_provider.dart';
import '../models/app_settings.dart';
import '../services/export_service.dart';
import 'iot_settings_screen.dart';
import 'light_meter_screen.dart';
import 'care_stats_screen.dart';
import 'location_list_screen.dart';
import '../utils/error_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  /// pubspec.yaml のバージョンを実行時に取得した表示用文字列（例: '1.3.0 (6)'）。
  /// 取得完了までは null で、その間はバージョン行を控えめに「取得中」と表示する。
  String? _appVersion;

  /// 一括変更の結果 SnackBar。設定画面を離れるときに閉じるため保持する（Issue #286）。
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _bulkResultSnackBar;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  @override
  void dispose() {
    // SnackBar はルートの ScaffoldMessenger に出るため、閉じないと設定画面を
    // 抜けた後もタブ画面に残り、植物一覧の FAB に重なって誤タップの原因になる。
    _bulkResultSnackBar?.close();
    super.dispose();
  }

  /// アプリのバージョンを取得して表示用に整形する（Issue #221）。
  ///
  /// 以前は画面側にバージョンをハードコードしていたため pubspec.yaml と
  /// 食い違い、配布APKで実際と異なるバージョンが表示されていた。
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      // 取得に失敗しても設定画面自体は使えるため、表示のみフォールバックする
      debugPrint('Error loading package info: $e');
      if (!mounted) return;
      setState(() {
        _appVersion = '不明';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
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
            subtitle: const Text('植物・ログ・画像を ZIP ファイルに保存／共有'),
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
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('ケア統計'),
            subtitle: const Text('月別のケア件数・植物ごとの頻度を振り返る'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CareStatsScreen())),
          ),
          const Divider(),

          // 植物管理
          _buildSectionHeader(context, '植物管理'),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('置き場所管理'),
            subtitle: const Text('リビング・ベランダ等の置き場所を登録・編集'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocationListScreen()),
            ),
          ),
          const Divider(),

          // 天気連動ケアアラート（Issue #176）
          _buildSectionHeader(context, '天気連動ケアアラート'),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              final lat = settings.settings.weatherLatitude;
              final lon = settings.settings.weatherLongitude;
              final hasLocation = lat != null && lon != null;
              return Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_outlined),
                    title: const Text('天気連動ケアアラート'),
                    subtitle: const Text('屋外の植物がある場合、猛暑・低温・大雨・強UVの前日に通知します'),
                    value: settings.settings.weatherAlertsEnabled,
                    onChanged: (value) async {
                      if (value && !hasLocation) {
                        // 座標未設定の場合は先に観測地点を入力させる
                        await _showWeatherLocationDialog(context, settings);
                        return;
                      }
                      await settings.updateWeatherAlertSettings(
                        enabled: value,
                        latitude: lat,
                        longitude: lon,
                      );
                    },
                  ),
                  if (settings.settings.weatherAlertsEnabled)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: const Text('観測地点'),
                      subtitle: Text(
                        hasLocation
                            ? '緯度 ${lat.toStringAsFixed(4)} / 経度 ${lon.toStringAsFixed(4)}'
                            : '未設定',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _showWeatherLocationDialog(context, settings),
                    ),
                ],
              );
            },
          ),
          const Divider(),

          // IoTセンサー連携
          _buildSectionHeader(context, 'IoTセンサー連携'),
          ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('センサー連携の設定'),
            subtitle: const Text('Nature Remo / SwitchBot の APIキーを管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
            ),
          ),
          const Divider(),

          // 光量メーター（Issue #181）
          _buildSectionHeader(context, '光量メーター'),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('光量メーター'),
            subtitle: const Text('カメラで置き場所の明るさの目安を測定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LightMeterScreen())),
          ),
          const Divider(),

          // About
          _buildSectionHeader(context, 'アプリについて'),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('バージョン'),
            subtitle: Text(_appVersion ?? '取得中…'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('開発情報'),
            subtitle: const Text('Flutter製の水やり管理アプリ'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Botanote',
                applicationVersion: _appVersion ?? '',
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
  /// 天気連動ケアアラートの観測地点（緯度・経度）を入力するダイアログ（Issue #176）。
  Future<void> _showWeatherLocationDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final latController = TextEditingController(
      text: settings.settings.weatherLatitude?.toString() ?? '',
    );
    final lonController = TextEditingController(
      text: settings.settings.weatherLongitude?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('観測地点を設定'),
        content: Form(
          key: formKey,
          // 入力を修正した時点でエラー表示を再評価し、赤枠・エラーメッセージを残さない
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Googleマップ等で自宅の座標を調べて入力してください。'),
              const SizedBox(height: 16),
              TextFormField(
                controller: latController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: '緯度',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < -90 || n > 90)
                    return '-90〜90の数値を入力してください';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lonController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: '経度',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < -180 || n > 180)
                    return '-180〜180の数値を入力してください';
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
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final lat = double.parse(latController.text);
    final lon = double.parse(lonController.text);
    await settings.updateWeatherAlertSettings(
      enabled: true,
      latitude: lat,
      longitude: lon,
    );
  }

  Future<void> _showBulkSetIntervalDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('水やり間隔を一括設定'),
        content: Form(
          key: formKey,
          // 入力を修正した時点でエラー表示を再評価し、赤枠・エラーメッセージを残さない
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
    if (!context.mounted) return;

    // 誤タップで全植物の間隔が書き換わらないよう、対象件数を示して確認する（Issue #274）
    final plantProvider = context.read<PlantProvider>();
    final targetCount = plantProvider.countBulkIntervalTargets(
      onlyWithInterval: false,
    );
    final applied = await _confirmBulkIntervalChange(
      context,
      title: '水やり間隔を一括設定',
      message: '$targetCount件の植物の水やり間隔を $days 日に変更します。よろしいですか？',
    );
    if (applied != true || !context.mounted) return;

    try {
      final previous = await plantProvider.bulkUpdateWateringInterval(days);
      if (!context.mounted) return;
      _showBulkIntervalResultSnackBar(
        context,
        message: '$targetCount件の植物の水やり間隔を $days 日に設定しました',
        previous: previous,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新に失敗しました: ${describeError(e)}')));
    }
  }

  /// 一括変更前の確認ダイアログ（Issue #274）。
  Future<bool?> _confirmBulkIntervalChange(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
  }

  /// 一括変更後の SnackBar。「元に戻す」で変更前の間隔へ復元できる（Issue #274）。
  void _showBulkIntervalResultSnackBar(
    BuildContext context, {
    required String message,
    required Map<String, int?> previous,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final plantProvider = context.read<PlantProvider>();
    _bulkResultSnackBar = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () async {
            try {
              await plantProvider.restoreWateringIntervals(previous);
              messenger.showSnackBar(
                const SnackBar(content: Text('水やり間隔を元に戻しました')),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('復元に失敗しました: ${describeError(e)}')),
              );
            }
          },
        ),
      ),
    );
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
    if (!context.mounted) return;

    final label = delta > 0 ? '+$delta' : '$delta';
    // 誤タップ対策の確認ダイアログ（Issue #274）
    final plantProvider = context.read<PlantProvider>();
    final targetCount = plantProvider.countBulkIntervalTargets(
      onlyWithInterval: true,
    );
    final applied = await _confirmBulkIntervalChange(
      context,
      title: '水やり間隔を一括調整',
      message: '$targetCount件の植物の水やり間隔を $label 日します。よろしいですか？',
    );
    if (applied != true || !context.mounted) return;

    try {
      final previous = await plantProvider.bulkAdjustWateringInterval(delta);
      if (!context.mounted) return;
      _showBulkIntervalResultSnackBar(
        context,
        message: '$targetCount件の植物の水やり間隔を $label 日調整しました',
        previous: previous,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新に失敗しました: ${describeError(e)}')));
    }
  }

  /// エクスポート処理
  ///
  /// 共有シート経由だとキャッシュ領域にしかファイルが残らず、OS の空き容量確保で
  /// 消える恐れがあるため、端末への保存を既定の選択肢として提示する（Issue #270）。
  Future<void> _handleExport(BuildContext context) async {
    final method = await showDialog<_ExportMethod>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('データをエクスポート'),
        content: const Text(
          '植物・ログ・画像を ZIP にまとめます。\n'
          '「端末に保存」は保存先を選んでファイルとして残します。\n'
          '「共有」はアプリ内の一時ファイルを他アプリへ送るだけで、端末には残りません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ExportMethod.share),
            child: const Text('共有'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_ExportMethod.saveToDevice),
            child: const Text('端末に保存'),
          ),
        ],
      ),
    );
    if (method == null || !context.mounted) return;

    setState(() => _isExporting = true);
    try {
      if (method == _ExportMethod.saveToDevice) {
        final path = await ExportService().exportToDeviceStorage();
        if (!context.mounted) return;
        // ユーザーがキャンセル
        if (path == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('バックアップを保存しました\n$path'),
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        final path = await ExportService().exportToFile();
        if (!context.mounted) return;
        // ユーザーがキャンセル
        if (path == null) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('バックアップファイルを共有しました')));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポートに失敗しました: ${describeError(e)}')),
      );
    } finally {
      if (context.mounted) setState(() => _isExporting = false);
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
      if (!context.mounted) return;
      if (result == null) {
        // キャンセル
        return;
      }
      // 各Providerを再読み込みして反映
      await context.read<PlantProvider>().loadPlants();
      if (!context.mounted) return;
      await context.read<NoteProvider>().loadNotes();
      if (!context.mounted) return;
      await context.read<SensorLogProvider>().loadLogs();
      if (!context.mounted) return;
      await context.read<LocationProvider>().loadLocations();
      if (!context.mounted) return;
      // 復元したアプリ設定（通知時刻・テーマ等）を画面と通知に反映する（Issue #239）
      if (result.settingsRestored) {
        await context.read<SettingsProvider>().loadSettings();
        if (!context.mounted) return;
      }
      // ダイアログ表示中もスピナーが回り続けないよう、先に読み込み状態を解除する
      setState(() => _isImporting = false);
      // 復元結果は見逃すと影響が大きいため、SnackBar ではなくダイアログで示す（Issue #225）
      // 画像を復元できなかった場合は、成功メッセージに紛れないよう警告として出す（Issue #289）
      final imageWarning = result.imageWarning;
      await _showImportResultDialog(
        context,
        title: imageWarning == null
            ? 'インポートが完了しました'
            : 'インポートが完了しました（一部の写真は未復元）',
        message: imageWarning == null
            ? '以下のデータを復元しました。\n\n$result'
            : '以下のデータを復元しました。\n\n$result\n\n⚠ $imageWarning',
      );
    } catch (e) {
      debugPrint('インポートに失敗: $e');
      if (!context.mounted) return;
      setState(() => _isImporting = false);
      await _showImportResultDialog(
        context,
        title: 'インポートできませんでした',
        message:
            'バックアップファイルが壊れているか、このバージョンでは'
            '対応していない形式の可能性があります。\n\n'
            '既存のデータは変更されていません。'
            '別のバックアップファイルでお試しください。',
      );
    } finally {
      if (context.mounted) setState(() => _isImporting = false);
    }
  }

  /// インポートの成否をダイアログで通知する（Issue #225）。
  ///
  /// バックアップ復元の結果は見逃すと影響が大きいため、
  /// 自動で消える SnackBar ではなくユーザーが閉じるまで残す。
  Future<void> _showImportResultDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

/// エクスポートの方法（Issue #270）。
enum _ExportMethod {
  /// 保存先を選んで端末に残す
  saveToDevice,

  /// OS の共有シートで他アプリへ送る（端末には残らない）
  share,
}
