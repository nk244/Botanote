import 'package:flutter_test/flutter_test.dart';

import 'package:bota_note/models/log_entry.dart';
import 'package:bota_note/models/plant.dart';
import 'package:bota_note/providers/plant_provider.dart';

/// 肥料・活力剤の次回予定日の起算日ルールの回帰テスト（Issue #285）。
///
/// `calcNextFertilizerDateFromLogs` / `calcNextVitalizerDateFromLogs` は
/// DBアクセスを伴わない同期メソッドなので、Provider を素で生成して検証できる。
void main() {
  final created = DateTime(2028, 8, 11);

  Plant buildPlant({
    int? wateringIntervalDays = 3,
    int? fertilizerIntervalDays,
    int? fertilizerEveryNWaterings,
    int? vitalizerIntervalDays,
    int? vitalizerEveryNWaterings,
  }) {
    return Plant(
      id: 'p1',
      name: 'テスト株',
      wateringIntervalDays: wateringIntervalDays,
      fertilizerIntervalDays: fertilizerIntervalDays,
      fertilizerEveryNWaterings: fertilizerEveryNWaterings,
      vitalizerIntervalDays: vitalizerIntervalDays,
      vitalizerEveryNWaterings: vitalizerEveryNWaterings,
      createdAt: created,
      updatedAt: created,
    );
  }

  LogEntry log(LogType type, DateTime date) {
    return LogEntry(
      id: '${type.name}-${date.toIso8601String()}',
      plantId: 'p1',
      type: type,
      date: date,
      createdAt: date,
      updatedAt: date,
    );
  }

  group('活力剤の次回予定日（日数指定）', () {
    test('活力剤ログが無い間、水やりを重ねても予定日が後ろへずれない', () {
      final provider = PlantProvider();
      final plant = buildPlant(vitalizerIntervalDays: 10);

      final firstWatering = DateTime(2028, 8, 11);
      final secondWatering = DateTime(2028, 8, 14);

      final afterFirst = provider.calcNextVitalizerDateFromLogs(
        plant,
        const <LogEntry>[],
        [log(LogType.watering, firstWatering)],
        DateTime(2028, 8, 14),
      );
      final afterSecond = provider.calcNextVitalizerDateFromLogs(
        plant,
        const <LogEntry>[],
        [
          log(LogType.watering, firstWatering),
          log(LogType.watering, secondWatering),
        ],
        DateTime(2028, 8, 17),
      );

      // 起算日は「最初の水やり日」に固定されるので 8/11 + 10日 = 8/21 のまま
      expect(afterFirst, DateTime(2028, 8, 21));
      expect(afterSecond, DateTime(2028, 8, 21));
    });

    test('活力剤ログがあれば最後の活力剤日を起算日にする', () {
      final provider = PlantProvider();
      final plant = buildPlant(vitalizerIntervalDays: 10);

      final result = provider.calcNextVitalizerDateFromLogs(
        plant,
        [log(LogType.vitalizer, DateTime(2028, 8, 20))],
        [
          log(LogType.watering, DateTime(2028, 8, 11)),
          log(LogType.watering, DateTime(2028, 8, 23)),
        ],
        DateTime(2028, 8, 26),
      );

      expect(result, DateTime(2028, 8, 30));
    });

    test('水やりログも無ければ次回水やり予定日を起算日にする', () {
      final provider = PlantProvider();
      final plant = buildPlant(vitalizerIntervalDays: 10);

      final result = provider.calcNextVitalizerDateFromLogs(
        plant,
        const <LogEntry>[],
        const <LogEntry>[],
        DateTime(2028, 8, 14),
      );

      expect(result, DateTime(2028, 8, 24));
    });
  });

  group('肥料の次回予定日（日数指定）', () {
    test('肥料ログが無い間、水やりを重ねても予定日が後ろへずれない', () {
      final provider = PlantProvider();
      final plant = buildPlant(fertilizerIntervalDays: 30);

      final waterings = [
        log(LogType.watering, DateTime(2028, 8, 11)),
        log(LogType.watering, DateTime(2028, 8, 14)),
        log(LogType.watering, DateTime(2028, 8, 17)),
      ];

      expect(
        provider.calcNextFertilizerDateFromLogs(
          plant,
          const <LogEntry>[],
          waterings.take(1).toList(),
          null,
        ),
        DateTime(2028, 9, 10),
      );
      expect(
        provider.calcNextFertilizerDateFromLogs(
          plant,
          const <LogEntry>[],
          waterings,
          null,
        ),
        DateTime(2028, 9, 10),
      );
    });
  });

  group('肥料の次回予定日（水やりN回に1回）', () {
    test('N回に到達したら期限は最後の水やり日（超過を隠さない）', () {
      final provider = PlantProvider();
      final plant = buildPlant(
        wateringIntervalDays: 3,
        fertilizerEveryNWaterings: 3,
      );

      final result = provider
          .calcNextFertilizerDateFromLogs(plant, const <LogEntry>[], [
            log(LogType.watering, DateTime(2028, 8, 11)),
            log(LogType.watering, DateTime(2028, 8, 14)),
            log(LogType.watering, DateTime(2028, 8, 17)),
          ], DateTime(2028, 8, 20));

      // 3回目で期限到達。Nサイクル先へ飛ばさず最後の水やり日を返す
      expect(result, DateTime(2028, 8, 17));
    });

    test('途中の回数なら残り回数ぶん先の日付を返す', () {
      final provider = PlantProvider();
      final plant = buildPlant(
        wateringIntervalDays: 3,
        fertilizerEveryNWaterings: 3,
      );

      final result = provider
          .calcNextFertilizerDateFromLogs(plant, const <LogEntry>[], [
            log(LogType.watering, DateTime(2028, 8, 11)),
            log(LogType.watering, DateTime(2028, 8, 14)),
          ], DateTime(2028, 8, 17));

      // 残り1回 → 最後の水やり日 8/14 + 3日
      expect(result, DateTime(2028, 8, 17));
    });

    test('水やりが1回も無ければN回ぶん先の日付を返す', () {
      final provider = PlantProvider();
      final plant = buildPlant(
        wateringIntervalDays: 3,
        fertilizerEveryNWaterings: 3,
      );

      final result = provider.calcNextFertilizerDateFromLogs(
        plant,
        const <LogEntry>[],
        const <LogEntry>[],
        DateTime(2028, 8, 14),
      );

      expect(result, DateTime(2028, 8, 23));
    });
  });
}
