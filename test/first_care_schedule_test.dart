import 'package:flutter_test/flutter_test.dart';

import 'package:bota_note/models/log_entry.dart';
import 'package:bota_note/models/plant.dart';
import 'package:bota_note/providers/plant_provider.dart';
import 'package:bota_note/utils/care_text_utils.dart';

/// 初回ケア（記録が1件も無い状態）の予定日と文言の回帰テスト（Issue #349）。
///
/// 購入日・登録日が過去の株を登録すると、初回の予定日まで過去になり
/// 「水やり 90日前（予定超過）」と表示されていた。一度も記録していないケアは
/// 遅れではなく「これから最初に行うケア」として扱う。
void main() {
  final now = DateTime(2026, 9, 6);

  Plant buildPlant({
    DateTime? purchaseDate,
    int? wateringIntervalDays = 7,
    int? fertilizerIntervalDays,
    int? vitalizerIntervalDays,
  }) {
    return Plant(
      id: 'p1',
      name: 'テスト株',
      purchaseDate: purchaseDate,
      wateringIntervalDays: wateringIntervalDays,
      fertilizerIntervalDays: fertilizerIntervalDays,
      vitalizerIntervalDays: vitalizerIntervalDays,
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
    );
  }

  group('初回の水やり予定日', () {
    test('購入日が過去でも、水やりログが無ければ予定日は今日まで繰り上がる', () {
      final provider = PlantProvider();
      final plant = buildPlant(purchaseDate: DateTime(2026, 6, 1));

      final next = provider.calcNextWateringDateFromLogs(
        plant,
        const <LogEntry>[],
        now: now,
      );

      // 6/1 + 7日 = 6/8（90日前）ではなく、今日に繰り上げる
      expect(next, DateTime(2026, 9, 6));
    });

    test('購入日が無ければ登録日を起算日にし、同じく今日まで繰り上がる', () {
      final provider = PlantProvider();
      final plant = buildPlant();

      final next = provider.calcNextWateringDateFromLogs(
        plant,
        const <LogEntry>[],
        now: now,
      );

      expect(next, DateTime(2026, 9, 6));
    });

    test('購入日が最近なら初回の予定日は未来のまま（繰り上げない）', () {
      final provider = PlantProvider();
      final plant = buildPlant(purchaseDate: DateTime(2026, 9, 4));

      final next = provider.calcNextWateringDateFromLogs(
        plant,
        const <LogEntry>[],
        now: now,
      );

      // 9/4 + 7日 = 9/11
      expect(next, DateTime(2026, 9, 11));
    });

    test('水やりログがあれば従来どおり最終水やり日から計算し、超過はそのまま出す', () {
      final provider = PlantProvider();
      final plant = buildPlant(purchaseDate: DateTime(2026, 6, 1));

      final next = provider.calcNextWateringDateFromLogs(plant, [
        LogEntry(
          id: 'w1',
          plantId: 'p1',
          type: LogType.watering,
          date: DateTime(2026, 8, 1),
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ),
      ], now: now);

      // 記録に基づく遅れは実態どおり残す（8/1 + 7日 = 8/8）
      expect(next, DateTime(2026, 8, 8));
    });
  });

  group('水やりログが無い株の肥料・活力剤の予定日', () {
    test('繰り上げ後の水やり予定日を起算日にするため、過去日にならない', () {
      final provider = PlantProvider();
      final plant = buildPlant(
        purchaseDate: DateTime(2026, 6, 1),
        fertilizerIntervalDays: 30,
        vitalizerIntervalDays: 14,
      );

      final nextWatering = provider.calcNextWateringDateFromLogs(
        plant,
        const <LogEntry>[],
        now: now,
      );
      final nextFertilizer = provider.calcNextFertilizerDateFromLogs(
        plant,
        const <LogEntry>[],
        const <LogEntry>[],
        nextWatering,
      );
      final nextVitalizer = provider.calcNextVitalizerDateFromLogs(
        plant,
        const <LogEntry>[],
        const <LogEntry>[],
        nextWatering,
      );

      // 「肥料が90日前」「活力剤が70日前」ではなく、今日を起点にした未来日になる
      expect(nextFertilizer, DateTime(2026, 10, 6));
      expect(nextVitalizer, DateTime(2026, 9, 20));
    });
  });

  group('初回ケアの文言', () {
    test('種別ごとに「最初の〇〇」を返す', () {
      expect(firstCareShortLabel(LogType.watering), '最初の水やり');
      expect(firstCareShortLabel(LogType.fertilizer), '最初の肥料');
      expect(firstCareShortLabel(LogType.vitalizer), '最初の活力剤');
      expect(firstCareGuideText(LogType.watering), '最初の水やりをしましょう');
      expect(firstCareGuideText(LogType.fertilizer), '最初の肥料をあげましょう');
      expect(firstCareGuideText(LogType.vitalizer), '最初の活力剤をあげましょう');
    });
  });
}
