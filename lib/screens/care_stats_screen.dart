import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/log_entry.dart';
import '../models/plant.dart';
import '../providers/plant_provider.dart';

/// 統計の集計期間（Issue #290）。
enum StatsPeriod {
  /// 直近6ヶ月（当月含む）
  months6,

  /// 直近12ヶ月（当月含む）
  months12,

  /// 記録のある全期間
  all,
}

/// ログデータから月別件数・種別合計・植物ごとの頻度を振り返る統計画面（Issue #182）。
class CareStatsScreen extends StatefulWidget {
  const CareStatsScreen({super.key});

  @override
  State<CareStatsScreen> createState() => _CareStatsScreenState();
}

class _CareStatsScreenState extends State<CareStatsScreen> {
  /// 植物ごとのケア頻度で、折りたたみ時に表示する件数
  static const int _rankingCollapsedCount = 10;

  bool _isLoading = true;
  List<LogEntry> _logs = [];

  /// 選択中の集計期間（Issue #290）
  StatsPeriod _period = StatsPeriod.months6;

  /// 植物ごとのケア頻度を全件表示しているか（Issue #290）
  bool _showAllRanking = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final logs = await context.read<PlantProvider>().getAllLogsAcrossPlants();
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  String _periodLabel(StatsPeriod period) {
    switch (period) {
      case StatsPeriod.months6:
        return '6ヶ月';
      case StatsPeriod.months12:
        return '12ヶ月';
      case StatsPeriod.all:
        return '全期間';
    }
  }

  /// 見出しに添える期間の説明を返す。
  String get _periodCaption {
    switch (_period) {
      case StatsPeriod.months6:
        return '直近6ヶ月';
      case StatsPeriod.months12:
        return '直近12ヶ月';
      case StatsPeriod.all:
        return '全期間';
    }
  }

  /// 集計対象に含める最も古い月（その月の1日）を返す。
  ///
  /// 全期間の場合は記録のある最も古い月を起点にする。
  DateTime _startMonth() {
    final now = DateTime.now();
    switch (_period) {
      case StatsPeriod.months6:
        return DateTime(now.year, now.month - 5);
      case StatsPeriod.months12:
        return DateTime(now.year, now.month - 11);
      case StatsPeriod.all:
        if (_logs.isEmpty) return DateTime(now.year, now.month);
        final oldest = _logs
            .map((log) => log.date)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        return DateTime(oldest.year, oldest.month);
    }
  }

  /// 選択中の期間に含まれるログだけを返す。
  List<LogEntry> get _logsInPeriod {
    if (_period == StatsPeriod.all) return _logs;
    final start = _startMonth();
    return _logs.where((log) => !log.date.isBefore(start)).toList();
  }

  String _typeLabel(LogType type) {
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

  IconData _typeIcon(LogType type) {
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

  /// 選択中の期間の月別ログ件数を返す（キー: yyyy-MM、古い月から昇順）。
  List<MapEntry<DateTime, int>> _monthlyCounts() {
    final now = DateTime.now();
    final start = _startMonth();
    final monthCount =
        (now.year - start.year) * 12 + (now.month - start.month) + 1;
    final months = List.generate(
      monthCount,
      (i) => DateTime(start.year, start.month + i),
    );

    final counts = {for (final m in months) m: 0};
    for (final log in _logsInPeriod) {
      final month = DateTime(log.date.year, log.date.month);
      if (counts.containsKey(month)) {
        counts[month] = counts[month]! + 1;
      }
    }
    return months.map((m) => MapEntry(m, counts[m]!)).toList();
  }

  Map<LogType, int> _typeCounts() {
    final counts = {for (final t in LogType.values) t: 0};
    for (final log in _logsInPeriod) {
      counts[log.type] = (counts[log.type] ?? 0) + 1;
    }
    return counts;
  }

  /// 植物ごとのケア件数を多い順に返す（表示件数の制限はしない）。
  List<MapEntry<Plant, int>> _plantRanking(List<Plant> plants) {
    final counts = <String, int>{};
    for (final log in _logsInPeriod) {
      counts[log.plantId] = (counts[log.plantId] ?? 0) + 1;
    }
    return plants
        .where((p) => counts.containsKey(p.id))
        .map((p) => MapEntry(p, counts[p.id]!))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ケア統計')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'まだケアの記録がありません',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '水やり・肥料等を記録すると、ここで振り返れます',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : Consumer<PlantProvider>(
                  builder: (context, plantProvider, _) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildPeriodSelector(context),
                        const SizedBox(height: 20),
                        Text('月別ケア件数（$_periodCaption）',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildMonthlyChart(context),
                        const SizedBox(height: 24),
                        Text('種別ごとの件数（$_periodCaption）',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildTypeCounts(context),
                        const SizedBox(height: 24),
                        _buildPlantRankingSection(context, plantProvider.plants),
                      ],
                    );
                  },
                ),
    );
  }

  /// 集計期間を切り替えるセグメントボタン（Issue #290）。
  Widget _buildPeriodSelector(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<StatsPeriod>(
        segments: StatsPeriod.values
            .map((period) => ButtonSegment<StatsPeriod>(
                  value: period,
                  label: Text(_periodLabel(period)),
                ))
            .toList(),
        selected: {_period},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() {
            _period = selection.first;
            // 期間を変えると母数が変わるため、ランキングの展開状態は畳み直す
            _showAllRanking = false;
          });
        },
      ),
    );
  }

  /// 月別グラフの横軸ラベルを組み立てる（Issue #236）。
  ///
  /// 直近6ヶ月が年を跨ぐと「1月」だけでは何年か分からないため、
  /// 先頭の月と、年の変わり目（1月）には西暦下2桁を添える。
  String _monthLabel(DateTime month, DateTime? previous) {
    final isYearBoundary = previous == null || month.year != previous.year;
    if (isYearBoundary) {
      final yy = (month.year % 100).toString().padLeft(2, '0');
      return "'$yy/${month.month}月";
    }
    return '${month.month}月';
  }

  Widget _buildMonthlyChart(BuildContext context) {
    final monthly = _monthlyCounts();
    final maxCount = monthly.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    const chartHeight = 120.0;
    // 6ヶ月までは画面幅いっぱいに広げ、それ以上は横スクロールにして
    // 棒とラベルが潰れないようにする（Issue #290）
    const monthsWithoutScroll = 6;
    const barSlotWidth = 52.0;
    final needsScroll = monthly.length > monthsWithoutScroll;

    final bars = monthly.asMap().entries.map((indexed) {
      final i = indexed.key;
      final entry = indexed.value;
      final prevMonth = i > 0 ? monthly[i - 1].key : null;
      final barHeight =
          maxCount == 0 ? 0.0 : chartHeight * entry.value / maxCount;
      final bar = Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${entry.value}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Container(
            height: barHeight < 4 && entry.value > 0 ? 4 : barHeight,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _monthLabel(entry.key, prevMonth),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      return needsScroll
          ? SizedBox(width: barSlotWidth, child: bar)
          : Expanded(child: bar);
    }).toList();

    final chart = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: needsScroll ? MainAxisSize.min : MainAxisSize.max,
      children: bars,
    );

    return SizedBox(
      height: chartHeight + 40,
      child: needsScroll
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: chart,
            )
          : chart,
    );
  }

  Widget _buildTypeCounts(BuildContext context) {
    final counts = _typeCounts();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: LogType.values.map((type) {
        final count = counts[type] ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Icon(_typeIcon(type),
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 4),
                Text('$count回',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(_typeLabel(type),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 植物ごとのケア頻度セクション（見出し＋一覧＋もっと見る）。Issue #290。
  Widget _buildPlantRankingSection(BuildContext context, List<Plant> plants) {
    final ranking = _plantRanking(plants);
    final isTruncated =
        !_showAllRanking && ranking.length > _rankingCollapsedCount;
    final visible =
        isTruncated ? ranking.take(_rankingCollapsedCount).toList() : ranking;

    final heading = ranking.isEmpty
        ? '植物ごとのケア頻度'
        : isTruncated
            ? '植物ごとのケア頻度（上位$_rankingCollapsedCount件）'
            : '植物ごとのケア頻度（全${ranking.length}件）';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildPlantRanking(context, visible),
        if (ranking.length > _rankingCollapsedCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  setState(() => _showAllRanking = !_showAllRanking),
              child: Text(
                isTruncated
                    ? 'もっと見る（残り${ranking.length - _rankingCollapsedCount}件）'
                    : '上位$_rankingCollapsedCount件だけ表示',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlantRanking(
      BuildContext context, List<MapEntry<Plant, int>> ranking) {
    if (ranking.isEmpty) {
      return Text('データがありません', style: Theme.of(context).textTheme.bodySmall);
    }

    return Column(
      children: ranking.asMap().entries.map((entry) {
        final rank = entry.key + 1;
        final plant = entry.value.key;
        final count = entry.value.value;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 14,
            child: Text('$rank', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(plant.name),
          trailing: Text('$count回',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }
}
