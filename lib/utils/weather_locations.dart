/// 天気連動ケアアラートの観測地点として選べる地点（Issue #332）。
///
/// 猛暑・低温・大雨・強UVの判定は市区町村レベルの精度で足りるため、
/// 都道府県庁所在地の座標をプリセットとして持つ。外部のジオコーディング
/// API にも位置情報パーミッションにも依存せずに設定できる。
class WeatherLocationPreset {
  /// 表示名（都道府県名）
  final String name;
  final double latitude;
  final double longitude;

  const WeatherLocationPreset(this.name, this.latitude, this.longitude);
}

/// 都道府県庁所在地の一覧（北から南の順）。
const List<WeatherLocationPreset> kWeatherLocationPresets = [
  WeatherLocationPreset('北海道（札幌）', 43.0642, 141.3469),
  WeatherLocationPreset('青森県（青森）', 40.8244, 140.7400),
  WeatherLocationPreset('岩手県（盛岡）', 39.7036, 141.1527),
  WeatherLocationPreset('宮城県（仙台）', 38.2688, 140.8721),
  WeatherLocationPreset('秋田県（秋田）', 39.7186, 140.1024),
  WeatherLocationPreset('山形県（山形）', 38.2404, 140.3633),
  WeatherLocationPreset('福島県（福島）', 37.7503, 140.4676),
  WeatherLocationPreset('茨城県（水戸）', 36.3418, 140.4468),
  WeatherLocationPreset('栃木県（宇都宮）', 36.5657, 139.8836),
  WeatherLocationPreset('群馬県（前橋）', 36.3907, 139.0604),
  WeatherLocationPreset('埼玉県（さいたま）', 35.8570, 139.6489),
  WeatherLocationPreset('千葉県（千葉）', 35.6051, 140.1233),
  WeatherLocationPreset('東京都（新宿）', 35.6896, 139.6917),
  WeatherLocationPreset('神奈川県（横浜）', 35.4478, 139.6425),
  WeatherLocationPreset('新潟県（新潟）', 37.9026, 139.0232),
  WeatherLocationPreset('富山県（富山）', 36.6953, 137.2113),
  WeatherLocationPreset('石川県（金沢）', 36.5947, 136.6256),
  WeatherLocationPreset('福井県（福井）', 36.0652, 136.2216),
  WeatherLocationPreset('山梨県（甲府）', 35.6642, 138.5684),
  WeatherLocationPreset('長野県（長野）', 36.6513, 138.1810),
  WeatherLocationPreset('岐阜県（岐阜）', 35.3912, 136.7223),
  WeatherLocationPreset('静岡県（静岡）', 34.9769, 138.3831),
  WeatherLocationPreset('愛知県（名古屋）', 35.1802, 136.9066),
  WeatherLocationPreset('三重県（津）', 34.7303, 136.5086),
  WeatherLocationPreset('滋賀県（大津）', 35.0045, 135.8686),
  WeatherLocationPreset('京都府（京都）', 35.0116, 135.7681),
  WeatherLocationPreset('大阪府（大阪）', 34.6863, 135.5200),
  WeatherLocationPreset('兵庫県（神戸）', 34.6913, 135.1830),
  WeatherLocationPreset('奈良県（奈良）', 34.6851, 135.8329),
  WeatherLocationPreset('和歌山県（和歌山）', 34.2261, 135.1675),
  WeatherLocationPreset('鳥取県（鳥取）', 35.5039, 134.2377),
  WeatherLocationPreset('島根県（松江）', 35.4723, 133.0505),
  WeatherLocationPreset('岡山県（岡山）', 34.6618, 133.9350),
  WeatherLocationPreset('広島県（広島）', 34.3963, 132.4596),
  WeatherLocationPreset('山口県（山口）', 34.1859, 131.4714),
  WeatherLocationPreset('徳島県（徳島）', 34.0658, 134.5593),
  WeatherLocationPreset('香川県（高松）', 34.3401, 134.0434),
  WeatherLocationPreset('愛媛県（松山）', 33.8416, 132.7657),
  WeatherLocationPreset('高知県（高知）', 33.5597, 133.5311),
  WeatherLocationPreset('福岡県（福岡）', 33.6064, 130.4183),
  WeatherLocationPreset('佐賀県（佐賀）', 33.2494, 130.2988),
  WeatherLocationPreset('長崎県（長崎）', 32.7448, 129.8737),
  WeatherLocationPreset('熊本県（熊本）', 32.7898, 130.7417),
  WeatherLocationPreset('大分県（大分）', 33.2382, 131.6126),
  WeatherLocationPreset('宮崎県（宮崎）', 31.9111, 131.4239),
  WeatherLocationPreset('鹿児島県（鹿児島）', 31.5602, 130.5581),
  WeatherLocationPreset('沖縄県（那覇）', 26.2124, 127.6809),
];

/// 保存済みの座標に最も近いプリセットを返す。
///
/// 手入力した座標でもプルダウンの初期選択を合わせるために使う。
/// [toleranceDegrees] を超えて離れている場合は null（＝手入力扱い）。
WeatherLocationPreset? findNearestWeatherPreset(
  double? latitude,
  double? longitude, {
  double toleranceDegrees = 0.5,
}) {
  if (latitude == null || longitude == null) return null;

  WeatherLocationPreset? nearest;
  var nearestDistance = double.infinity;
  for (final preset in kWeatherLocationPresets) {
    final dLat = preset.latitude - latitude;
    final dLon = preset.longitude - longitude;
    final distance = dLat * dLat + dLon * dLon;
    if (distance < nearestDistance) {
      nearest = preset;
      nearestDistance = distance;
    }
  }
  if (nearest == null) return null;
  return nearestDistance <= toleranceDegrees * toleranceDegrees
      ? nearest
      : null;
}
