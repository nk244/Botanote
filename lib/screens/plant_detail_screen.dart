import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/sensor_log.dart';
import '../providers/plant_provider.dart';
import '../providers/location_provider.dart';
import '../providers/note_provider.dart';
import '../providers/sensor_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/iot_service.dart';
import '../utils/date_utils.dart';
import 'add_plant_screen.dart';
import 'add_edit_note_screen.dart';
import 'iot_settings_screen.dart';
import 'note_detail_screen.dart';
import 'plant_growth_timeline_screen.dart';

/// SliverPersistentHeaderDelegate: TabBarを固定表示するためのデリゲート
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  const _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

class PlantDetailScreen extends StatefulWidget {
  final Plant plant;
  /// 初期表示タブインデックス（0:詳細, 1:ログ, 2:ノート）
  final int initialTabIndex;

  const PlantDetailScreen({
    super.key,
    required this.plant,
    this.initialTabIndex = 0,
  });

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<LogEntry> _wateringLogs = [];
  List<LogEntry> _fertilizerLogs = [];
  List<LogEntry> _vitalizerLogs = [];
  List<LogEntry> _otherCareLogs = [];

  /// 記録専用のケアタイプ一覧（Issue #175）
  static const _otherCareTypes = [
    LogType.repotting,
    LogType.pruning,
    LogType.misting,
    LogType.cleaning,
  ];
  DateTime? _nextWateringDate;
  List<SensorLog> _sensorLogs = [];
  bool _isFetchingSensor = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadLogs();
    await _loadNextWateringDate();
    await _loadSensorLogs();
  }

  Future<void> _loadSensorLogs() async {
    final logs = await context.read<SensorLogProvider>()
        .getLogsForPlant(widget.plant.id);
    if (mounted) {
      setState(() {
        _sensorLogs = logs;
      });
    }
  }

  Future<void> _loadLogs() async {
    final provider = context.read<PlantProvider>();
    final logs = await Future.wait([
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.watering),
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.fertilizer),
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.vitalizer),
      for (final type in _otherCareTypes)
        provider.getAllLogsForPlantAndType(widget.plant.id, type),
    ]);

    if (mounted) {
      setState(() {
        _wateringLogs = logs[0];
        _fertilizerLogs = logs[1];
        _vitalizerLogs = logs[2];
        _otherCareLogs = logs.sublist(3).expand((l) => l).toList();
      });
    }
  }

  Future<void> _loadNextWateringDate() async {
    final nextDate = await context.read<PlantProvider>()
        .calculateNextWateringDate(widget.plant.id);
    if (mounted) {
      setState(() {
        _nextWateringDate = nextDate;
      });
    }
  }

  String _getLogTypeName(LogType type) {
    switch (type) {
      case LogType.watering:
        return '水やり';
      case LogType.fertilizer:
        return '肥料';
      case LogType.vitalizer:
        return '活力剤';
      case LogType.repotting:
        return '植え替え';
      case LogType.pruning:
        return '剪定';
      case LogType.misting:
        return '葉水';
      case LogType.cleaning:
        return '掃除';
    }
  }

  /// 画像背景上でも見やすいアクションボタンを生成する（半透明の丸背景付き）
  Widget _buildImageOverlayAction(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: IconButton(
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
          iconSize: 22,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ),
    );
  }

  Future<void> _deletePlant() async {
    // async ギャップ前に context 依存の参照を取得しておく
    final plantProvider = context.read<PlantProvider>();
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        // ノートは削除せず紐付けを解除するだけなので、実挙動どおりに説明する（Issue #224）
        content: Text('「${widget.plant.name}」を削除してもよろしいですか？\n'
            'すべてのケアログも削除されます。\n'
            'ノートは残りますが、この植物との紐付けは解除されます。'),
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
      await plantProvider.deletePlant(widget.plant.id);
      if (!context.mounted) return;
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // TabBar ウィジェット（SliverPersistentHeader に渡す）
    final tabBar = TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: '情報'),
        Tab(text: 'ログ'),
        Tab(text: 'ノート'),
        Tab(text: '環境'),
      ],
    );

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // 植物画像を背景に持つ SliverAppBar
          SliverAppBar(
            expandedHeight: widget.plant.imagePath != null ? 260.0 : 160.0,
            pinned: true,
            floating: false,
            forceElevated: innerBoxIsScrolled,
            actions: [
              if (widget.plant.imagePath != null)
                _buildImageOverlayAction(
                    Icons.auto_awesome_motion, _navigateToGrowthTimeline)
              else
                IconButton(
                  icon: const Icon(Icons.auto_awesome_motion),
                  tooltip: '成長タイムライン',
                  onPressed: _navigateToGrowthTimeline,
                ),
              if (widget.plant.imagePath != null)
                _buildImageOverlayAction(Icons.edit, _navigateToEdit)
              else
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _navigateToEdit,
                ),
              if (widget.plant.imagePath != null)
                _buildImageOverlayAction(Icons.delete, _deletePlant)
              else
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deletePlant,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 16,
                end: 16,
              ),
              // 編集・削除ボタンと同じく半透明黒背景を付けて画像に関わらず視認性を確保
              title: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    widget.plant.name,
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              background: _buildHeaderBackground(context),
              collapseMode: CollapseMode.parallax,
            ),
          ),
          // TabBar をスクロール後も固定表示する SliverPersistentHeader
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(tabBar),
          ),
        ],
        // TabBarView を NestedScrollView の body に配置
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildInfoTab(),
            _buildUnifiedLogTab(),
            _buildNoteTab(),
            _buildEnvironmentTab(),
          ],
        ),
      ),
      // FAB は不要のため削除 (#69)
    );
  }

  /// SliverAppBar の背景ウィジェットを構築する
  Widget _buildHeaderBackground(BuildContext context) {
    if (widget.plant.imagePath != null) {
      // 画像あり: 植物画像を全画面背景として表示
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildFullImage(),
          // 下部にグラデーション（タイトル文字の視認性向上）
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.3, 1.0],
              ),
            ),
          ),
        ],
      );
    } else {
      // 画像なし: テーマカラーのグラデーションを表示
      final colorScheme = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.eco,
            size: 72,
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
          ),
        ),
      );
    }
  }

  /// 植物画像を表示する
  Widget _buildFullImage() {
    final path = widget.plant.imagePath!;

    // Base64 data URL の場合はメモリから表示する（レガシーデータ互換）
    if (path.startsWith('data:')) {
      try {
        final comma = path.indexOf(',');
        if (comma >= 0) {
          final bytes = base64Decode(path.substring(comma + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildBrokenImageIcon(context),
          );
        }
      } catch (_) {
        return _buildBrokenImageIcon(context);
      }
    }

    if (File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
      );
    } else {
      return _buildBrokenImageIcon(context);
    }
  }

  Widget _buildBrokenImageIcon(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image,
        size: 64,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _navigateToEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddPlantScreen(plant: widget.plant),
      ),
    );
    // 編集後は前の画面にデータ変更があったことを通知する
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  /// 成長タイムライン画面へ遷移する（Issue #179）。
  void _navigateToGrowthTimeline() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlantGrowthTimelineScreen(plant: widget.plant),
      ),
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBasicInfoCard(),
        const SizedBox(height: 16),
        _buildWateringInfoCard(),
        if (widget.plant.fertilizerIntervalDays != null ||
            widget.plant.fertilizerEveryNWaterings != null ||
            widget.plant.vitalizerIntervalDays != null ||
            widget.plant.vitalizerEveryNWaterings != null) ...[
          const SizedBox(height: 16),
          _buildFertilizerInfoCard(),
        ],
      ],
    );
  }

  Widget _buildBasicInfoCard() {
    return _InfoCard(
      title: '基本情報',
      children: [
        _InfoRow(label: '植物名', value: widget.plant.name),
        if (widget.plant.variety != null)
          _InfoRow(label: '品種名', value: widget.plant.variety!),
        if (widget.plant.purchaseDate != null)
          _InfoRow(
            label: '購入日',
            value: DateFormat('yyyy年MM月dd日').format(widget.plant.purchaseDate!),
          ),
        if (widget.plant.purchaseLocation != null)
          _InfoRow(label: '購入先', value: widget.plant.purchaseLocation!),
        // 登録・編集画面で設定した置き場所を確認できるようにする（Issue #215）
        if (_locationName != null)
          _InfoRow(label: '置き場所', value: _locationName!),
        if (widget.plant.isOutdoor) const _InfoRow(label: '設置', value: '屋外'),
      ],
    );
  }

  /// 植物に紐づく置き場所の名前を返す。未設定・削除済みの場合は null。
  String? get _locationName {
    final locationId = widget.plant.locationId;
    if (locationId == null) return null;
    final locations = context.watch<LocationProvider>().locations;
    for (final location in locations) {
      if (location.id == locationId) return location.name;
    }
    return null;
  }

  Widget _buildWateringInfoCard() {
    return _InfoCard(
      title: '水やり情報',
      children: [
        if (widget.plant.wateringIntervalDays != null)
          _InfoRow(
            label: '間隔',
            value: '${widget.plant.wateringIntervalDays}日ごと',
          ),
        if (_nextWateringDate != null)
          _InfoRow(
            label: '次回予定',
            value: AppDateUtils.formatRelativeDate(_nextWateringDate!),
            valueColor: _nextWateringDate!.isBefore(DateTime.now())
                ? Theme.of(context).colorScheme.error
                : null,
          ),
      ],
    );
  }

  Widget _buildFertilizerInfoCard() {
    String intervalText(int? days, int? everyN) {
      if (days != null) return '$days日ごと';
      if (everyN != null) return '水やり$everyN回に1回';
      return '未設定';
    }

    return _InfoCard(
      title: '施肥情報',
      children: [
        if (widget.plant.fertilizerIntervalDays != null ||
            widget.plant.fertilizerEveryNWaterings != null)
          _InfoRow(
            label: '肥料間隔',
            value: intervalText(
                widget.plant.fertilizerIntervalDays,
                widget.plant.fertilizerEveryNWaterings),
          ),
        if (widget.plant.vitalizerIntervalDays != null ||
            widget.plant.vitalizerEveryNWaterings != null)
          _InfoRow(
            label: '活力剤間隔',
            value: intervalText(
                widget.plant.vitalizerIntervalDays,
                widget.plant.vitalizerEveryNWaterings),
          ),
      ],
    );
  }

  Widget _buildUnifiedLogTab() {
    // 全ログを日付降順でマージ
    final allLogs = [
      ..._wateringLogs,
      ..._fertilizerLogs,
      ..._vitalizerLogs,
      ..._otherCareLogs,
    ]..sort((a, b) => b.date.compareTo(a.date));

    final recordCareButton = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _showRecordCareDialog,
          icon: const Icon(Icons.add),
          label: const Text('その他のケアを記録'),
        ),
      ),
    );

    if (allLogs.isEmpty) {
      return Column(
        children: [
          recordCareButton,
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'まだログがありません',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '「記録」ボタンから水やり・肝料・活力剤を記録できます',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 同日のログをグループ化（日付降順）
    final groupedByDate = <DateTime, List<LogEntry>>{};
    for (final log in allLogs) {
      final day = DateTime(log.date.year, log.date.month, log.date.day);
      groupedByDate.putIfAbsent(day, () => []).add(log);
    }
    final sortedDays = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedDays.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return recordCareButton;
        final day = sortedDays[index - 1];
        final logs = groupedByDate[day]!;
        return _buildGroupedLogRow(day, logs);
      },
    );
  }

  /// 「その他のケアを記録」ダイアログを表示し、選択結果を保存する（Issue #175）。
  Future<void> _showRecordCareDialog() async {
    // async ギャップ前に context 依存の参照を取得しておく
    final plantProvider = context.read<PlantProvider>();

    final result = await showDialog<_CareLogResult>(
      context: context,
      builder: (context) => const _RecordCareDialog(),
    );
    if (result == null) return;

    try {
      await plantProvider.recordCareLog(
        widget.plant.id,
        result.type,
        result.date,
        result.note,
      );
      if (mounted) await _loadLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('記録に失敗しました: $e')),
        );
      }
    }
  }

  Widget _buildNoteTab() {
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, _) {
        final plantNotes = noteProvider.notes
            .where((n) => n.plantIds.contains(widget.plant.id))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (plantNotes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.note_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'まだノートがありません',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddEditNoteScreen(
                        initialPlantId: widget.plant.id,
                      ),
                    ),
                  ).then((_) {
                    if (context.mounted) context.read<NoteProvider>().loadNotes();
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('ノートを追加'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: plantNotes.length,
          itemBuilder: (context, index) {
            final note = plantNotes[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.note),
                title: Text(note.title),
                subtitle: Text(
                  DateFormat('yyyy年MM月dd日').format(note.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteDetailScreen(note: note),
                  ),
                ).then((_) {
                  if (context.mounted) context.read<NoteProvider>().loadNotes();
                }),
              ),
            );
          },
        );
      },
    );
  }

  // ── 環境タブ ─────────────────────────────────────────────────

  Widget _buildEnvironmentTab() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final hasNatureRemo =
            settings.settings.natureRemoToken.isNotEmpty;
        final hasSwitchBot =
            settings.settings.switchBotToken.isNotEmpty &&
                settings.settings.switchBotSecret.isNotEmpty;
        final hasAnyIot = hasNatureRemo || hasSwitchBot;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildLatestSensorCard(),
            const SizedBox(height: 16),
            if (!hasAnyIot)
              _buildIotSetupPrompt()
            else ...[
              if (hasNatureRemo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _isFetchingSensor
                        ? null
                        : () => _startFetchFlow(SensorSource.natureRemo),
                    icon: _isFetchingSensor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sensors),
                    label: const Text('Nature Remo からデータ取得'),
                  ),
                ),
              if (hasSwitchBot)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _isFetchingSensor
                        ? null
                        : () => _startFetchFlow(SensorSource.switchBot),
                    icon: _isFetchingSensor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sensors),
                    label: const Text('SwitchBot からデータ取得'),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            if (_sensorLogs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.thermostat_outlined,
                        size: 48,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'センサー記録がありません',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                '記録履歴',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._sensorLogs.map(_buildSensorLogTile),
            ],
          ],
        );
      },
    );
  }

  /// 最新センサー値カード（温度・湿度を大きく表示）
  Widget _buildLatestSensorCard() {
    final latest = _sensorLogs.isNotEmpty ? _sensorLogs.first : null;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最新の環境データ',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(Icons.thermostat, size: 36,
                          color: colorScheme.primary),
                      const SizedBox(height: 4),
                      Text(
                        latest?.temperature != null
                            ? '${latest!.temperature!.toStringAsFixed(1)} ℃'
                            : '--',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('気温',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Icon(Icons.water_drop, size: 36,
                          color: colorScheme.primary),
                      const SizedBox(height: 4),
                      Text(
                        latest?.humidity != null
                            ? '${latest!.humidity!.toStringAsFixed(0)} %'
                            : '--',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('湿度',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 12),
              Text(
                '${latest.deviceName}  '
                '${DateFormat('MM月dd日 HH:mm').format(latest.recordedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// センサー未設定時の案内カード
  Widget _buildIotSetupPrompt() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.sensors_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'センサーが設定されていません',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const IotSettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.settings),
              label: const Text('センサー設定を開く'),
            ),
          ],
        ),
      ),
    );
  }

  /// センサーログ1件のリストタイル
  Widget _buildSensorLogTile(SensorLog log) {
    final parts = [
      if (log.temperature != null)
        '${log.temperature!.toStringAsFixed(1)} ℃',
      if (log.humidity != null)
        '${log.humidity!.toStringAsFixed(0)} %',
    ];
    final sourceLabel =
        log.source == SensorSource.natureRemo ? 'Nature Remo' : 'SwitchBot';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: const Icon(Icons.thermostat),
        title: Text(parts.join('   ')),
        subtitle: Text(
          '${log.deviceName}  ($sourceLabel)\n'
          '${DateFormat('MM月dd日 HH:mm').format(log.recordedAt)}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '削除',
          onPressed: () => _deleteSensorLog(log),
        ),
      ),
    );
  }

  /// センサーログを削除する（長押し操作）
  Future<void> _deleteSensorLog(SensorLog log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('記録を削除'),
        content: Text(
          '${DateFormat('yyyy年MM月dd日 HH:mm').format(log.recordedAt)} の'
          '記録を削除しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await context.read<SensorLogProvider>().deleteSensorLog(log.id); // ignore: use_build_context_synchronously
    await _loadSensorLogs();
  }

  /// IoTサービスからデータを取得してこの植物に紐付けて保存するフロー。
  ///
  /// マッピング設定に現在の植物が含まれているデバイスがある場合は
  /// そのデバイスを自動選択し、ない場合はデバイス選択ダイアログを表示する。
  Future<void> _startFetchFlow(SensorSource source) async {
    final settingsProvider = context.read<SettingsProvider>();
    final sensorProvider = context.read<SensorLogProvider>();
    final settings = settingsProvider.settings;

    setState(() {
      _isFetchingSensor = true;
    });

    try {
      // マッピング設定でこの植物に紐づくデバイスを検索
      final mappedDevice = settings.sensorDeviceMappings.where(
        (m) => m.source == source && m.plantIds.contains(widget.plant.id),
      ).firstOrNull;

      final List<SensorData> devices;
      if (source == SensorSource.natureRemo) {
        devices = await sensorProvider.fetchNatureRemoData(
            settings.natureRemoToken);
      } else {
        devices = await sensorProvider.fetchSwitchBotData(
            settings.switchBotToken, settings.switchBotSecret);
      }

      if (!mounted) return;

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('センサーデバイスが見つかりませんでした')),
        );
        return;
      }

      // マッピング済みデバイスがある場合は自動選択
      final SensorData selected;
      if (mappedDevice != null) {
        final found = devices.where(
          (d) => d.deviceId == mappedDevice.deviceId,
        ).firstOrNull;
        if (found != null) {
          selected = found;
        } else {
          // マッピングされたデバイスが取得結果に存在しない場合は手動選択にフォールバック
          if (devices.length == 1) {
            selected = devices.first;
          } else {
            final picked = await _showDevicePickerDialog(devices);
            if (!mounted || picked == null) return;
            selected = picked;
          }
        }
      } else if (devices.length == 1) {
        selected = devices.first;
      } else {
        final picked = await _showDevicePickerDialog(devices);
        if (!mounted || picked == null) return;
        selected = picked;
      }

      await sensorProvider.saveSensorLog( // ignore: use_build_context_synchronously
        data: selected,
        source: source,
        plantId: widget.plant.id,
      );

      if (!mounted) return;
      await _loadSensorLogs();

      ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
        SnackBar(content: Text('${selected.deviceName} のデータを記録しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得エラー: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSensor = false;
        });
      }
    }
  }

  /// 複数デバイスがある場合の選択ダイアログ
  Future<SensorData?> _showDevicePickerDialog(
      List<SensorData> devices) async {
    return showDialog<SensorData>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('デバイスを選択'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: devices
                .map(
                  (d) => ListTile(
                    title: Text(d.deviceName),
                    subtitle: Text([
                      if (d.temperature != null)
                        '${d.temperature!.toStringAsFixed(1)} ℃',
                      if (d.humidity != null)
                        '${d.humidity!.toStringAsFixed(0)} %',
                    ].join('   ')),
                    onTap: () => Navigator.of(ctx).pop(d),
                  ),
                )
                .toList(),
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

  Widget _buildGroupedLogRow(DateTime day, List<LogEntry> logs) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(
              DateFormat('yyyy年MM月dd日').format(day),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: logs.map((log) {
                  return Tooltip(
                    message: log.note ?? _getLogTypeName(log.type),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getIconForLogType(log.type),
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _getLogTypeName(log.type),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '${DateFormat('M月d日').format(day)}の記録を削除',
              onPressed: () => _deleteLogsForDay(day, logs),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLogsForDay(DateTime day, List<LogEntry> logs) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除'),
        content: Text(
            '${DateFormat('yyyy年MM月dd日').format(day)}の記録（${logs.length}件）を削除しますか？'),
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
      for (final log in logs) {
        await context.read<PlantProvider>().deleteLog(log.id); // ignore: use_build_context_synchronously
      }
      await _loadData();
      // ログ削除後は前の画面にデータ変更を通知（pop は行わない）
      // pop(true) は _navigateToEdit のみ（画面を閉じる操作）で行う
    }
  }

  IconData _getIconForLogType(LogType type) {
    switch (type) {
      case LogType.watering:
        return Icons.water_drop;
      case LogType.fertilizer:
        return Icons.grass;
      case LogType.vitalizer:
        return Icons.favorite;
      case LogType.repotting:
        return Icons.yard;
      case LogType.pruning:
        return Icons.content_cut;
      case LogType.misting:
        return Icons.grain;
      case LogType.cleaning:
        return Icons.cleaning_services;
    }
  }
}

/// 「その他のケアを記録」ダイアログの選択結果（Issue #175）
class _CareLogResult {
  final LogType type;
  final DateTime date;
  final String? note;

  const _CareLogResult({required this.type, required this.date, this.note});
}

/// 記録専用のケアタイプ（植え替え・剪定・葉水・掃除）を選択して記録するダイアログ。
class _RecordCareDialog extends StatefulWidget {
  const _RecordCareDialog();

  @override
  State<_RecordCareDialog> createState() => _RecordCareDialogState();
}

class _RecordCareDialogState extends State<_RecordCareDialog> {
  static const _choices = [
    (type: LogType.repotting, label: '植え替え', icon: Icons.yard),
    (type: LogType.pruning, label: '剪定', icon: Icons.content_cut),
    (type: LogType.misting, label: '葉水', icon: Icons.grain),
    (type: LogType.cleaning, label: '掃除', icon: Icons.cleaning_services),
  ];

  LogType _selectedType = LogType.repotting;
  DateTime _selectedDate = DateTime.now();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('その他のケアを記録'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _choices.map((choice) {
                return ChoiceChip(
                  label: Text(choice.label),
                  avatar: Icon(choice.icon, size: 18),
                  selected: _selectedType == choice.type,
                  onSelected: (_) {
                    setState(() => _selectedType = choice.type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('日付'),
              subtitle: Text(DateFormat('yyyy年MM月dd日').format(_selectedDate)),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'メモ（任意）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_CareLogResult(
              type: _selectedType,
              date: _selectedDate,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ));
          },
          child: const Text('記録'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

