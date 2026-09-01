/// 日本語の名前を五十音順で比較するためのユーティリティ（Issue #257）。
///
/// `String.compareTo` は UTF-16 のコードポイント順で比較するため、
/// 「冬型→多肉→月兎耳→朧月→火祭り」のように読みと無関係な順序になる。
/// ここでは以下の方針で並べる。
///
/// 1. 読み仮名（`nameReading`）が入力されていればそれを優先して使う
/// 2. 全角カタカナはひらがなへ、半角カナは全角へ正規化して比較する
/// 3. 濁点・半濁点・長音・小書き文字の違いは無視して比較し、
///    同値になった場合のみ元の文字列で比較して順序を安定させる
///
/// 漢字は読みを機械的に導けないため、読み仮名が未入力の漢字名は
/// かな名のあとにコードポイント順で並ぶ。
library;

/// ソート用のキー文字列を生成する。
///
/// [reading] があればそれを、無ければ [name] を正規化して返す。
String buildJapaneseSortKey(String name, String? reading) {
  final source = (reading != null && reading.trim().isNotEmpty)
      ? reading.trim()
      : name;
  return _normalizeForSort(source);
}

/// 五十音順に比較する。
///
/// 正規化後のキーが同値の場合は元の文字列で比較し、順序を安定させる。
int compareJapanese(
  String aName,
  String? aReading,
  String bName,
  String? bReading,
) {
  final aKey = buildJapaneseSortKey(aName, aReading);
  final bKey = buildJapaneseSortKey(bName, bReading);

  // かな始まりを漢字・英数字より先に並べる（読み順で探せるようにするため）
  final aKana = _startsWithKana(aKey);
  final bKana = _startsWithKana(bKey);
  if (aKana != bKana) return aKana ? -1 : 1;

  final byKey = aKey.compareTo(bKey);
  if (byKey != 0) return byKey;
  return aName.compareTo(bName);
}

/// 比較用に文字列を正規化する。
///
/// - 半角カナ → 全角カナ
/// - カタカナ → ひらがな
/// - 濁点/半濁点を除去（か = が）
/// - 小書き文字を大書きへ（っ = つ）
/// - 長音記号「ー」と中黒「・」、空白を除去
String _normalizeForSort(String input) {
  final buffer = StringBuffer();
  for (final rune in _toFullWidthKana(input).runes) {
    var c = rune;

    // カタカナ（ァ-ヶ）をひらがなへ寄せる
    if (c >= 0x30A1 && c <= 0x30F6) {
      c -= 0x60;
    }

    // 長音・中黒・各種空白は無視する
    if (c == 0x30FC || c == 0x30FB || c == 0x0020 || c == 0x3000) {
      continue;
    }

    // 濁点・半濁点・小書きを基本形へ寄せる
    c = _kanaBaseForm[c] ?? c;

    buffer.writeCharCode(c);
  }
  return buffer.toString();
}

/// 先頭がひらがな（正規化後）かどうか。
bool _startsWithKana(String normalized) {
  if (normalized.isEmpty) return false;
  final c = normalized.runes.first;
  return c >= 0x3041 && c <= 0x3096;
}

/// 半角カナを全角カナに変換する。
///
/// 濁点・半濁点は後段で落とすため、ここでは基本形のみ対応させる。
String _toFullWidthKana(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final mapped = _halfToFullKana[rune];
    buffer.write(mapped ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

/// 濁点・半濁点・小書きのひらがなを基本形に対応付ける表。
const Map<int, int> _kanaBaseForm = {
  0x304C: 0x304B, // が→か
  0x304E: 0x304D, // ぎ→き
  0x3050: 0x304F, // ぐ→く
  0x3052: 0x3051, // げ→け
  0x3054: 0x3053, // ご→こ
  0x3056: 0x3055, // ざ→さ
  0x3058: 0x3057, // じ→し
  0x305A: 0x3059, // ず→す
  0x305C: 0x305B, // ぜ→せ
  0x305E: 0x305D, // ぞ→そ
  0x3060: 0x305F, // だ→た
  0x3062: 0x3061, // ぢ→ち
  0x3065: 0x3064, // づ→つ
  0x3067: 0x3066, // で→て
  0x3069: 0x3068, // ど→と
  0x3070: 0x306F, // ば→は
  0x3071: 0x306F, // ぱ→は
  0x3073: 0x3072, // び→ひ
  0x3074: 0x3072, // ぴ→ひ
  0x3076: 0x3075, // ぶ→ふ
  0x3077: 0x3075, // ぷ→ふ
  0x3079: 0x3078, // べ→へ
  0x307A: 0x3078, // ぺ→へ
  0x307C: 0x307B, // ぼ→ほ
  0x307D: 0x307B, // ぽ→ほ
  0x3041: 0x3042, // ぁ→あ
  0x3043: 0x3044, // ぃ→い
  0x3045: 0x3046, // ぅ→う
  0x3047: 0x3048, // ぇ→え
  0x3049: 0x304A, // ぉ→お
  0x3063: 0x3064, // っ→つ
  0x3083: 0x3084, // ゃ→や
  0x3085: 0x3086, // ゅ→ゆ
  0x3087: 0x3088, // ょ→よ
  0x308E: 0x308F, // ゎ→わ
};

/// 半角カナ → 全角カナ（基本形のみ）
const Map<int, String> _halfToFullKana = {
  0xFF66: 'ヲ',
  0xFF67: 'ァ',
  0xFF68: 'ィ',
  0xFF69: 'ゥ',
  0xFF6A: 'ェ',
  0xFF6B: 'ォ',
  0xFF6C: 'ャ',
  0xFF6D: 'ュ',
  0xFF6E: 'ョ',
  0xFF6F: 'ッ',
  0xFF70: 'ー',
  0xFF71: 'ア',
  0xFF72: 'イ',
  0xFF73: 'ウ',
  0xFF74: 'エ',
  0xFF75: 'オ',
  0xFF76: 'カ',
  0xFF77: 'キ',
  0xFF78: 'ク',
  0xFF79: 'ケ',
  0xFF7A: 'コ',
  0xFF7B: 'サ',
  0xFF7C: 'シ',
  0xFF7D: 'ス',
  0xFF7E: 'セ',
  0xFF7F: 'ソ',
  0xFF80: 'タ',
  0xFF81: 'チ',
  0xFF82: 'ツ',
  0xFF83: 'テ',
  0xFF84: 'ト',
  0xFF85: 'ナ',
  0xFF86: 'ニ',
  0xFF87: 'ヌ',
  0xFF88: 'ネ',
  0xFF89: 'ノ',
  0xFF8A: 'ハ',
  0xFF8B: 'ヒ',
  0xFF8C: 'フ',
  0xFF8D: 'ヘ',
  0xFF8E: 'ホ',
  0xFF8F: 'マ',
  0xFF90: 'ミ',
  0xFF91: 'ム',
  0xFF92: 'メ',
  0xFF93: 'モ',
  0xFF94: 'ヤ',
  0xFF95: 'ユ',
  0xFF96: 'ヨ',
  0xFF97: 'ラ',
  0xFF98: 'リ',
  0xFF99: 'ル',
  0xFF9A: 'レ',
  0xFF9B: 'ロ',
  0xFF9C: 'ワ',
  0xFF9D: 'ン',
};
