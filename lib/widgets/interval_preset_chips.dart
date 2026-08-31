import 'package:flutter/material.dart';

/// 水やり・肥料などの間隔設定でよく使う日数（Issue #330）。
///
/// ±1日ボタンだけだと 30日・60日にするのに数十回タップが必要だったため、
/// 代表的な値をワンタップで選べるようにする。
const List<int> kIntervalPresetDays = [3, 5, 7, 10, 14, 21, 30, 60];

/// 間隔のプリセット選択チップ行を組み立てる。
///
/// [current] と一致するチップは選択状態で表示する。
/// [onSelected] にはタップされた日数が渡る。
Widget buildIntervalPresetChips(
  BuildContext context, {
  required int current,
  required ValueChanged<int> onSelected,
  List<int> presets = kIntervalPresetDays,
}) {
  return Wrap(
    alignment: WrapAlignment.center,
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final days in presets)
        ChoiceChip(
          label: Text('$days日'),
          selected: current == days,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onSelected(days),
        ),
    ],
  );
}
