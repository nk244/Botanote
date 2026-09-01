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

  /// 種別名から [LogType] を引く。未知の名前の場合は null を返す。
  ///
  /// 新しい種別を追加したバージョンで取ったバックアップを、それより古い
  /// バージョンで読み込むと未知の名前が現れる。ここで例外を投げると
  /// バックアップ全体の復元が失敗するため、呼び出し側が1件だけ読み飛ばせる
  /// ように null を返す（Issue #319）。
  static LogType? parseType(Object? raw) {
    if (raw is! String) return null;
    for (final type in LogType.values) {
      if (type.name == raw) return type;
    }
    return null;
  }

  /// DB から取得した Map を LogEntry に変換する。
  ///
  /// 種別名が未知の場合は [FormatException] をスローする。1件だけ読み飛ばして
  /// 処理を続けたい場合は [tryFromMap] を使うこと。
  factory LogEntry.fromMap(Map<String, dynamic> map) {
    final type = parseType(map['type']);
    if (type == null) {
      throw FormatException('未対応のログ種別です: ${map['type']}');
    }
    return LogEntry(
      id: map['id'] as String,
      plantId: map['plantId'] as String,
      type: type,
      // バックアップが UTC 表記（末尾 Z）の場合に日付が1日ずれないよう、
      // ローカル時刻へ揃える。ナイーブ表記に対しては値が変わらない（Issue #338）。
      date: DateTime.parse(map['date'] as String).toLocal(),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updatedAt'] as String).toLocal(),
    );
  }

  /// [fromMap] と同じ変換を行い、読み取れない場合は null を返す（Issue #319）。
  ///
  /// 未知の種別名や欠損フィールドがあっても例外を投げないため、
  /// インポートや一覧取得で「壊れた1件だけを読み飛ばす」用途に使える。
  static LogEntry? tryFromMap(Map<String, dynamic> map) {
    try {
      return LogEntry.fromMap(map);
    } catch (_) {
      return null;
    }
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
