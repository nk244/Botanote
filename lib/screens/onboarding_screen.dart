import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../providers/note_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';

/// 初回起動時に表示するオンボーディング画面（Issue #277）。
///
/// インストール直後は空の「水やりログ」画面がいきなり出るだけで、
/// 何をすればよいか分からなかった。3画面で使い方の流れを説明し、
/// 最後の画面で通知が必要な理由を示してから権限をリクエストする。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// 通知権限のリクエスト中かどうか（ボタンの二重押し防止）
  bool _isRequestingPermission = false;

  /// バックアップからの復元中かどうか（Issue #288）
  bool _isRestoring = false;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.eco,
      title: 'まずは植物を登録しましょう',
      description:
          '育てている植物を登録すると、水やり・肥料・活力剤の記録を\n'
          '1鉢ずつ管理できます。写真や購入日も残せます。',
    ),
    _OnboardingPage(
      icon: Icons.water_drop,
      title: '水やりの間隔を決めます',
      description:
          '「3日ごと」のように間隔を設定すると、次の水やり予定日を\n'
          'アプリが計算します。冬は間隔を自動で延ばすこともできます。',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active,
      title: '予定日にお知らせします',
      description:
          '水やり予定がある日だけ、決めた時刻に通知でお知らせします。\n'
          '通知から直接その日の水やりを記録することもできます。\n\n'
          'このあと通知の許可を確認します。',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastPage => _currentPage == _pages.length - 1;

  /// 通知権限リクエスト中か復元中で、操作を受け付けない状態か
  bool get _isBusy => _isRequestingPermission || _isRestoring;

  /// オンボーディングを完了させる。
  ///
  /// [requestPermission] が true の場合は通知権限をリクエストしてから閉じる。
  Future<void> _finish({required bool requestPermission}) async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);

    final settingsProvider = context.read<SettingsProvider>();
    try {
      if (requestPermission && settingsProvider.notificationEnabled) {
        final service = NotificationService();
        final granted = await service.requestPermission();
        if (granted) {
          await NotificationService.scheduleSmartWateringReminder(
            hour: settingsProvider.settings.notificationHour,
            minute: settingsProvider.settings.notificationMinute,
          );
        }
      }
    } catch (e) {
      // 権限リクエストに失敗してもオンボーディング自体は完了させる
      debugPrint('オンボーディングの通知権限リクエストに失敗しました: $e');
    }

    await settingsProvider.setOnboardingCompleted(true);
    if (mounted) setState(() => _isRequestingPermission = false);
  }

  /// バックアップZIPからデータを復元し、成功したらオンボーディングを完了する。
  ///
  /// 機種変更・再インストール直後の利用者が、設定画面まで辿り着かずに
  /// 手元のバックアップを取り込めるようにする（Issue #288）。
  Future<void> _restoreFromBackup() async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);

    try {
      final result = await ExportService().importFromFilePicker();
      if (!mounted) return;

      // ファイル選択をキャンセルした場合はオンボーディングを続ける
      if (result == null) {
        setState(() => _isRestoring = false);
        return;
      }

      // 復元したデータを各Providerに反映する
      await context.read<PlantProvider>().loadPlants();
      if (!mounted) return;
      await context.read<NoteProvider>().loadNotes();
      if (!mounted) return;
      await context.read<SensorLogProvider>().loadLogs();
      if (!mounted) return;
      await context.read<LocationProvider>().loadLocations();
      if (!mounted) return;
      if (result.settingsRestored) {
        await context.read<SettingsProvider>().loadSettings();
        if (!mounted) return;
      }

      setState(() => _isRestoring = false);

      final imageWarning = result.imageWarning;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('復元しました'),
          content: Text(
            imageWarning == null
                ? '以下のデータを復元しました。\n\n$result'
                : '以下のデータを復元しました。\n\n$result\n\n⚠ $imageWarning',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('はじめる'),
            ),
          ],
        ),
      );
      if (!mounted) return;

      // 復元できたらデータが入った状態でホームに入る。
      // 通知権限は既存データの予定に対しても必要なためリクエストする。
      await _finish(requestPermission: true);
    } catch (e) {
      debugPrint('オンボーディングからの復元に失敗しました: $e');
      if (!mounted) return;
      setState(() => _isRestoring = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('復元できませんでした'),
          content: const Text(
            'バックアップファイルが壊れているか、このバージョンでは'
            '対応していない形式の可能性があります。\n\n'
            'あとから 設定 → データ管理 でもう一度お試しください。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isBusy
                    ? null
                    : () => _finish(requestPermission: false),
                child: const Text('スキップ'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _buildPage(_pages[index]),
              ),
            ),
            // ページインジケーター
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isBusy
                      ? null
                      : () {
                          if (_isLastPage) {
                            _finish(requestPermission: true);
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_isLastPage ? 'はじめる' : '次へ'),
                ),
              ),
            ),
            // 機種変更・再インストール直後の復元導線。新規利用者の主導線を
            // 邪魔しないよう TextButton に留める（Issue #288）
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: TextButton.icon(
                onPressed: _isBusy ? null : _restoreFromBackup,
                icon: _isRestoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.settings_backup_restore, size: 18),
                label: Text(_isRestoring ? '復元しています…' : 'バックアップから復元'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(page.icon, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// オンボーディング1ページ分の内容。
class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });
}
