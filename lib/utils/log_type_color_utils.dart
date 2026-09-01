import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';

/// ログ種別ごとの表示色（[LogTypeColors]）をテーマモードに合わせて解決する。
///
/// [LogTypeColors] が持つ既定値は Material のライト用パステル
/// （blue.shade100 / green.shade100 / amber.shade100 と対応する shade900）で、
/// これをダークモードでもそのまま使うと、暗い画面の中でチップだけが
/// 明るい島のように浮いてしまう（Issue #324）。
///
/// 水やり=青・肥料=緑・活力剤=琥珀という種別の意味づけは保ちたいため、
/// テーマ色に置き換えるのではなく **色相を保ったまま明度だけを反転** させる。
class LogTypeColorScheme {
  /// チップの背景色
  final Color background;

  /// チップの文字・アイコン色
  final Color foreground;

  const LogTypeColorScheme({
    required this.background,
    required this.foreground,
  });

  /// ダークモードでの背景の明度。暗い面の上で沈みすぎない範囲に置く。
  static const double _darkBackgroundLightness = 0.22;

  /// ダークモードでの前景の明度。背景との比が十分取れる明るさにする。
  static const double _darkForegroundLightness = 0.85;

  /// [colors] と [brightness] から、この種別で使う配色を返す。
  factory LogTypeColorScheme.resolve(
    LogTypeColors colors,
    LogType type,
    Brightness brightness,
  ) {
    final (int bg, int fg) = switch (type) {
      LogType.watering => (colors.wateringBg, colors.wateringFg),
      LogType.fertilizer => (colors.fertilizerBg, colors.fertilizerFg),
      LogType.vitalizer => (colors.vitalizerBg, colors.vitalizerFg),
      // 記録専用のケア種別（Issue #175）は個別の色を持たない
      _ => (colors.wateringBg, colors.wateringFg),
    };

    if (brightness == Brightness.light) {
      return LogTypeColorScheme(background: Color(bg), foreground: Color(fg));
    }

    // ダークモードでは、設定されている背景色の色相・彩度を引き継いだまま
    // 明度だけを入れ替える。既定値でも利用者がカスタマイズした色でも
    // 同じ規則で暗い側の配色が得られる。
    final hsl = HSLColor.fromColor(Color(bg));
    return LogTypeColorScheme(
      background: hsl.withLightness(_darkBackgroundLightness).toColor(),
      foreground: hsl.withLightness(_darkForegroundLightness).toColor(),
    );
  }
}
