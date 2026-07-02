/// 休眠期とみなす月（北半球の冬季: 12月・1月・2月）
const Set<int> dormantSeasonMonths = {12, 1, 2};

/// 指定日が休眠期かどうかを判定する。
bool isDormantSeason(DateTime date) => dormantSeasonMonths.contains(date.month);

/// 季節調整を適用した間隔日数を返す。
///
/// [seasonalAdjustmentEnabled] が `false`、または [dormantMultiplier] が
/// `null` の場合は [baseIntervalDays] をそのまま返す。
/// [referenceDate]（間隔の起算日）が休眠期の場合のみ [dormantMultiplier] を
/// 乗算して間隔を延長する。
int applySeasonalAdjustment({
  required int baseIntervalDays,
  required bool seasonalAdjustmentEnabled,
  required double? dormantMultiplier,
  required DateTime referenceDate,
}) {
  if (!seasonalAdjustmentEnabled || dormantMultiplier == null) {
    return baseIntervalDays;
  }
  if (!isDormantSeason(referenceDate)) {
    return baseIntervalDays;
  }
  return (baseIntervalDays * dormantMultiplier).round();
}
