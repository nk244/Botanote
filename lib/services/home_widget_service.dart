import 'package:flutter/foundation.dart' show debugPrint;
import 'package:home_widget/home_widget.dart';
import '../models/plant.dart';

/// ホーム画面ウィジェット（今日の水やり予定表示）へのデータ連携を担うサービス（Issue #174）。
///
/// Android の RemoteViews ベースウィジェット（`TodayWateringWidgetProvider`）のみ対応。
/// ウィジェット未配置・プラットフォーム未対応（iOS/Web/Windows）の場合は例外を握りつぶし、
/// アプリ本体の動作に影響しないようにする。
class HomeWidgetService {
  static const _androidWidgetName = 'TodayWateringWidgetProvider';
  static const _countKey = 'pendingWateringCount';
  static const _summaryKey = 'pendingWateringSummary';

  /// 今日水やりが必要な [plants] の件数・植物名をウィジェットに反映する。
  static Future<void> updateTodayWateringWidget(List<Plant> plants) async {
    try {
      final count = plants.length;
      final summary = plants.isEmpty
          ? '今日の水やりはありません'
          : plants.take(3).map((p) => p.name).join('、') +
                (plants.length > 3 ? ' 他${plants.length - 3}件' : '');

      await HomeWidget.saveWidgetData<int>(_countKey, count);
      await HomeWidget.saveWidgetData<String>(_summaryKey, summary);
      await HomeWidget.updateWidget(name: _androidWidgetName);
    } catch (e) {
      // ウィジェット未配置・プラットフォーム未対応の場合はここに到達するが、
      // アプリ本体の動作には影響させない
      debugPrint('HomeWidget update skipped: $e');
    }
  }
}
