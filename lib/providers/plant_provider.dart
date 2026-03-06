import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/web_storage_service.dart';

/// 植物データとログを管理する Provider。
///
/// [DatabaseService](モバイル) または [WebStorageService](Web) を介して
/// 永続化する。ビジネスロジックの集約点として機能する。
class PlantProvider with ChangeNotifier {
  /// モバイル環境用 DBサービス（Web時は null）
  final DatabaseService? _db = kIsWeb ? null : DatabaseService();

  /// Web 環境用ストレージ（非 Web 時は null）
  final WebStorageService? _web = kIsWeb ? WebStorageService() : null;

  List<Plant> _plants = [];
  bool _isLoading = false;

  /// true になると loadPlants() が一度以上完了したことを示す。
  /// 初回起動時の「空リスト一瞬表示」を防ぐために使用する。
  bool _isInitialized = false;

  final Map<String, DateTime?> _nextWateringCache = {};

  /// カレンダー表示用：ログが存在する日付のセット（時刻なし）
  Set<DateTime> _logDatesCache = {};

  List<Plant> get plants => _plants;
  bool get isLoading => _isLoading;

  /// loadPlants() が一度以上正常完了した場合 true。
  /// 初回起動ローディング中は false のままになる。
  bool get isInitialized => _isInitialized;

  Set<DateTime> get logDates => _logDatesCache;

  /// 植物一覧をストレージから再読み込み、キャッシュを更新する。
  Future<void> loadPlants() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        _plants = await _web!.getAllPlants();
      } else {
        _plants = await _db!.getAllPlants();
      }
      
      // 次回水やり日キャッシュを更新
      for (var plant in _plants) {
        _nextWateringCache[plant.id] = await calculateNextWateringDate(plant.id);
      }
      // カレンダー表示用のログ日付セットを更新
      if (!kIsWeb) {
        final allLogs = await _db!.getAllLogs();
        _logDatesCache = allLogs
            .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
            .toSet();
      }
    } catch (e) {
      debugPrint('Error loading plants: $e');
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
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
      createdAt: now,
      updatedAt: now,
    );

    if (kIsWeb) {
      await _web!.insertPlant(plant);
    } else {
      await _db!.insertPlant(plant);
    }
    await loadPlants();
  }

  Future<void> updatePlant(Plant plant) async {
    if (kIsWeb) {
      await _web!.updatePlant(plant);
    } else {
      await _db!.updatePlant(plant);
    }
    await loadPlants();
  }

  Future<void> deletePlant(String id) async {
    if (kIsWeb) {
      await _web!.deletePlant(id);
    } else {
      await _db!.deletePlant(id);
    }

    // Issue #12: 削除した植物IDをノートの plantIds から除去する
    await _removePlantIdFromNotes(id);

    await loadPlants();
  }

  /// 削除された植物IDを参照しているすべてのノートの plantIds から除去する。
  Future<void> _removePlantIdFromNotes(String plantId) async {
    try {
      if (kIsWeb) {
        // Web: WebStorageServiceの専用メソッドで一括処理
        await _web!.removePlantIdFromNotes(plantId);
      } else {
        final notes = await _db!.getAllNotes();
        for (final note in notes) {
          if (note.plantIds.contains(plantId)) {
            final updatedNote = note.copyWith(
              plantIds: note.plantIds.where((id) => id != plantId).toList(),
              updatedAt: DateTime.now(),
            );
            await _db.updateNote(updatedNote);
          }
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
    
    if (kIsWeb) {
      await _web!.insertLog(log);
    } else {
      await _db!.insertLog(log);
    }

  // nextWateringDate はログから動的に計算するため、ログ記録時にはキャッシュ更新不要

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
    
    if (kIsWeb) {
      await _web!.insertLog(log);
    } else {
      await _db!.insertLog(log);
    }

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
    
    if (kIsWeb) {
      await _web!.insertLog(log);
    } else {
      await _db!.insertLog(log);
    }

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
        if (kIsWeb) {
          await _web!.insertLog(log);
        } else {
          await _db!.insertLog(log);
        }
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

  /// 最終水やりログから次回水やり日を動的に計算する。
  /// 水やり間隔が未設定の場合は null を返す。
  // 動的に次回水やり日を計算（ログから算出）
  Future<DateTime?> calculateNextWateringDate(String plantId) async {
    Plant? plant;
    if (kIsWeb) {
      plant = await _web!.getPlant(plantId);
    } else {
      plant = await _db!.getPlant(plantId);
    }
    
    if (plant == null || plant.wateringIntervalDays == null) return null;

    // 最新の水やり記録を取得
    List<LogEntry> wateringLogs;
    if (kIsWeb) {
      wateringLogs = await _web!.getLogsByPlantAndType(plantId, LogType.watering);
    } else {
      wateringLogs = await _db!.getLogsByPlantAndType(plantId, LogType.watering);
    }

    if (wateringLogs.isEmpty) {
      // ログなしの場合は購入日または登録日から計算
      final baseDate = plant.purchaseDate ?? plant.createdAt;
      return baseDate.add(Duration(days: plant.wateringIntervalDays!));
    }

    // 最新のログから計算
    wateringLogs.sort((a, b) => b.date.compareTo(a.date));
    final lastWatering = wateringLogs.first;
    return lastWatering.date.add(Duration(days: plant.wateringIntervalDays!));
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
    Plant? plant;
    if (kIsWeb) {
      plant = await _web!.getPlant(plantId);
    } else {
      plant = await _db!.getPlant(plantId);
    }
    if (plant == null) return null;

    List<LogEntry> fertLogs;
    if (kIsWeb) {
      fertLogs = await _web!.getLogsByPlantAndType(plantId, LogType.fertilizer);
    } else {
      fertLogs = await _db!.getLogsByPlantAndType(plantId, LogType.fertilizer);
    }

    // 日数指定の場合
    if (plant.fertilizerIntervalDays != null) {
      if (fertLogs.isNotEmpty) {
        // 起算日1: 最後に肥料を与えた日
        fertLogs.sort((a, b) => b.date.compareTo(a.date));
        return fertLogs.first.date
            .add(Duration(days: plant.fertilizerIntervalDays!));
      }
      // 起算日2: 最後に水やりをした日
      List<LogEntry> wateringLogs;
      if (kIsWeb) {
        wateringLogs =
            await _web!.getLogsByPlantAndType(plantId, LogType.watering);
      } else {
        wateringLogs =
            await _db!.getLogsByPlantAndType(plantId, LogType.watering);
      }
      if (wateringLogs.isNotEmpty) {
        wateringLogs.sort((a, b) => b.date.compareTo(a.date));
        return wateringLogs.first.date
            .add(Duration(days: plant.fertilizerIntervalDays!));
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(Duration(days: plant.fertilizerIntervalDays!));
      }
      return null;
    }

    // 水やりN回に1回の場合
    if (plant.fertilizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.fertilizerEveryNWaterings!;
      // 最終肥料日以降の水やりログを数える
      final lastFertDate =
          fertLogs.isEmpty ? null : () {
            fertLogs.sort((a, b) => b.date.compareTo(a.date));
            return fertLogs.first.date;
          }();

      List<LogEntry> wateringLogs;
      if (kIsWeb) {
        wateringLogs =
            await _web!.getLogsByPlantAndType(plantId, LogType.watering);
      } else {
        wateringLogs =
            await _db!.getLogsByPlantAndType(plantId, LogType.watering);
      }

      // 起算日が未定（肥料ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastFertDate == null
          ? (wateringLogs..sort((a, b) => a.date.compareTo(b.date)))
          : (wateringLogs
                .where((l) => l.date.isAfter(lastFertDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));

      // 現在のグループ内の残り回数を計算（N回ごとの次の区切りを求める）
      // 例: N=3, 水やり7回の場合 → 7%3=1 → 残り2回（次の区切りは9回目）
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? n // ちょうど区切り済み → 次のN回目
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastFertDate ?? (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate
          .add(Duration(days: plant.wateringIntervalDays! * remaining));
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
    Plant? plant;
    if (kIsWeb) {
      plant = await _web!.getPlant(plantId);
    } else {
      plant = await _db!.getPlant(plantId);
    }
    if (plant == null) return null;

    List<LogEntry> vitLogs;
    if (kIsWeb) {
      vitLogs = await _web!.getLogsByPlantAndType(plantId, LogType.vitalizer);
    } else {
      vitLogs = await _db!.getLogsByPlantAndType(plantId, LogType.vitalizer);
    }

    // 日数指定の場合
    if (plant.vitalizerIntervalDays != null) {
      if (vitLogs.isNotEmpty) {
        // 起算日1: 最後に活力剤を与えた日
        vitLogs.sort((a, b) => b.date.compareTo(a.date));
        return vitLogs.first.date
            .add(Duration(days: plant.vitalizerIntervalDays!));
      }
      // 起算日2: 最後に水やりをした日
      List<LogEntry> wateringLogs;
      if (kIsWeb) {
        wateringLogs =
            await _web!.getLogsByPlantAndType(plantId, LogType.watering);
      } else {
        wateringLogs =
            await _db!.getLogsByPlantAndType(plantId, LogType.watering);
      }
      if (wateringLogs.isNotEmpty) {
        wateringLogs.sort((a, b) => b.date.compareTo(a.date));
        return wateringLogs.first.date
            .add(Duration(days: plant.vitalizerIntervalDays!));
      }
      // 起算日3: 次回水やり予定日
      final nextWatering = await calculateNextWateringDate(plantId);
      if (nextWatering != null) {
        return nextWatering.add(Duration(days: plant.vitalizerIntervalDays!));
      }
      return null;
    }

    // 水やりN回に1回の場合
    if (plant.vitalizerEveryNWaterings != null &&
        plant.wateringIntervalDays != null) {
      final n = plant.vitalizerEveryNWaterings!;
      final lastVitDate =
          vitLogs.isEmpty ? null : () {
            vitLogs.sort((a, b) => b.date.compareTo(a.date));
            return vitLogs.first.date;
          }();

      List<LogEntry> wateringLogs;
      if (kIsWeb) {
        wateringLogs =
            await _web!.getLogsByPlantAndType(plantId, LogType.watering);
      } else {
        wateringLogs =
            await _db!.getLogsByPlantAndType(plantId, LogType.watering);
      }

      // 起算日が未定（活力剤ログなし）の場合は全水やりログを対象にする
      final wateringsAfter = lastVitDate == null
          ? (wateringLogs..sort((a, b) => a.date.compareTo(b.date)))
          : (wateringLogs
                .where((l) => l.date.isAfter(lastVitDate))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date)));

      // 現在のグループ内の残り回数を計算（N回ごとの次の区切りを求める）
      // 例: N=3, 水やり7回の場合 → 7%3=1 → 残り2回（次の区切りは9回目）
      final completedInCurrentGroup = wateringsAfter.length % n;
      final remaining = completedInCurrentGroup == 0
          ? n // ちょうど区切り済み → 次のN回目
          : n - completedInCurrentGroup;
      final baseDate = wateringsAfter.isNotEmpty
          ? wateringsAfter.last.date
          : (lastVitDate ?? (await calculateNextWateringDate(plantId) ?? DateTime.now()));
      return baseDate
          .add(Duration(days: plant.wateringIntervalDays! * remaining));
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

    List<LogEntry> logs;
    if (kIsWeb) {
      logs = await _web!.getLogsByPlantAndType(plantId, logType);
    } else {
      logs = await _db!.getLogsByPlantAndType(plantId, logType);
    }

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
      if (kIsWeb) {
        await _web!.deleteLog(log.id);
      } else {
        await _db!.deleteLog(log.id);
      }
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
    if (kIsWeb) {
      return await _web!.getLogsByPlantAndType(plantId, logType);
    } else {
      return await _db!.getLogsByPlantAndType(plantId, logType);
    }
  }

  /// 指定植物の全種別ログを1クエリで取得する（水やりログ画面の高速化用）。
  Future<List<LogEntry>> getAllLogsForPlant(String plantId) async {
    if (kIsWeb) {
      return await _web!.getLogsByPlant(plantId);
    } else {
      return await _db!.getLogsByPlant(plantId);
    }
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
      return baseDate.add(Duration(days: plant.wateringIntervalDays!));
    }
    final sorted = [...wateringLogs]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.first.date.add(Duration(days: plant.wateringIntervalDays!));
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
        return sorted.first.date
            .add(Duration(days: plant.fertilizerIntervalDays!));
      }
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date
            .add(Duration(days: plant.fertilizerIntervalDays!));
      }
      if (nextWateringDate != null) {
        return nextWateringDate
            .add(Duration(days: plant.fertilizerIntervalDays!));
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
      return baseDate
          .add(Duration(days: plant.wateringIntervalDays! * remaining));
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
        return sorted.first.date
            .add(Duration(days: plant.vitalizerIntervalDays!));
      }
      if (wateringLogs.isNotEmpty) {
        final sorted = [...wateringLogs]
          ..sort((a, b) => b.date.compareTo(a.date));
        return sorted.first.date
            .add(Duration(days: plant.vitalizerIntervalDays!));
      }
      if (nextWateringDate != null) {
        return nextWateringDate
            .add(Duration(days: plant.vitalizerIntervalDays!));
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
      return baseDate
          .add(Duration(days: plant.wateringIntervalDays! * remaining));
    }
    return null;
  }

  /// 指定IDのログを削除する。
  Future<void> deleteLog(String logId) async {
    if (kIsWeb) {
      await _web!.deleteLog(logId);
    } else {
      await _db!.deleteLog(logId);
    }
  }

  /// すべての植物の水やり間隔を指定日数に一括設定する。
  Future<void> bulkUpdateWateringInterval(int days) async {
    for (final plant in _plants) {
      final updated = plant.copyWith(
        wateringIntervalDays: days,
        updatedAt: DateTime.now(),
      );
      if (kIsWeb) {
        await _web!.updatePlant(updated);
      } else {
        await _db!.updatePlant(updated);
      }
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
      if (kIsWeb) {
        await _web!.updatePlant(updated);
      } else {
        await _db!.updatePlant(updated);
      }
    }
    await loadPlants();
  }
}
