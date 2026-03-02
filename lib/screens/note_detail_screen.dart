import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/plant_provider.dart';
import 'add_edit_note_screen.dart';
import '../providers/note_provider.dart';

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;
  final String noteId;
  const _FullScreenImageViewer({
    required this.imagePaths,
    required this.initialIndex,
    required this.noteId,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: widget.imagePaths.length > 1
            ? Text('${_currentIndex + 1} / ${widget.imagePaths.length}')
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final p = widget.imagePaths[index];
          final heroTag = 'note_image_${widget.noteId}_$index';
          final img = kIsWeb
              ? Image.network(p, fit: BoxFit.contain)
              : Image.file(
                  File(p),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined,
                                color: Colors.white54, size: 64),
                            SizedBox(height: 8),
                            Text('画像を読み込めませんでした',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                );
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Hero(
                tag: heroTag,
                child: img,
              ),
            ),
          );
        },
      ),
    );
  }
}

class NoteDetailScreen extends StatelessWidget {
  final Note note;
  const NoteDetailScreen({required this.note, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(note.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddEditNoteScreen(note: note)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('削除の確認'),
                  content: const Text('このノートを削除しますか？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('キャンセル')),
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('削除')),
                  ],
                ),
              );
              if (confirmed == true) {
                await context.read<NoteProvider>().deleteNote(note.id);
                if (context.mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 植物チップ
            if (note.plantIds.isNotEmpty)
              Consumer<PlantProvider>(builder: (context, plantProv, _) {
                final names = plantProv.plants
                    .where((p) => note.plantIds.contains(p.id))
                    .map((p) => p.name)
                    .toList();
                if (names.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: names
                        .map((name) => Chip(
                              label: Text(name),
                              avatar: const Icon(Icons.eco, size: 14),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                );
              }),

            // 内容
            if (note.content != null && note.content!.isNotEmpty)
              Text(note.content!, style: Theme.of(context).textTheme.bodyLarge),

            // 画像
            if (note.imagePaths.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: note.imagePaths.asMap().entries.map((entry) {
                  final index = entry.key;
                  final p = entry.value;
                  final heroTag = 'note_image_${note.id}_$index';
                  final img = kIsWeb
                      ? Image.network(p,
                          width: 120, height: 120, fit: BoxFit.cover)
                      : Image.file(
                          File(p),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 40),
                              ),
                        );
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _FullScreenImageViewer(
                          imagePaths: note.imagePaths,
                          initialIndex: index,
                          noteId: note.id,
                        ),
                      ),
                    ),
                    child: Hero(
                      tag: heroTag,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: img,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
