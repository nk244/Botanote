import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Open-Meteo（APIキー不要）から翌日の天気予報を取得し、
/// 屋外植物のケアに関わる注意点を判定するサービス（Issue #176）。
class WeatherService {
  static const Duration _timeout = Duration(seconds: 10);

  // 判定閾値
  static const double _heatWaveThresholdC = 35.0;
  static const double _frostThresholdC = 0.0;
  static const double _heavyRainThresholdMm = 30.0;
  static const double _highUvThreshold = 8.0;

  /// [latitude]/[longitude] 地点の翌日予報を取得し、
  /// 該当する注意喚起メッセージのリストを返す。
  /// 通信失敗時は空リストを返す（呼び出し元で通知をスキップする）。
  static Future<List<String>> checkTomorrowAlerts({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$latitude&longitude=$longitude'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,uv_index_max'
        '&timezone=auto&forecast_days=2',
      );
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('WeatherService: HTTP ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>?;
      if (daily == null) return [];

      // インデックス1 = 翌日（forecast_days=2 の2件目）
      const dayIndex = 1;
      final maxTempList = daily['temperature_2m_max'] as List<dynamic>?;
      final minTempList = daily['temperature_2m_min'] as List<dynamic>?;
      final precipList = daily['precipitation_sum'] as List<dynamic>?;
      final uvList = daily['uv_index_max'] as List<dynamic>?;

      if (maxTempList == null || maxTempList.length <= dayIndex) return [];

      final alerts = <String>[];

      final maxTemp = (maxTempList[dayIndex] as num?)?.toDouble();
      if (maxTemp != null && maxTemp >= _heatWaveThresholdC) {
        alerts.add('明日は猛暑日（最高${maxTemp.round()}℃）の予報です。'
            '屋外の植物は水切れ・葉焼けに注意し、朝夕の水やりを検討してください。');
      }

      final minTemp = minTempList != null && minTempList.length > dayIndex
          ? (minTempList[dayIndex] as num?)?.toDouble()
          : null;
      if (minTemp != null && minTemp <= _frostThresholdC) {
        alerts.add('明日は最低${minTemp.round()}℃まで冷え込む予報です。'
            '霜に弱い屋外の植物は室内への移動や防寒対策を検討してください。');
      }

      final precip = precipList != null && precipList.length > dayIndex
          ? (precipList[dayIndex] as num?)?.toDouble()
          : null;
      if (precip != null && precip >= _heavyRainThresholdMm) {
        alerts.add('明日は${precip.round()}mmの大雨が予想されています。'
            '鉢の水はけを確認し、必要であれば軒下に移動してください。');
      }

      final uv = uvList != null && uvList.length > dayIndex
          ? (uvList[dayIndex] as num?)?.toDouble()
          : null;
      if (uv != null && uv >= _highUvThreshold) {
        alerts.add('明日は強い紫外線（UVインデックス${uv.round()}）の予報です。'
            '直射日光に弱い植物は遮光を検討してください。');
      }

      return alerts;
    } catch (e) {
      debugPrint('WeatherService: failed to fetch forecast: $e');
      return [];
    }
  }
}
