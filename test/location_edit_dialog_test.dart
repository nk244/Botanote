import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bota_note/widgets/location_edit_dialog.dart';

void main() {
  group('LocationEditDialog（Issue #341）', () {
    testWidgets('保存すると入力内容が返り、閉じるまでにアサーションで落ちない', (tester) async {
      LocationEditResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await LocationEditDialog.show(
                    context,
                    title: '置き場所を追加',
                  );
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), ' Living ');
      await tester.pump();
      await tester.tap(find.widgetWithText(SwitchListTile, '屋外'));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      // 退場アニメーションが終わるまで進める。controller をダイアログ側で
      // 所有していないと、ここで _dependents.isEmpty のアサーションに失敗する。
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.name, 'Living');
      expect(result!.isOutdoor, isTrue);
    });

    testWidgets('場所名が空のあいだは保存できない', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => LocationEditDialog.show(
                  context,
                  title: '置き場所を追加',
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('キャンセルすると null が返る', (tester) async {
      LocationEditResult? result;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await LocationEditDialog.show(
                    context,
                    title: '置き場所を編集',
                    initialName: 'Desk',
                  );
                  closed = true;
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('Desk'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });
  });
}
