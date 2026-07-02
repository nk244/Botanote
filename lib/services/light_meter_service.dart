import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 明るさレベルの5段階分類（Issue #181）
enum LightLevel {
  dark, // 暗い（日陰）
  dimShade, // やや暗い（半日陰）
  brightShade, // 明るい半日陰
  bright, // 明るい
  directSun, // 直射日光相当
}

/// 光量測定結果
class LightMeterResult {
  /// 平均輝度（0〜255）
  final double luminance;
  final LightLevel level;

  const LightMeterResult({required this.luminance, required this.level});
}

/// カメラで撮影した画像の輝度を解析し、明るさの目安を算出するサービス（Issue #181）。
///
/// スマホ端末に依存するネイティブの照度センサーAPI（iOSには存在しない）ではなく、
/// 撮影画像の平均輝度を用いることでAndroid/iOS双方で同一ロジックを使用する。
/// カメラの自動露出補正の影響を受けるため、絶対値としての精度は低い（相対的な目安）。
class LightMeterService {
  /// 輝度計算のために画像を縮小する際の最大幅（処理軽量化のため）
  static const int _resizeWidth = 64;

  /// 画像バイト列から平均輝度と明るさレベルを算出する。
  /// デコードに失敗した場合は null を返す。
  static LightMeterResult? analyze(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final resized = img.copyResize(decoded, width: _resizeWidth);

    double total = 0;
    int count = 0;
    for (final pixel in resized) {
      total += pixel.luminance;
      count++;
    }
    if (count == 0) return null;

    final avg = total / count;
    return LightMeterResult(luminance: avg, level: _levelFor(avg));
  }

  static LightLevel _levelFor(double luminance) {
    if (luminance < 40) return LightLevel.dark;
    if (luminance < 90) return LightLevel.dimShade;
    if (luminance < 150) return LightLevel.brightShade;
    if (luminance < 210) return LightLevel.bright;
    return LightLevel.directSun;
  }

  static String labelFor(LightLevel level) {
    switch (level) {
      case LightLevel.dark:
        return '暗い（日陰）';
      case LightLevel.dimShade:
        return 'やや暗い（半日陰）';
      case LightLevel.brightShade:
        return '明るい半日陰';
      case LightLevel.bright:
        return '明るい';
      case LightLevel.directSun:
        return '直射日光相当';
    }
  }
}
