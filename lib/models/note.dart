import 'dart:convert';

/// copyWith で content を明示的に null にするための sentinel 値
const Object _sentinel = Object();

/// ノート（日記）データモデル
class Note {
  final String id;
  final String title;
  final String? content;

  /// 添付画像のファイルパスリスト
  final List<String> imagePaths;

  /// 関連する植物IDリスト
  final List<String> plantIds;

  /// タグ（`#` は含めない素の文字列。例: `発根管理`）（Issue #278）
  final List<String> tags;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.title,
    this.content,
    this.imagePaths = const [],
    this.plantIds = const [],
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBへの保存用 Map に変換する。
  /// リスト型フィールドは JSON 文字列にエンコードする。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'imagePaths': jsonEncode(imagePaths),
      'plantIds': jsonEncode(plantIds),
      'tags': jsonEncode(tags),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// DB から取得した Map を Note に変換する。
  factory Note.fromMap(Map<String, dynamic> map) {
    // 旧フォーマット（|区切り文字列）との後方互換性を保つ
    List<String> parseList(dynamic raw) {
      if (raw == null || (raw is String && raw.isEmpty)) return [];
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) return List<String>.from(decoded);
        } catch (_) {
          // 旧フォーマット（|区切り）のフォールバック
          return raw.split('|').where((s) => s.isNotEmpty).toList();
        }
      }
      return [];
    }

    return Note(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String?,
      imagePaths: parseList(map['imagePaths']),
      plantIds: parseList(map['plantIds']),
      tags: parseList(map['tags']),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// フィールドを部分的に更新した新しい Note を返す。
  /// [content] を明示的に null にしたい場合は `content: null` を渡す
  /// （sentinel パターンにより null と「未指定」を区別する）。
  Note copyWith({
    String? title,
    Object? content = _sentinel,
    List<String>? imagePaths,
    List<String>? plantIds,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content == _sentinel ? this.content : content as String?,
      imagePaths: imagePaths ?? this.imagePaths,
      plantIds: plantIds ?? this.plantIds,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
