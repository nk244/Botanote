/// 植物の置き場所（リビング・ベランダ等）データモデル（Issue #180）
class Location {
  /// 置き場所の一意識別子（UUID v4）
  final String id;

  /// 場所名
  final String name;

  /// 屋外かどうか（false: 屋内、true: 屋外）
  final bool isOutdoor;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Location({
    required this.id,
    required this.name,
    this.isOutdoor = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isOutdoor': isOutdoor ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Location.fromMap(Map<String, dynamic> map) {
    return Location(
      id: map['id'] as String,
      name: map['name'] as String,
      isOutdoor: (map['isOutdoor'] as int?) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// フィールドを部分的に更新した新しい Location を返す。
  Location copyWith({String? name, bool? isOutdoor, DateTime? updatedAt}) {
    return Location(
      id: id,
      name: name ?? this.name,
      isOutdoor: isOutdoor ?? this.isOutdoor,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
