import 'package:flutter_test/flutter_test.dart';
import 'package:bota_note/services/export_service.dart';

void main() {
  group('ExportService.parseImagePathList', () {
    test('写真が無いノートの "[]" は参照0件として扱う', () {
      // 素朴に '|' で分割すると "[]" を1件の参照として数えてしまい、
      // 写真の無いノートの数だけ「復元できませんでした」と誤警告が出る
      expect(ExportService.parseImagePathList('[]'), isEmpty);
    });

    test('空文字・null は参照0件として扱う', () {
      expect(ExportService.parseImagePathList(''), isEmpty);
      expect(ExportService.parseImagePathList(null), isEmpty);
    });

    test("ZIP エクスポートの '|' 区切りを分解できる", () {
      expect(
        ExportService.parseImagePathList(
          'images/notes/a_0.jpg|images/notes/a_1.jpg',
        ),
        ['images/notes/a_0.jpg', 'images/notes/a_1.jpg'],
      );
    });

    test("'|' を含まない単一パスも1件として返す", () {
      expect(ExportService.parseImagePathList('images/notes/a_0.jpg'), [
        'images/notes/a_0.jpg',
      ]);
    });

    test('DB 由来の JSON 配列を分解できる', () {
      expect(
        ExportService.parseImagePathList(
          '["/data/app/a.jpg","/data/app/b.jpg"]',
        ),
        ['/data/app/a.jpg', '/data/app/b.jpg'],
      );
    });

    test('リストがそのまま渡された場合も文字列リストにする', () {
      expect(ExportService.parseImagePathList(['/data/app/a.jpg']), [
        '/data/app/a.jpg',
      ]);
    });

    test("'[' で始まるが壊れた JSON は '|' 区切りとして解釈する", () {
      expect(ExportService.parseImagePathList('[broken|images/notes/a_0.jpg'), [
        '[broken',
        'images/notes/a_0.jpg',
      ]);
    });
  });
}
