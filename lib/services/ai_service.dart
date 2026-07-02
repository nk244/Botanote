import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// AI診断・同定サービスの呼び出し失敗を表す例外（Issue #177/#178）。
class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);

  @override
  String toString() => message;
}

/// Anthropic Claude API（vision）を用いて植物写真を解析するサービス。
///
/// APIキーはユーザーが設定画面で入力したものを利用する（アプリ側でのキー管理は行わない）。
class AiService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-4-8';
  static const _anthropicVersion = '2023-06-01';
  static const Duration _timeout = Duration(seconds: 30);

  /// 画像から病気・害虫の可能性と対処法を診断する。
  static Future<String> diagnosePlantHealth({
    required String apiKey,
    required Uint8List imageBytes,
    required String mediaType,
  }) {
    return _sendVisionRequest(
      apiKey: apiKey,
      imageBytes: imageBytes,
      mediaType: mediaType,
      prompt: '添付した植物の写真を見て、病気や害虫の可能性を診断してください。'
          '該当する症状があれば具体的な病名・害虫名の可能性と対処法を、'
          '特に問題が見当たらなければその旨を、日本語で簡潔に（300字程度で）回答してください。',
    );
  }

  /// 画像から植物名・品種名を推定する。
  static Future<String> identifyPlant({
    required String apiKey,
    required Uint8List imageBytes,
    required String mediaType,
  }) {
    return _sendVisionRequest(
      apiKey: apiKey,
      imageBytes: imageBytes,
      mediaType: mediaType,
      prompt: '添付した植物の写真から、植物の一般的な名前（和名または流通名）と、'
          '分かる場合は品種名を推定してください。'
          '出力は必ず次のJSON形式のみで、他の文章を含めないでください: '
          '{"name": "植物名", "variety": "品種名またはnull", "confidence": "high/medium/low"}',
    );
  }

  static Future<String> _sendVisionRequest({
    required String apiKey,
    required Uint8List imageBytes,
    required String mediaType,
    required String prompt,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException('APIキーが設定されていません。設定画面から登録してください。');
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _anthropicVersion,
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 1024,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': mediaType,
                        'data': base64Image,
                      },
                    },
                    {'type': 'text', 'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw AiServiceException(
            'AI診断リクエストに失敗しました（HTTP ${response.statusCode}）');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (data['stop_reason'] == 'refusal') {
        throw const AiServiceException('この画像は診断できませんでした。');
      }

      final content = data['content'] as List<dynamic>?;
      final textBlock = content?.firstWhere(
        (b) => (b as Map<String, dynamic>)['type'] == 'text',
        orElse: () => null,
      ) as Map<String, dynamic>?;

      final text = textBlock?['text'] as String?;
      if (text == null || text.isEmpty) {
        throw const AiServiceException('AIから有効な応答が得られませんでした。');
      }
      return text;
    } on AiServiceException {
      rethrow;
    } catch (e) {
      throw AiServiceException('AI診断に失敗しました: $e');
    }
  }
}
