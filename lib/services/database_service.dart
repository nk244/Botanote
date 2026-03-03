import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/plant.dart';
import '../models/log_entry.dart';
import '../models/note.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// SQLite データベースへのアクセスを担うサービス。
///
/// シングルトンパターンで実装されており、DB接続は遅延初期化される。
/// Web 環境は非対応（[WebStorageService] を利用）。
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
    if (kIsWeb) {
      throw UnsupportedError(
        'Database is not supported on the web. '
        'Please use Android or iOS for full functionality.',
      );
    }
    final dbDir = await getDatabasesPath();
    final newPath = join(dbDir, 'bota_note.db');

    return await openDatabase(
      newPath,
      version: 4,
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
  }

  // ── Plant CRUD ───────────────────────────────────────────────

  /// 植物を挙録（同一IDが存在する場合は上書き）する。
  Future<void> insertPlant(Plant plant) async {
    final db = await database;
    await db.insert('plants', plant.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// すべての植物を更新日時の降順で取得する。
  Future<List<Plant>> getAllPlants() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('plants',
        orderBy: 'updatedAt DESC');
    return List.generate(maps.length, (i) => Plant.fromMap(maps[i]));
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
