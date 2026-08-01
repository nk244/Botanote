/// 植物データモデル
class Plant {
  /// 植物の一意識別子（UUID v4）
  final String id;

  /// 植物名（必須）
  final String name;

  /// 植物名の読み仮名（任意）。五十音順の並び替えに使う（Issue #257）。
  ///
  /// 漢字の和名は読みを機械的に導けないため、正しく五十音順に並べたい
  /// ユーザーが任意で入力する。未入力の場合は [name] を代わりに使う。
  final String? nameReading;

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

  /// 屋外の植物かどうか（天気連動ケアアラート対象、Issue #176）
  final bool isOutdoor;

  /// 置き場所ID（[Location] への参照、Issue #180）
  final String? locationId;

  /// 冬季（12〜2月）の間隔延長を有効にするか
  final bool seasonalAdjustmentEnabled;

  /// 冬季の間隔倍率（例: 1.5 = 1.5倍に延長）。
  /// [seasonalAdjustmentEnabled] が true でもこれが null の場合は調整されない。
  final double? dormantSeasonIntervalMultiplier;

  /// 登録日時
  final DateTime createdAt;

  /// 最終更新日時
  final DateTime updatedAt;

  const Plant({
    required this.id,
    required this.name,
    this.nameReading,
    this.variety,
    this.purchaseDate,
    this.purchaseLocation,
    this.imagePath,
    this.wateringIntervalDays,
    this.fertilizerIntervalDays,
    this.fertilizerEveryNWaterings,
    this.vitalizerIntervalDays,
    this.vitalizerEveryNWaterings,
    this.isOutdoor = false,
    this.locationId,
    this.seasonalAdjustmentEnabled = false,
    this.dormantSeasonIntervalMultiplier,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nameReading': nameReading,
      'variety': variety,
      'purchaseDate': purchaseDate?.toIso8601String(),
      'purchaseLocation': purchaseLocation,
      'imagePath': imagePath,
      'wateringIntervalDays': wateringIntervalDays,
      'fertilizerIntervalDays': fertilizerIntervalDays,
      'fertilizerEveryNWaterings': fertilizerEveryNWaterings,
      'vitalizerIntervalDays': vitalizerIntervalDays,
      'vitalizerEveryNWaterings': vitalizerEveryNWaterings,
      'isOutdoor': isOutdoor ? 1 : 0,
      'locationId': locationId,
      'seasonalAdjustmentEnabled': seasonalAdjustmentEnabled ? 1 : 0,
      'dormantSeasonIntervalMultiplier': dormantSeasonIntervalMultiplier,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// DB から取得した Map を Plant に変換する。
  factory Plant.fromMap(Map<String, dynamic> map) {
    return Plant(
      id: map['id'] as String,
      name: map['name'] as String,
      nameReading: map['nameReading'] as String?,
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
      isOutdoor: (map['isOutdoor'] as int?) == 1,
      locationId: map['locationId'] as String?,
      seasonalAdjustmentEnabled: (map['seasonalAdjustmentEnabled'] as int?) == 1,
      dormantSeasonIntervalMultiplier:
          map['dormantSeasonIntervalMultiplier'] as double?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// フィールドを部分的に更新した新しい Plant を返す。
  /// nullable フィールドを明示的に null にしたい場合は sentinel パターンを使用する。
  Plant copyWith({
    String? name,
    Object? nameReading = _sentinel,
    Object? variety = _sentinel,
    Object? purchaseDate = _sentinel,
    Object? purchaseLocation = _sentinel,
    Object? imagePath = _sentinel,
    Object? wateringIntervalDays = _sentinel,
    Object? fertilizerIntervalDays = _sentinel,
    Object? fertilizerEveryNWaterings = _sentinel,
    Object? vitalizerIntervalDays = _sentinel,
    Object? vitalizerEveryNWaterings = _sentinel,
    bool? isOutdoor,
    Object? locationId = _sentinel,
    bool? seasonalAdjustmentEnabled,
    Object? dormantSeasonIntervalMultiplier = _sentinel,
    DateTime? updatedAt,
  }) {
    return Plant(
      id: id,
      name: name ?? this.name,
      nameReading:
          nameReading == _sentinel ? this.nameReading : nameReading as String?,
      variety: variety == _sentinel ? this.variety : variety as String?,
      purchaseDate: purchaseDate == _sentinel ? this.purchaseDate : purchaseDate as DateTime?,
      purchaseLocation: purchaseLocation == _sentinel ? this.purchaseLocation : purchaseLocation as String?,
      imagePath: imagePath == _sentinel ? this.imagePath : imagePath as String?,
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
      isOutdoor: isOutdoor ?? this.isOutdoor,
      locationId: locationId == _sentinel ? this.locationId : locationId as String?,
      seasonalAdjustmentEnabled:
          seasonalAdjustmentEnabled ?? this.seasonalAdjustmentEnabled,
      dormantSeasonIntervalMultiplier: dormantSeasonIntervalMultiplier == _sentinel
          ? this.dormantSeasonIntervalMultiplier
          : dormantSeasonIntervalMultiplier as double?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// copyWith で nullable フィールドを明示的に null にするための sentinel 値
const Object _sentinel = Object();
