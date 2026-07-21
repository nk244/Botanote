import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/home_widget_service.dart';
import '../utils/seasonal_interval_utils.dart';

/// 植物データとログを管理する Provider。
///
/// [DatabaseService] を介して SQLite に永続化する。
/// ビジネスロジックの集約点として機能する。
class PlantProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  List<Plant> _plants = [];
  bool _isLoading = false;

  /// true になると loadPlants() が一度以上完了したことを示す。
  /// 初回起動時の「空リスト一瞬表示」を防ぐために使用する。
  bool _isInitialized = false;

  /// loadPlants() が完了するたびに増加するデータ世代カウンタ。
  ///
  /// 画面側がこの値を監視することで、他画面での植物追加・削除・編集や
  /// バックアップからのインポート後にも自前のキャッシュを破棄できる（Issue #213）。
  int _dataVersion = 0;

  final Map<String, DateTime?> _nextWateringCache = {};

  /// カレンダー表示用：ログが存在する日付のセット（時刻なし）
  Set<DateTime> _logDatesCache = {};

  List<Plant> get plants => _plants;
  bool get isLoading => _isLoading;

  /// loadPlants() が一度以上正常完了した場合 true。
  /// 初回起動ローディング中は false のままになる。
  bool get isInitialized => _isInitialized;

  /// loadPlants() の完了回数。値が変わったらデータが入れ替わったことを示す。
  int get dataVersion => _dataVersion;

  Set<DateTime> get logDates => _logDatesCache;

  /// 指定した植物の次回水やり予定日をキャッシュから返す（同期・DBアクセスなし）。
  ///
  /// [loadPlants] 完了後に有効。間隔未設定などで算出できない場合は null。
  /// 一覧画面などで各植物の水やり状態をまとめて表示する用途に使う（Issue #233）。
  DateTime? cachedNextWateringDate(String plantId) => _nextWateringCache[plantId];

  /// 未来を含む「いずれかの植物の次回水やり予定日」の集合を返す（時刻なし）。
  ///
  /// カレンダーで予定日にマーカーを出す用途に使う（Issue #234）。
  Set<DateTime> get scheduledWateringDates {
    final result = <DateTime>{};
    for (final next in _nextWateringCache.values) {
      if (next == null) continue;
      result.add(DateTime(next.year, next.month, next.day));
    }
    return result;
  }

  /// 植物一覧をストレージから再読み込み、キャッシュを更新する。
  Future<void> loadPlants() async {
    _isLoading = true;
    notifyListeners();

    try {
      _plants = await _db.getAllPlants();

      // 次回水やり日キャッシュを更新
      for (var plant in _plants) {
        _nextWateringCache[plant.id] = await calculateNextWateringDate(plant.id);
      }
      // カレンダー表示用のログ日付セットを更新
      final allLogs = await _db.getAllLogs();
      _logDatesCache = allLogs
          .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
          .toSet();

      // ホーム画面ウィジェットに今日の水やり予定を反映する（Issue #174）
      await HomeWidgetService.updateTodayWateringWidget(
          getPlantsNeedingWateringToday());
    } catch (e) {
      debugPrint('Error loading plants: $e');
    } finally {
      _isLoading = false;
      _isInitialized = true;
      _dataVersion++;
      notifyListeners();
    }
  }

  /// 今日水やりが必要な植物一覧を返す（ホーム画面ウィジェット用、Issue #174）。
  /// 判定条件は [hasAnyWateringScheduledForToday] と同じ。
  List<Plant> getPlantsNeedingWateringToday() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return _plants.where((plant) {
      final next = _nextWateringCache[plant.id];
      if (next == null) return false;
      final nextDate = DateTime(next.year, next.month, next.day);
      return !nextDate.isAfter(todayDate);
    }).toList();
  }

  /// ソート設定に従ってソートした植物一覧を返す。
  List<Plant> getSortedPlants(PlantSortOrder sortOrder, List<String> customOrder) {
    final plantsCopy = List<Plant>.from(_plants);
    
    switch (sortOrder) {
      case PlantSortOrder.nameAsc:
        plantsCopy.sort((a, b) => a.name.compareTo(b.name));
        break;
      case PlantSortOrder.nameDesc:
        plantsCopy.sort((a, b) => b.name.compareTo(a.name));
        break;
      case PlantSortOrder.purchaseDateDesc:
        plantsCopy.sort((a, b) {
          if (a.purchaseDate == null && b.purchaseDate == null) return 0;
          if (a.purchaseDate == null) return 1;
          if (b.purchaseDate == null) return -1;
          return b.purchaseDate!.compareTo(a.purchaseDate!);
        });
        break;
      case PlantSortOrder.purchaseDateAsc:
        plantsCopy.sort((a, b) {
          if (a.purchaseDate == null && b.purchaseDate == null) return 0;
          if (a.purchaseDate == null) return 1;
          if (b.purchaseDate == null) return -1;
          return a.purchaseDate!.compareTo(b.purchaseDate!);
        });
        break;
      case PlantSortOrder.createdAtAsc:
        plantsCopy.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case PlantSortOrder.createdAtDesc:
        plantsCopy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case PlantSortOrder.custom:
        if (customOrder.isNotEmpty) {
          plantsCopy.sort((a, b) {
            final aIndex = customOrder.indexOf(a.id);
            final bIndex = customOrder.indexOf(b.id);
            if (aIndex == -1 && bIndex == -1) return 0;
            if (aIndex == -1) return 1;
            if (bIndex == -1) return -1;
            return aIndex.compareTo(bIndex);
          });
        }
        break;
      case PlantSortOrder.varietyAsc:
        // 品種名昇順（品種なしは末尾）
        plantsCopy.sort((a, b) {
          if (a.variety == null && b.variety == null) return 0;
          if (a.variety == null) return 1;
          if (b.variety == null) return -1;
          return a.variety!.compareTo(b.variety!);
        });
        break;
      case PlantSortOrder.varietyDesc:
        // 品種名降順（品種なしは末尾）
        plantsCopy.sort((a, b) {
          if (a.variety == null && b.variety == null) return 0;
          if (a.variety == null) return 1;
          if (b.variety == null) return -1;
          return b.variety!.compareTo(a.variety!);
        });
        break;
    }
    
    return plantsCopy;
  }

  Future<void> addPlant({
    required String name,
    String? variety,
    DateTime? purchaseDate,
    String? purchaseLocation,
    String? imagePath,
    int? wateringIntervalDays,
    int? fertilizerIntervalDays,
    int? fertilizerEveryNWaterings,
    int? vitalizerIntervalDays,
    int? vitalizerEveryNWaterings,
    bool isOutdoor = false,
    String? locationId,
    bool seasonalAdjustmentEnabled = false,
    double? dormantSeasonIntervalMultiplier,
  }) async {
    final now = DateTime.now();
    final plant = Plant(
      id: const Uuid().v4(),
      name: name,
      variety: variety,
      purchaseDate: purchaseDate,
      purchaseLocation: purchaseLocation,
      imagePath: imagePath,
      wateringIntervalDays: wateringIntervalDays,
      fertilizerIntervalDays: fertilizerIntervalDays,
      fertilizerEveryNWaterings: fertilizerEveryNWaterings,
      vitalizerIntervalDays: vitalizerIntervalDays,
      vitalizerEveryNWaterings: vitalizerEveryNWaterings,
      isOutdoor: isOutdoor,
      locationId: locationId,
      seasonalAdjustmentEnabled: seasonalAdjustmentEnabled,
      dormantSeasonIntervalMultiplier: dormantSeasonIntervalMultiplier,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertPlant(plant);
    await loadPlants();
  }

  Future<void> updatePlant(Plant plant) async {
    await _db.updatePlant(plant);
    await loadPlants();
  }

  /// 指定した管理場所に紐づく植物を一括で設定する。
  ///
  /// [plantIds] に含まれる植物は [locationId] を設定し、現在この場所に
  /// 属しているが [plantIds] に含まれない植物は場所の紐づけを解除する。
  Future<void> assignPlantsToLocation(
      String locationId, Set<String> plantIds) async {
    for (final plant in _plants) {
      final shouldBelong = plantIds.contains(plant.id);
      final currentlyBelongs = plant.locationId == locationId;
      if (shouldBelong && !currentlyBelongs) {
        await _db.updatePlant(plant.copyWith(
          locationId: locationId,
          updatedAt: DateTime.now(),
        ));
      } else if (!shouldBelong && currentlyBelongs) {
        await _db.updatePlant(plant.copyWith(
          locationId: null,
          updatedAt: DateTime.now(),
        ));
      }
    }
    await loadPlants();
  }

  Future<void> deletePlant(String id) async {
    await _db.deletePlant(id);

    // Issue #12: 削除した植物IDをノートの plantIds から除去する
    await _removePlantIdFromNotes(id);

    await loadPlants();
  }

  /// 削除された植物IDを参照しているすべてのノートの plantIds から除去する。
  Future<void> _removePlantIdFromNotes(String plantId) async {
    try {
      final notes = await _db.getAllNotes();
      for (final note in notes) {
        if (note.plantIds.contains(plantId)) {
          final updatedNote = note.copyWith(
            plantIds: note.plantIds.where((id) => id != plantId).toList(),
            updatedAt: DateTime.now(),
          );
          await _db.updateNote(updatedNote);
        }
      }
    } catch (e) {
      debugPrint('Error removing plantId from notes: $e');
    }
  }

  Future<void> recordWatering(String plantId, DateTime date, String? note) async {
    // Add watering log
    final log = LogEntry(
      id: const Uuid().v4(),
      plantId: plantId,
      type: LogType.watering,
      date: date,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    // nextWateringDate はログから動的に計算するため、ログ記録時にはキャッシュ更新不要
    await _db.insertLog(log);
    await loadPlants();
  }

  /// 肥料ログを記録する。
  Future<void> recordFertilizer(String plantId, DateTime date, String? note) async {
    final log = LogEntry(
      id: const Uuid().v4(),
      plantId: plantId,
      type: LogType.fertilizer,
      date: date,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertLog(log);
    await loadPlants();
  }

  /// 活力剤ログを記録する。
  Future<void> recordVitalizer(String plantId, DateTime date, String? note) async {
    final log = LogEntry(
      id: const Uuid().v4(),
      plantId: plantId,
      type: LogType.vitalizer,
      date: date,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertLog(log);
    await loadPlants();
  }

  /// 記録専用のケアログ（植え替え・剪定・葉水・掃除等）を記録する（Issue #175）。
  /// 水やり/肥料/活力剤と異なり間隔・スケジュールを持たない。
  Future<void> recordCareLog(
    String plantId,
    LogType type,
    DateTime date,
    String? note,
  ) async {
    final log = LogEntry(
      id: const Uuid().v4(),
      plantId: plantId,
      type: type,
      date: date,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertLog(log);
    await loadPlants();
  }

  /// 複数植物 × 複数ログ種別を一括挿入し、最後に loadPlants を 1回呼び出す。
  /// 画面のチラツキを防止するために一括登録時に使用する。
  Future<void> bulkRecordLogs(
    List<String> plantIds,
    List<LogType> logTypes,
    DateTime date,
  ) async {
    final now = DateTime.now();
    for (final plantId in plantIds) {
      for (final logType in logTypes) {
        final log = LogEntry(
          id: const Uuid().v4(),
          plantId: plantId,
          type: logType,
          date: date,
          note: null,
          createdAt: now,
          updatedAt: now,
        );
        await _db.insertLog(log);
      }
    }
    // 全挿入完了後に1回だけ再読み込み
    await loadPlants();
  }

  /// 今日水やり予定の植物が1つ以上あるか返す。
  /// 通知コールバック用。
  Future<bool> hasAnyWateringScheduledForToday() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    for (final plant in _plants) {
      final next = _nextWateringCache[plant.id];
      if (next != null) {
        final nextDate = DateTime(next.year, next.month, next.day);
        if (!nextDate.isAfter(todayDate)) return true;
      }
    }
    return false;
  }

  /// [plant] の季節調整設定を踏まえた実効間隔日数を返す（Issue #173）。
  ///
  /// [referenceDate]（間隔の起算日）が休眠期（12〜2月）かつ季節調整が
  /// 有効な場合、[baseIntervalDays] に倍率を乗じて延長する。
  int _adjustedInterval(Plant plant, int baseIntervalDays, DateTime referenceDate) {
    return applySeasonalAdjustment(
      baseIntervalDays: baseIntervalDays,
      seasonalAdjustmentEnabled: plant.seasonalAdjustmentEnabled,
      dormantMultiplier: plant.dormantSeasonIntervalMultiplier,
      referenceDate: referenceDate,
    );
  }

  /// 最終水やりログから次回水やり日を動的に計算する。
  /// 水やり間隔が未設定の場合は null を返す。
  // 動的に次回水やり日を計算（ログから算出）
  Future<DateTime?> calculateNextWateringDate(String plantId) async {
    final plant = await _db.getPlant(plantId);
    if (plant == null || plant.wateringIntervalDays == null) return null;

    // 最新の水やり記録を取得
    final wateringLogs = await _db.getLogsByPlantAndType(plantId, LogType.watering);

    if (wateringLogs.isEmpty) {
      // ログなしの場合は購入日または登録日から計算
      final baseDate = plant.purchaseDate ?? plant.createdAt;
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate)));
    }

    // 最新のログから計算
    wateringLogs.sort((a, b) => b.date.compareTo(a.date));
    final lastWatering = wateringLogs.first;
    return lastWatering.date.add(Duration(
        days: _adjustedInterval(
            plant, plant.wateringIntervalDays!, lastWatering.date)));
  }

  /// 最終肥料ログから次回肥料予定日を動的に計算する。
  ///
  /// 起算日の優先順位（日数指定モード）:
  /// 1. 最後に肥料を与えた日
  /// 2. 肥料ログがなければ最後に水やりをした日
  /// 3. 水やりログもなければ次回水やり予定日
  ///
  /// - [fertilizerEveryNWaterings] が設定されている場合: 最終肥料日以降の
  ///   水やり回数が N 回に達する日（水やり間隔から推定）
  /// どちらも未設定の場合は null を返す。
  Future<DateTime?> calculateNextFertilizerDate(String plantId) async {
    final plant = await _db.getPlant(plantId);
    if (plant == null) return null;

    final fertLogs = await _db.getLogsByPlantAndType(plantId, LogType.fertilizer);

    // 日数指定の場合
    if (plant.fertilizerIntervalDays != null) {
      if (fertLogs.isNotEmpty) {
        // 起算日1: 最後に肥料を与えた日
        final sorted = [...fertLogs]..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.fertilizerIntervalDays!, sorted.first.date)));
      }
      // 起算日2: 最後に水やりをした日
      final wateringLogs2 =
          await _db.getLogsByPlantAndType(plantId, LogType.watering);
      if (wateringLogs2.isNotEmpty) {
        final sorted2 = [...wateringLogs2]..sort((a, b) => b.date.compareTo(a.date));
        return sorted2.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.fertilizerIntervalDays!, sorted2.first.date)));
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(Duration(
            days:
                _adjustedInterval(plant, plant.fertilizerIntervalDays!, nextWatering)));
      }
      return null;
    }

    // 水やりN回に1回の場合
    if (plant.fertilizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.fertilizerEveryNWaterings!;
      // 最終肥料日以降の水やりログを数える
      final DateTime? lastFertDate = fertLogs.isEmpty
          ? null
          : ([...fertLogs]..sort((a, b) => b.date.compareTo(a.date))).first.date;

      final wateringLogs =
          await _db.getLogsByPlantAndType(plantId, LogType.watering);

      // 起算日が未定（肥料ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastFertDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([...wateringLogs]
                .where((l) => l.date.isAfter(lastFertDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));

      // 現在のグループ内の残り回数を計算（N回ごとの次の区切りを求める）
      // 例: N=3, 水やり7回の場合 → 7%3=1 → 残り2回（次の区切りは9回目）
      final completedInCurrentGroup = wateringsAfter.length % n;
      // completedInCurrentGroup == 0 は 2 パターンある:
      //   ・水やり実績なし（起算後まだ0回）→ 次のN回目が期限（remaining = n）
      //   ・水やりが N の倍数に到達済み（例: N=3 で3回）→ 施肥期限に到達済みで
      //     期限は最後の水やり日（remaining = 0）。ここを n にすると施肥忘れが
      //     Nサイクル先に飛び、超過状態が隠れてしまう。
      final remaining = completedInCurrentGroup == 0
          ? (wateringsAfter.isEmpty ? n : 0)
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastFertDate ?? (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining));
    }

    return null;
  }

  /// 最終活力剤ログから次回活力剤予定日を動的に計算する。
  ///
  /// 起算日の優先順位（日数指定モード）:
  /// 1. 最後に活力剤を与えた日
  /// 2. 活力剤ログがなければ最後に水やりをした日
  /// 3. 水やりログもなければ次回水やり予定日
  ///
  /// ロジックは [calculateNextFertilizerDate] と同様。
  Future<DateTime?> calculateNextVitalizerDate(String plantId) async {
    final plant = await _db.getPlant(plantId);
    if (plant == null) return null;

    final vitLogs = await _db.getLogsByPlantAndType(plantId, LogType.vitalizer);

    // 日数指定の場合
    if (plant.vitalizerIntervalDays != null) {
      if (vitLogs.isNotEmpty) {
        // 起算日1: 最後に活力剤を与えた日
        final sorted = [...vitLogs]..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.vitalizerIntervalDays!, sorted.first.date)));
      }
      // 起算日2: 最後に水やりをした日
      final wateringLogs2 =
          await _db.getLogsByPlantAndType(plantId, LogType.watering);
      if (wateringLogs2.isNotEmpty) {
        final sorted2 = [...wateringLogs2]..sort((a, b) => b.date.compareTo(a.date));
        return sorted2.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.vitalizerIntervalDays!, sorted2.first.date)));
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(Duration(
            days:
                _adjustedInterval(plant, plant.vitalizerIntervalDays!, nextWatering)));
      }
      return null;
    }

    // 水やりN回に1回の場合
    if (plant.vitalizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.vitalizerEveryNWaterings!;
      final DateTime? lastVitDate = vitLogs.isEmpty
          ? null
          : ([...vitLogs]..sort((a, b) => b.date.compareTo(a.date))).first.date;

      final wateringLogs =
          await _db.getLogsByPlantAndType(plantId, LogType.watering);

      // 起算日が未定（活力剤ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastVitDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([...wateringLogs]
                .where((l) => l.date.isAfter(lastVitDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));

      // 現在のグループ内の残り回数を計算（N回ごとの次の区切りを求める）
      // 例: N=3, 水やり7回の場合 → 7%3=1 → 残り2回（次の区切りは9回目）
      final completedInCurrentGroup = wateringsAfter.length % n;
      // completedInCurrentGroup == 0 は 2 パターンある:
      //   ・水やり実績なし（起算後まだ0回）→ 次のN回目が期限（remaining = n）
      //   ・水やりが N の倍数に到達済み（例: N=3 で3回）→ 期限に到達済みで
      //     期限は最後の水やり日（remaining = 0）。ここを n にすると付与忘れが
      //     Nサイクル先に飛び、超過状態が隠れてしまう。
      final remaining = completedInCurrentGroup == 0
          ? (wateringsAfter.isEmpty ? n : 0)
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastVitDate ?? (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining));
    }

    return null;
  }

  /// 指定植物・種別・日付のログ一覧を取得する。
  Future<List<LogEntry>> getLogsForDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final logs = await _db.getLogsByPlantAndType(plantId, logType);

    return logs.where((log) {
      return log.date.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
          log.date.isBefore(endOfDay.add(const Duration(seconds: 1)));
    }).toList();
  }

  /// 指定日に指定種別のログが存在するかチェックする。
  Future<bool> hasLogOnDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final logs = await getLogsForDate(plantId, logType, date);
    return logs.isNotEmpty;
  }

  /// 指定日の指定種別ログをすべて削除する。
  Future<void> deleteLogsForDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final logs = await getLogsForDate(plantId, logType, date);
    for (final log in logs) {
      await _db.deleteLog(log.id);
    }
  }

  /// 指定日の複数種別のログを一括削除する。
  Future<void> deleteMultipleLogsForDate(
    String plantId,
    List<LogType> logTypes,
    DateTime date,
  ) async {
    for (final logType in logTypes) {
      await deleteLogsForDate(plantId, logType, date);
    }
  }

  /// 指定植物・種別の全ログを取得する（日付フィルターなし）。
  Future<List<LogEntry>> getAllLogsForPlantAndType(
    String plantId,
    LogType logType,
  ) async {
    return _db.getLogsByPlantAndType(plantId, logType);
  }

  /// 指定植物の全種別ログを1クエリで取得する（水やりログ画面の高速化用）。
  Future<List<LogEntry>> getAllLogsForPlant(String plantId) async {
    return _db.getLogsByPlant(plantId);
  }

  /// 全植物・全種別のログを取得する（ケア統計画面用、Issue #182）。
  Future<List<LogEntry>> getAllLogsAcrossPlants() async {
    return _db.getAllLogs();
  }

  /// ログリストから次回水やり日を計算する（DBアクセスなし・同期的）。
  ///
  /// [plant] の [wateringIntervalDays] が null の場合は null を返す。
  DateTime? calcNextWateringDateFromLogs(
    Plant plant,
    List<LogEntry> wateringLogs,
  ) {
    if (plant.wateringIntervalDays == null) return null;
    if (wateringLogs.isEmpty) {
      // ログなしの場合は購入日または登録日から計算
      final baseDate = plant.purchaseDate ?? plant.createdAt;
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate)));
    }
    final sorted = [...wateringLogs]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.first.date.add(Duration(
        days:
            _adjustedInterval(plant, plant.wateringIntervalDays!, sorted.first.date)));
  }

  /// ログリストから次回肥料予定日を計算する（DBアクセスなし・同期的）。
  ///
  /// [nextWateringDate] は起算日3（水やり予定日）として使用する。
  DateTime? calcNextFertilizerDateFromLogs(
    Plant plant,
    List<LogEntry> fertLogs,
    List<LogEntry> wateringLogs,
    DateTime? nextWateringDate,
  ) {
    // 日数指定の場合
    if (plant.fertilizerIntervalDays != null) {
      if (fertLogs.isNotEmpty) {
        final sorted = [...fertLogs]..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.fertilizerIntervalDays!, sorted.first.date)));
      }
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.fertilizerIntervalDays!, sorted.first.date)));
      }
      if (nextWateringDate != null) {
        return nextWateringDate.add(Duration(
            days:
                _adjustedInterval(plant, plant.fertilizerIntervalDays!, nextWateringDate)));
      }
      return null;
    }
    // 水やりN回に1回の場合
    if (plant.fertilizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.fertilizerEveryNWaterings!;
      final DateTime? lastFertDate = fertLogs.isEmpty
          ? null
          : ([...fertLogs]..sort((a, b) => b.date.compareTo(a.date))).first.date;
      final wateringsAfter = lastFertDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([...wateringLogs]
                .where((l) => l.date.isAfter(lastFertDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? n
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastFertDate ?? (nextWateringDate ?? DateTime.now()));
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining));
    }
    return null;
  }

  /// ログリストから次回活力剤予定日を計算する（DBアクセスなし・同期的）。
  ///
  /// [nextWateringDate] は起算日3（水やり予定日）として使用する。
  DateTime? calcNextVitalizerDateFromLogs(
    Plant plant,
    List<LogEntry> vitLogs,
    List<LogEntry> wateringLogs,
    DateTime? nextWateringDate,
  ) {
    // 日数指定の場合
    if (plant.vitalizerIntervalDays != null) {
      if (vitLogs.isNotEmpty) {
        final sorted = [...vitLogs]..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.vitalizerIntervalDays!, sorted.first.date)));
      }
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(Duration(
            days: _adjustedInterval(
                plant, plant.vitalizerIntervalDays!, sorted.first.date)));
      }
      if (nextWateringDate != null) {
        return nextWateringDate.add(Duration(
            days:
                _adjustedInterval(plant, plant.vitalizerIntervalDays!, nextWateringDate)));
      }
      return null;
    }
    // 水やりN回に1回の場合
    if (plant.vitalizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.vitalizerEveryNWaterings!;
      final DateTime? lastVitDate = vitLogs.isEmpty
          ? null
          : ([...vitLogs]..sort((a, b) => b.date.compareTo(a.date))).first.date;
      final wateringsAfter = lastVitDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([...wateringLogs]
                .where((l) => l.date.isAfter(lastVitDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? n
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastVitDate ?? (nextWateringDate ?? DateTime.now()));
      return baseDate.add(Duration(
          days: _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining));
    }
    return null;
  }

  /// 指定IDのログを削除する。
  Future<void> deleteLog(String logId) async {
    await _db.deleteLog(logId);
  }

  /// すべての植物の水やり間隔を指定日数に一括設定する。
  Future<void> bulkUpdateWateringInterval(int days) async {
    for (final plant in _plants) {
      final updated = plant.copyWith(
        wateringIntervalDays: days,
        updatedAt: DateTime.now(),
      );
      await _db.updatePlant(updated);
    }
    await loadPlants();
  }

  /// 水やり間隔が設定されている植物のみ、間隔に delta を加算して一括調整する。
  /// 結果は最低 1 日にクランプする。
  Future<void> bulkAdjustWateringInterval(int delta) async {
    for (final plant in _plants) {
      if (plant.wateringIntervalDays == null) continue;
      final newDays = (plant.wateringIntervalDays! + delta).clamp(1, 9999);
      final updated = plant.copyWith(
        wateringIntervalDays: newDays,
        updatedAt: DateTime.now(),
      );
      await _db.updatePlant(updated);
    }
    await loadPlants();
  }
}

