import 'package:share_plus/share_plus.dart';

/// 植物の写真をClaudeアプリに共有し、AIによる診断・同定を依頼するサービス（Issue #177/#178）。
///
/// Anthropic APIを直接呼び出す従量課金方式ではなく、OSの共有シート経由で
/// Claudeアプリ（無料プラン・Proプランいずれでも利用可能）に画像と質問文を渡す。
/// 応答はClaudeアプリ上で確認し、ユーザーが手動でノート/入力欄に転記する。
class ClaudeShareService {
  /// 病害虫診断を依頼するプロンプト付きで画像を共有する。
  static Future<void> shareForDiagnosis(String imagePath) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: 'この植物の写真を見て、病気や害虫の可能性と対処法を教えてください。',
      subject: '植物の病害虫診断',
    );
  }

  /// 1枚の写真に写っている複数の植物の一覧作成を依頼する（Issue #66）。
  ///
  /// アプリ側で機械的に読み取れるよう、1行1植物・`名前 / 品種` の形式を指定する。
  static Future<void> shareForBulkIdentification(String imagePath) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: 'この写真に写っている植物をすべて挙げてください。'
          '1行に1つ、「名前 / 品種」の形式で、名前は和名または流通名でお願いします。'
          '品種が分からない場合は名前だけで構いません。'
          '説明文や見出しは付けず、一覧だけを返してください。',
      subject: '植物の一括同定',
    );
  }

  /// 植物名・品種の同定を依頼するプロンプト付きで画像を共有する。
  static Future<void> shareForIdentification(String imagePath) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: 'この植物の写真から、植物の一般的な名前（和名または流通名）と、'
          '分かる場合は品種名を教えてください。',
      subject: '植物名の同定',
    );
  }
}
