import 'package:intl/intl.dart';

/// 日付操作のユーティリティクラス
class AppDateUtils {
  /// 指定日の日の始まり（00:00:00）を返す。
  static DateTime getStartOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 指定日の日の終わり（23:59:59）を返す。
  static DateTime getEndOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// 時刻情報を除いた日付のみを返す。
  static DateTime getDateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 年をまたぐ場合だけ年を付けて日付をフォーマットする（Issue #256）。
  ///
  /// 現在の年と同じなら `M月d日`、異なる年なら `yyyy年M月d日` を返す。
  /// 「1月2日」とだけ表示されると来年なのか去年なのか判別できないため、
  /// 日付を表示する箇所はこのメソッドを経由させる。
  static String formatDateWithYearIfNeeded(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year) return DateFormat('M月d日').format(date);
    return DateFormat('yyyy年M月d日').format(date);
  }

  /// 相対日付文字列（今日・昨日・明日 等）にフォーマットする。
  ///
  /// 相対表現に当てはまらない場合は [formatDateWithYearIfNeeded] に委ねるため、
  /// 年をまたぐ予定日は年つきで表示される。
  static String formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final today = getDateOnly(now);
    final targetDay = getDateOnly(date);
    final difference = targetDay.difference(today).inDays;

    if (difference == 0) return '今日';
    if (difference == -1) return '昨日';
    if (difference == 1) return '明日';
    return formatDateWithYearIfNeeded(date);
  }

  /// 日付差を文字列化する。期限切れの場合は文言を付加する。
  static String formatDateDifference(DateTime date) {
    final now = DateTime.now();
    final today = getDateOnly(now);
    final targetDay = getDateOnly(date);
    final difference = targetDay.difference(today).inDays;

    if (difference == 0) return '今日';
    if (difference == -1) return '昨日（予定超過）';
    if (difference == 1) return '明日';
    if (difference < 0) return '${-difference}日前（予定超過）';
    return '$difference日後';
  }

  /// 2つの日時が同じ日かチェックする。
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
