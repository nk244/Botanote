import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/note.dart';
import '../models/sensor_log.dart';
import '../models/location.dart';
import '../utils/seasonal_interval_utils.dart';

/// SQLite データベースへのアクセスを担うサービス。
///
/// シングルトンパターンで実装されており、DB接続は遅延初期化される。
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  /// DB インスタンスを遅延初期化して返す。
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// DB ファイルを開き、必要に応じてマイグレーションを実行する。
  Future<Database> _initDatabase() async {
    final dbDir = await getDatabasesPath();
    final newPath = join(dbDir, 'bota_note.db');

    return await openDatabase(
      newPath,
      version: 10,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE notes(
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              content TEXT,
              imagePaths TEXT,
              plantIds TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
        }

        if (oldVersion < 3) {
          // notes テーブルに plantIds カラムを追加（旧DB向け）
          try {
            await db.execute('ALTER TABLE notes ADD COLUMN plantIds TEXT');
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
        }
        if (oldVersion < 4) {
          // plants テーブルに肥料・活力剤の間隔カラムを追加
          for (final col in [
            'fertilizerIntervalDays',
            'fertilizerEveryNWaterings',
            'vitalizerIntervalDays',
            'vitalizerEveryNWaterings',
          ]) {
            try {
              await db.execute('ALTER TABLE plants ADD COLUMN $col INTEGER');
            } catch (_) {
              // 既にカラムが存在する場合は無視
            }
          }
        }
        if (oldVersion < 5) {
          // センサーログテーブルを追加
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sensor_logs(
              id TEXT PRIMARY KEY,
              plantId TEXT,
              source TEXT NOT NULL,
              deviceId TEXT NOT NULL,
              deviceName TEXT NOT NULL,
              temperature REAL,
              humidity REAL,
              recordedAt TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) {
          // plants テーブルに季節調整（冬季の間隔延長）カラムを追加
          try {
            await db.execute(
              'ALTER TABLE plants ADD COLUMN seasonalAdjustmentEnabled INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
          try {
            await db.execute(
              'ALTER TABLE plants ADD COLUMN dormantSeasonIntervalMultiplier REAL',
            );
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
        }
        if (oldVersion < 7) {
          // plants テーブルに屋外フラグを追加（天気連動ケアアラート、Issue #176）
          try {
            await db.execute(
              'ALTER TABLE plants ADD COLUMN isOutdoor INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }

          // 置き場所（Location）テーブルを追加（Issue #180）
          await db.execute('''
            CREATE TABLE IF NOT EXISTS locations(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              isOutdoor INTEGER NOT NULL DEFAULT 0,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          try {
            await db.execute('ALTER TABLE plants ADD COLUMN locationId TEXT');
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
        }
        if (oldVersion < 8) {
          // sqflite は既定で PRAGMA foreign_keys=ON を設定しないため、logs テーブルの
          // `ON DELETE CASCADE` が効かず、植物を削除してもそのログが孤児として
          // 残り続けていた（DB肥大・カレンダーの幽霊ログ日付・バックアップ汚染）。
          // 参照先の植物が存在しない孤児ログをここで一括削除する。
          await db.execute(
            'DELETE FROM logs WHERE plantId NOT IN (SELECT id FROM plants)',
          );
        }
        if (oldVersion < 9) {
          // 名前順の並び替えを五十音順にするための読み仮名（Issue #257）。
          // 任意入力のため NOT NULL にはしない。
          try {
            await db.execute('ALTER TABLE plants ADD COLUMN nameReading TEXT');
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
        }
        if (oldVersion < 10) {
          // ノートのタグ（Issue #278）。JSON 配列の文字列として保持する。
          try {
            await db.execute('ALTER TABLE notes ADD COLUMN tags TEXT');
          } catch (_) {
            // 既にカラムが存在する場合は無視
          }
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE plants(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        nameReading TEXT,
        variety TEXT,
        purchaseDate TEXT,
        purchaseLocation TEXT,
        imagePath TEXT,
        wateringIntervalDays INTEGER,
        fertilizerIntervalDays INTEGER,
        fertilizerEveryNWaterings INTEGER,
        vitalizerIntervalDays INTEGER,
        vitalizerEveryNWaterings INTEGER,
        isOutdoor INTEGER NOT NULL DEFAULT 0,
        locationId TEXT,
        seasonalAdjustmentEnabled INTEGER NOT NULL DEFAULT 0,
        dormantSeasonIntervalMultiplier REAL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE locations(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        isOutdoor INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE logs(
        id TEXT PRIMARY KEY,
        plantId TEXT NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (plantId) REFERENCES plants (id) ON DELETE CASCADE
      )
    ''');

    // Notes table for standalone notes/diary entries
    await db.execute('''
      CREATE TABLE notes(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT,
        imagePaths TEXT,
        plantIds TEXT,
        tags TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // センサーログテーブル
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sensor_logs(
        id TEXT PRIMARY KEY,
        plantId TEXT,
        source TEXT NOT NULL,
        deviceId TEXT NOT NULL,
        deviceName TEXT NOT NULL,
        temperature REAL,
        humidity REAL,
        recordedAt TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  // ── 一括投入（インポート用） ─────────────────────────────────

  /// 複数テーブルのレコードを1つのトランザクションでまとめて投入する。
  ///
  /// [rowsByTable] はテーブル名をキーに、そのテーブルへ挿入する行のリストを持つ。
  /// キーの順序どおりに挿入するため、外部キー参照のある表は参照先を先に並べること。
  ///
  /// 1件ずつ [insertPlant] 等を await すると件数分の暗黙トランザクションが発生し、
  /// 数千件の復元に数十秒〜数分かかる。バッチ化して大幅に短縮する（Issue #214）。
  Future<void> insertRowsInBatch(
    Map<String, List<Map<String, dynamic>>> rowsByTable,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in rowsByTable.entries) {
        for (final row in entry.value) {
          batch.insert(
            entry.key,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  // ── Plant CRUD ───────────────────────────────────────────────

  /// 植物を挙録（同一IDが存在する場合は上書き）する。
  Future<void> insertPlant(Plant plant) async {
    final db = await database;
    await db.insert(
      'plants',
      plant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// すべての植物を更新日時の降順で取得する。
  ///
  /// imagePath に大きな Base64 データが含まれ Android CursorWindow を超過した場合は
  /// imagePath を除いたクエリで再試行する（#164）。
  Future<List<Plant>> getAllPlants() async {
    final db = await database;
    try {
      final maps = await db.query('plants', orderBy: 'updatedAt DESC');
      return maps.map(Plant.fromMap).toList();
    } catch (e) {
      // CursorWindowオーバーフロー対策: imagePath列を除いてリトライ
      debugPrint('getAllPlants失敗、imagePath除外でリトライ: $e');
      return _getAllPlantsWithoutImages(db);
    }
  }

  /// imagePath列を除いてすべての植物を取得する（CursorWindow回避用）
  Future<List<Plant>> _getAllPlantsWithoutImages(Database db) async {
    final maps = await db.rawQuery(
      'SELECT id, name, variety, purchaseDate, purchaseLocation, '
      'wateringIntervalDays, fertilizerIntervalDays, fertilizerEveryNWaterings, '
      'vitalizerIntervalDays, vitalizerEveryNWaterings, isOutdoor, locationId, '
      'seasonalAdjustmentEnabled, dormantSeasonIntervalMultiplier, createdAt, updatedAt '
      'FROM plants ORDER BY updatedAt DESC',
    );
    // imagePath を null として扱い、後続の逆移行処理がIDベースで別途処理する
    return maps.map((m) => Plant.fromMap({...m, 'imagePath': null})).toList();
  }

  /// 指定IDの植物を取得する。存在しない場合は null を返す。
  Future<Plant?> getPlant(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'plants',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Plant.fromMap(maps.first);
  }

  /// 植物情報を更新する。
  Future<void> updatePlant(Plant plant) async {
    final db = await database;
    await db.update(
      'plants',
      plant.toMap(),
      where: 'id = ?',
      whereArgs: [plant.id],
    );
  }

  /// 指定IDの植物を削除する（関連ログは CASCADE で自動削除）。
  Future<void> deletePlant(String id) async {
    final db = await database;
    // logs テーブルには `ON DELETE CASCADE` が宣言されているが、sqflite は既定で
    // PRAGMA foreign_keys=ON を設定しないためカスケードが発火しない。植物削除時に
    // ログが孤児として残らないよう、同一トランザクションで明示的に削除する。
    await db.transaction((txn) async {
      await txn.delete('logs', where: 'plantId = ?', whereArgs: [id]);
      await txn.delete('plants', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ── Log CRUD ─────────────────────────────────────────────────

  /// ログを挿入する。
  Future<void> insertLog(LogEntry log) async {
    final db = await database;
    await db.insert(
      'logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// ログ行を [LogEntry] に変換する。読み取れない行は飛ばす（Issue #319）。
  ///
  /// 未対応の種別名が1行でも混ざると、以前は一覧の取得ごと例外で落ちていた。
  /// 1行の異常でその植物のログがすべて見えなくなるのを避ける。
  List<LogEntry> _mapLogRows(List<Map<String, dynamic>> maps) {
    final logs = <LogEntry>[];
    for (final map in maps) {
      final log = LogEntry.tryFromMap(map);
      if (log == null) {
        debugPrint('DatabaseService: ログを1件読み飛ばしました (type=${map['type']})');
        continue;
      }
      logs.add(log);
    }
    return logs;
  }

  /// すべてのログを日付の降順で取得する。
  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      orderBy: 'date DESC',
    );
    return _mapLogRows(maps);
  }

  /// 指定植物のログを取得する。
  Future<List<LogEntry>> getLogsByPlant(String plantId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      where: 'plantId = ?',
      whereArgs: [plantId],
      orderBy: 'date DESC',
    );
    return _mapLogRows(maps);
  }

  /// 指定植物かつ種別のログを取得する。
  Future<List<LogEntry>> getLogsByPlantAndType(
    String plantId,
    LogType type,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      where: 'plantId = ? AND type = ?',
      whereArgs: [plantId, type.name],
      orderBy: 'date DESC',
    );
    return _mapLogRows(maps);
  }

  Future<void> updateLog(LogEntry log) async {
    final db = await database;
    await db.update('logs', log.toMap(), where: 'id = ?', whereArgs: [log.id]);
  }

  Future<void> deleteLog(String id) async {
    final db = await database;
    await db.delete('logs', where: 'id = ?', whereArgs: [id]);
  }

  // ── Location CRUD（Issue #180） ─────────────────────────────

  /// 置き場所を挿入する。
  Future<void> insertLocation(Location location) async {
    final db = await database;
    await db.insert(
      'locations',
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// すべての置き場所を名前順で取得する。
  Future<List<Location>> getAllLocations() async {
    final db = await database;
    final maps = await db.query('locations', orderBy: 'name ASC');
    return maps.map(Location.fromMap).toList();
  }

  /// 置き場所情報を更新する。
  Future<void> updateLocation(Location location) async {
    final db = await database;
    await db.update(
      'locations',
      location.toMap(),
      where: 'id = ?',
      whereArgs: [location.id],
    );
  }

  /// 指定IDの置き場所を削除し、その場所が設定されていた植物の
  /// [Plant.locationId] を NULL にクリアする。
  Future<void> deleteLocation(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'plants',
        {'locationId': null},
        where: 'locationId = ?',
        whereArgs: [id],
      );
      await txn.delete('locations', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ── Notes CRUD ───────────────────────────────────────────────

  /// ノートを挿入する。
  Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// すべてのノートを更新日時の降順で取得する。
  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      orderBy: 'updatedAt DESC',
    );
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  /// ノート情報を更新する。
  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  /// 指定IDのノートを削除する。
  Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// 種別 [type] のログについて、植物IDごとの最終記録日を1クエリで取得する。
  ///
  /// 「最終水やり日」だけが必要な処理でログを全件読み込むとログ件数に比例して
  /// 遅くなるため、SQL の集約関数で1行に畳んでから返す（Issue #252）。
  Future<Map<String, DateTime>> _getLastLogDateByPlant(LogType type) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT plantId, MAX(date) AS lastDate FROM logs '
      'WHERE type = ? GROUP BY plantId',
      [type.name],
    );

    final result = <String, DateTime>{};
    for (final row in rows) {
      final plantId = row['plantId'] as String?;
      final lastDate = row['lastDate'] as String?;
      if (plantId == null || lastDate == null) continue;
      final parsed = DateTime.tryParse(lastDate);
      if (parsed != null) result[plantId] = parsed;
    }
    return result;
  }

  /// 指定日に水やり予定がある植物リストを取得する。
  ///
  /// バックグラウンドIsolateから直接呼び出すためのメソッド。
  /// 各植物の最終水やりログと [wateringIntervalDays] から次回予定日を計算し、
  /// [targetDate] 以前になっている植物のみを返す。
  ///
  /// 間隔には季節調整（休眠期の延長）を適用する。適用しないと通知だけが
  /// 素の間隔で発火し、画面表示の「次回予定」より早く通知が届く（Issue #223）。
  Future<List<Plant>> getPlantsDueOn(DateTime targetDate) async {
    final plants = await getAllPlants();
    if (plants.isEmpty) return [];

    final targetDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    // 必要なのは植物ごとの「最終水やり日」1件だけなので、
    // ログを全件取得せず SQL 側で集約する（Issue #252）。
    final lastWateredByPlantId = await _getLastLogDateByPlant(LogType.watering);

    final duePlants = <Plant>[];

    for (final plant in plants) {
      // 水やり間隔が未設定の植物はスキップ
      if (plant.wateringIntervalDays == null) continue;

      // 最終水やりログ日を起算日とする。ログが無ければ購入日または登録日。
      final baseDate =
          lastWateredByPlantId[plant.id] ??
          plant.purchaseDate ??
          plant.createdAt;

      // 起算日が休眠期なら間隔を延長する（画面表示側と同じ計算に揃える）
      final intervalDays = applySeasonalAdjustment(
        baseIntervalDays: plant.wateringIntervalDays!,
        seasonalAdjustmentEnabled: plant.seasonalAdjustmentEnabled,
        dormantMultiplier: plant.dormantSeasonIntervalMultiplier,
        referenceDate: baseDate,
      );

      final nextDate = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
      ).add(Duration(days: intervalDays));

      // 次回予定日がtargetDay以前であれば対象
      if (!nextDate.isAfter(targetDay)) {
        duePlants.add(plant);
      }
    }

    return duePlants;
  }

  // ── SensorLog CRUD ───────────────────────────────────────────

  /// センサーログを挿入する。
  Future<void> insertSensorLog(SensorLog log) async {
    final db = await database;
    await db.insert(
      'sensor_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// すべてのセンサーログを計測日時の降順で取得する。
  Future<List<SensorLog>> getAllSensorLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sensor_logs',
      orderBy: 'recordedAt DESC',
    );
    return List.generate(maps.length, (i) => SensorLog.fromMap(maps[i]));
  }

  /// 指定植物のセンサーログを取得する。
  Future<List<SensorLog>> getSensorLogsByPlant(String plantId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sensor_logs',
      where: 'plantId = ?',
      whereArgs: [plantId],
      orderBy: 'recordedAt DESC',
    );
    return List.generate(maps.length, (i) => SensorLog.fromMap(maps[i]));
  }

  /// 指定IDのセンサーログを削除する。
  Future<void> deleteSensorLog(String id) async {
    final db = await database;
    await db.delete('sensor_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
