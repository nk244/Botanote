/// 植物データモデル
class Plant {
  /// 植物の一意識別子（UUID v4）
  final String id;

  /// 植物名（必須）
  final String name;

  /// 品種名
  final String? variety;

  /// 購入日
  final DateTime? purchaseDate;

  /// 購入先
  final String? purchaseLocation;

  /// 画像ファイルパス（Web の場合は base64）
  final String? imagePath;

  /// 水やり間隔（日数）
  final int? wateringIntervalDays;

  /// 肥料間隔（日数指定）。[fertilizerEveryNWaterings] と排他
  final int? fertilizerIntervalDays;

  /// 肥料間隔（水やりN回に1回）。[fertilizerIntervalDays] と排他
  final int? fertilizerEveryNWaterings;

  /// 活力剤間隔（日数指定）。[vitalizerEveryNWaterings] と排他
  final int? vitalizerIntervalDays;

  /// 活力剤間隔（水やりN回に1回）。[vitalizerIntervalDays] と排他
  final int? vitalizerEveryNWaterings;

  /// 登録日時
  final DateTime createdAt;

  /// 最終更新日時
  final DateTime updatedAt;

  const Plant({
    required this.id,
    required this.name,
    this.variety,
    this.purchaseDate,
    this.purchaseLocation,
    this.imagePath,
    this.wateringIntervalDays,
    this.fertilizerIntervalDays,
    this.fertilizerEveryNWaterings,
    this.vitalizerIntervalDays,
    this.vitalizerEveryNWaterings,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'variety': variety,
      'purchaseDate': purchaseDate?.toIso8601String(),
      'purchaseLocation': purchaseLocation,
      'imagePath': imagePath,
      'wateringIntervalDays': wateringIntervalDays,
      'fertilizerIntervalDays': fertilizerIntervalDays,
      'fertilizerEveryNWaterings': fertilizerEveryNWaterings,
      'vitalizerIntervalDays': vitalizerIntervalDays,
      'vitalizerEveryNWaterings': vitalizerEveryNWaterings,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// DB から取得した Map を Plant に変換する。
  factory Plant.fromMap(Map<String, dynamic> map) {
    return Plant(
      id: map['id'] as String,
      name: map['name'] as String,
      variety: map['variety'] as String?,
      purchaseDate: map['purchaseDate'] != null
          ? DateTime.parse(map['purchaseDate'] as String)
          : null,
      purchaseLocation: map['purchaseLocation'] as String?,
      imagePath: map['imagePath'] as String?,
      wateringIntervalDays: map['wateringIntervalDays'] as int?,
      fertilizerIntervalDays: map['fertilizerIntervalDays'] as int?,
      fertilizerEveryNWaterings: map['fertilizerEveryNWaterings'] as int?,
      vitalizerIntervalDays: map['vitalizerIntervalDays'] as int?,
      vitalizerEveryNWaterings: map['vitalizerEveryNWaterings'] as int?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// フィールドを部分的に更新した新しい Plant を返す。
  /// nullable フィールドを明示的に null にしたい場合は sentinel パターンを使用する。
  Plant copyWith({
    String? name,
    String? variety,
    DateTime? purchaseDate,
    String? purchaseLocation,
    String? imagePath,
    Object? wateringIntervalDays = _sentinel,
    Object? fertilizerIntervalDays = _sentinel,
    Object? fertilizerEveryNWaterings = _sentinel,
    Object? vitalizerIntervalDays = _sentinel,
    Object? vitalizerEveryNWaterings = _sentinel,
    DateTime? updatedAt,
  }) {
    return Plant(
      id: id,
      name: name ?? this.name,
      variety: variety ?? this.variety,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseLocation: purchaseLocation ?? this.purchaseLocation,
      imagePath: imagePath ?? this.imagePath,
      wateringIntervalDays: wateringIntervalDays == _sentinel
          ? this.wateringIntervalDays
          : wateringIntervalDays as int?,
      fertilizerIntervalDays: fertilizerIntervalDays == _sentinel
          ? this.fertilizerIntervalDays
          : fertilizerIntervalDays as int?,
      fertilizerEveryNWaterings: fertilizerEveryNWaterings == _sentinel
          ? this.fertilizerEveryNWaterings
          : fertilizerEveryNWaterings as int?,
      vitalizerIntervalDays: vitalizerIntervalDays == _sentinel
          ? this.vitalizerIntervalDays
          : vitalizerIntervalDays as int?,
      vitalizerEveryNWaterings: vitalizerEveryNWaterings == _sentinel
          ? this.vitalizerEveryNWaterings
          : vitalizerEveryNWaterings as int?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// copyWith で nullable フィールドを明示的に null にするための sentinel 値
const Object _sentinel = Object();
