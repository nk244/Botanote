import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/database_service.dart';
import '../services/web_storage_service.dart';

/// ノートデータを管理する Provider。
///
/// [DatabaseService](モバイル) または [WebStorageService](Web) を介して永続化する。
class NoteProvider with ChangeNotifier {
  /// モバイル環境用 DBサービス（Web時は null）
  final DatabaseService? _db = kIsWeb ? null : DatabaseService();

  /// Web 環境用ストレージ（非 Web 時は null）
  final WebStorageService? _web = kIsWeb ? WebStorageService() : null;

  List<Note> _notes = [];
  bool _isLoading = false;

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;

  /// ノート一覧をストレージから再読み込みする。
  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        final maps = await _web!.getAllNotes();
        _notes = maps.map((m) => Note.fromMap(Map<String, dynamic>.from(m))).toList();
      } else {
        _notes = await _db!.getAllNotes();
      }
    } catch (e) {
      debugPrint('ノート読み込みエラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 新しいノートを追加する。
  ///
  /// [createdAt] を省略すると現在日時が使われる。
  Future<void> addNote({
    required String title,
    String? content,
    List<String>? plantIds,
    List<String>? imagePaths,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: const Uuid().v4(),
      title: title,
      content: content,
      plantIds: plantIds ?? [],
      imagePaths: imagePaths ?? [],
      createdAt: createdAt ?? now,
      updatedAt: now,
    );

    if (kIsWeb) {
      await _web!.insertNote(note);
    } else {
      await _db!.insertNote(note);
    }

    await loadNotes();
  }

  /// 既存のノートを更新する。
  Future<void> updateNote(Note note) async {
    if (kIsWeb) {
      await _web!.updateNote(note);
    } else {
      await _db!.updateNote(note);
    }
    await loadNotes();
  }

  /// 指定IDのノートを削除する。
  Future<void> deleteNote(String id) async {
    if (kIsWeb) {
      await _web!.deleteNote(id);
    } else {
      await _db!.deleteNote(id);
    }
    await loadNotes();
  }
}
