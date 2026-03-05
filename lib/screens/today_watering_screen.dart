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
import 'plant_detail_screen.dart';
import 'settings_screen.dart';

class TodayWateringScreen extends StatefulWidget {
  const TodayWateringScreen({super.key});

  @override
  State<TodayWateringScreen> createState() => _TodayWateringScreenState();
}

class _TodayWateringScreenState extends State<TodayWateringScreen> {
  // 現在選択中の日付
  DateTime _selectedDate = AppDateUtils.getDateOnly(DateTime.now());
  DateTime _focusedDay = DateTime.now();
  bool _isCalendarView = false;

  // PageView用コントローラー。中央値を初期ページとして対応日数小を計算する。
  static const int _initialPage = 10000;
  late final PageController _pageController;

  // FutureBuilderの再実行トリガー用カウンタ
  int _refreshKey = 0;

  final Set<String> _selectedPlantIds = {};
  final Set<LogType> _selectedBulkLogTypes = {LogType.watering};
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<PlantProvider>().loadPlants();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TodayWateringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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

    final allPlants = {...plantsWithRecords, ...plantsNeedingAction}.toList();
    allPlants.sort((a, b) => _comparePlantsFor(a, b, logStatus, nextWateringDateCache));
    return allPlants;
  }

  int _comparePlantsFor(
    Plant a,
    Plant b,
    DailyLogStatus logStatus,
    Map<String, DateTime?> nextWateringDateCache,
  ) {
    final aCompleted = logStatus.isWatered(a.id);
    final bCompleted = logStatus.isWatered(b.id);

    // 完了済みは下に並ぶ
    if (aCompleted && !bCompleted) return 1;
    if (!aCompleted && bCompleted) return -1;

    final settings = context.read<SettingsProvider>();
    final sortOrder = settings.plantSortOrder;
    
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
        final customOrder = settings.customSortOrder;
        if (customOrder.isNotEmpty) {
          final aIndex = customOrder.indexOf(a.id);
          final bIndex = customOrder.indexOf(b.id);
          if (aIndex == -1 && bIndex == -1) return 0;
          if (aIndex == -1) return 1;
          if (bIndex == -1) return -1;
          return aIndex.compareTo(bIndex);
        }
        // フォールバック：水やり予定日順
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

  Future<void> _recordLog(
    PlantProvider provider,
    String plantId,
    LogType logType,
  ) async {
    switch (logType) {
      case LogType.watering:
        await provider.recordWatering(plantId, _selectedDate, null);
        break;
      case LogType.fertilizer:
        await provider.recordFertilizer(plantId, _selectedDate, null);
        break;
      case LogType.vitalizer:
        await provider.recordVitalizer(plantId, _selectedDate, null);
        break;
    }
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

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteLog(
    String plantId,
    LogType logType,
    DailyLogStatus logStatus,
  ) async {
    // 水やりの場合、仙6記録があるか確認
    final hasOtherLogs = (logType == LogType.watering) &&
        logStatus.hasOtherLogs(plantId, LogType.watering);
    
    final logTypesToDelete = await _confirmDeletion(hasOtherLogs, plantId, logType, logStatus);
    if (logTypesToDelete == null) return;

    final plantProvider = context.read<PlantProvider>();
    await plantProvider.deleteMultipleLogsForDate(
      plantId,
      logTypesToDelete,
      _selectedDate,
    );

    await _refreshAfterLogChange();
    _showSuccessMessage(_buildDeleteMessage(logTypesToDelete, logType));
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
          IconButton(
            icon: const Icon(Icons.settings),
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
      floatingActionButton: _selectedPlantIds.isNotEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
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
                FloatingActionButton.extended(
                  onPressed: _bulkLog,
                  icon: const Icon(Icons.check),
                  label: Text('${_selectedPlantIds.length}件登録'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildCalendarView() {
    return Consumer<PlantProvider>(
      builder: (context, plantProvider, _) {
        final logDates = plantProvider.logDates;

        return Column(
          children: [
            TableCalendar(
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
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              eventLoader: (day) {
                final d = DateTime(day.year, day.month, day.day);
                return logDates.contains(d) ? [true] : [];
              },
              calendarStyle: CalendarStyle(
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
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

  /// 指定日のログデータをDBから取得するFuture
  Future<_DatePageData> _loadDatePageData(DateTime date) async {
    final plantProvider = context.read<PlantProvider>();
    final plants = plantProvider.plants;
    final wateredMap = <String, bool>{};
    final fertilizedMap = <String, bool>{};
    final vitalizedMap = <String, bool>{};
    final nextWateringDateCache = <String, DateTime?>{};
    final nextFertilizerDateCache = <String, DateTime?>{};
    final nextVitalizerDateCache = <String, DateTime?>{};

    for (final plant in plants) {
      nextWateringDateCache[plant.id] =
          await plantProvider.calculateNextWateringDate(plant.id);
      nextFertilizerDateCache[plant.id] =
          await plantProvider.calculateNextFertilizerDate(plant.id);
      nextVitalizerDateCache[plant.id] =
          await plantProvider.calculateNextVitalizerDate(plant.id);
      wateredMap[plant.id] =
          await plantProvider.hasLogOnDate(plant.id, LogType.watering, date);
      fertilizedMap[plant.id] =
          await plantProvider.hasLogOnDate(plant.id, LogType.fertilizer, date);
      vitalizedMap[plant.id] =
          await plantProvider.hasLogOnDate(plant.id, LogType.vitalizer, date);
    }

    return _DatePageData(
      logStatus: DailyLogStatus(
        watered: wateredMap,
        fertilized: fertilizedMap,
        vitalized: vitalizedMap,
      ),
      nextWateringDateCache: nextWateringDateCache,
      nextFertilizerDateCache: nextFertilizerDateCache,
      nextVitalizerDateCache: nextVitalizerDateCache,
    );
  }

  /// 1日分のページを構築する
  Widget _buildDatePage(DateTime date) {
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final isToday = AppDateUtils.isSameDay(date, today);

    return Consumer<PlantProvider>(
      builder: (context, plantProvider, _) {
        return FutureBuilder<_DatePageData>(
          // _refreshKeyが変化するたびにFutureが再実行される
          key: ValueKey('${date.millisecondsSinceEpoch}_$_refreshKey'),
          future: _loadDatePageData(date),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
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
                if (logStatus.hasAnyRecords) _buildSummaryFor(logStatus),
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
            onPressed: () {
              if (_isCalendarView) {
                final prev = AppDateUtils.getDateOnly(
                    date.subtract(const Duration(days: 1)));
                setState(() {
                  _selectedDate = prev;
                  _focusedDay = prev;
                  _selectedPlantIds.clear();
                });
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
            onPressed: () {
              if (_isCalendarView) {
                final next = AppDateUtils.getDateOnly(
                    date.add(const Duration(days: 1)));
                setState(() {
                  _selectedDate = next;
                  _focusedDay = next;
                  _selectedPlantIds.clear();
                });
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

  Widget _buildSummaryFor(DailyLogStatus logStatus) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (logStatus.wateredCount > 0)
            _buildSummaryItem(
              Icons.water_drop,
              '${logStatus.wateredCount}件の水やり',
            ),
          if (logStatus.fertilizedCount > 0)
            _buildSummaryItem(
              Icons.grass,
              '${logStatus.fertilizedCount}件の肥料',
            ),
          if (logStatus.vitalizedCount > 0)
            _buildSummaryItem(
              Icons.favorite,
              '${logStatus.vitalizedCount}件の活力剤',
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
        ),
      ],
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

    return Column(
      children: [
        if (incompletePlants.isNotEmpty)
          _buildBulkSelectionHeader(incompletePlants),
        Expanded(
          child: ListView.builder(
            controller: _listScrollController,
            padding: const EdgeInsets.only(
                left: 8, right: 8, top: 8, bottom: 80),
            itemCount: incompletePlants.length +
                (completedPlants.isNotEmpty ? 1 : 0) +
                completedPlants.length,
            itemBuilder: (context, index) {
              if (index < incompletePlants.length) {
                return _buildPlantCard(
                    incompletePlants[index], logStatus,
                    nextWateringDateCache, nextFertilizerDateCache,
                    nextVitalizerDateCache, date);
              }
              if (index == incompletePlants.length &&
                  completedPlants.isNotEmpty) {
                return _buildDivider();
              }
              final completedIndex = index -
                  incompletePlants.length -
                  (completedPlants.isNotEmpty ? 1 : 0);
              return _buildPlantCard(
                  completedPlants[completedIndex], logStatus,
                  nextWateringDateCache, nextFertilizerDateCache,
                  nextVitalizerDateCache, date);
            },
          ),
        ),
        _buildAddUnscheduledWateringButton(hasPlants: true),
      ],
    );
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.eco_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isToday ? '今日は水やりの予定と記録がありません' : 'この日は水やりの予定と記録がありません',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showUnscheduledWateringDialog,
            icon: const Icon(Icons.add),
            label: const Text('水やり記録をつける'),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              thickness: 2,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '水やり完了',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Divider(
              thickness: 2,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
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
          label: Text(hasPlants ? 'その他の植物に水やり' : '水やり記録をつける'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ),
    );
  }

  Future<void> _showUnscheduledWateringDialog() async {
    final plantProvider = context.read<PlantProvider>();
    final allPlants = plantProvider.plants;
    // 現在の日付データを直接DBから取得して未予定植物を判定する
    final data = await _loadDatePageData(_selectedDate);
    final plantsForDate = _getPlantsForDate(
      allPlants, _selectedDate, data.logStatus,
      data.nextWateringDateCache, data.nextFertilizerDateCache, data.nextVitalizerDateCache,
    ).toSet();
    
    // Get plants not in today's list
    final unscheduledPlants = allPlants
        .where((plant) => !plantsForDate.contains(plant))
        .toList();
    
    if (unscheduledPlants.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('すべての植物が表示されています')),
        );
      }
      return;
    }

    final selectedPlant = await showDialog<Plant>(
      context: context,
      builder: (context) => _UnscheduledWateringDialog(
        plants: unscheduledPlants,
      ),
    );

    if (selectedPlant != null && mounted) {
      // Show log type selection dialog
      final selectedLogTypes = await showDialog<Set<LogType>>(
        context: context,
        builder: (context) => _LogTypeSelectionDialog(),
      );

      if (selectedLogTypes != null && selectedLogTypes.isNotEmpty && mounted) {
        // Record selected log types for the plant
        for (final logType in selectedLogTypes) {
          await _recordLog(plantProvider, selectedPlant.id, logType);
        }
        await _refreshAfterLogChange();
        
        final logTypeNames = selectedLogTypes
            .map((type) => _getLogTypeName(type))
            .join('・');
        _showSuccessMessage('${selectedPlant.name}に$logTypeNamesを記録しました');
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
    final nextDay = nextWateringDate != null
        ? AppDateUtils.getDateOnly(nextWateringDate)
        : null;
    // 水やり超過: 予定日 ≦ 今日
    final isOverdue = nextDay != null && !nextDay.isAfter(today);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3)
          : null,
      child: ListTile(
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
        title: Text(plant.name),
        subtitle: _buildPlantSubtitle(
          plant,
          nextWateringDate,
          nextFertilizerDate,
          nextVitalizerDate,
          selectedDay,
          isOverdue,
          hasAnyLog,
          isWatered,
          isFertilized,
          isVitalized,
          logStatus,
        ),
        onTap: () => _navigateToPlantDetail(plant),
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
    bool isOverdue,
    bool hasAnyLog,
    bool isWatered,
    bool isFertilized,
    bool isVitalized,
    DailyLogStatus logStatus,
  ) {
    // 肥料・活力剤の超過判定も今日基準で統一する (#124)
    final today = AppDateUtils.getDateOnly(DateTime.now());
    bool isDateDue(DateTime? d) =>
        d != null && !AppDateUtils.getDateOnly(d).isAfter(today);

    // 水やり・肥料・活力剤の予定を横並び1行でまとめて表示する (#125)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plant.variety != null) Text(plant.variety!),
        // 予定がある項目を Wrap で横並びにまとめる
        if (nextWateringDate != null ||
            nextFertilizerDate != null ||
            nextVitalizerDate != null)
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              if (nextWateringDate != null)
                _buildScheduleChip(
                  icon: Icons.water_drop,
                  label: AppDateUtils.formatDateDifference(nextWateringDate),
                  isOverdue: isOverdue,
                  normalColor: Theme.of(context).colorScheme.primary,
                ),
              if (nextFertilizerDate != null)
                _buildScheduleChip(
                  icon: Icons.grass,
                  label: AppDateUtils.formatDateDifference(nextFertilizerDate),
                  isOverdue: isDateDue(nextFertilizerDate),
                  normalColor: Theme.of(context).colorScheme.secondary,
                ),
              if (nextVitalizerDate != null)
                _buildScheduleChip(
                  icon: Icons.favorite,
                  label: AppDateUtils.formatDateDifference(nextVitalizerDate),
                  isOverdue: isDateDue(nextVitalizerDate),
                  normalColor: Theme.of(context).colorScheme.tertiary,
                ),
            ],
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

  /// 予定日チップ（アイコン＋テキスト）を構築する (#125)
  Widget _buildScheduleChip({
    required IconData icon,
    required String label,
    required bool isOverdue,
    required Color normalColor,
  }) {
    final color = isOverdue ? Theme.of(context).colorScheme.error : normalColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: isOverdue ? color : null, fontSize: 12)),
      ],
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
    }
  }

  Future<void> _navigateToPlantDetail(Plant plant) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        // 水やりログ画面からの遷移はログタブ（index=1）を直接開く (#127)
        builder: (context) => PlantDetailScreen(plant: plant, initialTabIndex: 1),
      ),
    );
    // 詳細画面から戻った後にFutureBuilderを再実行して最新データを反映する
    if (mounted) {
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
    }
  }
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

/// Dialog for selecting unscheduled plants to water
class _UnscheduledWateringDialog extends StatefulWidget {
  final List<Plant> plants;

  const _UnscheduledWateringDialog({required this.plants});

  @override
  State<_UnscheduledWateringDialog> createState() => _UnscheduledWateringDialogState();
}

class _UnscheduledWateringDialogState extends State<_UnscheduledWateringDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredPlants = widget.plants
        .where((plant) =>
            plant.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (plant.variety?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
        .toList();

    return AlertDialog(
      title: const Text('水やり記録をつける'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400, // ダイアログの最大高さを制限してRenderFlexオーバーフロー回避
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '検索',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredPlants.isEmpty
                  ? const Center(child: Text('植物が見つかりません'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredPlants.length,
                      itemBuilder: (context, index) {
                        final plant = filteredPlants[index];
                        return ListTile(
                          leading: PlantImageWidget(plant: plant, width: 40, height: 40),
                          title: Text(plant.name),
                          subtitle: plant.variety != null ? Text(plant.variety!) : null,
                          onTap: () => Navigator.of(context).pop(plant),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }
}
