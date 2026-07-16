import 'package:flutter_test/flutter_test.dart';
import 'package:bota_note/utils/seasonal_interval_utils.dart';

/// #200 の検証: 冬季間隔延長は「間隔の起算日（＝最後にケアした日）」が
/// 休眠期の場合にのみ適用される、という設計を明文化する回帰テスト。
void main() {
  group('applySeasonalAdjustment', () {
    test('休眠期（12〜2月）の起算日では倍率が適用され間隔が延びる', () {
      // 12月に水やり → 次回間隔は 7 * 1.5 = 10.5 → 11日
      expect(
        applySeasonalAdjustment(
          baseIntervalDays: 7,
          seasonalAdjustmentEnabled: true,
          dormantMultiplier: 1.5,
          referenceDate: DateTime(2026, 12, 3),
        ),
        11,
      );
      // 1月・2月も休眠期
      expect(
        applySeasonalAdjustment(
          baseIntervalDays: 10,
          seasonalAdjustmentEnabled: true,
          dormantMultiplier: 2.0,
          referenceDate: DateTime(2027, 1, 15),
        ),
        20,
      );
    });

    test('非休眠期の起算日では延長されない（例: 8月に水やり）', () {
      // 8月に水やり → 12月に画面を見ても間隔は起算日基準なので延びない。
      // これはシミュレーションで観測した「12月でも次回予定が変わらない」挙動が
      // 設計通りであることを示す（Issue #200 は誤検知）。
      expect(
        applySeasonalAdjustment(
          baseIntervalDays: 7,
          seasonalAdjustmentEnabled: true,
          dormantMultiplier: 1.5,
          referenceDate: DateTime(2026, 8, 3),
        ),
        7,
      );
    });

    test('季節調整が無効なら休眠期でも延長されない', () {
      expect(
        applySeasonalAdjustment(
          baseIntervalDays: 7,
          seasonalAdjustmentEnabled: false,
          dormantMultiplier: 1.5,
          referenceDate: DateTime(2026, 12, 3),
        ),
        7,
      );
    });

    test('倍率が null なら延長されない', () {
      expect(
        applySeasonalAdjustment(
          baseIntervalDays: 7,
          seasonalAdjustmentEnabled: true,
          dormantMultiplier: null,
          referenceDate: DateTime(2026, 12, 3),
        ),
        7,
      );
    });

    test('isDormantSeason は 12・1・2 月のみ true', () {
      expect(isDormantSeason(DateTime(2026, 12, 1)), isTrue);
      expect(isDormantSeason(DateTime(2027, 1, 1)), isTrue);
      expect(isDormantSeason(DateTime(2027, 2, 28)), isTrue);
      expect(isDormantSeason(DateTime(2027, 3, 1)), isFalse);
      expect(isDormantSeason(DateTime(2026, 11, 30)), isFalse);
      expect(isDormantSeason(DateTime(2026, 8, 3)), isFalse);
    });
  });
}
