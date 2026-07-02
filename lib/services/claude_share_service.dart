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
}
