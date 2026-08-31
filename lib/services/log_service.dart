import '../models/log_entry.dart';

/// ログ操作を担うサービス。
///
/// ストレージサービス（DB/Web）を抽象化するレイヤー。
class LogService {
  final dynamic _storage;

  LogService(this._storage);

  /// 指定植物・種別・日付のログ一覧を取得する。
  Future<List<LogEntry>> getLogsForDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final logs = await _storage.getLogsByPlantAndType(plantId, logType);
    return _filterLogsByDate(logs, date);
  }

  /// 指定植物・種別・日付にログが存在するかチェックする。
  Future<bool> hasLogOnDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final logs = await getLogsForDate(plantId, logType, date);
    return logs.isNotEmpty;
  }

  /// 指定日付のログをすべて削除する。
  Future<void> deleteLogsForDate(
    String plantId,
    LogType logType,
    DateTime date,
  ) async {
    final logs = await getLogsForDate(plantId, logType, date);
    for (final log in logs) {
      await _storage.deleteLog(log.id);
    }
  }

  /// 指定日のログのみをフィルタリングする。
  List<LogEntry> _filterLogsByDate(List<LogEntry> logs, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return logs.where((log) {
      return log.date.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
          log.date.isBefore(endOfDay.add(const Duration(seconds: 1)));
    }).toList();
  }
}
