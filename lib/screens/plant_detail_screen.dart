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
import '../utils/seasonal_interval_utils.dart';
import 'add_plant_screen.dart';
import 'add_edit_note_screen.dart';
import 'iot_settings_screen.dart';
import 'light_meter_screen.dart';
import 'note_detail_screen.dart';
import 'plant_growth_timeline_screen.dart';
import '../utils/error_utils.dart';

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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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

/// ログタブの種別フィルタ（Issue #325）。
enum _LogTabFilter {
  all,
  watering,
  fertilizer,
  vitalizer,

  /// 植え替え・剪定・葉水・掃除（記録専用のケア種別）
  other;

  /// この絞り込みが [type] を含むかどうか。
  bool matches(LogType type) {
    switch (this) {
      case _LogTabFilter.all:
        return true;
      case _LogTabFilter.watering:
        return type == LogType.watering;
      case _LogTabFilter.fertilizer:
        return type == LogType.fertilizer;
      case _LogTabFilter.vitalizer:
        return type == LogType.vitalizer;
      case _LogTabFilter.other:
        return type != LogType.watering &&
            type != LogType.fertilizer &&
            type != LogType.vitalizer;
    }
  }
}

class _PlantDetailScreenState extends State<PlantDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// ログタブで選択中の種別フィルタ（Issue #325）
  _LogTabFilter _logFilter = _LogTabFilter.all;

  /// 表示中の植物。編集画面から戻った際に最新の内容へ差し替える（Issue #243）。
  late Plant _plant;

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

  /// 肥料・活力剤の次回予定日（「次のケア」カード用。Issue #294）
  DateTime? _nextFertilizerDate;
  DateTime? _nextVitalizerDate;
  List<SensorLog> _sensorLogs = [];
  bool _isFetchingSensor = false;

  @override
  void initState() {
    super.initState();
    _plant = widget.plant;
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
    final logs = await context.read<SensorLogProvider>().getLogsForPlant(
      _plant.id,
    );
    if (mounted) {
      setState(() {
        _sensorLogs = logs;
      });
    }
  }

  Future<void> _loadLogs() async {
    final provider = context.read<PlantProvider>();
    final logs = await Future.wait([
      provider.getAllLogsForPlantAndType(_plant.id, LogType.watering),
      provider.getAllLogsForPlantAndType(_plant.id, LogType.fertilizer),
      provider.getAllLogsForPlantAndType(_plant.id, LogType.vitalizer),
      for (final type in _otherCareTypes)
        provider.getAllLogsForPlantAndType(_plant.id, type),
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
    final provider = context.read<PlantProvider>();
    final dates = await Future.wait([
      provider.calculateNextWateringDate(_plant.id),
      provider.calculateNextFertilizerDate(_plant.id),
      provider.calculateNextVitalizerDate(_plant.id),
    ]);
    if (mounted) {
      setState(() {
        _nextWateringDate = dates[0];
        _nextFertilizerDate = dates[1];
        _nextVitalizerDate = dates[2];
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
  ///
  /// [tooltip] はスクリーンリーダーの読み上げにも使われるため必須とする（Issue #282）。
  Widget _buildImageOverlayAction(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: IconButton(
          icon: Icon(icon, color: Colors.white),
          tooltip: tooltip,
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
        content: Text(
          '「${_plant.name}」を削除してもよろしいですか？\n'
          'すべてのケアログも削除されます。\n'
          'ノートは残りますが、この植物との紐付けは解除されます。',
        ),
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
      await plantProvider.deletePlant(_plant.id);
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
            expandedHeight: _plant.imagePath != null ? 260.0 : 160.0,
            pinned: true,
            floating: false,
            forceElevated: innerBoxIsScrolled,
            actions: [
              if (_plant.imagePath != null)
                _buildImageOverlayAction(
                  Icons.auto_awesome_motion,
                  '成長タイムライン',
                  _navigateToGrowthTimeline,
                )
              else
                IconButton(
                  icon: const Icon(Icons.auto_awesome_motion),
                  tooltip: '成長タイムライン',
                  onPressed: _navigateToGrowthTimeline,
                ),
              if (_plant.imagePath != null)
                _buildImageOverlayAction(Icons.edit, '編集', _navigateToEdit)
              else
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '編集',
                  onPressed: _navigateToEdit,
                ),
              if (_plant.imagePath != null)
                _buildImageOverlayAction(Icons.delete, '削除', _deletePlant)
              else
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: '削除',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    _plant.name,
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
    if (_plant.imagePath != null) {
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
    final path = _plant.imagePath!;

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
      return Image.file(File(path), fit: BoxFit.cover);
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => AddPlantScreen(plant: _plant)),
    );
    if (!mounted) return;
    // キャンセル時は何もしない（この画面に留まる）
    if (saved != true) return;

    // 保存された場合は最新の内容へ差し替えて再読み込みする。
    // 一覧側は PlantProvider を watch しているため自動的に更新される。
    final plantProvider = context.read<PlantProvider>();
    final updated = plantProvider.plants
        .where((p) => p.id == _plant.id)
        .firstOrNull;
    setState(() {
      if (updated != null) _plant = updated;
    });
    await _loadData();
  }

  /// 成長タイムライン画面へ遷移する（Issue #179）。
  void _navigateToGrowthTimeline() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlantGrowthTimelineScreen(plant: _plant),
      ),
    );
  }

  Widget _buildInfoTab() {
    final nextCareCard = _buildNextCareCard();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // まず「次に何をすればよいか」を出す（Issue #294）
        if (nextCareCard != null) ...[nextCareCard, const SizedBox(height: 16)],
        _buildBasicInfoCard(),
        // 水やり間隔も次回予定も無い場合は見出しだけの空カードになるため表示しない
        if (_plant.wateringIntervalDays != null ||
            _nextWateringDate != null) ...[
          const SizedBox(height: 16),
          _buildWateringInfoCard(),
        ],
        if (_plant.fertilizerIntervalDays != null ||
            _plant.fertilizerEveryNWaterings != null ||
            _plant.vitalizerIntervalDays != null ||
            _plant.vitalizerEveryNWaterings != null) ...[
          const SizedBox(height: 16),
          _buildFertilizerInfoCard(),
        ],
      ],
    );
  }

  /// 「次のケア」カード（Issue #294）。
  ///
  /// 水やり・肥料・活力剤の予定を1行ずつ並べ、遅れている行は error 色で強調して
  /// 同じ行から記録できるようにする。予定が1つも無ければ null を返す。
  Widget? _buildNextCareCard() {
    final entries = <(LogType, DateTime)>[
      if (_nextWateringDate != null) (LogType.watering, _nextWateringDate!),
      if (_nextFertilizerDate != null)
        (LogType.fertilizer, _nextFertilizerDate!),
      if (_nextVitalizerDate != null) (LogType.vitalizer, _nextVitalizerDate!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    if (entries.isEmpty) return null;

    return _InfoCard(
      title: '次のケア',
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const Divider(height: 16),
          _buildNextCareRow(entries[i].$1, entries[i].$2),
        ],
      ],
    );
  }

  Widget _buildNextCareRow(LogType logType, DateTime nextDate) {
    final scheme = Theme.of(context).colorScheme;
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final due = AppDateUtils.getDateOnly(nextDate);
    final isDue = !due.isAfter(today);
    final isOverdue = due.isBefore(today);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOverdue
                  ? scheme.errorContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getLogTypeIcon(logType),
              size: 22,
              color: isOverdue
                  ? scheme.onErrorContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getLogTypeName(logType)} ${AppDateUtils.formatDateDifference(nextDate)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isOverdue ? scheme.error : null,
                    fontWeight: isOverdue ? FontWeight.bold : null,
                  ),
                ),
                Text(
                  '予定 ${DateFormat('M月d日（E）', 'ja').format(nextDate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 予定日を迎えているものは塗りつぶし、まだ先のものは輪郭ボタンにする
          if (isDue)
            FilledButton(
              onPressed: () => _recordCareNow(logType),
              child: const Text('記録'),
            )
          else
            OutlinedButton(
              onPressed: () => _recordCareNow(logType),
              child: const Text('記録'),
            ),
        ],
      ),
    );
  }

  IconData _getLogTypeIcon(LogType type) {
    switch (type) {
      case LogType.fertilizer:
        return Icons.grass;
      case LogType.vitalizer:
        return Icons.favorite;
      default:
        return Icons.water_drop;
    }
  }

  /// 「次のケア」カードから今日の記録を1件つける（Issue #294）。
  Future<void> _recordCareNow(LogType logType) async {
    final plantProvider = context.read<PlantProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await plantProvider.bulkRecordLogs(
        [_plant.id],
        [logType],
        DateTime.now(),
      );
      if (!mounted) return;
      await _loadData();
      messenger.showSnackBar(
        SnackBar(content: Text('${_getLogTypeName(logType)}を記録しました')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('記録に失敗しました: ${describeError(e)}')),
      );
    }
  }

  Widget _buildBasicInfoCard() {
    return _InfoCard(
      title: '基本情報',
      children: [
        _InfoRow(label: '植物名', value: _plant.name),
        if (_plant.variety != null)
          _InfoRow(label: '品種名', value: _plant.variety!),
        if (_plant.purchaseDate != null)
          _InfoRow(
            label: '購入日',
            value: DateFormat('yyyy年MM月dd日').format(_plant.purchaseDate!),
          ),
        if (_plant.purchaseLocation != null)
          _InfoRow(label: '購入先', value: _plant.purchaseLocation!),
        // 登録・編集画面で設定した置き場所を確認できるようにする（Issue #215）
        if (_locationName != null)
          _InfoRow(label: '置き場所', value: _locationName!),
        if (_plant.isOutdoor) const _InfoRow(label: '設置', value: '屋外'),
      ],
    );
  }

  /// 植物に紐づく置き場所の名前を返す。未設定・削除済みの場合は null。
  String? get _locationName {
    final locationId = _plant.locationId;
    if (locationId == null) return null;
    final locations = context.watch<LocationProvider>().locations;
    for (final location in locations) {
      if (location.id == locationId) return location.name;
    }
    return null;
  }

  /// 次回予定日の起算日（最終水やり日。ログが無ければ購入日または登録日）。
  ///
  /// 季節調整が効いているかの判定に使うため、`PlantProvider` の
  /// `calcNextWateringDateFromLogs` と同じ基準で求める。
  DateTime get _wateringBaseDate {
    if (_wateringLogs.isEmpty) {
      return _plant.purchaseDate ?? _plant.createdAt;
    }
    final sorted = [..._wateringLogs]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.first.date;
  }

  /// 季節調整を反映した実効の水やり間隔（日数）。
  int? get _effectiveWateringIntervalDays {
    final base = _plant.wateringIntervalDays;
    if (base == null) return null;
    return applySeasonalAdjustment(
      baseIntervalDays: base,
      seasonalAdjustmentEnabled: _plant.seasonalAdjustmentEnabled,
      dormantMultiplier: _plant.dormantSeasonIntervalMultiplier,
      referenceDate: _wateringBaseDate,
    );
  }

  Widget _buildWateringInfoCard() {
    final base = _plant.wateringIntervalDays;
    final effective = _effectiveWateringIntervalDays;
    // 休眠期は間隔が延長されるため、素の間隔だけを出すと
    // 「14日ごと」なのに次回が28日後、という矛盾に見える（Issue #255）
    final isExtended = base != null && effective != null && effective != base;

    return _InfoCard(
      title: '水やり情報',
      children: [
        if (base != null)
          _InfoRow(
            label: '間隔',
            value: isExtended ? '$effective日ごと' : '$base日ごと',
          ),
        if (isExtended)
          _InfoRow(label: '季節調整', value: '休眠期のため $base日 → $effective日'),
        // 現在延長中でなくても設定内容が分かるようにする（Issue #279）
        if (!isExtended)
          _InfoRow(label: '冬季の延長', value: _seasonalAdjustmentDescription(base)),
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

  /// 「冬季は間隔を延長する」設定の内容を人が読める文言にする（Issue #279）。
  ///
  /// [baseIntervalDays] が分かる場合は延長後の日数も添える。
  String _seasonalAdjustmentDescription(int? baseIntervalDays) {
    final multiplier = _plant.dormantSeasonIntervalMultiplier;
    if (!_plant.seasonalAdjustmentEnabled || multiplier == null) {
      return 'しない';
    }
    final months = dormantSeasonMonths.toList()..sort();
    // 12・1・2月を「12〜2月」と読みやすく表記する
    final monthsLabel = months.contains(12) && months.contains(1)
        ? '12〜${months.where((m) => m != 12).reduce((a, b) => a > b ? a : b)}月'
        : '${months.join('・')}月';
    final multiplierLabel = multiplier == multiplier.roundToDouble()
        ? '${multiplier.round()}'
        : '$multiplier';

    if (baseIntervalDays == null) {
      return '$monthsLabel は間隔を$multiplierLabel倍にする';
    }
    final extended = (baseIntervalDays * multiplier).round();
    return '$monthsLabel は $baseIntervalDays日 → $extended日（$multiplierLabel倍）';
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
        if (_plant.fertilizerIntervalDays != null ||
            _plant.fertilizerEveryNWaterings != null)
          _InfoRow(
            label: '肥料間隔',
            value: intervalText(
              _plant.fertilizerIntervalDays,
              _plant.fertilizerEveryNWaterings,
            ),
          ),
        if (_plant.vitalizerIntervalDays != null ||
            _plant.vitalizerEveryNWaterings != null)
          _InfoRow(
            label: '活力剤間隔',
            value: intervalText(
              _plant.vitalizerIntervalDays,
              _plant.vitalizerEveryNWaterings,
            ),
          ),
      ],
    );
  }

  /// ログタブの種別フィルタ（Issue #325）。
  ///
  /// 2年以上使うと1鉢あたり200件を超え、件数の大半を占める水やりに
  /// 埋もれて「去年の植え替えはいつか」を探せなくなるため。
  Widget _buildLogTypeFilterChips() {
    Widget chip(String label, _LogTabFilter value) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _logFilter == value,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _logFilter = value),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          chip('すべて', _LogTabFilter.all),
          chip('水やり', _LogTabFilter.watering),
          chip('肥料', _LogTabFilter.fertilizer),
          chip('活力剤', _LogTabFilter.vitalizer),
          chip('その他', _LogTabFilter.other),
        ],
      ),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'まだログがありません',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // 実際の導線に合わせた案内にする（Issue #269）
                  Text(
                    '「その他のケアを記録」から植え替え・剪定・葉水・掃除を記録できます。\n'
                    '水やり・肥料・活力剤は「水やりログ」タブから記録します。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 種別で絞り込む（Issue #325）
    final filteredLogs = allLogs
        .where((log) => _logFilter.matches(log.type))
        .toList();

    // 同日のログをグループ化（日付降順）
    final groupedByDate = <DateTime, List<LogEntry>>{};
    for (final log in filteredLogs) {
      final day = DateTime(log.date.year, log.date.month, log.date.day);
      groupedByDate.putIfAbsent(day, () => []).add(log);
    }
    final sortedDays = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // 年月の見出しを挟んで、長いログでも時期の当たりを付けられるようにする
    // （Issue #325）。日付行だけを何百件も並べると遡りようがない。
    final rows = <Widget>[];
    DateTime? currentMonth;
    for (final day in sortedDays) {
      final month = DateTime(day.year, day.month);
      if (currentMonth != month) {
        currentMonth = month;
        rows.add(_buildLogMonthHeader(month, groupedByDate, sortedDays));
      }
      rows.add(_buildGroupedLogRow(day, groupedByDate[day]!));
    }

    return Column(
      children: [
        recordCareButton,
        _buildLogTypeFilterChips(),
        if (rows.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'この種別の記録はありません',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: rows.length,
              itemBuilder: (context, index) => rows[index],
            ),
          ),
      ],
    );
  }

  /// ログタブの年月見出し（Issue #325）。その月の件数も添える。
  Widget _buildLogMonthHeader(
    DateTime month,
    Map<DateTime, List<LogEntry>> groupedByDate,
    List<DateTime> sortedDays,
  ) {
    final count = sortedDays
        .where((d) => d.year == month.year && d.month == month.month)
        .fold<int>(0, (sum, d) => sum + groupedByDate[d]!.length);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Row(
        children: [
          Text(
            '${month.year}年${month.month}月',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count件',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
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
        _plant.id,
        result.type,
        result.date,
        result.note,
      );
      if (mounted) await _loadLogs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('記録に失敗しました: ${describeError(e)}')),
        );
      }
    }
  }

  Widget _buildNoteTab() {
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, _) {
        final plantNotes =
            noteProvider.notes
                .where((n) => n.plantIds.contains(_plant.id))
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
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'まだノートがありません',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AddEditNoteScreen(initialPlantId: _plant.id),
                        ),
                      )
                      .then((_) {
                        if (context.mounted)
                          context.read<NoteProvider>().loadNotes();
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
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => NoteDetailScreen(note: note),
                      ),
                    )
                    .then((_) {
                      if (context.mounted)
                        context.read<NoteProvider>().loadNotes();
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
        final hasNatureRemo = settings.settings.natureRemoToken.isNotEmpty;
        final hasSwitchBot =
            settings.settings.switchBotToken.isNotEmpty &&
            settings.settings.switchBotSecret.isNotEmpty;
        final hasAnyIot = hasNatureRemo || hasSwitchBot;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildLatestSensorCard(),
            const SizedBox(height: 16),
            // 光量メーターは設定画面の奥にあり見つけにくいため、
            // 「この植物の置き場所の明るさを測る」文脈からも開けるようにする（Issue #248）
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LightMeterScreen()),
                ),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('置き場所の明るさを測る'),
              ),
            ),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.4),
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.thermostat,
                        size: 36,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        latest?.temperature != null
                            ? '${latest!.temperature!.toStringAsFixed(1)} ℃'
                            : '--',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('気温', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.water_drop,
                        size: 36,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        latest?.humidity != null
                            ? '${latest!.humidity!.toStringAsFixed(0)} %'
                            : '--',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('湿度', style: Theme.of(context).textTheme.bodySmall),
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'センサーが設定されていません',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IotSettingsScreen()),
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
      if (log.temperature != null) '${log.temperature!.toStringAsFixed(1)} ℃',
      if (log.humidity != null) '${log.humidity!.toStringAsFixed(0)} %',
    ];
    final sourceLabel = log.source == SensorSource.natureRemo
        ? 'Nature Remo'
        : 'SwitchBot';

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

    await context.read<SensorLogProvider>().deleteSensorLog(
      log.id,
    ); // ignore: use_build_context_synchronously
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
      final mappedDevice = settings.sensorDeviceMappings
          .where((m) => m.source == source && m.plantIds.contains(_plant.id))
          .firstOrNull;

      final List<SensorData> devices;
      if (source == SensorSource.natureRemo) {
        devices = await sensorProvider.fetchNatureRemoData(
          settings.natureRemoToken,
        );
      } else {
        devices = await sensorProvider.fetchSwitchBotData(
          settings.switchBotToken,
          settings.switchBotSecret,
        );
      }

      if (!mounted) return;

      if (devices.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('センサーデバイスが見つかりませんでした')));
        return;
      }

      // マッピング済みデバイスがある場合は自動選択
      final SensorData selected;
      if (mappedDevice != null) {
        final found = devices
            .where((d) => d.deviceId == mappedDevice.deviceId)
            .firstOrNull;
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

      await sensorProvider.saveSensorLog(
        // ignore: use_build_context_synchronously
        data: selected,
        source: source,
        plantId: _plant.id,
      );

      if (!mounted) return;
      await _loadSensorLogs();

      ScaffoldMessenger.of(context).showSnackBar(
        // ignore: use_build_context_synchronously
        SnackBar(content: Text('${selected.deviceName} のデータを記録しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取得エラー: ${describeError(e)}')));
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSensor = false;
        });
      }
    }
  }

  /// 複数デバイスがある場合の選択ダイアログ
  Future<SensorData?> _showDevicePickerDialog(List<SensorData> devices) async {
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
                    subtitle: Text(
                      [
                        if (d.temperature != null)
                          '${d.temperature!.toStringAsFixed(1)} ℃',
                        if (d.humidity != null)
                          '${d.humidity!.toStringAsFixed(0)} %',
                      ].join('   '),
                    ),
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
    final theme = Theme.of(context);
    // メモ付きのログは本文としても表示する（Issue #267）
    final logsWithNote = logs
        .where((log) => (log.note ?? '').trim().isNotEmpty)
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  DateFormat('yyyy年MM月dd日').format(day),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: logs
                        .map((log) => _buildLogTypeChip(log))
                        .toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: '${DateFormat('M月d日').format(day)}の記録をすべて削除',
                  onPressed: () => _deleteLogsForDay(day, logs),
                ),
              ],
            ),
            if (logsWithNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...logsWithNote.map(_buildLogNoteLine),
            ],
          ],
        ),
      ),
    );
  }

  /// ログ1件分のチップ。× で種類ごとに個別削除できる（Issue #272）。
  ///
  /// メモがある場合はタップで全文を表示する（Issue #267）。
  Widget _buildLogTypeChip(LogEntry log) {
    final theme = Theme.of(context);
    final typeName = _getLogTypeName(log.type);
    final hasNote = (log.note ?? '').trim().isNotEmpty;

    return InputChip(
      avatar: Icon(
        _getIconForLogType(log.type),
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text(
        typeName,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: hasNote ? () => _showLogNoteDialog(log) : null,
      deleteIcon: const Icon(Icons.close, size: 16),
      deleteButtonTooltipMessage: '$typeName の記録を削除',
      onDeleted: () => _deleteSingleLog(log),
    );
  }

  /// ログのメモを一覧上に本文として表示する行（Issue #267）。
  ///
  /// 長い場合は2行で省略し、タップで全文ダイアログを開く。
  Widget _buildLogNoteLine(LogEntry log) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showLogNoteDialog(log),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${_getLogTypeName(log.type)}: ${log.note!.trim()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ログのメモ全文を表示する（Issue #267）。
  Future<void> _showLogNoteDialog(LogEntry log) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_getLogTypeName(log.type)}のメモ'),
        content: SingleChildScrollView(child: SelectableText(log.note ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// ログを1件だけ削除する（Issue #272）。
  Future<void> _deleteSingleLog(LogEntry log) async {
    // async ギャップ前に context 依存の参照を取得しておく
    final plantProvider = context.read<PlantProvider>();
    final typeName = _getLogTypeName(log.type);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除'),
        content: Text(
          '${DateFormat('yyyy年MM月dd日').format(log.date)}の「$typeName」の記録を削除しますか？',
        ),
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
      await plantProvider.deleteLog(log.id);
      await _loadData();
    }
  }

  Future<void> _deleteLogsForDay(DateTime day, List<LogEntry> logs) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除'),
        content: Text(
          '${DateFormat('yyyy年MM月dd日').format(day)}の記録（${logs.length}件）を削除しますか？',
        ),
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
        await context.read<PlantProvider>().deleteLog(
          log.id,
        ); // ignore: use_build_context_synchronously
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
            Navigator.of(context).pop(
              _CareLogResult(
                type: _selectedType,
                date: _selectedDate,
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              ),
            );
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

  const _InfoRow({required this.label, required this.value, this.valueColor});

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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
