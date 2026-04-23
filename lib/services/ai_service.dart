import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

/// AI機能を提供するサービスクラス。
///
/// Gemini API を利用して植物の自動識別・健康診断・パーソナルコーチ機能を提供する。
class AiService {
  /// Gemini APIキーが未設定の場合にスローする例外メッセージ
  static const String _noApiKeyMessage =
      'Gemini APIキーが設定されていません。設定画面でAPIキーを入力してください。';

  /// 植物の写真から植物名と品種を識別する。
  ///
  /// [imageBytes] にトリミング済みの画像バイト列を渡す。
  /// [apiKey] はGemini APIキー。
  /// 識別結果として `{'name': '...', 'variety': '...'}` を返す。
  /// エラー時は [AiServiceException] をスローする。
  Future<PlantIdentificationResult> identifyPlant({
    required Uint8List imageBytes,
    required String apiKey,
  }) async {
    _validateApiKey(apiKey);

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    const prompt = '''
あなたは植物識別の専門家です。この画像に写っている植物を識別してください。

以下の形式で回答してください（必ずJSONで返してください）:
{
  "name": "植物の一般的な日本語名称",
  "variety": "品種名や学名（不明な場合は空文字）",
  "confidence": "high/medium/low のいずれか",
  "notes": "補足情報（任意）"
}

植物以外が写っている場合は:
{
  "name": "",
  "variety": "",
  "confidence": "low",
  "notes": "植物を識別できませんでした"
}
''';

    try {
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]);

      final text = response.text ?? '';
      return _parsePlantIdentification(text);
    } on GenerativeAIException catch (e) {
      throw AiServiceException('植物の識別に失敗しました: ${e.message}');
    } catch (e) {
      throw AiServiceException('植物の識別中にエラーが発生しました: $e');
    }
  }

  /// 植物の健康状態を診断する。
  ///
  /// [plantName] 植物名、[symptomDescription] ユーザーが入力した症状の説明。
  /// [imageBytes] に症状の写真バイト列を渡せる（null可）。
  Future<String> diagnoseHealth({
    required String plantName,
    required String symptomDescription,
    Uint8List? imageBytes,
    required String apiKey,
  }) async {
    _validateApiKey(apiKey);

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );

    final prompt = '''
あなたは植物の健康管理の専門家です。以下の植物の症状を診断してアドバイスしてください。

植物名: $plantName
症状の説明: $symptomDescription

以下の構成で回答してください:
1. **考えられる原因**（箇条書き）
2. **対処法**（具体的な手順）
3. **予防策**
4. **注意点**（重篤な場合や専門家への相談が必要な場合は明記）

日本語で回答してください。
''';

    try {
      final parts = <Part>[TextPart(prompt)];
      if (imageBytes != null) {
        parts.add(DataPart('image/jpeg', imageBytes));
      }

      final response = await model.generateContent([Content.multi(parts)]);
      return response.text ?? '診断結果を取得できませんでした。';
    } on GenerativeAIException catch (e) {
      throw AiServiceException('健康診断に失敗しました: ${e.message}');
    } catch (e) {
      throw AiServiceException('健康診断中にエラーが発生しました: $e');
    }
  }

  /// パーソナルコーチとチャット形式で対話する。
  ///
  /// [messages] はこれまでの会話履歴（ロール: 'user' / 'model'）。
  /// [userMessage] はユーザーの新しいメッセージ。
  /// [plantContext] は育てている植物情報の要約文字列（任意）。
  Future<String> chat({
    required List<ChatMessage> messages,
    required String userMessage,
    String? plantContext,
    required String apiKey,
  }) async {
    _validateApiKey(apiKey);

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(
        '''あなたは植物育成のパーソナルコーチです。ユーザーが育てている植物のケアについて、
わかりやすく親切にアドバイスします。

${plantContext != null ? '【ユーザーが育てている植物】\n$plantContext\n' : ''}
- 専門用語は避け、初心者にもわかりやすい言葉で説明する
- 具体的なアドバイスを心がける
- 質問には丁寧に答える
- 日本語で回答する''',
      ),
    );

    // 会話履歴を変換
    final history = messages.map((m) {
      return Content(m.role, [TextPart(m.text)]);
    }).toList();

    final chat = model.startChat(history: history);

    try {
      final response = await chat.sendMessage(Content.text(userMessage));
      return response.text ?? 'メッセージを取得できませんでした。';
    } on GenerativeAIException catch (e) {
      throw AiServiceException('チャットに失敗しました: ${e.message}');
    } catch (e) {
      throw AiServiceException('チャット中にエラーが発生しました: $e');
    }
  }

  /// APIキーが設定されているか検証する。
  void _validateApiKey(String apiKey) {
    if (apiKey.trim().isEmpty) {
      throw AiServiceException(_noApiKeyMessage);
    }
  }

  /// Gemini の応答テキストから植物識別結果をパースする。
  PlantIdentificationResult _parsePlantIdentification(String text) {
    // JSONブロックを抽出する
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch == null) {
      return PlantIdentificationResult(
        name: '',
        variety: '',
        confidence: 'low',
        notes: '識別結果のパースに失敗しました',
      );
    }

    try {
      final jsonStr = jsonMatch.group(0)!;
      // 簡易パース（jsonパッケージ不使用で抽出）
      final name = _extractJsonString(jsonStr, 'name');
      final variety = _extractJsonString(jsonStr, 'variety');
      final confidence = _extractJsonString(jsonStr, 'confidence');
      final notes = _extractJsonString(jsonStr, 'notes');
      return PlantIdentificationResult(
        name: name,
        variety: variety,
        confidence: confidence,
        notes: notes,
      );
    } catch (_) {
      return PlantIdentificationResult(
        name: '',
        variety: '',
        confidence: 'low',
        notes: '識別結果のパースに失敗しました',
      );
    }
  }

  /// JSONオブジェクト文字列から指定キーの文字列値を抽出する。
  String _extractJsonString(String json, String key) {
    final match = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(json);
    return match?.group(1) ?? '';
  }
}

/// 植物識別結果を保持するデータクラス。
class PlantIdentificationResult {
  final String name;
  final String variety;
  final String confidence;
  final String notes;

  const PlantIdentificationResult({
    required this.name,
    required this.variety,
    required this.confidence,
    required this.notes,
  });

  /// 識別に成功したかどうか（植物名が取得できたか）
  bool get isSuccessful => name.isNotEmpty;

  /// 信頼度の日本語表現
  String get confidenceLabel {
    switch (confidence) {
      case 'high':
        return '高';
      case 'medium':
        return '中';
      default:
        return '低';
    }
  }
}

/// チャットメッセージを保持するデータクラス。
class ChatMessage {
  /// 'user' または 'model'
  final String role;
  final String text;

  const ChatMessage({required this.role, required this.text});
}

/// AIサービスで発生するエラーを表す例外クラス。
class AiServiceException implements Exception {
  final String message;

  const AiServiceException(this.message);

  @override
  String toString() => 'AiServiceException: $message';
}
