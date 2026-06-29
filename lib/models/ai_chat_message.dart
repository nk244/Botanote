import 'package:uuid/uuid.dart';

/// AIチャットのメッセージデータモデル
class AiChatMessage {
  /// メッセージの一意識別子（UUID v4）
  final String id;

  /// true=ユーザー発言, false=AI応答
  final bool isUser;

  /// メッセージ本文
  final String text;

  /// ユーザーが添付した画像（Base64エンコード済み）
  final String? imageBase64;

  /// 作成日時
  final DateTime createdAt;

  AiChatMessage({
    String? id,
    required this.isUser,
    required this.text,
    this.imageBase64,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
