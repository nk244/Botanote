import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_chat_message.dart';

/// Claude API との通信を担うサービス
class AiService {
  static const String _apiUrl =
      'https://api.anthropic.com/v1/messages';
  static const String _modelDefault = 'claude-haiku-4-5-20251001';
  static const Duration _timeout = Duration(seconds: 30);

  /// テキスト・画像を含むメッセージをClaude APIに送信し、応答テキストを返す。
  ///
  /// [apiKey] が空の場合は [ArgumentError] をスローする。
  /// APIエラー時は [AiServiceException] をスローする。
  Future<String> sendMessage({
    required String apiKey,
    required String systemPrompt,
    required List<AiChatMessage> history,
    String model = _modelDefault,
  }) async {
    if (apiKey.isEmpty) {
      throw ArgumentError('APIキーが設定されていません');
    }

    final messages = _buildMessages(history);

    final body = jsonEncode({
      'model': model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': messages,
    });

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: body,
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      throw AiServiceException('ネットワークエラー: $e');
    }

    return _parseResponse(response);
  }

  /// 植物の写真から植物名・品種をJSON形式で返す。
  ///
  /// 戻り値: `{"name": "...", "variety": "..."}`
  Future<Map<String, String?>> identifyPlant({
    required String apiKey,
    required String imageBase64,
  }) async {
    const systemPrompt =
        '植物識別の専門家です。送られた画像から植物名と品種を特定し、必ずJSON形式のみで返してください。'
        '例: {"name": "モンステラ", "variety": "デリシオサ"}'
        '品種が不明な場合は "variety" を null にしてください。';

    final message = AiChatMessage(
      isUser: true,
      text: 'この植物の名前と品種を教えてください。',
      imageBase64: imageBase64,
    );

    final raw = await sendMessage(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      history: [message],
    );

    // JSONブロックを抽出してパース
    try {
      final jsonStr = _extractJson(raw);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return {
        'name': map['name'] as String?,
        'variety': map['variety'] as String?,
      };
    } catch (_) {
      throw AiServiceException('植物を識別できませんでした');
    }
  }

  /// 植物の健康診断を行い、診断結果テキストを返す。
  Future<String> diagnoseHealth({
    required String apiKey,
    required String plantName,
    required String? variety,
    required String? symptomText,
    required int? wateringIntervalDays,
    required DateTime? lastWateredAt,
    required String? imageBase64,
  }) async {
    const systemPrompt =
        'あなたは植物の健康アドバイザーです。ユーザーから植物の情報と症状を受け取り、'
        '考えられる原因と対処法を丁寧に日本語で説明してください。';

    final buffer = StringBuffer();
    buffer.writeln('植物名: $plantName');
    if (variety != null) buffer.writeln('品種: $variety');
    if (wateringIntervalDays != null) {
      buffer.writeln('水やり間隔: $wateringIntervalDays日ごと');
    }
    if (lastWateredAt != null) {
      final days = DateTime.now().difference(lastWateredAt).inDays;
      buffer.writeln('前回の水やりから: $days日経過');
    }
    if (symptomText != null && symptomText.isNotEmpty) {
      buffer.writeln('症状: $symptomText');
    }

    final message = AiChatMessage(
      isUser: true,
      text: buffer.toString(),
      imageBase64: imageBase64,
    );

    return sendMessage(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      history: [message],
    );
  }

  /// [AiChatMessage] のリストをClaude API用のメッセージ形式に変換する。
  List<Map<String, dynamic>> _buildMessages(List<AiChatMessage> history) {
    return history.map((msg) {
      final List<Map<String, dynamic>> content = [];

      // 画像がある場合は先にコンテンツブロックに追加
      if (msg.imageBase64 != null) {
        content.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/jpeg',
            'data': msg.imageBase64,
          },
        });
      }

      content.add({'type': 'text', 'text': msg.text});

      return {
        'role': msg.isUser ? 'user' : 'assistant',
        'content': content,
      };
    }).toList();
  }

  /// APIレスポンスをパースしてテキストを返す。
  String _parseResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw AiServiceException('APIキーが無効です。設定を確認してください。');
    }
    if (response.statusCode == 429) {
      throw AiServiceException('リクエストが多すぎます。しばらく待ってから再試行してください。');
    }
    if (response.statusCode != 200) {
      throw AiServiceException('APIエラー (${response.statusCode})');
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = json['content'] as List<dynamic>;
      final text = (content.first as Map<String, dynamic>)['text'] as String;
      return text;
    } catch (_) {
      throw AiServiceException('レスポンスの解析に失敗しました');
    }
  }

  /// レスポンス文字列からJSONブロックを抽出する。
  String _extractJson(String text) {
    // ```json ... ``` ブロックがあれば抽出
    final jsonBlockRegex = RegExp(r'```(?:json)?\s*(\{.*?\})\s*```', dotAll: true);
    final match = jsonBlockRegex.firstMatch(text);
    if (match != null) return match.group(1)!;

    // { ... } を直接探す
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }

    return text;
  }
}

/// AI サービスのエラー
class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);

  @override
  String toString() => message;
}
