import 'package:flutter_test/flutter_test.dart';
import 'package:bota_note/screens/bulk_add_plants_screen.dart';

void main() {
  group('parsePlantList', () {
    test('1行1植物として名前を読み取る', () {
      final drafts = parsePlantList('モンステラ\nポトス\nサンスベリア');
      expect(drafts.map((d) => d.nameController.text).toList(), [
        'モンステラ',
        'ポトス',
        'サンスベリア',
      ]);
      expect(drafts.every((d) => d.varietyController.text.isEmpty), isTrue);
    });

    test('「名前 / 品種」を名前と品種に分ける', () {
      final drafts = parsePlantList('モンステラ / デリシオサ');
      expect(drafts.single.nameController.text, 'モンステラ');
      expect(drafts.single.varietyController.text, 'デリシオサ');
    });

    test('「名前（品種）」を名前と品種に分ける', () {
      final drafts = parsePlantList('サンスベリア（ローレンチー）');
      expect(drafts.single.nameController.text, 'サンスベリア');
      expect(drafts.single.varietyController.text, 'ローレンチー');
    });

    test('箇条書き記号・番号・Markdownの強調を取り除く', () {
      final drafts = parsePlantList(
        '- モンステラ\n'
        '1. ポトス\n'
        '* **サンスベリア**\n'
        '・アガベ',
      );
      expect(drafts.map((d) => d.nameController.text).toList(), [
        'モンステラ',
        'ポトス',
        'サンスベリア',
        'アガベ',
      ]);
    });

    test('空行と記号だけの行は無視する', () {
      final drafts = parsePlantList('モンステラ\n\n---\n\nポトス');
      expect(drafts.map((d) => d.nameController.text).toList(), [
        'モンステラ',
        'ポトス',
      ]);
    });

    test('同じ名前と品種の行が重複しても1件にまとめる', () {
      final drafts = parsePlantList('モンステラ\nモンステラ\nモンステラ / デリシオサ');
      expect(drafts.length, 2);
      expect(drafts[0].varietyController.text, '');
      expect(drafts[1].varietyController.text, 'デリシオサ');
    });

    test('読み取った候補は既定で選択済みになる', () {
      final drafts = parsePlantList('モンステラ');
      expect(drafts.single.selected, isTrue);
    });

    test('空文字からは何も読み取らない', () {
      expect(parsePlantList(''), isEmpty);
      expect(parsePlantList('   \n\n  '), isEmpty);
    });
  });
}
