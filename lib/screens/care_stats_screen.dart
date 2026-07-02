import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/log_entry.dart';
import '../models/plant.dart';
import '../providers/plant_provider.dart';

/// ログデータから月別件数・種別合計・植物ごとの頻度を振り返る統計画面（Issue #182）。
class CareStatsScreen extends StatefulWidget {
  const CareStatsScreen({super.key});

  @override
  State<CareStatsScreen> createState() => _CareStatsScreenState();
}

class _CareStatsScreenState extends State<CareStatsScreen> {
  bool _isLoading = true;
  List<LogEntry> _logs = [];

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

  /// 直近6ヶ月（当月含む）の月別ログ件数を返す（キー: yyyy-MM、古い月から昇順）。
  List<MapEntry<DateTime, int>> _monthlyCounts() {
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final target = DateTime(now.year, now.month - (5 - i));
      return DateTime(target.year, target.month);
    });

    final counts = {for (final m in months) m: 0};
    for (final log in _logs) {
      final month = DateTime(log.date.year, log.date.month);
      if (counts.containsKey(month)) {
        counts[month] = counts[month]! + 1;
      }
    }
    return months.map((m) => MapEntry(m, counts[m]!)).toList();
  }

  Map<LogType, int> _typeCounts() {
    final counts = {for (final t in LogType.values) t: 0};
    for (final log in _logs) {
      counts[log.type] = (counts[log.type] ?? 0) + 1;
    }
    return counts;
  }

  List<MapEntry<Plant, int>> _plantRanking(List<Plant> plants) {
    final counts = <String, int>{};
    for (final log in _logs) {
      counts[log.plantId] = (counts[log.plantId] ?? 0) + 1;
    }
    final ranking = plants
        .where((p) => counts.containsKey(p.id))
        .map((p) => MapEntry(p, counts[p.id]!))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranking.take(10).toList();
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
                        Text('月別ケア件数（直近6ヶ月）',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildMonthlyChart(context),
                        const SizedBox(height: 24),
                        Text('種別ごとの合計件数',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildTypeCounts(context),
                        const SizedBox(height: 24),
                        Text('植物ごとのケア頻度（上位10件）',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _buildPlantRanking(context, plantProvider.plants),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildMonthlyChart(BuildContext context) {
    final monthly = _monthlyCounts();
    final maxCount = monthly.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    const chartHeight = 120.0;

    return SizedBox(
      height: chartHeight + 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: monthly.map((entry) {
          final barHeight =
              maxCount == 0 ? 0.0 : chartHeight * entry.value / maxCount;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${entry.value}',
                    style: Theme.of(context).textTheme.bodySmall),
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
                  '${entry.key.month}月',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }).toList(),
      ),
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

  Widget _buildPlantRanking(BuildContext context, List<Plant> plants) {
    final ranking = _plantRanking(plants);
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
