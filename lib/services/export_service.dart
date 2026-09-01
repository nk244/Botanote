import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/note.dart';
import '../models/sensor_log.dart';
import '../models/app_settings.dart';
import '../models/location.dart';
import 'database_service.dart';
import 'settings_service.dart';

/// データのエクスポート / インポートを担うサービス
///
/// 画像を含む ZIP アーカイブとして保存・復元する。
/// ZIP 構成:
///   botanote_backup_yyyyMMdd_HHmm.zip
///   ├── data.json          # Plants / Logs / Notes (imagePath は ZIP 内相対パス)
///   └── images/
///       ├── plants/`plant_id`.jpg
///       └── notes/`note_id`_`index`.jpg
class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final _db = DatabaseService();
  final _settingsService = SettingsService();

  /// 書き出すバックアップのバージョン。
  /// 5 でアプリ設定（`settings`）を含めるようになった（Issue #239）。
  /// 6 で植物に読み仮名（`nameReading`）が加わった（Issue #257）。
  /// 7 でノートにタグ（`tags`）が加わった（Issue #278）。
  ///
  /// 旧バージョンのアプリが新しい形式を取り込むと、DB に存在しない列を
  /// insert しようとして失敗するため、版数を上げて明示的に弾く。
  static const int _backupVersion = 7;

  /// バックアップに含めないアプリ設定のキー。
  ///
  /// バックアップ ZIP は OS の共有シートで外部サービスへ送られるため、
  /// IoT サービスの認証情報は書き出さない（復元時も端末側の値を保持する）。
  static const Set<String> _secretSettingKeys = {
    'natureRemoToken',
    'switchBotToken',
    'switchBotSecret',
  };

  /// エクスポート対象のアプリ設定を返す（認証情報は除外する）。
  Future<Map<String, dynamic>> _exportableSettingsMap() async {
    final settings = await _settingsService.loadSettings();
    final map = settings.toMap();
    map.removeWhere((key, _) => _secretSettingKeys.contains(key));
    return map;
  }

  // ── エクスポート ──────────────────────────────────────────

  /// ZIP を一時ディレクトリに生成し、OS のシェアシートで共有する。
  ///
  /// キャンセル時は null を返す。
  Future<String?> exportToFile() async {
    // ファイル名から取得日時が読み取れるようにする（Issue #216）。
    // エポックミリ秒だと、ファイルピッカーで名前が省略表示された際に
    // 複数世代のバックアップを判別できない。
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'botanote_backup_$ts.zip';

    // ZIP バイト列を生成して一時ファイルに書き出す
    final zipBytes = await _buildZipBytes();
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(p.join(tmpDir.path, fileName));
    await tmpFile.writeAsBytes(zipBytes);

    // OS のシェアシート経由で保存先を選ばせる
    final result = await Share.shareXFiles([
      XFile(tmpFile.path, mimeType: 'application/zip'),
    ], subject: 'Botanote バックアップ');

    if (result.status == ShareResultStatus.dismissed) return null;
    return tmpFile.path;
  }

  /// ZIP を端末の任意の場所に保存する（Issue #270）。
  ///
  /// 共有シート経由の [exportToFile] はキャッシュ領域にしかファイルが残らず、
  /// OS の空き容量確保で削除されうる。こちらは SAF（Android のファイル選択
  /// ダイアログ）でユーザーが選んだ保存先に書き出すため、確実に端末へ残る。
  ///
  /// キャンセル時は null を返す。戻り値は保存先のパス。
  Future<String?> exportToDeviceStorage() async {
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'botanote_backup_$ts.zip';

    final zipBytes = await _buildZipBytes();

    // Android/iOS では bytes を渡さないとファイルが書き込まれないため必ず渡す
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'バックアップの保存先を選択',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: zipBytes,
    );
    if (savedPath == null) return null;

    // デスクトップ（Windows/macOS/Linux）では bytes が書き込まれず
    // パスだけが返るため、こちら側で書き出す。
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await File(savedPath).writeAsBytes(zipBytes);
    }

    return savedPath;
  }

  /// ZIP バイト列を生成する
  Future<Uint8List> _buildZipBytes() async {
    final plants = await _db.getAllPlants();
    final allLogs = <LogEntry>[];
    for (final plant in plants) {
      final logs = await _db.getLogsByPlant(plant.id);
      allLogs.addAll(logs);
    }
    final notes = await _db.getAllNotes();

    final archive = Archive();

    // ── 植物画像を収集 ──
    final plantMaps = <Map<String, dynamic>>[];
    for (final plant in plants) {
      final map = plant.toMap();
      if (plant.imagePath != null) {
        final path = plant.imagePath!;
        if (path.startsWith('data:')) {
          // #158対応: data URL（Base64）形式の場合はデコードしてZIPに格納する
          try {
            final comma = path.indexOf(',');
            if (comma >= 0) {
              final bytes = base64Decode(path.substring(comma + 1));
              const zipPath = 'images/plants/';
              final zipFilePath = '$zipPath${plant.id}.jpg';
              archive.addFile(ArchiveFile(zipFilePath, bytes.length, bytes));
              map['imagePath'] = zipFilePath; // ZIP 内相対パスに変換
            } else {
              map['imagePath'] = null;
            }
          } catch (_) {
            map['imagePath'] = null;
          }
        } else {
          // 旧形式: ファイルパスの場合はファイルから読み込む（後方互換）
          final imgFile = File(path);
          if (await imgFile.exists()) {
            final ext = p.extension(path).isNotEmpty
                ? p.extension(path)
                : '.jpg';
            final zipPath = 'images/plants/${plant.id}$ext';
            archive.addFile(
              ArchiveFile(
                zipPath,
                await imgFile.length(),
                await imgFile.readAsBytes(),
              ),
            );
            map['imagePath'] = zipPath; // ZIP 内相対パスに変換
          } else {
            map['imagePath'] = null;
          }
        }
      }
      plantMaps.add(map);
    }

    // ── ノート画像を収集 ──
    final noteMaps = <Map<String, dynamic>>[];
    for (final note in notes) {
      final map = note.toMap();
      if (note.imagePaths.isNotEmpty) {
        final zipRelPaths = <String>[];
        for (int i = 0; i < note.imagePaths.length; i++) {
          final imgFile = File(note.imagePaths[i]);
          if (await imgFile.exists()) {
            final ext = p.extension(note.imagePaths[i]).isNotEmpty
                ? p.extension(note.imagePaths[i])
                : '.jpg';
            final zipPath = 'images/notes/${note.id}_$i$ext';
            archive.addFile(
              ArchiveFile(
                zipPath,
                await imgFile.length(),
                await imgFile.readAsBytes(),
              ),
            );
            zipRelPaths.add(zipPath);
          }
        }
        // imagePaths を ZIP 内相対パスの '|' 区切りに変換
        map['imagePaths'] = zipRelPaths.join('|');
      }
      noteMaps.add(map);
    }

    // ── センサーログを収集 ──
    final sensorLogs = await _db.getAllSensorLogs();

    // ── 置き場所を収集 ──
    // 植物が locationId で参照するため、これを含めないと復元時に置き場所が
    // 全消失し、植物側の locationId が孤児参照になる（Issue #206）。
    final locations = await _db.getAllLocations();

    // ── アプリ設定を収集（Issue #239） ──
    // 通知時刻やテーマを含めないと機種変更で設定だけが初期値に戻る。
    final settingsMap = await _exportableSettingsMap();

    // ── data.json を生成 ──
    final data = {
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'plants': plantMaps,
      'logs': allLogs.map((l) => l.toMap()).toList(),
      'notes': noteMaps,
      'sensorLogs': sensorLogs.map((s) => s.toMap()).toList(),
      'locations': locations.map((l) => l.toMap()).toList(),
      'settings': settingsMap,
    };
    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));

    // ZIP エンコード
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // ── インポート ────────────────────────────────────────────

  /// ファイルピッカーでファイルを選択してインポートする（ZIP / JSON 両対応）
  ///
  /// 戻り値: 成功した場合は [ImportResult]、キャンセルの場合は null
  Future<ImportResult?> importFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return null;

    // 拡張子ではなくバイナリのマジックバイトでZIP判定（#86）
    final bytes = await File(path).readAsBytes();
    if (_isZipBytes(bytes)) {
      return _importFromZip(path);
    } else {
      // BOM付きUTF-8・通常UTF-8のどちらも対応
      return _importFromJson(_decodeUtf8(bytes));
    }
  }

  /// ZIPのマジックバイト（PK\x03\x04）でZIPかどうか判定する
  bool _isZipBytes(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 && // P
        bytes[1] == 0x4B && // K
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  /// BOM付きUTF-8も含めてUTF-8デコードする
  String _decodeUtf8(List<int> bytes) {
    // UTF-8 BOM (EF BB BF) が付いている場合は除去してデコード
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    return utf8.decode(bytes);
  }

  /// ZIP ファイルからデータを復元する
  Future<ImportResult> _importFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // ── data.json を取得 ──
    final jsonEntry = archive.findFile('data.json');
    if (jsonEntry == null) {
      throw const FormatException('ZIP 内に data.json が見つかりません');
    }
    final jsonStr = utf8.decode(jsonEntry.content as List<int>);
    final Map<String, dynamic> data =
        jsonDecode(jsonStr) as Map<String, dynamic>;

    final version = data['version'] as int? ?? 1;
    if (version > _backupVersion) {
      throw FormatException('未対応のバックアップバージョン: $version');
    }

    // ── 画像をドキュメントディレクトリに展開 ──
    final docsDir = await getApplicationDocumentsDirectory();
    // ZIP 内相対パス → 絶対パス のマップ
    final pathMap = <String, String>{};
    for (final entry in archive) {
      if (entry.isFile && entry.name.startsWith('images/')) {
        final destPath = p.join(docsDir.path, entry.name);
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(entry.content as List<int>);
        pathMap[entry.name] = destPath;
      }
    }

    // ── DB にデータを保存 ──
    return _importData(data, pathMap);
  }

  /// JSON 文字列からデータを復元する（既存データは保持して追加/上書き）
  Future<ImportResult> _importFromJson(String jsonStr) async {
    final Map<String, dynamic> data =
        jsonDecode(jsonStr) as Map<String, dynamic>;
    final version = data['version'] as int? ?? 1;
    if (version > _backupVersion) {
      throw FormatException('未対応のバックアップバージョン: $version');
    }
    return _importData(data, const {});
  }

  /// ノートの `imagePaths` を文字列リストとして取り出す。
  ///
  /// ZIP エクスポートが書き出す `'|'` 区切りと、DB の `Note.toMap()` が書き出す
  /// JSON 配列（写真が無ければ `"[]"`）の両方を受け取る。判別できない値は
  /// 空リストとして扱い、参照が無いものを未解決として数えないようにする。
  @visibleForTesting
  static List<String> parseImagePathList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is! String || raw.isEmpty) return const [];

    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // JSON として壊れている場合は '|' 区切りとして解釈を試みる
      }
    }
    return raw.split('|').where((path) => path.isNotEmpty).toList();
  }

  /// [data] を DB に保存する。[pathMap] は ZIP 内相対パス→絶対パスの対応表。
  Future<ImportResult> _importData(
    Map<String, dynamic> data,
    Map<String, String> pathMap,
  ) async {
    int plantCount = 0;
    int logCount = 0;
    int noteCount = 0;
    int locationCount = 0;
    bool settingsRestored = false;
    // 画像参照の解決状況（Issue #289）
    int imageCount = 0;
    int unresolvedImageCount = 0;
    // 読み取れずに飛ばしたレコード数（Issue #319）
    int skippedRecordCount = 0;

    // 解決できなかった画像参照を相対パスのまま書き戻すと、ConflictAlgorithm.replace で
    // 既存行が丸ごと置き換わり、有効だった写真が消える。既存値を退避しておき、
    // 解決できなかった参照はこちらで埋める（Issue #289）。
    final existingPlantImagePaths = <String, String?>{
      for (final plant in await _db.getAllPlants()) plant.id: plant.imagePath,
    };
    final existingNoteImagePaths = <String, List<String>>{
      for (final note in await _db.getAllNotes()) note.id: note.imagePaths,
    };

    // 復元対象の行をテーブルごとに組み立て、最後に1トランザクションで投入する
    // （1件ずつ insert すると数千件で数十秒〜数分かかるため。Issue #214）。
    // 外部キー参照のある表より参照先が先に来るよう、挿入順に並べる。
    final locationRows = <Map<String, dynamic>>[];
    final plantRows = <Map<String, dynamic>>[];
    final logRows = <Map<String, dynamic>>[];
    final noteRows = <Map<String, dynamic>>[];
    final sensorLogRows = <Map<String, dynamic>>[];

    // 置き場所をインポート（植物が locationId で参照するため植物より先に復元する）
    // version 4 以降のバックアップにのみ含まれる。
    final locationsJson = data['locations'] as List<dynamic>?;
    final hasLocations = locationsJson != null;
    if (hasLocations) {
      for (final l0 in locationsJson) {
        try {
          locationRows.add(
            Location.fromMap(Map<String, dynamic>.from(l0 as Map)).toMap(),
          );
          locationCount++;
        } catch (e) {
          // 1件が壊れていてもバックアップ全体を失わせない（Issue #319）
          skippedRecordCount++;
          debugPrint('ExportService: 置き場所を1件読み飛ばしました: $e');
        }
      }
    }

    // 植物をインポート
    final plantsJson = data['plants'] as List<dynamic>? ?? [];
    for (final p0 in plantsJson) {
      final map = Map<String, dynamic>.from(p0 as Map);
      final imageCountBefore = imageCount;
      final unresolvedBefore = unresolvedImageCount;
      // 画像パスを絶対パスに解決
      if (map['imagePath'] != null) {
        final rel = map['imagePath'] as String;
        final resolved = pathMap[rel];
        if (resolved != null) {
          map['imagePath'] = resolved;
          imageCount++;
        } else {
          // 解決できない相対パスで既存の写真を上書きしない（Issue #289）
          unresolvedImageCount++;
          map['imagePath'] = existingPlantImagePaths[map['id']];
        }
      }
      // 置き場所を含まない旧バックアップ（version <= 3）は、植物が持つ
      // locationId の参照先が存在しないため、孤児参照を避けてクリアする。
      if (!hasLocations) {
        map['locationId'] = null;
      }
      try {
        plantRows.add(Plant.fromMap(map).toMap());
        plantCount++;
      } catch (e) {
        // 1件が壊れていてもバックアップ全体を失わせない（Issue #319）。
        // 読み飛ばす植物の画像は数えないよう、加算分を巻き戻す。
        imageCount = imageCountBefore;
        unresolvedImageCount = unresolvedBefore;
        skippedRecordCount++;
        debugPrint('ExportService: 植物を1件読み飛ばしました: $e');
      }
    }

    // ログをインポート。
    // 未知の種別名（新しいバージョンで追加された種別など）を含む1件のために
    // バックアップ全体の復元が失敗しないよう、読めない行だけを飛ばす（Issue #319）。
    final logsJson = data['logs'] as List<dynamic>? ?? [];
    for (final l in logsJson) {
      final log = LogEntry.tryFromMap(Map<String, dynamic>.from(l as Map));
      if (log == null) {
        skippedRecordCount++;
        continue;
      }
      logRows.add(log.toMap());
      logCount++;
    }

    // ノートをインポート
    final notesJson = data['notes'] as List<dynamic>? ?? [];
    for (final n in notesJson) {
      final map = Map<String, dynamic>.from(n as Map);
      // imagePaths を絶対パスに解決する。
      // ZIP エクスポートは '|' 区切り、DB 由来の値は JSON 配列（写真なしなら "[]"）
      // の両方がありうるため、素朴に '|' で分割すると "[]" を1件の参照として
      // 数えてしまい、写真の無いノートの数だけ誤った警告が出る。
      final relPaths = parseImagePathList(map['imagePaths']);
      if (relPaths.isNotEmpty) {
        final absPaths = <String>[];
        var unresolvedInNote = 0;
        for (final rel in relPaths) {
          final resolved = pathMap[rel];
          if (resolved != null) {
            absPaths.add(resolved);
            imageCount++;
          } else {
            unresolvedInNote++;
            unresolvedImageCount++;
          }
        }
        // 1枚も解決できなかった場合は、相対パスで潰さず既存の写真を維持する（Issue #289）
        if (absPaths.isEmpty && unresolvedInNote > 0) {
          map['imagePaths'] =
              (existingNoteImagePaths[map['id']] ?? const <String>[]).join('|');
        } else {
          map['imagePaths'] = absPaths.join('|');
        }
      }
      try {
        noteRows.add(Note.fromMap(map).toMap());
        noteCount++;
      } catch (e) {
        // 1件が壊れていてもバックアップ全体を失わせない（Issue #319）
        skippedRecordCount++;
        debugPrint('ExportService: ノートを1件読み飛ばしました: $e');
      }
    }

    // センサーログをインポート
    int sensorLogCount = 0;
    final sensorLogsJson = data['sensorLogs'] as List<dynamic>? ?? [];
    for (final s in sensorLogsJson) {
      try {
        final log = SensorLog.fromMap(Map<String, dynamic>.from(s as Map));
        sensorLogRows.add(log.toMap());
        sensorLogCount++;
      } catch (e) {
        // 1件が壊れていてもバックアップ全体を失わせない（Issue #319）
        skippedRecordCount++;
        debugPrint('ExportService: センサーログを1件読み飛ばしました: $e');
      }
    }

    // アプリ設定を復元する（version 5 以降のバックアップにのみ含まれる。Issue #239）。
    // 認証情報はバックアップに含めないため、端末側の現在値をそのまま引き継ぐ。
    final settingsJson = data['settings'];
    if (settingsJson is Map) {
      try {
        final current = await _settingsService.loadSettings();
        final merged = Map<String, dynamic>.from(current.toMap())
          ..addAll(
            Map<String, dynamic>.from(settingsJson)
              ..removeWhere((key, _) => _secretSettingKeys.contains(key)),
          );
        await _settingsService.saveSettings(AppSettings.fromMap(merged));
        settingsRestored = true;
      } catch (e) {
        // 設定の復元に失敗してもデータ本体の復元は続行する
        settingsRestored = false;
      }
    }

    // 参照先（locations → plants）を先に投入する順序で一括コミットする
    await _db.insertRowsInBatch({
      'locations': locationRows,
      'plants': plantRows,
      'logs': logRows,
      'notes': noteRows,
      'sensor_logs': sensorLogRows,
    });

    return ImportResult(
      plantCount: plantCount,
      logCount: logCount,
      noteCount: noteCount,
      sensorLogCount: sensorLogCount,
      locationCount: locationCount,
      settingsRestored: settingsRestored,
      imageCount: imageCount,
      unresolvedImageCount: unresolvedImageCount,
      skippedRecordCount: skippedRecordCount,
    );
  }
}

/// インポート結果を保持するデータクラス
class ImportResult {
  final int plantCount;
  final int logCount;
  final int noteCount;
  final int sensorLogCount;
  final int locationCount;

  /// アプリ設定（通知時刻・テーマ等）を復元したかどうか。
  /// version 4 以前のバックアップには設定が含まれないため false になる。
  final bool settingsRestored;

  /// ZIP から実ファイルに解決できた画像参照の件数（Issue #289）
  final int imageCount;

  /// 実ファイルに解決できなかった画像参照の件数（Issue #289）。
  ///
  /// JSON のみのバックアップや、画像を含まない ZIP を取り込むと発生する。
  /// これらの参照は復元されず、既存の写真がそのまま維持される。
  final int unresolvedImageCount;

  /// 読み取れずに飛ばしたレコードの件数（Issue #319）。
  ///
  /// 未対応のログ種別を含む行など、1件だけ壊れているケースで加算される。
  /// バックアップ全体の復元を失敗させず、件数だけを利用者に伝える。
  final int skippedRecordCount;

  const ImportResult({
    required this.plantCount,
    required this.logCount,
    required this.noteCount,
    this.sensorLogCount = 0,
    this.locationCount = 0,
    this.settingsRestored = false,
    this.imageCount = 0,
    this.unresolvedImageCount = 0,
    this.skippedRecordCount = 0,
  });

  /// 解決できなかった画像参照があるかどうか。
  bool get hasUnresolvedImages => unresolvedImageCount > 0;

  /// 読み取れずに飛ばしたレコードがあるかどうか（Issue #319）。
  bool get hasSkippedRecords => skippedRecordCount > 0;

  /// 読み飛ばしたレコードがある場合に表示する警告文。問題がなければ null。
  String? get skippedWarning {
    if (!hasSkippedRecords) return null;
    return 'このバックアップに含まれる$skippedRecordCount件のデータは、'
        'このバージョンでは読み取れなかったため復元されませんでした。\n'
        'それ以外のデータは正常に復元しています。';
  }

  @override
  String toString() {
    final parts = ['植物: $plantCount件', 'ログ: $logCount件', 'ノート: $noteCount件'];
    if (sensorLogCount > 0) parts.add('センサーログ: $sensorLogCount件');
    if (locationCount > 0) parts.add('置き場所: $locationCount件');
    // 画像は0件でも「入っていなかった」ことが分かるよう常に出す（Issue #289）
    parts.add('画像: $imageCount件');
    if (settingsRestored) parts.add('アプリ設定');
    return parts.join('、');
  }

  /// 画像を復元できなかった場合に表示する警告文。問題がなければ null。
  String? get imageWarning {
    if (!hasUnresolvedImages) return null;
    return 'このバックアップには画像が含まれていないため、'
        '$unresolvedImageCount件の写真を復元できませんでした。\n'
        '端末に残っていた写真はそのまま保持しています。';
  }
}
