/// ログの種別を表す列挙型
enum LogType {
  /// 水やり
  watering,

  /// 肥料
  fertilizer,

  /// 活力剤
  vitalizer,

  /// 植え替え（Issue #175: 記録専用、間隔・スケジュールなし）
  repotting,

  /// 剪定（Issue #175: 記録専用、間隔・スケジュールなし）
  pruning,

  /// 葉水（Issue #175: 記録専用、間隔・スケジュールなし）
  misting,

  /// 掃除（Issue #175: 記録専用、間隔・スケジュールなし）
  cleaning,
}

/// 植物へのケアログ（水やり・肥料・活力剤）データモデル
class LogEntry {
  /// ログの一意識別子（UUID v4）
  final String id;

  /// 対象植物のID
  final String plantId;

  /// ログ種別
  final LogType type;

  /// 記録日時
  final DateTime date;

  /// メモ
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;

  const LogEntry({
    required this.id,
    required this.plantId,
    required this.type,
    required this.date,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBへの保存用 Map に変換する。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plantId': plantId,
      'type': type.name,
      'date': date.toIso8601String(),
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// DB から取得した Map を LogEntry に変換する。
  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'] as String,
      plantId: map['plantId'] as String,
      type: LogType.values.firstWhere((e) => e.name == map['type']),
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// フィールドを部分的に更新した新しい LogEntry を返す。
  LogEntry copyWith({DateTime? date, String? note, DateTime? updatedAt}) {
    return LogEntry(
      id: id,
      plantId: plantId,
      type: type,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
