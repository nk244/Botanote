import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plant.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import 'plant_image_widget.dart';

/// 植物を複数選択するための共通ダイアログ。
///
/// ノート編集・水やりログ・置き場所詳細の3箇所で使う。並び順は必ず
/// [PlantProvider.getSortedPlants] を通すため、どの画面から開いても
/// アプリの並び順設定に従う（Issue #293）。
class PlantPickerDialog extends StatefulWidget {
  const PlantPickerDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.candidates,
    this.initialSelectedIds = const <String>{},
    this.allowEmptyConfirm = true,
    this.showImages = false,
    this.subtitleBuilder,
  });

  /// ダイアログのタイトル
  final String title;

  /// 確定ボタンのラベル
  final String confirmLabel;

  /// 選択対象を絞り込む場合に渡す。null なら登録済みの全植物を対象にする。
  ///
  /// 渡した場合も並び順は呼び出し元の順序ではなくアプリ設定に従う。
  final List<Plant>? candidates;

  /// 初期選択状態の植物ID
  final Set<String> initialSelectedIds;

  /// 未選択のまま確定できるか。false の場合は確定ボタンを非活性にする。
  final bool allowEmptyConfirm;

  /// 各行にサムネイル画像を表示するか
  final bool showImages;

  /// 行のサブタイトルを差し替える。null を返した行は品種名を表示する。
  final String? Function(Plant plant)? subtitleBuilder;

  /// ダイアログを表示し、選択された植物IDの集合を返す。
  ///
  /// キャンセルされた場合は null を返す。
  static Future<Set<String>?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    List<Plant>? candidates,
    Set<String> initialSelectedIds = const <String>{},
    bool allowEmptyConfirm = true,
    bool showImages = false,
    String? Function(Plant plant)? subtitleBuilder,
  }) {
    return showDialog<Set<String>>(
      context: context,
      builder: (_) => PlantPickerDialog(
        title: title,
        confirmLabel: confirmLabel,
        candidates: candidates,
        initialSelectedIds: initialSelectedIds,
        allowEmptyConfirm: allowEmptyConfirm,
        showImages: showImages,
        subtitleBuilder: subtitleBuilder,
      ),
    );
  }

  @override
  State<PlantPickerDialog> createState() => _PlantPickerDialogState();
}

class _PlantPickerDialogState extends State<PlantPickerDialog> {
  late final Set<String> _selectedIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  /// アプリの並び順設定に従って並べた選択候補を返す。
  List<Plant> _sortedCandidates(BuildContext context) {
    final plantProvider = context.read<PlantProvider>();
    final settings = context.read<SettingsProvider>();
    final sorted = plantProvider.getSortedPlants(
      settings.plantSortOrder,
      settings.customSortOrder,
    );

    final candidates = widget.candidates;
    if (candidates == null) return sorted;

    // 呼び出し元が対象を絞っている場合も、並びは常にアプリ設定に合わせる
    final allowedIds = candidates.map((p) => p.id).toSet();
    return sorted.where((p) => allowedIds.contains(p.id)).toList();
  }

  /// 検索文字列で絞り込んだ結果を返す（植物名・品種名を対象にする）。
  List<Plant> _filter(List<Plant> plants) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return plants;
    return plants
        .where(
          (plant) =>
              plant.name.toLowerCase().contains(query) ||
              (plant.variety?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  /// 絞り込み結果に対して全選択／全解除を切り替える。
  void _toggleSelectAll(List<Plant> filtered, bool allSelected) {
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(filtered.map((p) => p.id));
      } else {
        _selectedIds.addAll(filtered.map((p) => p.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _sortedCandidates(context);
    final filtered = _filter(candidates);
    final allSelected =
        filtered.isNotEmpty &&
        filtered.every((plant) => _selectedIds.contains(plant.id));

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '検索',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedIds.length}件選択中',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: filtered.isEmpty
                      ? null
                      : () => _toggleSelectAll(filtered, allSelected),
                  child: Text(allSelected ? '全解除' : '全選択'),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('植物が見つかりません'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, index) =>
                          _buildPlantTile(filtered[index]),
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
        FilledButton(
          onPressed: !widget.allowEmptyConfirm && _selectedIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.from(_selectedIds)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  Widget _buildPlantTile(Plant plant) {
    final customSubtitle = widget.subtitleBuilder?.call(plant);
    final subtitleText = customSubtitle ?? plant.variety;

    return CheckboxListTile(
      value: _selectedIds.contains(plant.id),
      onChanged: (checked) {
        setState(() {
          if (checked == true) {
            _selectedIds.add(plant.id);
          } else {
            _selectedIds.remove(plant.id);
          }
        });
      },
      title: Text(plant.name),
      subtitle: subtitleText != null ? Text(subtitleText) : null,
      secondary: widget.showImages
          ? PlantImageWidget(plant: plant, width: 40, height: 40)
          : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
