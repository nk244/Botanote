import '../models/log_entry.dart';

/// ケア種別の日本語名を返す。
String careTypeLabel(LogType type) {
  switch (type) {
    case LogType.watering:
      return '水やり';
    case LogType.fertilizer:
      return '肥料';
    case LogType.vitalizer:
      return '活力剤';
    case LogType.repotting:
      return '植え替え';
    case LogType.pruning:
      return '剪定';
    case LogType.misting:
      return '葉水';
    case LogType.cleaning:
      return '掃除';
  }
}

/// まだ1件も記録が無い種別に出す短いラベル（Issue #349）。
///
/// 一覧カードやチップなど、幅の限られた場所で使う。
String firstCareShortLabel(LogType type) => '最初の${careTypeLabel(type)}';

/// まだ1件も記録が無い種別に出す案内文（Issue #349）。
///
/// 購入日や登録日が過去の株を登録すると、初回の予定日まで過去になり
/// 「水やり 90日前（予定超過）」のような、実際には一度も記録していないのに
/// 遅れているかのような表示になっていた。初回はケアを促す文言に置き換える。
String firstCareGuideText(LogType type) {
  switch (type) {
    case LogType.watering:
      return '最初の水やりをしましょう';
    case LogType.fertilizer:
      return '最初の肥料をあげましょう';
    case LogType.vitalizer:
      return '最初の活力剤をあげましょう';
    default:
      return '最初の${careTypeLabel(type)}をしましょう';
  }
}
