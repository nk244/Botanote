import 'package:flutter_test/flutter_test.dart';
import 'package:bota_note/models/log_entry.dart';

/// 未対応のログ種別を含むバックアップで復元全体が失敗した不具合の回帰テスト
/// （Issue #319）。あわせて UTC 表記の取り扱い（Issue #338）も確認する。
void main() {
  Map<String, dynamic> baseMap({
    String type = 'watering',
    String date = '2026-08-31T09:00:00.000',
  }) {
    return {
      'id': 'log-1',
      'plantId': 'plant-1',
      'type': type,
      'date': date,
      'note': null,
      'createdAt': date,
      'updatedAt': date,
    };
  }

  group('LogEntry.parseType', () {
    test('既知の種別名は対応する LogType を返す', () {
      expect(LogEntry.parseType('watering'), LogType.watering);
      expect(LogEntry.parseType('repotting'), LogType.repotting);
      expect(LogEntry.parseType('cleaning'), LogType.cleaning);
    });

    test('未知の種別名・非文字列は null を返す', () {
      // 新しいバージョンで追加された種別を古いバージョンが読む場合に起きる
      expect(LogEntry.parseType('repot'), isNull);
      expect(LogEntry.parseType(''), isNull);
      expect(LogEntry.parseType(null), isNull);
      expect(LogEntry.parseType(123), isNull);
    });
  });

  group('LogEntry.fromMap', () {
    test('未対応の種別名では FormatException をスローする', () {
      // 以前は StateError('Bad state: No element') になり、
      // 何が問題か分からないまま復元全体が失敗していた
      expect(
        () => LogEntry.fromMap(baseMap(type: 'repot')),
        throwsA(isA<FormatException>()),
      );
    });

    test('既知の種別名なら通常どおり変換できる', () {
      final log = LogEntry.fromMap(baseMap(type: 'fertilizer'));
      expect(log.type, LogType.fertilizer);
      expect(log.plantId, 'plant-1');
    });
  });

  group('LogEntry.tryFromMap', () {
    test('未対応の種別名では null を返し、例外を投げない', () {
      // 1件だけ読み飛ばしてバックアップ全体の復元を続けられるようにする
      expect(LogEntry.tryFromMap(baseMap(type: 'repot')), isNull);
    });

    test('フィールドが欠けていても null を返す', () {
      final broken = baseMap()..remove('plantId');
      expect(LogEntry.tryFromMap(broken), isNull);
    });

    test('日付が壊れていても null を返す', () {
      expect(LogEntry.tryFromMap(baseMap(date: 'not-a-date')), isNull);
    });

    test('正常な行はそのまま変換できる', () {
      final log = LogEntry.tryFromMap(baseMap(type: 'vitalizer'));
      expect(log, isNotNull);
      expect(log!.type, LogType.vitalizer);
    });
  });

  group('日時のローカル変換（Issue #338）', () {
    test('UTC 表記（末尾 Z）はローカル時刻に揃えられる', () {
      final log = LogEntry.fromMap(baseMap(date: '2026-08-31T00:00:00.000Z'));
      expect(log.date.isUtc, isFalse);
      // ローカルの同一時刻を指していること（タイムゾーンに依らず成立する）
      expect(log.date.toUtc(), DateTime.utc(2026, 8, 31));
    });

    test('ナイーブ表記はそのままローカル時刻として扱う', () {
      final log = LogEntry.fromMap(baseMap(date: '2026-08-31T09:00:00.000'));
      expect(log.date.isUtc, isFalse);
      expect(log.date, DateTime(2026, 8, 31, 9));
    });
  });
}
