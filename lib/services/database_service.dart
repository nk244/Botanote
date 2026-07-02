import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/note.dart';
import '../models/sensor_log.dart';

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
      version: 6,
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
              await db.execute(
                  'ALTER TABLE plants ADD COLUMN $col INTEGER');
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
          // plants テーブルに屋外フラグを追加（天気連動ケアアラート、Issue #176）
          try {
            await db.execute(
                'ALTER TABLE plants ADD COLUMN isOutdoor INTEGER NOT NULL DEFAULT 0');
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

  // ── Plant CRUD ───────────────────────────────────────────────

  /// 植物を挙録（同一IDが存在する場合は上書き）する。
  Future<void> insertPlant(Plant plant) async {
    final db = await database;
    await db.insert('plants', plant.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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
      'vitalizerIntervalDays, vitalizerEveryNWaterings, isOutdoor, createdAt, updatedAt '
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
    await db.delete(
      'plants',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Log CRUD ─────────────────────────────────────────────────

  /// ログを挿入する。
  Future<void> insertLog(LogEntry log) async {
    final db = await database;
    await db.insert('logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// すべてのログを日付の降順で取得する。
  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => LogEntry.fromMap(maps[i]));
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
    return List.generate(maps.length, (i) => LogEntry.fromMap(maps[i]));
  }

  /// 指定植物かつ種別のログを取得する。
  Future<List<LogEntry>> getLogsByPlantAndType(
      String plantId, LogType type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'logs',
      where: 'plantId = ? AND type = ?',
      whereArgs: [plantId, type.name],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => LogEntry.fromMap(maps[i]));
  }

  Future<void> updateLog(LogEntry log) async {
    final db = await database;
    await db.update(
      'logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<void> deleteLog(String id) async {
    final db = await database;
    await db.delete(
      'logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Notes CRUD ───────────────────────────────────────────────

  /// ノートを挿入する。
  Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert('notes', note.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// すべてのノートを更新日時の降順で取得する。
  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes', orderBy: 'updatedAt DESC');
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  /// ノート情報を更新する。
  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  /// 指定IDのノートを削除する。
  Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// 指定日に水やり予定がある植物リストを取得する。
  ///
  /// バックグラウンドIsolateから直接呼び出すためのメソッド。
  /// 各植物の最終水やりログと [wateringIntervalDays] から次回予定日を計算し、
  /// [targetDate] 以前になっている植物のみを返す。
  Future<List<Plant>> getPlantsDueOn(DateTime targetDate) async {
    // 全植物と全水やりログを取得
    final plants = await getAllPlants();
    if (plants.isEmpty) return [];

    final targetDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    final duePlants = <Plant>[];

    for (final plant in plants) {
      // 水やり間隔が未設定の植物はスキップ
      if (plant.wateringIntervalDays == null) continue;

      final logs = await getLogsByPlantAndType(plant.id, LogType.watering);

      final DateTime baseDate;
      if (logs.isEmpty) {
        // ログなし: 購入日または登録日を起算日とする
        baseDate = plant.purchaseDate ?? plant.createdAt;
      } else {
        // 最終水やりログ日を起算日とする
        logs.sort((a, b) => b.date.compareTo(a.date));
        baseDate = logs.first.date;
      }

      final nextDate = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
      ).add(Duration(days: plant.wateringIntervalDays!));

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
    await db.insert('sensor_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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
