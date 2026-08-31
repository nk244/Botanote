import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/daily_log_status.dart';
import '../models/app_settings.dart';
import '../utils/date_utils.dart';
import '../widgets/plant_image_widget.dart';
import '../widgets/plant_picker_dialog.dart';
import 'care_stats_screen.dart';
import 'plant_detail_screen.dart';
import 'settings_screen.dart';
import 'add_plant_screen.dart';

class TodayWateringScreen extends StatefulWidget {
  const TodayWateringScreen({super.key});

  @override
  State<TodayWateringScreen> createState() => _TodayWateringScreenState();
}

class _TodayWateringScreenState extends State<TodayWateringScreen>
    with WidgetsBindingObserver {
  // 現在選択中の日付
  DateTime _selectedDate = AppDateUtils.getDateOnly(DateTime.now());
  DateTime _focusedDay = DateTime.now();
  bool _isCalendarView = false;

  // この画面が基準としている「今日」。アプリを起動したまま日付を跨いだ場合に
  // resume 時の再計算判定に使う（Issue #202）。
  DateTime _knownToday = AppDateUtils.getDateOnly(DateTime.now());

  // PageView用コントローラー。中央値を初期ページとして対応日数小を計算する。
  static const int _initialPage = 10000;
  late final PageController _pageController;

  // FutureBuilderの再実行トリガー用カウンタ（インクリメントで全キャッシュを無効化）
  int _refreshKey = 0;

  // PlantProviderのdataVersion前回値。loadPlants()完了検知に使用する（Issue #213）。
  int? _prevDataVersion;

  // SettingsProviderのソート設定前回値。ソート変更検知に使用する。
  PlantSortOrder? _prevSortOrder;
  List<String> _prevCustomOrder = [];

  // 日付ページデータのキャッシュ。キーは '${date.ms}_$_refreshKey'。
  // _refreshKey が変わるとキーが変わり、古いエントリは自然に参照されなくなる。
  final Map<String, _DatePageData> _pageDataCache = {};

  // FutureBuilder に渡す Future のキャッシュ。キーは _pageDataCache と同一。
  // build のたびに `_loadDatePageData()` を直接呼ぶと毎回別の Future になり、
  // FutureBuilder が再描画のたびに待ち直してスピナーがちらつくため、
  // キーが同じ間は同じ Future を使い回す（Issue #252）。
  final Map<String, Future<_DatePageData>> _pageFutureCache = {};

  // キャッシュエントリ数の上限（±2日×5日分＋余裕分）
  static const int _cacheMaxSize = 20;

  final Set<String> _selectedPlantIds = {};

  /// 記録済みセクションを展開しているか（Issue #294）
  bool _isCompletedExpanded = false;
  final Set<LogType> _selectedBulkLogTypes = {LogType.watering};
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<PlantProvider>().loadPlants();
      if (!mounted) return;
      // loadPlants() 完了後にキャッシュをリセットして FutureBuilder を再実行させる。
      // loadPlants() 中に空の植物リストでキャッシュが作られることを防ぐ。
      setState(() {
        _refreshKey++;
      });
      // 初期表示時：選択日を優先ロードしてから±2日分をバックグラウンドプリロード
      await _loadSelectedDateFirst(_selectedDate);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;

    // アプリを起動したまま日付を跨いだ場合、「今日」の表示や予定超過の判定が
    // 古い日付のままになる不具合への対応（Issue #202）。
    // resume 時に日付が変わっていれば表示を再計算する。
    final newToday = AppDateUtils.getDateOnly(DateTime.now());
    if (newToday == _knownToday) return;

    // 「今日」を表示していたユーザーだけ新しい今日へ追従させる。
    // 過去・未来の日付を明示的に選んでいた場合は選択日を維持する。
    final wasViewingToday = _selectedDate == _knownToday;
    _knownToday = newToday;
    if (!mounted) return;
    setState(() {
      if (wasViewingToday) {
        _selectedDate = newToday;
        _focusedDay = DateTime.now();
      }
      // 予定超過表示など日付依存の表示を再計算させる。
      _refreshKey++;
    });
    _loadSelectedDateFirst(_selectedDate).ignore();
  }

  @override
  void didUpdateWidget(TodayWateringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PlantProvider を listen: true で購読することで、他画面での植物追加・削除・
    // 編集やインポート完了時にも didChangeDependencies が再実行される。
    final plantProvider = Provider.of<PlantProvider>(context);

    // loadPlants() の完了を dataVersion の変化で検知してキャッシュをリセットし、
    // 最新の植物データで再プリロードする。
    //
    // 以前は isLoading の true→false 遷移で検知していたが、設定画面など別画面が
    // push された状態で loadPlants() が始まって終わるとこの画面が遷移を観測できず、
    // 古いキャッシュが残り続けていた（Issue #213: インポート後に
    // 「今日は水やりの予定と記録がありません」のままになる不具合）。
    final dataVersion = plantProvider.dataVersion;
    if (_prevDataVersion != null && _prevDataVersion != dataVersion) {
      setState(() {
        _refreshKey++;
      });
      _loadSelectedDateFirst(_selectedDate).ignore();
    }
    _prevDataVersion = dataVersion;

    // SettingsProvider のソート設定変更（ソート順 or カスタム順の変化）を検知して
    // キャッシュをリセットし、新しいソート順で再プリロードする。
    final settings = context.read<SettingsProvider>();
    final currentSortOrder = settings.plantSortOrder;
    final currentCustomOrder = settings.customSortOrder;
    if (_prevSortOrder != null &&
        (_prevSortOrder != currentSortOrder ||
            !listEquals(_prevCustomOrder, currentCustomOrder))) {
      setState(() {
        _refreshKey++;
      });
      _loadSelectedDateFirst(_selectedDate).ignore();
    }
    _prevSortOrder = currentSortOrder;
    _prevCustomOrder = List<String>.from(currentCustomOrder);
  }

  /// 選択日のデータを優先ロードし、その後±2日分をバックグラウンドでプリロードする。
  ///
  /// 選択日はキャッシュヒット確認後、ミスなら先にawaitでロードしてからsetStateで
  /// 画面を更新する。±2日分は後からバックグラウンドで実行する。
  Future<void> _loadSelectedDateFirst(DateTime center) async {
    // 選択日がキャッシュにない場合は優先的にロード
    final centerKey =
        '${AppDateUtils.getDateOnly(center).millisecondsSinceEpoch}_$_refreshKey';
    if (!_pageDataCache.containsKey(centerKey)) {
      await _loadDatePageData(center);
      // ロード完了後に再描画して即座に反映する
      if (mounted) setState(() {});
    }
    // 前後±2日分（選択日除く）をバックグラウンドでプリロード
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final date = AppDateUtils.getDateOnly(center.add(Duration(days: i)));
      _loadDatePageData(date).ignore();
    }
  }

  /// キャッシュサイズが上限を超えた場合に古いエントリを削除する。
  void _evictOldCacheEntries() {
    // 現在の_refreshKeyに属さないエントリを優先的に削除する
    final currentKeySuffix = '_$_refreshKey';
    // データが未確定でも Future だけ残ることがあるため、先に古い世代を掃除する
    _pageFutureCache.removeWhere((k, _) => !k.endsWith(currentKeySuffix));
    if (_pageDataCache.length <= _cacheMaxSize) return;
    final oldKeys = _pageDataCache.keys
        .where((k) => !k.endsWith(currentKeySuffix))
        .toList();
    for (final key in oldKeys) {
      _removeCacheEntry(key);
      if (_pageDataCache.length <= _cacheMaxSize) return;
    }
    // それでも超えている場合は先頭から削除
    while (_pageDataCache.length > _cacheMaxSize) {
      _removeCacheEntry(_pageDataCache.keys.first);
    }
  }

  /// データと Future のキャッシュを同じキーで揃えて破棄する。
  void _removeCacheEntry(String key) {
    _pageDataCache.remove(key);
    _pageFutureCache.remove(key);
  }

  /// 指定日に表示すべき植物リストを決定する
  List<Plant> _getPlantsForDate(
    List<Plant> plants,
    DateTime date,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final selectedDay = AppDateUtils.getDateOnly(date);
    final todayDay = AppDateUtils.getDateOnly(DateTime.now());

    // 記録がある植物
    final plantsWithRecords = plants
        .where((plant) => logStatus.hasAnyLog(plant.id))
        .toSet();

    // 予定日が来ている植物か判定するヘルパー
    bool isActionNeeded(DateTime? nextDate) {
      if (nextDate == null) return false;
      final nextDay = AppDateUtils.getDateOnly(nextDate);
      if (AppDateUtils.isSameDay(selectedDay, todayDay)) {
        return !nextDay.isAfter(selectedDay);
      }
      if (selectedDay.isBefore(todayDay)) {
        return !nextDay.isAfter(selectedDay);
      }
      // 未来の日付
      return nextDay.isAtSameMomentAs(selectedDay) || nextDay.isBefore(todayDay);
    }

    // 水やり・肥料・活力剤のいずれかが必要な植物
    final plantsNeedingAction = plants.where((plant) {
      return isActionNeeded(nextWateringDateCache[plant.id]) ||
          isActionNeeded(nextFertilizerDateCache[plant.id]) ||
          isActionNeeded(nextVitalizerDateCache[plant.id]);
    }).toSet();

    final settings = context.read<SettingsProvider>();
    final allPlants = {...plantsWithRecords, ...plantsNeedingAction}.toList();
    allPlants.sort((a, b) => _comparePlantsFor(
      a, b, logStatus, nextWateringDateCache,
      settings.plantSortOrder, settings.customSortOrder,
    ));
    return allPlants;
  }

  int _comparePlantsFor(
    Plant a,
    Plant b,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    PlantSortOrder sortOrder,
    List<String> customSortOrder,
  ) {
    final aCompleted = logStatus.isWatered(a.id);
    final bCompleted = logStatus.isWatered(b.id);

    // 完了済みは下に並ぶ
    if (aCompleted && !bCompleted) return 1;
    if (!aCompleted && bCompleted) return -1;
    
    switch (sortOrder) {
      case PlantSortOrder.nameAsc:
        return a.name.compareTo(b.name);
      case PlantSortOrder.nameDesc:
        return b.name.compareTo(a.name);
      case PlantSortOrder.purchaseDateDesc:
        if (a.purchaseDate == null && b.purchaseDate == null) return 0;
        if (a.purchaseDate == null) return 1;
        if (b.purchaseDate == null) return -1;
        return b.purchaseDate!.compareTo(a.purchaseDate!);
      case PlantSortOrder.purchaseDateAsc:
        if (a.purchaseDate == null && b.purchaseDate == null) return 0;
        if (a.purchaseDate == null) return 1;
        if (b.purchaseDate == null) return -1;
        return a.purchaseDate!.compareTo(b.purchaseDate!);
      case PlantSortOrder.createdAtAsc:
        return a.createdAt.compareTo(b.createdAt);
      case PlantSortOrder.createdAtDesc:
        return b.createdAt.compareTo(a.createdAt);
      case PlantSortOrder.custom:
        if (customSortOrder.isNotEmpty) {
          final customOrder = customSortOrder;
          final aIndex = customOrder.indexOf(a.id);
          final bIndex = customOrder.indexOf(b.id);
          if (aIndex == -1 && bIndex == -1) return 0;
          if (aIndex == -1) return 1;
          if (bIndex == -1) return -1;
          return aIndex.compareTo(bIndex);
        } else {
          // フォールバック：水やり予定日順
        }
        final aNextDate = nextWateringDateCache[a.id];
        final bNextDate = nextWateringDateCache[b.id];
        if (aNextDate == null && bNextDate == null) return 0;
        if (aNextDate == null) return 1;
        if (bNextDate == null) return -1;
        return aNextDate.compareTo(bNextDate);
      case PlantSortOrder.varietyAsc:
        // 品種名昇順（品種なしは末尾）
        if (a.variety == null && b.variety == null) return 0;
        if (a.variety == null) return 1;
        if (b.variety == null) return -1;
        return a.variety!.compareTo(b.variety!);
      case PlantSortOrder.varietyDesc:
        // 品種名降順（品種なしは末尾）
        if (a.variety == null && b.variety == null) return 0;
        if (a.variety == null) return 1;
        if (b.variety == null) return -1;
        return b.variety!.compareTo(a.variety!);
      case PlantSortOrder.nextWateringAsc:
        // 次回水やり予定が近い順（予定超過が先頭、予定なしは末尾、Issue #271）
        final aNext = nextWateringDateCache[a.id];
        final bNext = nextWateringDateCache[b.id];
        if (aNext == null && bNext == null) return 0;
        if (aNext == null) return 1;
        if (bNext == null) return -1;
        return aNext.compareTo(bNext);
    }
  }


  Future<void> _bulkLog() async {
    if (_selectedPlantIds.isEmpty) return;

    final plantProvider = context.read<PlantProvider>();
    // _refreshAfterLogChange() 内で _selectedPlantIds.clear() が呼ばれるため、
    // 件数は先にローカル変数にコピーしておく (#37)
    final count = _selectedPlantIds.length;
    final plantIds = _selectedPlantIds.toList();
    final logTypes = _selectedBulkLogTypes.toList();

    // bulkRecordLogs で全挿入後に loadPlants を1回だけ呼ぶ (#50 ちらつき修正)
    await plantProvider.bulkRecordLogs(plantIds, logTypes, _selectedDate);

    await _refreshAfterLogChange();
    _showSuccessMessage(_buildLogMessage(count));
  }

  String _buildLogMessage(int count) {
    final actionNames = _selectedBulkLogTypes
        .map((type) => _getLogTypeName(type))
        .join('・');
    return '$count件の$actionNamesを登録しました';
  }

  Future<void> _refreshAfterLogChange() async {
    final scrollOffset = _listScrollController.hasClients
        ? _listScrollController.offset
        : 0.0;
    await context.read<PlantProvider>().loadPlants();
    if (mounted) {
      setState(() {
        _selectedPlantIds.clear();
        // FutureBuilderを再実行させるためにキーをインクリメント
        _refreshKey++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listScrollController.hasClients) {
          final maxScroll = _listScrollController.position.maxScrollExtent;
          _listScrollController.jumpTo(scrollOffset.clamp(0.0, maxScroll));
        }
      });
    }
  }

  /// 操作結果の SnackBar を表示する。
  ///
  /// 画面下部には「その他の植物に水やり」ボタンや一括記録バーがあり、既定の
  /// 固定表示だとそれらに重なってしまうため、フローティング表示にして下端に
  /// 余白を確保する（Issue #280）。[onUndo] を渡すと「元に戻す」を表示する。
  void _showSuccessMessage(String message, {VoidCallback? onUndo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: onUndo == null ? 2 : 6),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        action: onUndo == null
            ? null
            : SnackBarAction(label: '元に戻す', onPressed: onUndo),
      ),
    );
  }

  Future<void> _deleteLog(
    String plantId,
    LogType logType,
    DailyLogStatus logStatus,
  ) async {
    // async ギャップ前にプロバイダー参照を取得しておく
    final plantProvider = context.read<PlantProvider>();

    // 水やりの場合、他の記録（肥料・活力剤）があるか確認
    final hasOtherLogs = (logType == LogType.watering) &&
        logStatus.hasOtherLogs(plantId, LogType.watering);

    final logTypesToDelete = await _confirmDeletion(hasOtherLogs, plantId, logType, logStatus);
    if (logTypesToDelete == null) return;

    final deletedLogs = await plantProvider.deleteMultipleLogsForDate(
      plantId,
      logTypesToDelete,
      _selectedDate,
    );

    await _refreshAfterLogChange();
    _showSuccessMessage(
      _buildDeleteMessage(logTypesToDelete, logType),
      // 誤って取り消した場合に元の記録へ戻せるようにする（Issue #280）
      onUndo: deletedLogs.isEmpty
          ? null
          : () async {
              await plantProvider.restoreLogs(deletedLogs);
              await _refreshAfterLogChange();
              _showSuccessMessage('記録を元に戻しました');
            },
    );
  }

  Future<List<LogType>?> _confirmDeletion(
    bool hasOtherLogs,
    String plantId,
    LogType logType,
    DailyLogStatus logStatus,
  ) async {
    if (!hasOtherLogs) {
      return [logType];
    }

    // 削除確認ダイアログを表示
    final deleteAll = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録の取り消し'),
        content: const Text('水やりを取り消します。\n肥料や活力剤の記録も一緒に取り消しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('水やりのみ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('すべて取り消し'),
          ),
        ],
      ),
    );
    
    if (deleteAll == null) return null;
    
    return deleteAll ? logStatus.getActiveLogTypes(plantId) : [logType];
  }

  String _buildDeleteMessage(List<LogType> deletedTypes, LogType primaryType) {
    if (deletedTypes.length > 1) {
      return 'すべての記録を取り消しました';
    }
    return '${_getLogTypeName(primaryType)}の記録を取り消しました';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('水やりログ'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isCalendarView ? Icons.list : Icons.calendar_today),
            tooltip: _isCalendarView ? 'リスト表示' : 'カレンダー表示',
            onPressed: () => setState(() => _isCalendarView = !_isCalendarView),
          ),
          // ケア統計は「設定」ではなく振り返り機能なので、ログ画面からも開けるようにする
          // （Issue #248）。設定画面からの導線も従来どおり残している。
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'ケア統計',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CareStatsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isCalendarView ? _buildCalendarView() : _buildPagedLogList(),
    );
  }

  /// 一括記録バー。選択中の植物がある場合に画面下部へ表示する。
  ///
  /// FloatingActionButton として浮かせると、下部の「その他の植物に水やり」ボタンや
  /// カレンダー表示時の植物カードに重なってしまうため、レイアウト上の領域を
  /// 占める通常のウィジェットとして配置する（Issue #240）。
  Widget _buildBulkActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Log type selection chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '登録する記録',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          final colors = settings.logTypeColors;
                          return Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('水やり'),
                                avatar: const Icon(Icons.water_drop, size: 18),
                                selected: _selectedBulkLogTypes.contains(LogType.watering),
                                selectedColor: Color(colors.wateringBg),
                                checkmarkColor: Color(colors.wateringFg),
                                labelStyle: TextStyle(
                                  color: _selectedBulkLogTypes.contains(LogType.watering)
                                      ? Color(colors.wateringFg)
                                      : null,
                                  fontWeight: _selectedBulkLogTypes.contains(LogType.watering)
                                      ? FontWeight.w600
                                      : null,
                                ),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedBulkLogTypes.add(LogType.watering);
                                    } else if (_selectedBulkLogTypes.length > 1) {
                                      _selectedBulkLogTypes.remove(LogType.watering);
                                    }
                                  });
                                },
                              ),
                              FilterChip(
                                label: const Text('肥料'),
                                avatar: const Icon(Icons.grass, size: 18),
                                selected: _selectedBulkLogTypes.contains(LogType.fertilizer),
                                selectedColor: Color(colors.fertilizerBg),
                                checkmarkColor: Color(colors.fertilizerFg),
                                labelStyle: TextStyle(
                                  color: _selectedBulkLogTypes.contains(LogType.fertilizer)
                                      ? Color(colors.fertilizerFg)
                                      : null,
                                  fontWeight: _selectedBulkLogTypes.contains(LogType.fertilizer)
                                      ? FontWeight.w600
                                      : null,
                                ),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedBulkLogTypes.add(LogType.fertilizer);
                                    } else if (_selectedBulkLogTypes.length > 1) {
                                      _selectedBulkLogTypes.remove(LogType.fertilizer);
                                    }
                                  });
                                },
                              ),
                              FilterChip(
                                label: const Text('活力剤'),
                                avatar: const Icon(Icons.favorite, size: 18),
                                selected: _selectedBulkLogTypes.contains(LogType.vitalizer),
                                selectedColor: Color(colors.vitalizerBg),
                                checkmarkColor: Color(colors.vitalizerFg),
                                labelStyle: TextStyle(
                                  color: _selectedBulkLogTypes.contains(LogType.vitalizer)
                                      ? Color(colors.vitalizerFg)
                                      : null,
                                  fontWeight: _selectedBulkLogTypes.contains(LogType.vitalizer)
                                      ? FontWeight.w600
                                      : null,
                                ),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedBulkLogTypes.add(LogType.vitalizer);
                                    } else if (_selectedBulkLogTypes.length > 1) {
                                      _selectedBulkLogTypes.remove(LogType.vitalizer);
                                    }
                                  });
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Action button
                FilledButton.icon(
                  onPressed: _bulkLog,
                  icon: const Icon(Icons.check),
                  label: Text('${_selectedPlantIds.length}件登録'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
        ),
      ),
    );
  }

  /// カレンダーのマーカードット1つ分。
  Widget _calendarDot(Color color) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildCalendarView() {
    return Consumer<PlantProvider>(
      builder: (context, plantProvider, _) {
        final logDates = plantProvider.logDates;
        // 未来を含む水やり予定日（Issue #234）。過去ログのドットとは色を分けて表示する。
        final scheduledDates = plantProvider.scheduledWateringDates;
        final today = AppDateUtils.getDateOnly(DateTime.now());

        return Column(
          children: [
            // TableCalendar（3.2.0時点）のセマンティクスサブツリーは、一度読み取られると
            // 画面全体のセマンティクスツリーを失わせる（Issue #241）。実測では
            // カレンダー表示中は1回目のダンプが125ノード、2回目以降は4ノード
            // （ルートのみ）に落ち、以後復帰しない。スクリーンリーダー利用者は
            // 画面の内容を一切読み上げられなくなる。
            //
            // カレンダー自体をセマンティクスから除外すると、残りの画面（日付ヘッダー・
            // 植物リスト・記録ボタン）は安定する。日付の変更は日付ヘッダーの
            // 「前の日」「次の日」ボタンと、日付タップで開く日付ピッカーから
            // 行えるため、操作手段は失われない。
            Semantics(
              container: true,
              label: 'カレンダー。日付を変更するには、下の日付欄をタップして'
                  '日付を選ぶか、「前の日」「次の日」のボタンを使ってください。',
              child: ExcludeSemantics(
                child: TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDate = AppDateUtils.getDateOnly(selectedDay);
                      _focusedDay = focusedDay;
                      _selectedPlantIds.clear();
                    });
                    // 選択日を優先ロードしてから±2日分をバックグラウンドプリロード
                    _loadSelectedDateFirst(_selectedDate).ignore();
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                  },
                  calendarBuilders: CalendarBuilders(
                    // 過去ログのある日（primary）と、未来の水やり予定日（secondary）で
                    // マーカーを塗り分ける。両方に該当する場合は実績（過去ログ）を優先。
                    markerBuilder: (context, day, events) {
                      final d = AppDateUtils.getDateOnly(day);
                      final hasLog = logDates.contains(d);
                      final isScheduled = scheduledDates.contains(d);
                      // 予定日を過ぎても水やりされていない日はエラー色で出す（Issue #275）。
                      // 従来は「今日より後」の予定しかマーカーが出ず、
                      // カレンダーを見ても予定超過に気づけなかった。
                      final isOverdue = isScheduled && !d.isAfter(today);
                      if (!hasLog && !isScheduled) return null;

                      final Color color;
                      if (isOverdue) {
                        color = Theme.of(context).colorScheme.error;
                      } else if (hasLog) {
                        color = Theme.of(context).colorScheme.primary;
                      } else {
                        color = Theme.of(context).colorScheme.tertiary;
                      }

                      // 実績と予定超過が同じ日に重なる場合は両方のドットを並べる
                      final showLogDot = hasLog;
                      final showOverdueDot = isOverdue;
                      final dots = <Widget>[
                        if (showLogDot)
                          _calendarDot(Theme.of(context).colorScheme.primary),
                        if (showOverdueDot)
                          _calendarDot(Theme.of(context).colorScheme.error),
                        if (!showLogDot && !showOverdueDot) _calendarDot(color),
                      ];

                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: dots,
                          ),
                        ),
                      );
                    },
                  ),
                  calendarStyle: CalendarStyle(
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  locale: 'ja_JP',
                ),
              ),
            ),
            // 凡例：実績（過去ログ）と予定（未来の水やり）の色を説明する
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CalendarLegendDot(
                      color: Theme.of(context).colorScheme.primary, label: '記録'),
                  const SizedBox(width: 16),
                  _CalendarLegendDot(
                      color: Theme.of(context).colorScheme.tertiary, label: '予定'),
                  const SizedBox(width: 16),
                  // 予定超過（Issue #275）
                  _CalendarLegendDot(
                      color: Theme.of(context).colorScheme.error, label: '予定超過'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildDatePage(_selectedDate),
            ),
          ],
        );
      },
    );
  }

  /// PageViewによるページめくり式日付切替リスト表示
  Widget _buildPagedLogList() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        final diff = index - _initialPage;
        final newDate = AppDateUtils.getDateOnly(
          DateTime.now().add(Duration(days: diff)),
        );
        setState(() {
          _selectedDate = newDate;
          _selectedPlantIds.clear();
        });
        // 選択日を優先ロードしてから±2日分をバックグラウンドプリロード
        _loadSelectedDateFirst(newDate).ignore();
      },
      itemBuilder: (context, index) {
        final diff = index - _initialPage;
        final date = AppDateUtils.getDateOnly(
          DateTime.now().add(Duration(days: diff)),
        );
        return _buildDatePage(date);
      },
    );
  }

  /// 指定日のログデータをDBから取得する。キャッシュヒット時は即座に返す。
  /// 指定日のページデータ取得 Future を返す。
  ///
  /// build のたびに `_loadDatePageData()` を直接呼ぶと毎回別の Future になり、
  /// FutureBuilder が再描画のたびに待ち直してしまうため、
  /// キーが同じ間は同じ Future を返す（Issue #252）。
  Future<_DatePageData> _datePageFuture(DateTime date) {
    final cacheKey = _pageCacheKey(date);
    return _pageFutureCache[cacheKey] ??= _loadDatePageData(date);
  }

  /// 日付ページのキャッシュキー。
  String _pageCacheKey(DateTime date) =>
      '${AppDateUtils.getDateOnly(date).millisecondsSinceEpoch}_$_refreshKey';

  Future<_DatePageData> _loadDatePageData(DateTime date) async {
    final cacheKey = _pageCacheKey(date);
    // キャッシュヒット時はDBアクセスをスキップ
    if (_pageDataCache.containsKey(cacheKey)) {
      return _pageDataCache[cacheKey]!;
    }

    final plantProvider = context.read<PlantProvider>();
    final plants = plantProvider.plants;

    // 植物リストがロード中、または未初期化の場合はキャッシュせずに空データを返す。
    // loadPlants() 完了前にキャッシュされると空データが表示され続けるため。
    if (plantProvider.isLoading || !plantProvider.isInitialized) {
      return _DatePageData(
        logStatus: DailyLogStatus(
          watered: {},
          fertilized: {},
          vitalized: {},
        ),
        nextWateringDateCache: {},
        nextFertilizerDateCache: {},
        nextVitalizerDateCache: {},
      );
    }
    final wateredMap = <String, bool>{};
    final fertilizedMap = <String, bool>{};
    final vitalizedMap = <String, bool>{};
    final nextWateringDateCache = <String, DateTime?>{};
    final nextFertilizerDateCache = <String, DateTime?>{};
    final nextVitalizerDateCache = <String, DateTime?>{};

    // 植物1件あたり1クエリ（全種別ログ一括取得）で計算する
    final startOfDay = AppDateUtils.getDateOnly(date);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    for (final plant in plants) {
      // 全ログを1回のDBクエリで取得し、種別ごとに振り分ける
      final allLogs = await plantProvider.getAllLogsForPlant(plant.id);
      final wateringLogs =
          allLogs.where((l) => l.type == LogType.watering).toList();
      final fertLogs =
          allLogs.where((l) => l.type == LogType.fertilizer).toList();
      final vitLogs =
          allLogs.where((l) => l.type == LogType.vitalizer).toList();

      // 次回予定日はDBアクセスなしで同期計算
      final nextWatering =
          plantProvider.calcNextWateringDateFromLogs(plant, wateringLogs);
      nextWateringDateCache[plant.id] = nextWatering;
      nextFertilizerDateCache[plant.id] =
          plantProvider.calcNextFertilizerDateFromLogs(
              plant, fertLogs, wateringLogs, nextWatering);
      nextVitalizerDateCache[plant.id] =
          plantProvider.calcNextVitalizerDateFromLogs(
              plant, vitLogs, wateringLogs, nextWatering);

      // 指定日のログ有無を判定
      bool hasOnDate(List<LogEntry> logs) => logs.any((l) =>
          !l.date.isBefore(startOfDay) &&
          l.date.isBefore(endOfDay.add(const Duration(seconds: 1))));
      wateredMap[plant.id] = hasOnDate(wateringLogs);
      fertilizedMap[plant.id] = hasOnDate(fertLogs);
      vitalizedMap[plant.id] = hasOnDate(vitLogs);
    }

    final data = _DatePageData(
      logStatus: DailyLogStatus(
        watered: wateredMap,
        fertilized: fertilizedMap,
        vitalized: vitalizedMap,
      ),
      nextWateringDateCache: nextWateringDateCache,
      nextFertilizerDateCache: nextFertilizerDateCache,
      nextVitalizerDateCache: nextVitalizerDateCache,
    );
    // キャッシュに保存し、上限超過時は古いエントリを削除
    _pageDataCache[cacheKey] = data;
    _evictOldCacheEntries();
    return data;
  }

  /// 1日分のページを構築する
  Widget _buildDatePage(DateTime date) {
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final isToday = AppDateUtils.isSameDay(date, today);

    return Consumer<PlantProvider>(
      builder: (context, plantProvider, _) {
        return FutureBuilder<_DatePageData>(
          // _refreshKey が変化するとキャッシュキーが変わり Future が再実行される
          future: _datePageFuture(date),
          builder: (context, snapshot) {
            // 未初期化中（初回loadPlants完了前）またはデータ待ちはスピナー表示
            // isInitialized を先に評価することで、_loadDatePageData が未初期化中に
            // 空データを即返した場合（snapshot.hasData=true）でもスピナーが表示される。
            if (!plantProvider.isInitialized || !snapshot.hasData) {
              return Column(
                children: [
                  _buildDateHeader(date, isToday),
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final logStatus = data.logStatus;
            final nextWateringDateCache = data.nextWateringDateCache;
            final nextFertilizerDateCache = data.nextFertilizerDateCache;
            final nextVitalizerDateCache = data.nextVitalizerDateCache;
            final plantsForDate = _getPlantsForDate(
              plantProvider.plants, date, logStatus,
              nextWateringDateCache, nextFertilizerDateCache, nextVitalizerDateCache,
            );

            return Column(
              children: [
                _buildDateHeader(date, isToday),
                // 日付を移動しても骨格が変わらないよう、3タイルの形は保ったまま
                // 中身だけ切り替える（Issue #316）
                if (isToday)
                  _buildStatusSummaryBand(
                    plantsForDate, logStatus,
                    nextWateringDateCache, nextFertilizerDateCache,
                    nextVitalizerDateCache,
                  )
                else if (date.isBefore(AppDateUtils.getDateOnly(DateTime.now())))
                  _buildPastDateSummaryBand(logStatus)
                else
                  _buildFutureDateSummaryBand(
                    plantsForDate, date,
                    nextWateringDateCache, nextFertilizerDateCache,
                    nextVitalizerDateCache,
                  ),
                Expanded(
                  child: _buildPlantList(
                    plantsForDate, isToday, logStatus,
                    nextWateringDateCache, nextFertilizerDateCache,
                    nextVitalizerDateCache, date,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }



  Widget _buildDateHeader(DateTime date, bool isToday) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '前の日',
            onPressed: () {
              if (_isCalendarView) {
                final prev = AppDateUtils.getDateOnly(
                    date.subtract(const Duration(days: 1)));
                setState(() {
                  _selectedDate = prev;
                  _focusedDay = prev;
                  _selectedPlantIds.clear();
                });
                // 選択日を優先ロードしてから±2日分をバックグラウンドプリロード
                _loadSelectedDateFirst(prev).ignore();
              } else {
                _pageController.animateToPage(
                  _pageController.page!.round() - 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          ),
          Expanded(
            child: InkWell(
              onTap: _selectDate,
              child: Column(
                children: [
                  Text(
                    isToday ? '今日' : AppDateUtils.formatRelativeDate(date),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    DateFormat('yyyy年M月d日').format(date),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '次の日',
            onPressed: () {
              if (_isCalendarView) {
                final next = AppDateUtils.getDateOnly(
                    date.add(const Duration(days: 1)));
                setState(() {
                  _selectedDate = next;
                  _focusedDay = next;
                  _selectedPlantIds.clear();
                });
                // 選択日を優先ロードしてから±2日分をバックグラウンドプリロード
                _loadSelectedDateFirst(next).ignore();
              } else {
                _pageController.animateToPage(
                  _pageController.page!.round() + 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      final today = AppDateUtils.getDateOnly(DateTime.now());
      final diff = AppDateUtils.getDateOnly(date).difference(today).inDays;
      _pageController.animateToPage(
        _initialPage + diff,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 今日の状況を「予定超過 / 今日の予定 / 記録済み」の3タイルで示す帯（Issue #294）。
  ///
  /// リストを見る前に、まず何件やることが残っているかが分かるようにする。
  Widget _buildStatusSummaryBand(
    List<Plant> plantsForDate,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final today = AppDateUtils.getDateOnly(DateTime.now());
    var overdueCount = 0;
    var dueTodayCount = 0;
    var recordedCount = 0;

    for (final plant in plantsForDate) {
      if (logStatus.hasAnyLog(plant.id)) recordedCount++;
      if (logStatus.isWatered(plant.id)) continue;
      if (_isPastDue(plant.id, nextWateringDateCache, nextFertilizerDateCache,
          nextVitalizerDateCache)) {
        overdueCount++;
      } else if (_isDueOn(plant.id, today, nextWateringDateCache,
          nextFertilizerDateCache, nextVitalizerDateCache)) {
        dueTodayCount++;
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _buildSummaryTile(
            label: '予定超過',
            count: overdueCount,
            icon: Icons.priority_high,
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '今日の予定',
            count: dueTodayCount,
            icon: Icons.water_drop,
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '記録済み',
            count: recordedCount,
            icon: Icons.check_circle,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 過去日のサマリー帯。その日に記録した件数を種別ごとに出す（Issue #316）。
  ///
  /// 今日の帯と同じ3タイルの形を保ち、色は surfaceContainerHighest に統一して
  /// 「過ぎた日を見ている」ことが分かるようにする。
  Widget _buildPastDateSummaryBand(DailyLogStatus logStatus) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _buildSummaryTile(
            label: '水やり',
            count: logStatus.wateredCount,
            icon: Icons.water_drop,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '肥料',
            count: logStatus.fertilizedCount,
            icon: Icons.grass,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '活力剤',
            count: logStatus.vitalizedCount,
            icon: Icons.favorite,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 未来日のサマリー帯。その日が予定日になっている件数を種別ごとに出す（Issue #316）。
  ///
  /// 今日の「予定超過（error）／今日の予定（primary）」とは別系統の tertiary を使い、
  /// 先の日付を見ていることが色でも分かるようにする。
  Widget _buildFutureDateSummaryBand(
    List<Plant> plantsForDate,
    DateTime date,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final day = AppDateUtils.getDateOnly(date);
    var wateringCount = 0;
    var fertilizerCount = 0;
    var vitalizerCount = 0;

    for (final plant in plantsForDate) {
      final watering = _dueDateOnly(plant.id, nextWateringDateCache);
      final fertilizer = _dueDateOnly(plant.id, nextFertilizerDateCache);
      final vitalizer = _dueDateOnly(plant.id, nextVitalizerDateCache);
      if (watering != null && AppDateUtils.isSameDay(watering, day)) {
        wateringCount++;
      }
      if (fertilizer != null && AppDateUtils.isSameDay(fertilizer, day)) {
        fertilizerCount++;
      }
      if (vitalizer != null && AppDateUtils.isSameDay(vitalizer, day)) {
        vitalizerCount++;
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _buildSummaryTile(
            label: '水やり',
            count: wateringCount,
            icon: Icons.water_drop,
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '肥料',
            count: fertilizerCount,
            icon: Icons.grass,
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          _buildSummaryTile(
            label: '活力剤',
            count: vitalizerCount,
            icon: Icons.favorite,
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
        ],
      ),
    );
  }

  /// サマリー帯の1タイル。
  ///
  /// テーマ色によっては「予定超過（error）」と「今日の予定（primary）」が
  /// 同系色になり色だけでは区別できないため、アイコンも添える（Issue #303）。
  /// 0件のタイルは彩度を落とし、片付いた状態が伝わるようにする（Issue #305）。
  Widget _buildSummaryTile({
    required String label,
    required int count,
    required IconData icon,
    required Color background,
    required Color foreground,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isEmpty = count == 0;
    final tileBackground = isEmpty ? scheme.surfaceContainerHigh : background;
    final tileForeground = isEmpty ? scheme.onSurfaceVariant : foreground;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tileBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: tileForeground,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 2),
                Text('件',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tileForeground)),
              ],
            ),
            Row(
              children: [
                Icon(icon, size: 13, color: tileForeground),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tileForeground,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 未来日を見ていることを伝える注記（Issue #316）。
  Widget _buildFutureDateNotice() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '先の日付を見ています。記録は当日になってから、'
              'または「この日の記録を追加」から行えます。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantList(
    List<Plant> plantsForDate,
    bool isToday,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
    DateTime date,
  ) {
    if (plantsForDate.isEmpty) {
      return _buildEmptyState(isToday);
    }

    // 未完了と完了に分割
    final incompletePlants = plantsForDate
        .where((plant) => !logStatus.isWatered(plant.id))
        .toList();
    final completedPlants = plantsForDate
        .where((plant) => logStatus.isWatered(plant.id))
        .toList();

    final items = _buildLogListItems(
      plantsForDate,
      incompletePlants,
      completedPlants,
      isToday,
      date,
      logStatus,
      nextWateringDateCache,
      nextFertilizerDateCache,
      nextVitalizerDateCache,
    );

    final isFutureDate =
        !isToday && !date.isBefore(AppDateUtils.getDateOnly(DateTime.now()));

    return Column(
      children: [
        if (incompletePlants.isNotEmpty)
          _buildBulkSelectionHeader(incompletePlants),
        // 先の日付では記録できないと誤解されないよう、追加手段を1行で示す（Issue #316）
        if (isFutureDate) _buildFutureDateNotice(),
        Expanded(
          child: ListView.builder(
            controller: _listScrollController,
            padding: const EdgeInsets.only(
                left: 8, right: 8, top: 8, bottom: 80),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final plant = item.plant;
              if (plant != null) {
                return _buildPlantCard(
                    plant, logStatus,
                    nextWateringDateCache, nextFertilizerDateCache,
                    nextVitalizerDateCache, date);
              }
              if (item.isAllDone) return _buildAllDoneMessage();
              if (item.completedCount != null) {
                return _buildCompletedToggle(item.completedCount!);
              }
              return _buildSectionHeader(item.headerLabel!, item.headerColor!);
            },
          ),
        ),
        // 選択中は一括記録バーへ切り替える（両方を同時に出すと重なるため）
        if (_selectedPlantIds.isNotEmpty)
          _buildBulkActionBar()
        else
          _buildAddUnscheduledWateringButton(hasPlants: true),
      ],
    );
  }

  /// リストに並べる要素（セクション見出し・植物カード・記録済みの折りたたみ）を組み立てる。
  ///
  /// 見出しは表示中の日付を基準にする。今日は「予定超過／今日の予定」、
  /// 過去日は「この日の記録／この日は記録なし」、未来日は
  /// 「この日の予定／予定日を過ぎたまま」に分ける（Issue #294, #316）。
  List<_LogListItem> _buildLogListItems(
    List<Plant> plantsForDate,
    List<Plant> incompletePlants,
    List<Plant> completedPlants,
    bool isToday,
    DateTime date,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final items = <_LogListItem>[];

    void addSectionFor(String label, Color color, List<Plant> plants) {
      if (plants.isEmpty) return;
      items.add(_LogListItem.header(label, color));
      items.addAll(plants.map(_LogListItem.plant));
    }

    final today = AppDateUtils.getDateOnly(DateTime.now());
    final day = AppDateUtils.getDateOnly(date);

    if (!isToday && day.isBefore(today)) {
      // 過去日: その日に記録があったかどうかで分ける
      addSectionFor(
        'この日の記録',
        scheme.primary,
        plantsForDate.where((p) => logStatus.hasAnyLog(p.id)).toList(),
      );
      addSectionFor(
        'この日は記録なし',
        scheme.outline,
        plantsForDate.where((p) => !logStatus.hasAnyLog(p.id)).toList(),
      );
      return items;
    }

    if (!isToday) {
      // 未来日: その日が予定日のものと、今日より前で放置されているものを分ける。
      // 後者に「この日に水やり」と出すのは誤りになるため一緒にしない。
      final dueThatDay = <Plant>[];
      final stillOverdue = <Plant>[];
      for (final plant in plantsForDate) {
        if (_isDueOn(plant.id, day, nextWateringDateCache,
            nextFertilizerDateCache, nextVitalizerDateCache)) {
          dueThatDay.add(plant);
        } else {
          stillOverdue.add(plant);
        }
      }
      addSectionFor('この日の予定', scheme.tertiary, dueThatDay);
      addSectionFor('予定日を過ぎたまま', scheme.error, stillOverdue);
      return items;
    }

    if (isToday) {
      final today = AppDateUtils.getDateOnly(DateTime.now());
      final overdue = <Plant>[];
      final dueToday = <Plant>[];
      final upcoming = <Plant>[];

      for (final plant in incompletePlants) {
        if (_isPastDue(plant.id, nextWateringDateCache,
            nextFertilizerDateCache, nextVitalizerDateCache)) {
          overdue.add(plant);
        } else if (_isDueOn(plant.id, today, nextWateringDateCache,
            nextFertilizerDateCache, nextVitalizerDateCache)) {
          dueToday.add(plant);
        } else {
          upcoming.add(plant);
        }
      }

      // 予定超過だけは、件数が増えるとどれから手を付ければよいか分からなくなるため
      // 遅れが大きい順に並べ替える。他のセクションはアプリの並び順設定に従う（Issue #302）。
      overdue.sort((a, b) {
        final aDate = _earliestDueDate(a.id, nextWateringDateCache,
            nextFertilizerDateCache, nextVitalizerDateCache);
        final bDate = _earliestDueDate(b.id, nextWateringDateCache,
            nextFertilizerDateCache, nextVitalizerDateCache);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

      addSectionFor('予定超過', scheme.error, overdue);
      addSectionFor('今日の予定', scheme.primary, dueToday);
      addSectionFor('これからの予定', scheme.outline, upcoming);
    }

    if (completedPlants.isNotEmpty) {
      // 今日やることが残っていないなら、片付いたことを明示する（Issue #305）。
      // 植物が0鉢のときの空状態とは別物なので、記録済みがある場合のみ出す。
      if (incompletePlants.isEmpty) {
        items.add(const _LogListItem.allDone());
      }
      items.add(_LogListItem.completed(completedPlants.length));
      if (_isCompletedExpanded) {
        items.addAll(completedPlants.map(_LogListItem.plant));
      }
    }
    return items;
  }

  /// その日のケアをすべて記録し終えたことを示す表示（Issue #305）。
  Widget _buildAllDoneMessage() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Column(
        children: [
          Icon(Icons.task_alt, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            '今日のケアは完了しました',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'お疲れさまでした。予定はすべて記録済みです。',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// セクション見出し（色ドット＋ラベル）。Issue #294。
  Widget _buildSectionHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  /// 記録済みをまとめる折りたたみ行（Issue #294）。
  Widget _buildCompletedToggle(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              setState(() => _isCompletedExpanded = !_isCompletedExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '記録済み $count件',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  _isCompletedExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 水やり・肥料・活力剤のうち、最も早い予定日を返す。予定が無ければ null。
  DateTime? _earliestDueDate(
    String plantId,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final dates = [
      _dueDateOnly(plantId, nextWateringDateCache),
      _dueDateOnly(plantId, nextFertilizerDateCache),
      _dueDateOnly(plantId, nextVitalizerDateCache),
    ].whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// いずれかの予定日が [day] と同じかどうかを返す。
  bool _isDueOn(
    String plantId,
    DateTime day,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    return [
      _dueDateOnly(plantId, nextWateringDateCache),
      _dueDateOnly(plantId, nextFertilizerDateCache),
      _dueDateOnly(plantId, nextVitalizerDateCache),
    ].any((date) => date != null && AppDateUtils.isSameDay(date, day));
  }

  Widget _buildBulkSelectionHeader(List<Plant> incompletePlants) {
    final allSelected = incompletePlants.every((plant) => _selectedPlantIds.contains(plant.id));
    final someSelected = _selectedPlantIds.isNotEmpty && !allSelected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) {
              setState(() {
                if (allSelected || someSelected) {
                  // Unselect all
                  _selectedPlantIds.clear();
                } else {
                  // Select all incomplete plants
                  _selectedPlantIds.addAll(
                    incompletePlants.map((plant) => plant.id),
                  );
                }
              });
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedPlantIds.isEmpty
                  ? 'すべて選択'
                  : '${_selectedPlantIds.length}件選択中',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_selectedPlantIds.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedPlantIds.clear();
                });
              },
              child: const Text('選択解除'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isToday) {
    // 植物が1件も無いうちは「予定がありません」より先に登録を促す（Issue #277）
    final hasNoPlants = context.read<PlantProvider>().plants.isEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.eco_outlined,
              size: 64,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              hasNoPlants
                  ? 'まずは植物を登録しましょう'
                  : isToday
                      ? '今日は水やりの予定と記録がありません'
                      : 'この日は水やりの予定と記録がありません',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (hasNoPlants) ...[
              const SizedBox(height: 8),
              Text(
                '植物を登録すると、水やりの予定日と記録を管理できます。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: hasNoPlants
                  ? _navigateToAddPlant
                  : _showUnscheduledWateringDialog,
              icon: const Icon(Icons.add),
              label: Text(hasNoPlants ? '植物を登録' : '水やり記録をつける'),
            ),
          ],
        ),
      ),
    );
  }

  /// 植物の追加画面へ遷移する（Issue #277 の空状態導線）。
  Future<void> _navigateToAddPlant() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddPlantScreen()),
    );
    if (!mounted) return;
    await context.read<PlantProvider>().loadPlants();
  }

  Widget _buildAddUnscheduledWateringButton({bool hasPlants = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: OutlinedButton.icon(
          onPressed: _showUnscheduledWateringDialog,
          icon: const Icon(Icons.add),
          // 今日以外を見ているときは、その日に対する操作だと分かる文言にする（Issue #316）
          label: Text(
            !AppDateUtils.isSameDay(
                    _selectedDate, AppDateUtils.getDateOnly(DateTime.now()))
                ? 'この日の記録を追加'
                : hasPlants
                    ? 'その他の植物に水やり'
                    : '水やり記録をつける',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ),
    );
  }

  /// 植物が未登録のときに、植物登録を促すダイアログを表示する。
  ///
  /// 「登録する」を選ぶと植物追加画面へ遷移する。
  Future<void> _showNoPlantsDialog() async {
    final goToAdd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('植物が登録されていません'),
        content: const Text('水やりを記録するには、まず植物を登録してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('植物を登録'),
          ),
        ],
      ),
    );
    if (goToAdd == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const AddPlantScreen()),
      );
    }
  }

  Future<void> _showUnscheduledWateringDialog() async {
    final plantProvider = context.read<PlantProvider>();
    final settings = context.read<SettingsProvider>();
    // ソート設定に従って並べた全植物リストを取得する
    final sortedPlants = plantProvider.getSortedPlants(
      settings.plantSortOrder,
      settings.customSortOrder,
    );
    // 現在の日付データを直接DBから取得して未予定植物を判定する
    final data = await _loadDatePageData(_selectedDate);
    final plantsForDate = _getPlantsForDate(
      sortedPlants, _selectedDate, data.logStatus,
      data.nextWateringDateCache, data.nextFertilizerDateCache, data.nextVitalizerDateCache,
    ).toSet();

    // 植物が1件も登録されていない場合は、未予定判定より先に案内する。
    // 初回起動直後の唯一の導線を押したときに手詰まりにならないようにする（Issue #208）。
    if (sortedPlants.isEmpty) {
      if (!context.mounted) return;
      await _showNoPlantsDialog();
      return;
    }

    // ソート順を保持したまま未予定植物を抽出する
    final unscheduledPlants = sortedPlants
        .where((plant) => !plantsForDate.contains(plant))
        .toList();

    if (unscheduledPlants.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべての植物が表示されています')),
      );
      return;
    }
    if (!context.mounted) return;

    // 3画面で共通のダイアログを使う（Issue #293）
    final selectedIds = await PlantPickerDialog.show(
      context,
      title: '水やり記録をつける',
      confirmLabel: '記録する',
      candidates: unscheduledPlants,
      allowEmptyConfirm: false,
      showImages: true,
    );
    final selectedPlants = selectedIds == null
        ? <Plant>[]
        : unscheduledPlants.where((p) => selectedIds.contains(p.id)).toList();

    if (selectedPlants.isNotEmpty && mounted) {
      // ログ種別選択ダイアログを表示
      final selectedLogTypes = await showDialog<Set<LogType>>(
        context: context,
        builder: (context) => _LogTypeSelectionDialog(),
      );

      if (selectedLogTypes != null && selectedLogTypes.isNotEmpty && mounted) {
        // 選択した全植物 × 全ログ種別を一括登録する
        final plantIds = selectedPlants.map((p) => p.id).toList();
        await plantProvider.bulkRecordLogs(plantIds, selectedLogTypes.toList(), _selectedDate);
        await _refreshAfterLogChange();

        final logTypeNames = selectedLogTypes
            .map((type) => _getLogTypeName(type))
            .join('・');
        final plantLabel = selectedPlants.length == 1
            ? selectedPlants.first.name
            : '${selectedPlants.length}件の植物';
        _showSuccessMessage('$plantLabelに$logTypeNamesを記録しました');
      }
    }
  }

  Widget _buildPlantCard(
    Plant plant,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
    DateTime date,
  ) {
    final isWatered = logStatus.isWatered(plant.id);
    final isFertilized = logStatus.isFertilized(plant.id);
    final isVitalized = logStatus.isVitalized(plant.id);
    final hasAnyLog = logStatus.hasAnyLog(plant.id);
    final isSelected = _selectedPlantIds.contains(plant.id);
    final selectedDay = AppDateUtils.getDateOnly(date);
    // 赤字判定は選択日に関わらず「今日」を基準にする (#124)
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final nextWateringDate = nextWateringDateCache[plant.id];
    final nextFertilizerDate = nextFertilizerDateCache[plant.id];
    final nextVitalizerDate = nextVitalizerDateCache[plant.id];
    // 予定超過（予定日 < 今日）のカードは左端にエラー色のラインを引いて
    // リストの中でひと目で拾えるようにする（Issue #294）。
    // ただし今日以外の日を見ているときは、今日基準の強調を出すと
    // 何の日付を見ているのか分からなくなるため出さない（Issue #299, #301）。
    final isViewingToday = AppDateUtils.isSameDay(selectedDay, today);
    final isPastDue = isViewingToday &&
        _isPastDue(
          plant.id,
          nextWateringDateCache,
          nextFertilizerDateCache,
          nextVitalizerDateCache,
        );
    final scheme = Theme.of(context).colorScheme;

    final tile = ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasAnyLog)
              Checkbox(
                value: isSelected,
                onChanged: (value) => _togglePlantSelection(plant.id, value),
              ),
            PlantImageWidget(plant: plant),
          ],
        ),
        // 長い名前で1枚のカードが画面を占有しないよう2行で省略する（Issue #306）。
        // 全文は植物詳細で確認できる。
        title: Text(
          plant.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildPlantSubtitle(
          plant,
          nextWateringDate,
          nextFertilizerDate,
          nextVitalizerDate,
          selectedDay,
          hasAnyLog,
          isWatered,
          isFertilized,
          isVitalized,
          logStatus,
        ),
        // 予定がある未記録の植物には、その場で記録できるボタンを出す（Issue #294）。
        // 今日以外を見ているときは何を記録するのか判断できないため出さない（Issue #299, #301）。
        // 一括選択中も、個別記録と一括記録のどちらを操作しているのか
        // 分からなくなるため出さない（Issue #312）。
        trailing: (!isViewingToday || _selectedPlantIds.isNotEmpty)
            ? null
            : _buildQuickRecordButton(
                plant,
                logStatus,
                nextWateringDateCache,
                nextFertilizerDateCache,
                nextVitalizerDateCache,
                isPastDue,
              ),
        onTap: () => _navigateToPlantDetail(plant),
      );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: isSelected ? 4 : 1,
      clipBehavior: Clip.antiAlias,
      color: isSelected
          ? scheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      // アクセントラインは Stack で重ねる。Row + CrossAxisAlignment.stretch だと
      // ListView 内で高さが非制約になり、子に無限高さが渡ってレイアウトが壊れる。
      child: Stack(
        children: [
          tile,
          if (isPastDue)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: scheme.error),
            ),
        ],
      ),
    );
  }

  /// カード右端のワンタップ記録ボタン（Issue #294）。
  ///
  /// 予定が無い、またはその日すでに記録済みの植物には出さない。
  /// 遅れている種別を優先して記録する。
  Widget? _buildQuickRecordButton(
    Plant plant,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
    bool isPastDue,
  ) {
    final logType = _quickRecordLogType(
      plant.id,
      logStatus,
      nextWateringDateCache,
      nextFertilizerDateCache,
      nextVitalizerDateCache,
    );
    if (logType == null) return null;

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(_getLogTypeIcon(logType)),
        tooltip: '${_getLogTypeName(logType)}を記録',
        style: IconButton.styleFrom(
          backgroundColor: isPastDue ? scheme.primary : scheme.primaryContainer,
          foregroundColor:
              isPastDue ? scheme.onPrimary : scheme.onPrimaryContainer,
        ),
        onPressed: () => _recordSingleLog(plant, logType),
      ),
    );
  }

  void _togglePlantSelection(String plantId, bool? value) {
    setState(() {
      if (value == true) {
        _selectedPlantIds.add(plantId);
      } else {
        _selectedPlantIds.remove(plantId);
      }
    });
  }

  Widget _buildPlantSubtitle(
    Plant plant,
    DateTime? nextWateringDate,
    DateTime? nextFertilizerDate,
    DateTime? nextVitalizerDate,
    DateTime selectedDay,
    bool hasAnyLog,
    bool isWatered,
    bool isFertilized,
    bool isVitalized,
    DailyLogStatus logStatus,
  ) {
    // 肥料・活力剤の超過判定も今日基準で統一する (#124)。
    // 「予定日 < 今日」だけを超過とし、予定日が今日ちょうどのものは含めない。
    // セクション分割（_isPastDue）と判定を揃え、「今日の予定」セクションのカードに
    // 超過色のチップが出る矛盾を防ぐ（Issue #298）。
    final today = AppDateUtils.getDateOnly(DateTime.now());
    bool isDatePastDue(DateTime? d) =>
        d != null && AppDateUtils.getDateOnly(d).isBefore(today);

    // 次回予定は「今日」からの相対表示のため、今日以外を見ているときに出すと
    // その日の状態と誤解される（4/22 を見ているのに「2日後」と出る）。
    // 過去日ではその日の記録だけを示す（Issue #249）。
    // 未来日にも同じ問題があり、「明日」の画面に「3日前（予定超過）」と
    // 出てしまうため、今日以外はまとめて出さない（Issue #301）。
    final isViewingToday = AppDateUtils.isSameDay(selectedDay, today);

    // 水やり・肥料・活力剤の予定を横並び1行でまとめて表示する (#125)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plant.variety != null) Text(plant.variety!),
        // 予定がある項目を Wrap で横並びにまとめる
        if (isViewingToday &&
            (nextWateringDate != null ||
                nextFertilizerDate != null ||
                nextVitalizerDate != null))
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              if (nextWateringDate != null)
                _buildScheduleChip(
                  icon: Icons.water_drop,
                  label: AppDateUtils.formatDateDifference(nextWateringDate),
                  isOverdue: isDatePastDue(nextWateringDate),
                  normalColor: Theme.of(context).colorScheme.primary,
                ),
              if (nextFertilizerDate != null)
                _buildScheduleChip(
                  icon: Icons.grass,
                  label: AppDateUtils.formatDateDifference(nextFertilizerDate),
                  isOverdue: isDatePastDue(nextFertilizerDate),
                  normalColor: Theme.of(context).colorScheme.secondary,
                ),
              if (nextVitalizerDate != null)
                _buildScheduleChip(
                  icon: Icons.favorite,
                  label: AppDateUtils.formatDateDifference(nextVitalizerDate),
                  isOverdue: isDatePastDue(nextVitalizerDate),
                  normalColor: Theme.of(context).colorScheme.tertiary,
                ),
            ],
          ),
        // 未来日は、その日が予定日の種別だけを「この日に〜」として出す。
        // 今日基準の日数（「3日前」等）は出さない（Issue #316）。
        if (!isViewingToday && !selectedDay.isBefore(today))
          _buildFutureDateChips(
            selectedDay,
            nextWateringDate,
            nextFertilizerDate,
            nextVitalizerDate,
          ),
        if (hasAnyLog)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (isWatered) _buildLogChip(plant.id, LogType.watering, logStatus),
                if (isFertilized) _buildLogChip(plant.id, LogType.fertilizer, logStatus),
                if (isVitalized) _buildLogChip(plant.id, LogType.vitalizer, logStatus),
              ],
            ),
          ),
      ],
    );
  }

  /// 未来日のカードに出す予定チップ（Issue #316）。
  ///
  /// その日が予定日になっている種別だけを「この日に水やり」の形で示す。
  /// 予定日が今日より前のまま残っているものは日数を出さず、
  /// 過ぎていることだけを伝える。
  Widget _buildFutureDateChips(
    DateTime selectedDay,
    DateTime? nextWateringDate,
    DateTime? nextFertilizerDate,
    DateTime? nextVitalizerDate,
  ) {
    final scheme = Theme.of(context).colorScheme;
    bool isDueOnSelectedDay(DateTime? d) =>
        d != null && AppDateUtils.isSameDay(AppDateUtils.getDateOnly(d), selectedDay);

    final chips = <Widget>[
      if (isDueOnSelectedDay(nextWateringDate))
        _buildScheduleChip(
          icon: Icons.water_drop,
          label: 'この日に水やり',
          isOverdue: false,
          normalColor: scheme.tertiary,
        ),
      if (isDueOnSelectedDay(nextFertilizerDate))
        _buildScheduleChip(
          icon: Icons.grass,
          label: 'この日に肥料',
          isOverdue: false,
          normalColor: scheme.tertiary,
        ),
      if (isDueOnSelectedDay(nextVitalizerDate))
        _buildScheduleChip(
          icon: Icons.favorite,
          label: 'この日に活力剤',
          isOverdue: false,
          normalColor: scheme.tertiary,
        ),
    ];

    if (chips.isEmpty) {
      // その日が予定日ではないのに並んでいる＝予定日を過ぎたまま残っているもの
      return _buildScheduleChip(
        icon: Icons.priority_high,
        label: '予定日を過ぎています',
        isOverdue: true,
        normalColor: scheme.error,
      );
    }

    return Wrap(spacing: 8, runSpacing: 2, children: chips);
  }

  /// 予定日チップ（アイコン＋テキスト）を構築する (#125)
  ///
  /// 超過しているものだけ errorContainer で塗りつぶし、リストの中で
  /// 遅れている予定が拾えるようにする（Issue #294）。
  Widget _buildScheduleChip({
    required IconData icon,
    required String label,
    required bool isOverdue,
    required Color normalColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isOverdue ? scheme.onErrorContainer : normalColor;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: isOverdue ? color : null,
            fontSize: 12,
            fontWeight: isOverdue ? FontWeight.w700 : null,
          ),
        ),
      ],
    );

    if (!isOverdue) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }

  Widget _buildLogChip(String plantId, LogType logType, DailyLogStatus logStatus) {
    final config = _getLogChipConfig(logType);
    return ActionChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            config.label,
            style: TextStyle(
              fontSize: 11,
              color: config.foregroundColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.close,
            size: 12,
            color: config.foregroundColor(context),
          ),
        ],
      ),
      avatar: Icon(
        config.icon,
        size: 14,
        color: config.foregroundColor(context),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      backgroundColor: config.backgroundColor(context),
      onPressed: () => _deleteLog(plantId, logType, logStatus),
    );
  }

  _LogChipConfig _getLogChipConfig(LogType logType) {
    final colors = context.read<SettingsProvider>().logTypeColors;
    
    switch (logType) {
      case LogType.watering:
        return _LogChipConfig(
          label: '水やり',
          icon: Icons.water_drop,
          backgroundColor: (context) => Color(colors.wateringBg),
          foregroundColor: (context) => Color(colors.wateringFg),
        );
      case LogType.fertilizer:
        return _LogChipConfig(
          label: '肥料',
          icon: Icons.grass,
          backgroundColor: (context) => Color(colors.fertilizerBg),
          foregroundColor: (context) => Color(colors.fertilizerFg),
        );
      case LogType.vitalizer:
        return _LogChipConfig(
          label: '活力剤',
          icon: Icons.favorite,
          backgroundColor: (context) => Color(colors.vitalizerBg),
          foregroundColor: (context) => Color(colors.vitalizerFg),
        );
      default:
        // 記録専用のケアタイプ（Issue #175）はスケジュール画面に表示されないため
        // 到達しない想定だが、exhaustive switch のため汎用表示を返す
        return _LogChipConfig(
          label: 'その他',
          icon: Icons.spa,
          backgroundColor: (context) =>
              Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: (context) =>
              Theme.of(context).colorScheme.onSecondaryContainer,
        );
    }
  }

  Future<void> _navigateToPlantDetail(Plant plant) async {
    // データが変更された場合に true が返る
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        // 水やりログ画面からの遷移はログタブ（index=1）を直接開く (#127)
        builder: (context) => PlantDetailScreen(plant: plant, initialTabIndex: 1),
      ),
    );
    // データ変更があった場合のみ再ロードする（ログを見ただけなら不要）
    if (mounted && changed == true) {
      await context.read<PlantProvider>().loadPlants();
      setState(() {
        _refreshKey++;
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
      default:
        return 'その他';
    }
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

  /// 予定日（日付のみ）を取り出す。予定が無ければ null。
  DateTime? _dueDateOnly(String plantId, Map<String, DateTime?> cache) {
    final date = cache[plantId];
    return date == null ? null : AppDateUtils.getDateOnly(date);
  }

  /// 予定超過（いずれかの予定日が今日より前）かどうかを返す（Issue #294）。
  bool _isPastDue(
    String plantId,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final today = AppDateUtils.getDateOnly(DateTime.now());
    return [
      _dueDateOnly(plantId, nextWateringDateCache),
      _dueDateOnly(plantId, nextFertilizerDateCache),
      _dueDateOnly(plantId, nextVitalizerDateCache),
    ].any((date) => date != null && date.isBefore(today));
  }

  /// ワンタップ記録ボタンで記録する種別を返す（Issue #294）。
  ///
  /// 予定日が今日以前で、かつ選択日にまだ記録していない種別のうち、
  /// 最も予定日が早いものを選ぶ。該当が無ければ null（ボタンを出さない）。
  LogType? _quickRecordLogType(
    String plantId,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
    Map<String, DateTime?> nextFertilizerDateCache,
    Map<String, DateTime?> nextVitalizerDateCache,
  ) {
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final candidates = <LogType, DateTime?>{
      LogType.watering: logStatus.isWatered(plantId)
          ? null
          : _dueDateOnly(plantId, nextWateringDateCache),
      LogType.fertilizer: logStatus.isFertilized(plantId)
          ? null
          : _dueDateOnly(plantId, nextFertilizerDateCache),
      LogType.vitalizer: logStatus.isVitalized(plantId)
          ? null
          : _dueDateOnly(plantId, nextVitalizerDateCache),
    };

    LogType? best;
    DateTime? bestDate;
    for (final entry in candidates.entries) {
      final date = entry.value;
      if (date == null || date.isAfter(today)) continue;
      if (bestDate == null || date.isBefore(bestDate)) {
        best = entry.key;
        bestDate = date;
      }
    }
    return best;
  }

  /// 1件だけその場で記録する（Issue #294）。取り消しは SnackBar から行える。
  Future<void> _recordSingleLog(Plant plant, LogType logType) async {
    final plantProvider = context.read<PlantProvider>();
    await plantProvider.bulkRecordLogs([plant.id], [logType], _selectedDate);
    await _refreshAfterLogChange();
    _showSuccessMessage(
      '${plant.name}に${_getLogTypeName(logType)}を記録しました',
      onUndo: () async {
        final deleted = await plantProvider.deleteMultipleLogsForDate(
          plant.id,
          [logType],
          _selectedDate,
        );
        await _refreshAfterLogChange();
        if (deleted.isNotEmpty) _showSuccessMessage('記録を取り消しました');
      },
    );
  }
}

/// 水やりログのリストに並べる1要素（Issue #294）。
///
/// セクション見出し・植物カード・記録済みの折りたたみ行のいずれかを表す。
class _LogListItem {
  /// セクション見出しのラベル（見出し以外では null）
  final String? headerLabel;

  /// セクション見出しの色（見出し以外では null）
  final Color? headerColor;

  /// 植物カードとして表示する植物（カード以外では null）
  final Plant? plant;

  /// 記録済みの折りたたみ行の件数（折りたたみ行以外では null）
  final int? completedCount;

  /// その日のケアを完了したことを示す表示か（Issue #305）
  final bool isAllDone;

  const _LogListItem.header(String label, Color color)
      : headerLabel = label,
        headerColor = color,
        plant = null,
        completedCount = null,
        isAllDone = false;

  const _LogListItem.plant(this.plant)
      : headerLabel = null,
        headerColor = null,
        completedCount = null,
        isAllDone = false;

  const _LogListItem.completed(int count)
      : headerLabel = null,
        headerColor = null,
        plant = null,
        completedCount = count,
        isAllDone = false;

  const _LogListItem.allDone()
      : headerLabel = null,
        headerColor = null,
        plant = null,
        completedCount = null,
        isAllDone = true;
}

/// ログチップの設定
class _LogChipConfig {
  final String label;
  final IconData icon;
  final Color Function(BuildContext) backgroundColor;
  final Color Function(BuildContext) foregroundColor;

  _LogChipConfig({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });
}

/// _buildDatePage で使用する1日分のデータ集約クラス
class _DatePageData {
  final DailyLogStatus logStatus;
  final Map<String, DateTime?> nextWateringDateCache;
  final Map<String, DateTime?> nextFertilizerDateCache;
  final Map<String, DateTime?> nextVitalizerDateCache;

  const _DatePageData({
    required this.logStatus,
    required this.nextWateringDateCache,
    required this.nextFertilizerDateCache,
    required this.nextVitalizerDateCache,
  });
}

/// ログ種別選択ダイアログ
class _LogTypeSelectionDialog extends StatefulWidget {
  const _LogTypeSelectionDialog();

  @override
  State<_LogTypeSelectionDialog> createState() => _LogTypeSelectionDialogState();
}

class _LogTypeSelectionDialogState extends State<_LogTypeSelectionDialog> {
  final Set<LogType> _selectedTypes = {LogType.watering};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('記録する内容を選択'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: _selectedTypes.contains(LogType.watering),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedTypes.add(LogType.watering);
                } else if (_selectedTypes.length > 1) {
                  _selectedTypes.remove(LogType.watering);
                }
              });
            },
            title: const Text('水やり'),
            secondary: const Icon(Icons.water_drop),
          ),
          CheckboxListTile(
            value: _selectedTypes.contains(LogType.fertilizer),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedTypes.add(LogType.fertilizer);
                } else if (_selectedTypes.length > 1) {
                  _selectedTypes.remove(LogType.fertilizer);
                }
              });
            },
            title: const Text('肥料'),
            secondary: const Icon(Icons.grass),
          ),
          CheckboxListTile(
            value: _selectedTypes.contains(LogType.vitalizer),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedTypes.add(LogType.vitalizer);
                } else if (_selectedTypes.length > 1) {
                  _selectedTypes.remove(LogType.vitalizer);
                }
              });
            },
            title: const Text('活力剤'),
            secondary: const Icon(Icons.favorite),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedTypes),
          child: const Text('記録する'),
        ),
      ],
    );
  }
}

/// カレンダー凡例の1項目（色付きドット＋ラベル）。Issue #234。
class _CalendarLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _CalendarLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
