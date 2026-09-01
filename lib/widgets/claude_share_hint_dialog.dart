import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claude連携（画像共有）の仕組みを初回だけ説明するダイアログ（Issue #261）。
///
/// 「Claudeで診断」を押すと OS の共有シートが開く実装のため、
/// 何も説明が無いと Google検索・印刷・Maps などが並ぶ画面が出てきて面食らう。
/// 共有シートを開く前に一度だけ手順を示し、以降は表示しない。
const String _hintShownKey = 'claude_share_hint_shown';

/// 必要なら説明ダイアログを表示し、共有処理を続行してよいかを返す。
///
/// 戻り値が `false` の場合はユーザーがキャンセルしたので共有しない。
/// 2回目以降は何も表示せず `true` を返す。
Future<bool> confirmClaudeShare(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_hintShownKey) ?? false) return true;
  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Claudeアプリに写真を送ります'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'このあと共有先を選ぶ画面が開きます。'
            '一覧から「Claude」を選ぶと、質問文つきで写真が送られます。',
          ),
          SizedBox(height: 12),
          Text(
            'Claudeアプリが一覧に出てこない場合は、'
            'ストアからインストールしてからお試しください。',
          ),
          SizedBox(height: 12),
          Text(
            '※ 回答はClaudeアプリ側に表示されます。'
            'この画面には自動で反映されないため、必要な内容は手動で書き写してください。',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('共有先を選ぶ'),
        ),
      ],
    ),
  );

  if (proceed == true) {
    await prefs.setBool(_hintShownKey, true);
    return true;
  }
  return false;
}
