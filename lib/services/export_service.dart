import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
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
  static const int _backupVersion = 5;

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
    final result = await Share.shareXFiles(
      [XFile(tmpFile.path, mimeType: 'application/zip')],
      subject: 'Botanote バックアップ',
    );

    if (result.status == ShareResultStatus.dismissed) return null;
    return tmpFile.path;
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
            final ext = p.extension(path).isNotEmpty ? p.extension(path) : '.jpg';
            final zipPath = 'images/plants/${plant.id}$ext';
            archive.addFile(
              ArchiveFile(zipPath, await imgFile.length(),
                  await imgFile.readAsBytes()),
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
              ArchiveFile(zipPath, await imgFile.length(),
                  await imgFile.readAsBytes()),
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
    final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
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
        locationRows.add(
          Location.fromMap(Map<String, dynamic>.from(l0 as Map)).toMap(),
        );
        locationCount++;
      }
    }

    // 植物をインポート
    final plantsJson = data['plants'] as List<dynamic>? ?? [];
    for (final p0 in plantsJson) {
      final map = Map<String, dynamic>.from(p0 as Map);
      // 画像パスを絶対パスに解決
      if (map['imagePath'] != null) {
        final rel = map['imagePath'] as String;
        map['imagePath'] = pathMap[rel] ?? map['imagePath'];
      }
      // 置き場所を含まない旧バックアップ（version <= 3）は、植物が持つ
      // locationId の参照先が存在しないため、孤児参照を避けてクリアする。
      if (!hasLocations) {
        map['locationId'] = null;
      }
      plantRows.add(Plant.fromMap(map).toMap());
      plantCount++;
    }

    // ログをインポート
    final logsJson = data['logs'] as List<dynamic>? ?? [];
    for (final l in logsJson) {
      final log = LogEntry.fromMap(Map<String, dynamic>.from(l as Map));
      logRows.add(log.toMap());
      logCount++;
    }

    // ノートをインポート
    final notesJson = data['notes'] as List<dynamic>? ?? [];
    for (final n in notesJson) {
      final map = Map<String, dynamic>.from(n as Map);
      // imagePaths を絶対パスに解決（'|' 区切り文字列）
      if (map['imagePaths'] != null && (map['imagePaths'] as String).isNotEmpty) {
        final relPaths = (map['imagePaths'] as String).split('|');
        final absPaths = relPaths
            .map((rel) => pathMap[rel] ?? rel)
            .where((path) => path.isNotEmpty)
            .toList();
        map['imagePaths'] = absPaths.join('|');
      }
      noteRows.add(Note.fromMap(map).toMap());
      noteCount++;
    }

    // センサーログをインポート
    int sensorLogCount = 0;
    final sensorLogsJson = data['sensorLogs'] as List<dynamic>? ?? [];
    for (final s in sensorLogsJson) {
      final log = SensorLog.fromMap(Map<String, dynamic>.from(s as Map));
      sensorLogRows.add(log.toMap());
      sensorLogCount++;
    }

    // アプリ設定を復元する（version 5 以降のバックアップにのみ含まれる。Issue #239）。
    // 認証情報はバックアップに含めないため、端末側の現在値をそのまま引き継ぐ。
    final settingsJson = data['settings'];
    if (settingsJson is Map) {
      try {
        final current = await _settingsService.loadSettings();
        final merged = Map<String, dynamic>.from(current.toMap())
          ..addAll(Map<String, dynamic>.from(settingsJson)
            ..removeWhere((key, _) => _secretSettingKeys.contains(key)));
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

  const ImportResult({
    required this.plantCount,
    required this.logCount,
    required this.noteCount,
    this.sensorLogCount = 0,
    this.locationCount = 0,
    this.settingsRestored = false,
  });

  @override
  String toString() {
    final parts = [
      '植物: $plantCount件',
      'ログ: $logCount件',
      'ノート: $noteCount件',
    ];
    if (sensorLogCount > 0) parts.add('センサーログ: $sensorLogCount件');
    if (locationCount > 0) parts.add('置き場所: $locationCount件');
    if (settingsRestored) parts.add('アプリ設定');
    return parts.join('、');
  }
}
