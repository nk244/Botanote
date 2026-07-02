import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/plant.dart';
import '../models/note.dart';
import '../providers/note_provider.dart';
import '../widgets/plant_image_widget.dart';

/// タイムライン上の1枚の写真エントリ
class _TimelinePhoto {
  final String imagePath;
  final DateTime date;
  final String caption;

  const _TimelinePhoto({
    required this.imagePath,
    required this.date,
    required this.caption,
  });
}

/// 植物ごとの成長写真タイムライン画面（Issue #179）。
///
/// ノートに添付された画像と植物の登録時写真を時系列に並べて表示する。
/// 新規データを持たず、既存のノート・植物データのみから構成する。
class PlantGrowthTimelineScreen extends StatelessWidget {
  final Plant plant;

  const PlantGrowthTimelineScreen({super.key, required this.plant});

  List<_TimelinePhoto> _buildTimeline(List<Note> notes) {
    final entries = <_TimelinePhoto>[];

    if (plant.imagePath != null) {
      entries.add(_TimelinePhoto(
        imagePath: plant.imagePath!,
        date: plant.purchaseDate ?? plant.createdAt,
        caption: '登録時の写真',
      ));
    }

    for (final note in notes) {
      for (final path in note.imagePaths) {
        entries.add(_TimelinePhoto(
          imagePath: path,
          date: note.createdAt,
          caption: note.title,
        ));
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  void _showFullImage(BuildContext context, _TimelinePhoto photo) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: PlantImageWidget(
                imagePath: photo.imagePath,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBeforeAfter(BuildContext context, List<_TimelinePhoto> entries) {
    final before = entries.first;
    final after = entries.last;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ビフォーアフター'),
        content: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('yyyy/MM/dd').format(before.date),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  AspectRatio(
                    aspectRatio: 1,
                    child: PlantImageWidget(
                      imagePath: before.imagePath,
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('yyyy/MM/dd').format(after.date),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  AspectRatio(
                    aspectRatio: 1,
                    child: PlantImageWidget(
                      imagePath: after.imagePath,
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, _) {
        final plantNotes = noteProvider.notes
            .where((n) => n.plantIds.contains(plant.id))
            .toList();
        final entries = _buildTimeline(plantNotes);

        return Scaffold(
          appBar: AppBar(
            title: Text('${plant.name}の成長タイムライン'),
            actions: [
              if (entries.length >= 2)
                IconButton(
                  icon: const Icon(Icons.compare),
                  tooltip: 'ビフォーアフターを比較',
                  onPressed: () => _showBeforeAfter(context, entries),
                ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_motion_outlined,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'まだ成長記録がありません',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'ノートに写真を追加すると、ここに時系列で表示されます',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final photo = entries[index];
                    return GestureDetector(
                      onTap: () => _showFullImage(context, photo),
                      child: Tooltip(
                        message: photo.caption,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: PlantImageWidget(
                              imagePath: photo.imagePath,
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('yyyy/MM/dd').format(photo.date),
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
