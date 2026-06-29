import 'package:flutter/foundation.dart';
import '../models/ai_chat_message.dart';
import '../models/log_entry.dart';
import '../models/plant.dart';
import '../services/ai_service.dart';

/// AI機能の状態を管理する Provider。
///
/// チャット履歴はセッション内のみ保持し、画面を閉じるとリセットされる。
class AiProvider with ChangeNotifier {
  final AiService _aiService = AiService();

  List<AiChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// チャット履歴をリセットする。
  void clearMessages() {
    _messages = [];
    _error = null;
    notifyListeners();
  }

  /// ユーザーメッセージを送信し、AIの応答を取得する。
  Future<void> sendMessage({
    required String apiKey,
    required String text,
    String? imageBase64,
    required List<Plant> plants,
    required List<LogEntry> recentLogs,
  }) async {
    _error = null;

    final userMessage = AiChatMessage(
      isUser: true,
      text: text,
      imageBase64: imageBase64,
    );
    _messages = [..._messages, userMessage];
    _isLoading = true;
    notifyListeners();

    try {
      final systemPrompt = _buildSystemPrompt(plants, recentLogs);
      // 最大20往復（40メッセージ）にトリミング
      final trimmedHistory = _messages.length > 40
          ? _messages.sublist(_messages.length - 40)
          : _messages;

      final responseText = await _aiService.sendMessage(
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        history: trimmedHistory,
      );

      final aiMessage = AiChatMessage(isUser: false, text: responseText);
      _messages = [..._messages, aiMessage];
    } on AiServiceException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'エラーが発生しました: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 植物の健康診断を実行し、診断結果を返す。
  Future<String> diagnoseHealth({
    required String apiKey,
    required String plantName,
    required String? variety,
    required String? symptomText,
    required int? wateringIntervalDays,
    required DateTime? lastWateredAt,
    required String? imageBase64,
  }) async {
    return _aiService.diagnoseHealth(
      apiKey: apiKey,
      plantName: plantName,
      variety: variety,
      symptomText: symptomText,
      wateringIntervalDays: wateringIntervalDays,
      lastWateredAt: lastWateredAt,
      imageBase64: imageBase64,
    );
  }

  /// 写真から植物を識別し、名前と品種を返す。
  Future<Map<String, String?>> identifyPlant({
    required String apiKey,
    required String imageBase64,
  }) async {
    return _aiService.identifyPlant(
      apiKey: apiKey,
      imageBase64: imageBase64,
    );
  }

  /// コーチ機能用のシステムプロンプトを生成する。
  String _buildSystemPrompt(List<Plant> plants, List<LogEntry> recentLogs) {
    final buffer = StringBuffer();
    buffer.writeln('あなたは親切な植物ケアのコーチです。ユーザーの植物の状況を踏まえて、'
        '具体的で実践的なアドバイスを日本語でしてください。');

    if (plants.isNotEmpty) {
      buffer.writeln('\n## ユーザーの植物一覧');
      for (final plant in plants) {
        buffer.write('- ${plant.name}');
        if (plant.variety != null) buffer.write('（${plant.variety}）');
        if (plant.wateringIntervalDays != null) {
          buffer.write('：水やり${plant.wateringIntervalDays}日ごと');
        }
        buffer.writeln();
      }
    }

    if (recentLogs.isNotEmpty) {
      buffer.writeln('\n## 直近のケア記録（最新${recentLogs.length}件）');
      for (final log in recentLogs) {
        final plant = plants.where((p) => p.id == log.plantId).firstOrNull;
        final plantName = plant?.name ?? '不明な植物';
        final logTypeName = switch (log.type) {
          LogType.watering => '水やり',
          LogType.fertilizer => '肥料',
          LogType.vitalizer => '活力剤',
        };
        final dateStr =
            '${log.date.year}/${log.date.month}/${log.date.day}';
        buffer.writeln('- $dateStr: $plantName に $logTypeName');
      }
    }

    return buffer.toString();
  }
}
