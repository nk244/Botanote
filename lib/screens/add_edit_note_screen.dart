import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../models/note.dart';
import '../providers/note_provider.dart';

class AddEditNoteScreen extends StatefulWidget {
  final Note? note;
  final String? initialPlantId;
  const AddEditNoteScreen({this.note, this.initialPlantId, super.key});

  @override
  State<AddEditNoteScreen> createState() => _AddEditNoteScreenState();
}

class _AddEditNoteScreenState extends State<AddEditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  List<String> _selectedPlantIds = [];
  List<String> _selectedImagePaths = [];

  /// 新規作成時のみ使用する作成日（デフォルト=今日）
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _selectedPlantIds = widget.note?.plantIds ??
        (widget.initialPlantId != null ? [widget.initialPlantId!] : []);
    _selectedImagePaths = widget.note?.imagePaths ?? [];
    // 新規作成時：今日を初期値、編集時：既存のcreatedAt
    final now = DateTime.now();
    _selectedDate = widget.note?.createdAt ??
        DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// 作成日選択UIウィジェット群（新規作成時のみ利用）
  List<Widget> _buildDatePicker(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final formatted =
        '${_selectedDate.year}年${_selectedDate.month.toString().padLeft(2, '0')}月${_selectedDate.day.toString().padLeft(2, '0')}日';
    return [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(now.year - 5),
            lastDate: now,
            locale: locale,
            helpText: '作成日を選択',
          );
          if (picked != null) setState(() => _selectedDate = picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 18),
              const SizedBox(width: 8),
              Text('作成日', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(formatted,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<NoteProvider>();

    if (widget.note == null) {
      await provider.addNote(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        plantIds: _selectedPlantIds,
        imagePaths: _selectedImagePaths,
        createdAt: _selectedDate,
      );
    } else {
      final updated = widget.note!.copyWith(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        plantIds: _selectedPlantIds,
        imagePaths: _selectedImagePaths,
        updatedAt: DateTime.now(),
      );
      await provider.updateNote(updated);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'ノート作成' : 'ノート編集'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 作成日（新規作成時のみ表示）
            if (widget.note == null) ..._buildDatePicker(context),

            // タイトル
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'タイトルを入力してください' : null,
            ),
            const SizedBox(height: 16),

            // 植物選択
            Consumer<PlantProvider>(builder: (context, plantProv, _) {
              final selectedNames = plantProv.plants
                  .where((p) => _selectedPlantIds.contains(p.id))
                  .map((p) => p.name)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('植物', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _selectPlants(context, plantProv),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('選択'),
                      ),
                    ],
                  ),
                  if (selectedNames.isEmpty)
                    Text('選択されていません',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: selectedNames
                          .map((name) => Chip(
                                label: Text(name),
                                avatar: const Icon(Icons.eco, size: 14),
                                visualDensity: VisualDensity.compact,
                                onDeleted: () {
                                  final id = plantProv.plants
                                      .firstWhere((p) => p.name == name)
                                      .id;
                                  setState(() => _selectedPlantIds.remove(id));
                                },
                              ))
                          .toList(),
                    ),
                ],
              );
            }),
            const SizedBox(height: 16),

            // 内容
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                hintText: 'ノートの内容を入力してください',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              minLines: 6,
              maxLines: null,
            ),
            const SizedBox(height: 16),

            // 画像
            Row(
              children: [
                Text('画像', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showImageSourceOptions,
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            if (_selectedImagePaths.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedImagePaths.map((p) => _buildImageThumb(p)).toList(),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumb(String path) {
    final image = Image.file(File(path), width: 72, height: 72, fit: BoxFit.cover);

    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
        Positioned(
          right: 0,
          top: 0,
          child: InkWell(
            onTap: () => setState(() => _selectedImagePaths.remove(path)),
            child: const CircleAvatar(radius: 10, child: Icon(Icons.close, size: 12)),
          ),
        )
      ],
    );
  }

  Future<void> _selectPlants(BuildContext context, PlantProvider plantProv) async {
    // 植物データが未ロードの場合は先にロードする
    if (plantProv.plants.isEmpty) await plantProv.loadPlants();

    // ソート設定に従って並べた植物リストを取得する
    final settings = context.read<SettingsProvider>(); // ignore: use_build_context_synchronously
    final allPlants = plantProv.getSortedPlants(
      settings.plantSortOrder,
      settings.customSortOrder,
    );
    final tempSelected = List<String>.from(_selectedPlantIds);

    await showDialog<void>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('植物を選択'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: allPlants.map((p) {
                    final checked = tempSelected.contains(p.id);
                    return CheckboxListTile(
                      value: checked,
                      title: Text(p.name),
                      subtitle: p.variety != null ? Text(p.variety!) : null,
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            if (!tempSelected.contains(p.id)) {
                              tempSelected.add(p.id);
                            }
                          } else {
                            tempSelected.remove(p.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('キャンセル')),
                TextButton(
                    onPressed: () {
                      setState(() => _selectedPlantIds = List.from(tempSelected));
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('OK')),
              ],
            );
          },
        );
      },
    );
  }

  void _showImageSourceOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラ'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリー'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (x != null) setState(() => _selectedImagePaths.add(x.path));
    } else {
      final xs = await picker.pickMultiImage(imageQuality: 80);
      if (xs.isNotEmpty) setState(() => _selectedImagePaths.addAll(xs.map((e) => e.path)));
    }
  }
}
