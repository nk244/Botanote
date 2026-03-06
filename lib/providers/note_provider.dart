import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/database_service.dart';

/// ノートデータを管理する Provider。
///
/// [DatabaseService] を介して SQLite に永続化する。
class NoteProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  List<Note> _notes = [];
  bool _isLoading = false;

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;

  /// ノート一覧をストレージから再読み込みする。
  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await _db.getAllNotes();
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
    await _db.insertNote(note);
    await loadNotes();
  }

  /// 既存のノートを更新する。
  Future<void> updateNote(Note note) async {
    await _db.updateNote(note);
    await loadNotes();
  }

  /// 指定IDのノートを削除する。
  Future<void> deleteNote(String id) async {
    await _db.deleteNote(id);
    await loadNotes();
  }
}
