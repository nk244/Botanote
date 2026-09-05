import 'package:flutter/material.dart';

/// 置き場所の追加・編集ダイアログの入力結果（Issue #341）。
class LocationEditResult {
  /// 入力された場所名（前後の空白は除去済み）。
  final String name;

  /// 屋外かどうか。
  final bool isOutdoor;

  const LocationEditResult({required this.name, required this.isOutdoor});
}

/// 置き場所を追加・編集するダイアログ（Issue #341）。
///
/// `TextEditingController` をこのダイアログ自身が所有し、[State.dispose] で
/// 破棄する。呼び出し側が `showDialog` の直後に破棄すると、退場アニメーション中の
/// `TextField` が破棄済みの controller を参照し、debug ビルドで
/// `_dependents.isEmpty` のアサーションに失敗して画面が赤くなっていた。
class LocationEditDialog extends StatefulWidget {
  /// ダイアログのタイトル。
  final String title;

  /// 場所名の初期値。
  final String initialName;

  /// 「屋外」スイッチの初期値。
  final bool initialIsOutdoor;

  const LocationEditDialog({
    super.key,
    required this.title,
    this.initialName = '',
    this.initialIsOutdoor = false,
  });

  /// ダイアログを表示し、保存されたら入力内容を返す。
  ///
  /// キャンセル・場所名が空のまま閉じた場合は null を返す。
  static Future<LocationEditResult?> show(
    BuildContext context, {
    required String title,
    String initialName = '',
    bool initialIsOutdoor = false,
  }) {
    return showDialog<LocationEditResult>(
      context: context,
      builder: (_) => LocationEditDialog(
        title: title,
        initialName: initialName,
        initialIsOutdoor: initialIsOutdoor,
      ),
    );
  }

  @override
  State<LocationEditDialog> createState() => _LocationEditDialogState();
}

class _LocationEditDialogState extends State<LocationEditDialog> {
  late final TextEditingController _nameController;
  late bool _isOutdoor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _isOutdoor = widget.initialIsOutdoor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(
      context,
    ).pop(LocationEditResult(name: name, isOutdoor: _isOutdoor));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      // 名前欄を自動フォーカスするとIMEのフローティングツールバーが「屋外」
      // スイッチに重なり、タップしても切り替わらなくなる（Issue #268）。
      // 自動フォーカスをやめ、内容もスクロール可能にして退避できるようにする。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '場所名',
                border: OutlineInputBorder(),
                hintText: '例: リビング、ベランダ',
              ),
              // 保存ボタンの活性状態を即座に反映するため、入力のたびに再描画する
              onChanged: (_) => setState(() {}),
              // 入力確定でキーボードを閉じ、下のスイッチを操作できるようにする
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('屋外'),
              subtitle: const Text('天気連動ケアアラートの対象になります'),
              value: _isOutdoor,
              onChanged: (value) {
                // スイッチ操作時にキーボードが出ていれば閉じる
                FocusScope.of(context).unfocus();
                setState(() => _isOutdoor = value);
              },
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
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
