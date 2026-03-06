import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../providers/plant_provider.dart';
import '../providers/note_provider.dart';
import '../utils/date_utils.dart';
import 'add_plant_screen.dart';
import 'add_edit_note_screen.dart';
import 'note_detail_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  DateTime? _nextWateringDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
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
  }

  Future<void> _loadLogs() async {
    final provider = context.read<PlantProvider>();
    final logs = await Future.wait([
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.watering),
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.fertilizer),
      provider.getAllLogsForPlantAndType(widget.plant.id, LogType.vitalizer),
    ]);
    
    if (mounted) {
      setState(() {
        _wateringLogs = logs[0];
        _fertilizerLogs = logs[1];
        _vitalizerLogs = logs[2];
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text('「${widget.plant.name}」を削除してもよろしいですか？\nすべてのログとノートも削除されます。'),
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
      await context.read<PlantProvider>().deletePlant(widget.plant.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
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
              title: Text(
                widget.plant.name,
                style: widget.plant.imagePath != null
                    // 画像あり: 暗いグラデーション背景なので白字＋影で視認性を確保
                    ? const TextStyle(
                        shadows: [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 8,
                            color: Colors.black87,
                          ),
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 4,
                            color: Colors.black54,
                          ),
                        ],
                      )
                    // 画像なし: 明るいグラデーション背景なのでテーマ色を使う
                    : TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        shadows: null,
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

  /// 植物画像をWebとモバイルで出し分けて表示する
  Widget _buildFullImage() {
    if (kIsWeb) {
      return Image.network(
        widget.plant.imagePath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildBrokenImageIcon(context),
      );
    } else {
      if (File(widget.plant.imagePath!).existsSync()) {
        return Image.file(
          File(widget.plant.imagePath!),
          fit: BoxFit.cover,
        );
      } else {
        return _buildBrokenImageIcon(context);
      }
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
      ],
    );
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
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (allLogs.isEmpty) {
      return Center(
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
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final logs = groupedByDate[day]!;
        return _buildGroupedLogRow(day, logs);
      },
    );
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
                  ).then((_) => context.read<NoteProvider>().loadNotes()),
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
                ).then((_) => context.read<NoteProvider>().loadNotes()),
              ),
            );
          },
        );
      },
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
    }
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

