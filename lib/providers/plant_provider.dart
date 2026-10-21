import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../utils/japanese_sort_utils.dart';
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

  /// 次回肥料・活力剤予定日のキャッシュ（Issue #322）。
  ///
  /// 植物一覧が水やりの超過しか表示できなかったのは、この2つを
  /// [loadPlants] 時に持っていなかったため。
  final Map<String, DateTime?> _nextFertilizerCache = {};
  final Map<String, DateTime?> _nextVitalizerCache = {};

  /// カレンダー表示用：ログが存在する日付のセット（時刻なし）
  Set<DateTime> _logDatesCache = {};

  /// まだ1件も記録が無いケア種別のキャッシュ（Issue #349）。
  ///
  /// 「予定超過」ではなく「これから最初に行うケア」として案内するために、
  /// 画面側が種別ごとの初回判定を同期的に引けるようにする。
  final Map<String, Set<LogType>> _firstCareTypesCache = {};

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
  DateTime? cachedNextWateringDate(String plantId) =>
      _nextWateringCache[plantId];

  /// 指定した植物の次回肥料予定日をキャッシュから返す（Issue #322）。
  DateTime? cachedNextFertilizerDate(String plantId) =>
      _nextFertilizerCache[plantId];

  /// 指定した植物の次回活力剤予定日をキャッシュから返す（Issue #322）。
  DateTime? cachedNextVitalizerDate(String plantId) =>
      _nextVitalizerCache[plantId];

  /// 指定した植物で、予定日を過ぎたまま記録されていない種別の一覧を返す。
  ///
  /// 「予定日 < 今日」を超過とし、当日ちょうどは含めない。水やりログ画面の
  /// 判定（Issue #298）と揃えている。一覧画面が水やり以外の遅れにも
  /// 気づけるようにするための材料（Issue #322）。
  List<LogType> overdueCareTypes(String plantId, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    bool isOverdue(DateTime? next) =>
        next != null && _dateOnly(next).isBefore(today);

    return [
      if (isOverdue(_nextWateringCache[plantId])) LogType.watering,
      if (isOverdue(_nextFertilizerCache[plantId])) LogType.fertilizer,
      if (isOverdue(_nextVitalizerCache[plantId])) LogType.vitalizer,
    ];
  }

  /// 指定した植物・種別のログがまだ1件も無い場合 true を返す（Issue #349）。
  ///
  /// [loadPlants] 完了後に有効。初回のケアは「◯日前（予定超過）」ではなく
  /// 「最初の水やりをしましょう」と案内するための判定に使う。
  bool isFirstCare(String plantId, LogType type) =>
      _firstCareTypesCache[plantId]?.contains(type) ?? false;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 初回ケアの予定日が過去になる場合、今日まで繰り上げる（Issue #349）。
  ///
  /// 記録が1件も無い間の予定日は購入日・登録日からの推定でしかないため、
  /// 過去の購入日を入力しただけで「90日前（予定超過）」と出てしまっていた。
  /// 一度も記録していないケアに遅れ日数を出すのは実態に合わないので、
  /// 予定日は今日（＝これから行う日）に丸める。
  DateTime _clampFirstCareDate(DateTime date, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    return _dateOnly(date).isBefore(today) ? today : date;
  }

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

  /// 通知の再スケジュールをまとめるためのタイマー（Issue #246）。
  ///
  /// 一括記録などで loadPlants() が連続して走ると通知登録も連続してしまうため、
  /// 短時間の変更をまとめて最後の1回だけ実行する。
  Timer? _reminderDebounce;

  /// 通知再スケジュールのまとめ待ち時間。
  static const _reminderDebounceDuration = Duration(milliseconds: 500);

  /// 水やりリマインダーを張り直す（デバウンス付き）。
  ///
  /// 通知設定は [NotificationService] 側が SharedPreferences から読むため、
  /// 通知が無効なら内部でスキップされる。
  void _scheduleWateringReminder() {
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(_reminderDebounceDuration, () async {
      try {
        await NotificationService.scheduleSmartWateringReminder();
      } catch (e) {
        debugPrint('水やりリマインダーの再スケジュールに失敗: $e');
      }
    });
  }

  @override
  void dispose() {
    _reminderDebounce?.cancel();
    super.dispose();
  }

  /// 植物一覧をストレージから再読み込み、キャッシュを更新する。
  Future<void> loadPlants() async {
    _isLoading = true;
    notifyListeners();

    try {
      _plants = await _db.getAllPlants();

      // 全ログを1クエリで取り、植物ごとに仕分けてから3種別の次回予定日を求める。
      // 以前は植物1件ごとに calculateNextWateringDate() が DB を引いていたが、
      // 鉢数に比例してクエリが増えるうえ、肥料・活力剤の予定日は取れなかった
      // （植物一覧が水やりの超過しか出せない原因。Issue #322）。
      final allLogs = await _db.getAllLogs();
      final logsByPlant = <String, List<LogEntry>>{};
      for (final log in allLogs) {
        (logsByPlant[log.plantId] ??= <LogEntry>[]).add(log);
      }

      _nextWateringCache.clear();
      _nextFertilizerCache.clear();
      _nextVitalizerCache.clear();
      _firstCareTypesCache.clear();
      for (final plant in _plants) {
        final logs = logsByPlant[plant.id] ?? const <LogEntry>[];
        final wateringLogs = logs
            .where((l) => l.type == LogType.watering)
            .toList();
        final fertilizerLogs = logs
            .where((l) => l.type == LogType.fertilizer)
            .toList();
        final vitalizerLogs = logs
            .where((l) => l.type == LogType.vitalizer)
            .toList();

        // まだ記録が無い種別を控えておく（Issue #349）
        _firstCareTypesCache[plant.id] = {
          if (wateringLogs.isEmpty) LogType.watering,
          if (fertilizerLogs.isEmpty) LogType.fertilizer,
          if (vitalizerLogs.isEmpty) LogType.vitalizer,
        };

        final nextWatering = calcNextWateringDateFromLogs(plant, wateringLogs);
        _nextWateringCache[plant.id] = nextWatering;
        _nextFertilizerCache[plant.id] = calcNextFertilizerDateFromLogs(
          plant,
          fertilizerLogs,
          wateringLogs,
          nextWatering,
        );
        _nextVitalizerCache[plant.id] = calcNextVitalizerDateFromLogs(
          plant,
          vitalizerLogs,
          wateringLogs,
          nextWatering,
        );
      }

      // カレンダー表示用のログ日付セットを更新
      _logDatesCache = allLogs
          .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
          .toSet();

      // ホーム画面ウィジェットに今日の水やり予定を反映する（Issue #174）
      await HomeWidgetService.updateTodayWateringWidget(
        getPlantsNeedingWateringToday(),
      );

      // 植物やログの変更で次回予定日が変わるため、通知を張り直す（Issue #246）。
      // 植物の追加・編集・削除もログの記録・取り消しも loadPlants() を通るため、
      // ここに集約することで呼び忘れを防ぐ。
      _scheduleWateringReminder();
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
  List<Plant> getSortedPlants(
    PlantSortOrder sortOrder,
    List<String> customOrder,
  ) {
    final plantsCopy = List<Plant>.from(_plants);

    switch (sortOrder) {
      // 単純な compareTo だとコードポイント順になり和名が読み順に並ばないため、
      // 読み仮名とかな正規化を考慮して比較する（Issue #257）
      case PlantSortOrder.nameAsc:
        plantsCopy.sort(
          (a, b) =>
              compareJapanese(a.name, a.nameReading, b.name, b.nameReading),
        );
        break;
      case PlantSortOrder.nameDesc:
        plantsCopy.sort(
          (a, b) =>
              compareJapanese(b.name, b.nameReading, a.name, a.nameReading),
        );
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
      case PlantSortOrder.nextWateringAsc:
        // 次回水やり予定が近い順。予定日が過去（予定超過）のものほど先頭に来る。
        // 水やり間隔が未設定で予定日を持たない植物は末尾にまとめる（Issue #271）。
        plantsCopy.sort((a, b) {
          final aNext = _nextWateringCache[a.id];
          final bNext = _nextWateringCache[b.id];
          if (aNext == null && bNext == null) {
            return compareJapanese(
              a.name,
              a.nameReading,
              b.name,
              b.nameReading,
            );
          }
          if (aNext == null) return 1;
          if (bNext == null) return -1;
          final diff = aNext.compareTo(bNext);
          if (diff != 0) return diff;
          // 同じ予定日なら名前順で安定させる
          return compareJapanese(a.name, a.nameReading, b.name, b.nameReading);
        });
        break;
    }

    return plantsCopy;
  }

  Future<void> addPlant({
    required String name,
    String? nameReading,
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
      nameReading: nameReading,
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
    String locationId,
    Set<String> plantIds,
  ) async {
    for (final plant in _plants) {
      final shouldBelong = plantIds.contains(plant.id);
      final currentlyBelongs = plant.locationId == locationId;
      if (shouldBelong && !currentlyBelongs) {
        await _db.updatePlant(
          plant.copyWith(locationId: locationId, updatedAt: DateTime.now()),
        );
      } else if (!shouldBelong && currentlyBelongs) {
        await _db.updatePlant(
          plant.copyWith(locationId: null, updatedAt: DateTime.now()),
        );
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

  Future<void> recordWatering(
    String plantId,
    DateTime date,
    String? note,
  ) async {
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
  Future<void> recordFertilizer(
    String plantId,
    DateTime date,
    String? note,
  ) async {
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
  Future<void> recordVitalizer(
    String plantId,
    DateTime date,
    String? note,
  ) async {
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
  /// 戻り値は登録したログの一覧。[deleteLogs] に渡すと一括記録を取り消せる
  /// （Issue #328 の「元に戻す」用）。
  Future<List<LogEntry>> bulkRecordLogs(
    List<String> plantIds,
    List<LogType> logTypes,
    DateTime date,
  ) async {
    final now = DateTime.now();
    final created = <LogEntry>[];
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
        created.add(log);
      }
    }
    // 全挿入完了後に1回だけ再読み込み
    await loadPlants();
    return created;
  }

  /// 指定したログを ID 指定でまとめて削除する（Issue #328 の「元に戻す」）。
  ///
  /// [bulkRecordLogs] が返したログをそのまま渡すことで、一括記録だけを
  /// 取り消せる。既に消えている ID が混ざっても何も起きない。
  Future<void> deleteLogs(List<LogEntry> logs) async {
    for (final log in logs) {
      await _db.deleteLog(log.id);
    }
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
  int _adjustedInterval(
    Plant plant,
    int baseIntervalDays,
    DateTime referenceDate,
  ) {
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
    final wateringLogs = await _db.getLogsByPlantAndType(
      plantId,
      LogType.watering,
    );

    if (wateringLogs.isEmpty) {
      // ログなしの場合は購入日または登録日から計算し、
      // 過去になる場合は今日へ繰り上げる（Issue #349）
      final baseDate = plant.purchaseDate ?? plant.createdAt;
      return _clampFirstCareDate(
        baseDate.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.wateringIntervalDays!,
              baseDate,
            ),
          ),
        ),
      );
    }

    // 最新のログから計算
    wateringLogs.sort((a, b) => b.date.compareTo(a.date));
    final lastWatering = wateringLogs.first;
    return lastWatering.date.add(
      Duration(
        days: _adjustedInterval(
          plant,
          plant.wateringIntervalDays!,
          lastWatering.date,
        ),
      ),
    );
  }

  /// 最終肥料ログから次回肥料予定日を動的に計算する。
  ///
  /// 起算日の優先順位（日数指定モード）:
  /// 1. 最後に肥料を与えた日
  /// 2. 肥料ログがなければ**最初に**水やりをした日
  /// 3. 水やりログもなければ次回水やり予定日
  ///
  /// 起算日2で「最後の水やり日」を使うと、水やりを記録するたびに予定日が
  /// 後ろへずれて永久に到来しなくなる（Issue #285）。肥料ログが1件も無い間の
  /// 起算日は、以降の水やりで動かない「ケアを始めた日」に固定する。
  ///
  /// - [fertilizerEveryNWaterings] が設定されている場合: 最終肥料日以降の
  ///   水やり回数が N 回に達する日（水やり間隔から推定）
  /// どちらも未設定の場合は null を返す。
  Future<DateTime?> calculateNextFertilizerDate(String plantId) async {
    final plant = await _db.getPlant(plantId);
    if (plant == null) return null;

    final fertLogs = await _db.getLogsByPlantAndType(
      plantId,
      LogType.fertilizer,
    );

    // 日数指定の場合
    if (plant.fertilizerIntervalDays != null) {
      if (fertLogs.isNotEmpty) {
        // 起算日1: 最後に肥料を与えた日
        final sorted = [...fertLogs]..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      // 起算日2: 最初に水やりをした日（Issue #285）
      final wateringLogs2 = await _db.getLogsByPlantAndType(
        plantId,
        LogType.watering,
      );
      if (wateringLogs2.isNotEmpty) {
        final sorted2 = [...wateringLogs2]
          ..sort((a, b) => a.date.compareTo(b.date));
        return sorted2.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              sorted2.first.date,
            ),
          ),
        );
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              nextWatering,
            ),
          ),
        );
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
          : ([
              ...fertLogs,
            ]..sort((a, b) => b.date.compareTo(a.date))).first.date;

      final wateringLogs = await _db.getLogsByPlantAndType(
        plantId,
        LogType.watering,
      );

      // 起算日が未定（肥料ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastFertDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([
                ...wateringLogs,
              ].where((l) => l.date.isAfter(lastFertDate)).toList()
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
          : (lastFertDate ??
                (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate.add(
        Duration(
          days:
              _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining,
        ),
      );
    }

    return null;
  }

  /// 最終活力剤ログから次回活力剤予定日を動的に計算する。
  ///
  /// 起算日の優先順位（日数指定モード）:
  /// 1. 最後に活力剤を与えた日
  /// 2. 活力剤ログがなければ**最初に**水やりをした日（Issue #285）
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
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      // 起算日2: 最初に水やりをした日（Issue #285）
      final wateringLogs2 = await _db.getLogsByPlantAndType(
        plantId,
        LogType.watering,
      );
      if (wateringLogs2.isNotEmpty) {
        final sorted2 = [...wateringLogs2]
          ..sort((a, b) => a.date.compareTo(b.date));
        return sorted2.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              sorted2.first.date,
            ),
          ),
        );
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              nextWatering,
            ),
          ),
        );
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

      final wateringLogs = await _db.getLogsByPlantAndType(
        plantId,
        LogType.watering,
      );

      // 起算日が未定（活力剤ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastVitDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([
                ...wateringLogs,
              ].where((l) => l.date.isAfter(lastVitDate)).toList()
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
          : (lastVitDate ??
                (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate.add(
        Duration(
          days:
              _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining,
        ),
      );
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
      return log.date.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
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
  ///
  /// 戻り値は削除したログの一覧。[restoreLogs] に渡すと取り消しを戻せる
  /// （Issue #280 の「元に戻す」用）。
  Future<List<LogEntry>> deleteMultipleLogsForDate(
    String plantId,
    List<LogType> logTypes,
    DateTime date,
  ) async {
    final deleted = <LogEntry>[];
    for (final logType in logTypes) {
      // 削除前のログを控えてから消す
      deleted.addAll(await getLogsForDate(plantId, logType, date));
      await deleteLogsForDate(plantId, logType, date);
    }
    return deleted;
  }

  /// 削除したログを元の内容のまま復元する（Issue #280 の「元に戻す」）。
  ///
  /// ID も含めて同一のレコードを書き戻すため、二重実行しても増えない。
  Future<void> restoreLogs(List<LogEntry> logs) async {
    for (final log in logs) {
      await _db.insertLog(log);
    }
  }

  /// 指定植物・種別の全ログを取得する（日付フィルターなし）。
  Future<List<LogEntry>> getAllLogsForPlantAndType(
    String plantId,
    LogType logType,
  ) async {
    return _db.getLogsByPlantAndType(plantId, logType);
  }

  /// 指定植物のケアログ件数を返す（削除確認の件数表示用、Issue #345）。
  Future<int> countLogsForPlant(String plantId) async {
    return _db.countLogsByPlant(plantId);
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
  /// [now] は初回予定日の繰り上げ基準日（省略時は現在日時。テスト用）。
  DateTime? calcNextWateringDateFromLogs(
    Plant plant,
    List<LogEntry> wateringLogs, {
    DateTime? now,
  }) {
    if (plant.wateringIntervalDays == null) return null;
    if (wateringLogs.isEmpty) {
      // ログなしの場合は購入日または登録日から計算し、
      // 過去になる場合は今日へ繰り上げる（Issue #349）
      final baseDate = plant.purchaseDate ?? plant.createdAt;
      return _clampFirstCareDate(
        baseDate.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.wateringIntervalDays!,
              baseDate,
            ),
          ),
        ),
        now: now,
      );
    }
    final sorted = [...wateringLogs]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.first.date.add(
      Duration(
        days: _adjustedInterval(
          plant,
          plant.wateringIntervalDays!,
          sorted.first.date,
        ),
      ),
    );
  }

  /// ログリストから次回肥料予定日を計算する（DBアクセスなし・同期的）。
  ///
  /// 起算日の優先順位は [calculateNextFertilizerDate] と同じ。
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
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      // 起算日2: 最初に水やりをした日（Issue #285）
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => a.date.compareTo(b.date));
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      if (nextWateringDate != null) {
        return nextWateringDate.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.fertilizerIntervalDays!,
              nextWateringDate,
            ),
          ),
        );
      }
      return null;
    }
    // 水やりN回に1回の場合
    if (plant.fertilizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.fertilizerEveryNWaterings!;
      final DateTime? lastFertDate = fertLogs.isEmpty
          ? null
          : ([
              ...fertLogs,
            ]..sort((a, b) => b.date.compareTo(a.date))).first.date;
      final wateringsAfter = lastFertDate == null
          ? ([...wateringLogs]..sort((a, b) => a.date.compareTo(b.date)))
          : ([
                ...wateringLogs,
              ].where((l) => l.date.isAfter(lastFertDate)).toList()
              ..sort((a, b) => a.date.compareTo(b.date)));
      // completedInCurrentGroup == 0 は 2 パターンある（DBアクセス版と同じ扱いにする）:
      //   ・水やり実績なし（起算後まだ0回）→ 次のN回目が期限（remaining = n）
      //   ・水やりが N の倍数に到達済み（例: N=3 で3回）→ 施肥期限に到達済みで
      //     期限は最後の水やり日（remaining = 0）。ここを n にすると施肥忘れが
      //     Nサイクル先に飛び、超過状態が隠れてしまう。
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? (wateringsAfter.isEmpty ? n : 0)
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastFertDate ?? (nextWateringDate ?? DateTime.now()));
      return baseDate.add(
        Duration(
          days:
              _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining,
        ),
      );
    }
    return null;
  }

  /// ログリストから次回活力剤予定日を計算する（DBアクセスなし・同期的）。
  ///
  /// 起算日の優先順位は [calculateNextVitalizerDate] と同じ。
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
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      // 起算日2: 最初に水やりをした日（Issue #285）
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => a.date.compareTo(b.date));
        return sorted.first.date.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              sorted.first.date,
            ),
          ),
        );
      }
      if (nextWateringDate != null) {
        return nextWateringDate.add(
          Duration(
            days: _adjustedInterval(
              plant,
              plant.vitalizerIntervalDays!,
              nextWateringDate,
            ),
          ),
        );
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
          : ([
                ...wateringLogs,
              ].where((l) => l.date.isAfter(lastVitDate)).toList()
              ..sort((a, b) => a.date.compareTo(b.date)));
      // completedInCurrentGroup == 0 は 2 パターンある（DBアクセス版と同じ扱いにする）:
      //   ・水やり実績なし（起算後まだ0回）→ 次のN回目が期限（remaining = n）
      //   ・水やりが N の倍数に到達済み（例: N=3 で3回）→ 期限に到達済みで
      //     期限は最後の水やり日（remaining = 0）。ここを n にすると付与忘れが
      //     Nサイクル先に飛び、超過状態が隠れてしまう。
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? (wateringsAfter.isEmpty ? n : 0)
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastVitDate ?? (nextWateringDate ?? DateTime.now()));
      return baseDate.add(
        Duration(
          days:
              _adjustedInterval(plant, plant.wateringIntervalDays!, baseDate) *
              remaining,
        ),
      );
    }
    return null;
  }

  /// 指定IDのログを削除する。
  Future<void> deleteLog(String logId) async {
    await _db.deleteLog(logId);
  }

  /// すべての植物の水やり間隔を指定日数に一括設定する。
  /// 一括変更の対象となる植物の件数を返す（Issue #274）。
  ///
  /// [onlyWithInterval] が true の場合は、水やり間隔が設定済みの植物だけを数える
  /// （一括調整の対象件数）。
  int countBulkIntervalTargets({required bool onlyWithInterval}) {
    if (!onlyWithInterval) return _plants.length;
    return _plants.where((p) => p.wateringIntervalDays != null).length;
  }

  /// 変更前の水やり間隔を植物IDごとに控える（Issue #274 の「元に戻す」用）。
  Map<String, int?> _snapshotWateringIntervals() {
    return {for (final plant in _plants) plant.id: plant.wateringIntervalDays};
  }

  /// すべての植物の水やり間隔を [days] に設定する。
  ///
  /// 戻り値は変更前の間隔（植物ID → 日数）。「元に戻す」に使う。
  Future<Map<String, int?>> bulkUpdateWateringInterval(int days) async {
    final previous = _snapshotWateringIntervals();
    for (final plant in _plants) {
      final updated = plant.copyWith(
        wateringIntervalDays: days,
        updatedAt: DateTime.now(),
      );
      await _db.updatePlant(updated);
    }
    await loadPlants();
    return previous;
  }

  /// 水やり間隔が設定されている植物のみ、間隔に delta を加算して一括調整する。
  /// 結果は最低 1 日にクランプする。
  ///
  /// 戻り値は変更前の間隔（植物ID → 日数）。「元に戻す」に使う。
  Future<Map<String, int?>> bulkAdjustWateringInterval(int delta) async {
    final previous = _snapshotWateringIntervals();
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
    return previous;
  }

  /// 一括変更前の水やり間隔を復元する（Issue #274 の「元に戻す」）。
  ///
  /// [previous] に含まれない植物（一括変更後に追加された等）は対象外。
  Future<void> restoreWateringIntervals(Map<String, int?> previous) async {
    for (final plant in _plants) {
      if (!previous.containsKey(plant.id)) continue;
      final before = previous[plant.id];
      if (plant.wateringIntervalDays == before) continue;
      final updated = plant.copyWith(
        wateringIntervalDays: before,
        updatedAt: DateTime.now(),
      );
      await _db.updatePlant(updated);
    }
    await loadPlants();
  }
}
