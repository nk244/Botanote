import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
import '../models/location.dart';
import '../services/database_service.dart';
import '../utils/japanese_sort_utils.dart';

/// 置き場所（Location）データを管理する Provider（Issue #180）。
class LocationProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  List<Location> _locations = [];
  bool _isLoading = false;

  List<Location> get locations => _locations;
  bool get isLoading => _isLoading;

  /// 置き場所一覧をストレージから再読み込みする。
  Future<void> loadLocations() async {
    _isLoading = true;
    notifyListeners();

    try {
      final locations = await _db.getAllLocations();
      // DB は name の昇順（コードポイント順）で返すため、「2階ホール」「キッチン」が
      // 「リビング」より前に来るなど日本語の読み順にならない。
      // 植物の並び順（Issue #257）と同じ比較でかな順に揃える（Issue #309）。
      locations.sort((a, b) => compareJapanese(a.name, null, b.name, null));
      _locations = locations;
    } catch (e) {
      debugPrint('Error loading locations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 置き場所を新規追加し、追加した置き場所を返す。
  ///
  /// 追加直後にその場所を選択状態にしたい呼び出し元（植物登録画面）が
  /// ID を必要とするため、生成した [Location] を返す（Issue #291）。
  Future<Location> addLocation(String name, bool isOutdoor) async {
    final now = DateTime.now();
    final location = Location(
      id: const Uuid().v4(),
      name: name,
      isOutdoor: isOutdoor,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insertLocation(location);
    await loadLocations();
    return location;
  }

  /// 置き場所を更新する。
  Future<void> updateLocation(Location location) async {
    await _db.updateLocation(location);
    await loadLocations();
  }

  /// 置き場所を削除する。参照していた植物の場所は自動的に未設定に戻る。
  Future<void> deleteLocation(String id) async {
    await _db.deleteLocation(id);
    await loadLocations();
  }

  /// 指定IDの置き場所名を返す（見つからない場合はnull）。
  String? getLocationName(String? locationId) {
    if (locationId == null) return null;
    for (final location in _locations) {
      if (location.id == locationId) return location.name;
    }
    return null;
  }
}
