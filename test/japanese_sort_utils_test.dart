import 'package:flutter_test/flutter_test.dart';
import 'package:bota_note/utils/japanese_sort_utils.dart';

/// 名前だけのリストを五十音順に並べたものを返すテスト用ヘルパー。
List<String> _sortedByName(List<String> names) {
  final copy = [...names]..sort((a, b) => compareJapanese(a, null, b, null));
  return copy;
}

/// (名前, 読み仮名) のリストを五十音順に並べて名前だけ返すヘルパー。
List<String> _sortedWithReading(List<(String, String?)> entries) {
  final copy = [...entries]
    ..sort((a, b) => compareJapanese(a.$1, a.$2, b.$1, b.$2));
  return copy.map((e) => e.$1).toList();
}

void main() {
  group('compareJapanese', () {
    test('ひらがなは五十音順に並ぶ', () {
      expect(_sortedByName(['さくら', 'あさがお', 'かすみそう']), ['あさがお', 'かすみそう', 'さくら']);
    });

    test('カタカナはひらがなと同じ読み位置に並ぶ', () {
      expect(_sortedByName(['サクラ', 'あさがお', 'カスミソウ']), ['あさがお', 'カスミソウ', 'サクラ']);
    });

    test('濁点・半濁点は清音と同じ位置で比較される', () {
      // が・か は同値扱いなので、2文字目の「き」「く」で決まる
      expect(_sortedByName(['がく', 'かき']), ['かき', 'がく']);
    });

    test('長音・中黒は無視される', () {
      // 「アガベ・チタノタ」→「あかへちたのた」、「アガベ」→「あかへ」
      expect(_sortedByName(['アガベ・チタノタ', 'アガベ']), ['アガベ', 'アガベ・チタノタ']);
    });

    test('小書き文字は大書きと同じ位置で比較される', () {
      // 「きゃ」→「きや」なので「きは」より後ろ
      expect(_sortedByName(['きゃく', 'きはい']), ['きはい', 'きゃく']);
    });

    test('読み仮名が入力されていれば漢字名でも五十音順に並ぶ', () {
      // Issue #257: 読み仮名が無いとコードポイント順になってしまうケース
      expect(
        _sortedWithReading([
          ('火祭り', 'ひまつり'),
          ('朧月', 'おぼろづき'),
          ('月兎耳', 'つきとじ'),
          ('多肉', 'たにく'),
        ]),
        ['朧月', '多肉', '月兎耳', '火祭り'],
      );
    });

    test('かな名は読み仮名なしの漢字名より先に並ぶ', () {
      final sorted = _sortedWithReading([
        ('朧月', null),
        ('アガベ', null),
        ('さくら', null),
      ]);
      expect(sorted.take(2), ['アガベ', 'さくら']);
      expect(sorted.last, '朧月');
    });

    test('読み仮名が空文字の場合は名前で比較する', () {
      expect(_sortedWithReading([('さくら', '   '), ('あさがお', '')]), [
        'あさがお',
        'さくら',
      ]);
    });

    test('半角カナは全角カナと同じ位置で比較される', () {
      expect(_sortedByName(['ｻｸﾗ', 'あさがお']), ['あさがお', 'ｻｸﾗ']);
    });
  });

  group('buildJapaneseSortKey', () {
    test('読み仮名があればそれを正規化して返す', () {
      expect(buildJapaneseSortKey('朧月', 'オボロヅキ'), 'おほろつき');
    });

    test('読み仮名が無ければ名前を正規化して返す', () {
      expect(buildJapaneseSortKey('アガベ・チタノタ', null), 'あかへちたのた');
    });
  });
}
