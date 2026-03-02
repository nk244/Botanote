import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../models/plant.dart';
import '../providers/note_provider.dart';
import '../providers/plant_provider.dart';
import 'add_edit_note_screen.dart';
import 'note_detail_screen.dart';
import 'settings_screen.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterPlantId; // null = すべての植物
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<NoteProvider>().loadNotes();
      context.read<PlantProvider>().loadPlants();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 検索・フィルタを適用したノートリストを返す
  List<Note> _applyFilters(List<Note> notes) {
    var result = notes;

    // キーワード検索（タイトル・内容）
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((n) {
        return n.title.toLowerCase().contains(q) ||
            (n.content?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // 植物フィルタ
    if (_filterPlantId != null) {
      result = result.where((n) => n.plantIds.contains(_filterPlantId)).toList();
    }

    return result;
  }

  /// ノートを日付（createdAt の日付部分）でグループ化して、降順で返す
  Map<String, List<Note>> _groupByDate(List<Note> notes) {
    final Map<String, List<Note>> grouped = {};
    for (final note in notes) {
      final key = DateFormat('yyyy-MM-dd').format(note.createdAt);
      grouped.putIfAbsent(key, () => []).add(note);
    }
    for (final key in grouped.keys) {
      grouped[key]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  String _formatDateHeader(String dateKey) {
    final dt = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);

    if (d == today) return '今日  ${DateFormat('MM月dd日 (E)', 'ja').format(dt)}';
    if (d == yesterday) return '昨日  ${DateFormat('MM月dd日 (E)', 'ja').format(dt)}';
    return DateFormat('yyyy年MM月dd日 (E)', 'ja').format(dt);
  }

  void _showPlantFilterSheet(BuildContext context, List<Plant> plants) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('植物で絞り込む',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.all_inclusive),
                    title: const Text('すべて'),
                    trailing: _filterPlantId == null
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() => _filterPlantId = null);
                      Navigator.of(ctx).pop();
                    },
                  ),
                  ...plants.map((p) => ListTile(
                        leading: const Icon(Icons.eco),
                        title: Text(p.name),
                        trailing: _filterPlantId == p.id
                            ? Icon(Icons.check,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () {
                          setState(() => _filterPlantId = p.id);
                          Navigator.of(ctx).pop();
                        },
                      )),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'タイトル・内容を検索…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('ノート'),
        actions: [
          // 検索トグル
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '検索を閉じる' : '検索',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          // 設定画面へ遷移 (#104)
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '設定',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          // 植物フィルタ
          Consumer<PlantProvider>(
            builder: (context, plantProvider, _) {
              final hasFilter = _filterPlantId != null;
              return IconButton(
                icon: Badge(
                  isLabelVisible: hasFilter,
                  child: const Icon(Icons.filter_list),
                ),
                tooltip: '植物で絞り込む',
                onPressed: plantProvider.plants.isEmpty
                    ? null
                    : () => _showPlantFilterSheet(context, plantProvider.plants),
              );
            },
          ),
        ],
      ),
      body: Consumer2<NoteProvider, PlantProvider>(
        builder: (context, noteProvider, plantProvider, _) {
          if (noteProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // フィルタ適用
          final filteredNotes = _applyFilters(noteProvider.notes);

          // 絞り込み中のフィルタバー
          final isFiltering = _searchQuery.isNotEmpty || _filterPlantId != null;

          if (noteProvider.notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('まだノートがありません',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('右下の ＋ ボタンから記録しましょう',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          }

          return Column(
            children: [
              // ── アクティブフィルタバー ──
              if (isFiltering)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSecondaryContainer),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _buildFilterLabel(plantProvider.plants),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          _filterPlantId = null;
                          _isSearching = false;
                        }),
                        child: Icon(Icons.close,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),

              // ── ノートリスト ──
              Expanded(
                child: filteredNotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 56,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('該当するノートがありません',
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      )
                    : _buildNoteList(filteredNotes, plantProvider.plants, noteProvider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final noteProvider = context.read<NoteProvider>();
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AddEditNoteScreen()))
              .then((_) => noteProvider.loadNotes());
        },
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  String _buildFilterLabel(List<Plant> plants) {
    final parts = <String>[];
    if (_searchQuery.isNotEmpty) parts.add('「$_searchQuery」');
    if (_filterPlantId != null) {
      final name = plants
          .where((p) => p.id == _filterPlantId)
          .map((p) => p.name)
          .firstOrNull;
      if (name != null) parts.add(name);
    }
    return '${parts.join(' ・ ')} で絞り込み中';
  }

  Widget _buildNoteList(
      List<Note> notes, List<Plant> plants, NoteProvider noteProvider) {
    final grouped = _groupByDate(notes);
    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: dateKeys.length,
      itemBuilder: (context, i) {
        final key = dateKeys[i];
        final dayNotes = grouped[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 日付ヘッダー ──
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDateHeader(key),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ],
              ),
            ),

            // ── タイムライン ──
            ...dayNotes.asMap().entries.map((entry) {
              final isLast = entry.key == dayNotes.length - 1;
              final note = entry.value;
              final plantNames = plants
                  .where((p) => note.plantIds.contains(p.id))
                  .map((p) => p.name)
                  .toList();

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 縦線 + ドット
                    SizedBox(
                      width: 32,
                      child: Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: 2,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // カード
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(
                                    builder: (_) => NoteDetailScreen(note: note),
                                  ))
                                  .then((_) => noteProvider.loadNotes());
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 時刻 + タイトル
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('HH:mm').format(note.createdAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          note.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // 内容プレビュー
                                  if (note.content != null &&
                                      note.content!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      note.content!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],

                                  // 植物チップ
                                  if (plantNames.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: plantNames
                                          .map((name) => Chip(
                                                label: Text(name),
                                                avatar: const Icon(Icons.eco,
                                                    size: 12),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                labelStyle: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ))
                                          .toList(),
                                    ),
                                  ],

                                  // 画像枚数
                                  if (note.imagePaths.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.photo_library_outlined,
                                            size: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.5)),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${note.imagePaths.length} 枚',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
