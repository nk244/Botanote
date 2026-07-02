import '../models/log_entry.dart';

/// 特定日における植物ごとのログ状態を保持するクラス
class DailyLogStatus {
  final Map<String, bool> _watered;
  final Map<String, bool> _fertilized;
  final Map<String, bool> _vitalized;

  DailyLogStatus({
    required Map<String, bool> watered,
    required Map<String, bool> fertilized,
    required Map<String, bool> vitalized,
  })  : _watered = watered,
        _fertilized = fertilized,
        _vitalized = vitalized;

  factory DailyLogStatus.empty() {
    return DailyLogStatus(
      watered: {},
      fertilized: {},
      vitalized: {},
    );
  }

  bool isWatered(String plantId) => _watered[plantId] ?? false;
  bool isFertilized(String plantId) => _fertilized[plantId] ?? false;
  bool isVitalized(String plantId) => _vitalized[plantId] ?? false;
  bool hasAnyLog(String plantId) =>
      isWatered(plantId) || isFertilized(plantId) || isVitalized(plantId);

  int get wateredCount => _watered.values.where((v) => v).length;
  int get fertilizedCount => _fertilized.values.where((v) => v).length;
  int get vitalizedCount => _vitalized.values.where((v) => v).length;
  bool get hasAnyRecords =>
      wateredCount > 0 || fertilizedCount > 0 || vitalizedCount > 0;

  /// 指定した植物・ログ種別のステータスを更新する
  void updateStatus(String plantId, LogType logType, bool value) {
    switch (logType) {
      case LogType.watering:
        _watered[plantId] = value;
        break;
      case LogType.fertilizer:
        _fertilized[plantId] = value;
        break;
      case LogType.vitalizer:
        _vitalized[plantId] = value;
        break;
      default:
        // 記録専用のケアタイプ（植え替え・剪定・葉水・掃除等）は
        // スケジュール管理対象外のため何もしない（Issue #175）
        break;
    }
  }

  /// 指定した種別以外のログが存在するか確認する
  bool hasOtherLogs(String plantId, LogType excludeType) {
    switch (excludeType) {
      case LogType.watering:
        return isFertilized(plantId) || isVitalized(plantId);
      case LogType.fertilizer:
        return isWatered(plantId) || isVitalized(plantId);
      case LogType.vitalizer:
        return isWatered(plantId) || isFertilized(plantId);
      default:
        // 記録専用のケアタイプ（Issue #175）はスケジュール管理対象外
        return isWatered(plantId) || isFertilized(plantId) || isVitalized(plantId);
    }
  }

  /// 植物のログが存在するすべての種別を返す
  List<LogType> getActiveLogTypes(String plantId) {
    final types = <LogType>[];
    if (isWatered(plantId)) types.add(LogType.watering);
    if (isFertilized(plantId)) types.add(LogType.fertilizer);
    if (isVitalized(plantId)) types.add(LogType.vitalizer);
    return types;
  }

  Map<String, bool> get wateredMap => Map.unmodifiable(_watered);
  Map<String, bool> get fertilizedMap => Map.unmodifiable(_fertilized);
  Map<String, bool> get vitalizedMap => Map.unmodifiable(_vitalized);
}
