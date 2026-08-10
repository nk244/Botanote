import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/location.dart';
import '../providers/location_provider.dart';
import '../providers/plant_provider.dart';
import '../services/claude_share_service.dart';
import '../utils/error_utils.dart';

/// 複数の植物をまとめて登録する画面（Issue #66）。
///
/// 棚の写真のように複数の植物が写った1枚の画像を Claude アプリに共有して
/// 判別してもらい、返ってきた一覧を貼り付けると、行ごとに植物として
/// 連続登録できる。判別を使わず、名前を直接書き並べて登録することもできる。
///
/// AI連携は Anthropic API を直接叩かず、OSの共有シート経由で Claude アプリに
/// 渡す方式に揃えている（Issue #177/#178 と同じ理由で従量課金を避けるため）。
class BulkAddPlantsScreen extends StatefulWidget {
  const BulkAddPlantsScreen({super.key});

  @override
  State<BulkAddPlantsScreen> createState() => _BulkAddPlantsScreenState();
}

class _BulkAddPlantsScreenState extends State<BulkAddPlantsScreen> {
  final _picker = ImagePicker();
  final _pastedTextController = TextEditingController();

  /// 判別を依頼した写真（任意）
  String? _imagePath;

  /// 貼り付けたテキストから読み取った登録候補
  final List<PlantDraft> _drafts = [];

  /// 全候補に共通で設定する水やり間隔（null = 未設定）
  int? _wateringInterval;

  /// 全候補に共通で設定する置き場所（null = 未設定）
  String? _locationId;

  bool _isSaving = false;

  @override
  void dispose() {
    _pastedTextController.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  /// 判別してもらう写真を選ぶ。
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return;
      setState(() => _imagePath = picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の取得に失敗しました: ${describeError(e)}')),
      );
    }
  }

  /// 写真を Claude アプリに共有して、写っている植物の一覧を作ってもらう。
  Future<void> _shareForBulkIdentification() async {
    final path = _imagePath;
    if (path == null) return;
    try {
      await ClaudeShareService.shareForBulkIdentification(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('共有に失敗しました: ${describeError(e)}')),
      );
    }
  }

  /// 貼り付けたテキストを1行1植物として読み取る。
  void _parsePastedText() {
    final drafts = parsePlantList(_pastedTextController.text);
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('植物名を読み取れませんでした。1行に1つずつ入力してください')),
      );
      return;
    }
    setState(() {
      for (final draft in _drafts) {
        draft.dispose();
      }
      _drafts
        ..clear()
        ..addAll(drafts);
    });
  }

  /// 選択された候補をまとめて登録する。
  Future<void> _saveAll() async {
    final targets = _drafts.where((d) => d.selected).toList();
    if (targets.isEmpty) return;

    setState(() => _isSaving = true);
    final plantProvider = context.read<PlantProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      for (final draft in targets) {
        final name = draft.nameController.text.trim();
        if (name.isEmpty) continue;
        final variety = draft.varietyController.text.trim();
        await plantProvider.addPlant(
          name: name,
          variety: variety.isEmpty ? null : variety,
          wateringIntervalDays: _wateringInterval,
          locationId: _locationId,
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text('${targets.length}件の植物を登録しました')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('登録に失敗しました: ${describeError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _drafts.where((d) => d.selected).length;

    return Scaffold(
      appBar: AppBar(title: const Text('植物をまとめて登録')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _buildStepHeader(context, 1, '写真から判別する（任意）'),
          const SizedBox(height: 8),
          Text(
            '複数の植物が写った写真を Claude アプリに送ると、写っている植物の一覧を'
            '作ってもらえます。返ってきた一覧をコピーして、次の欄に貼り付けてください。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('撮影'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('写真を選ぶ'),
              ),
              FilledButton.tonalIcon(
                onPressed: _imagePath == null ? null : _shareForBulkIdentification,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Claudeで判別'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildStepHeader(context, 2, '植物名を貼り付ける'),
          const SizedBox(height: 8),
          TextField(
            controller: _pastedTextController,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              hintText: 'モンステラ / デリシオサ\n'
                  'サンスベリア（ローレンチー）\n'
                  'ポトス',
              helperText: '1行に1つ。「名前 / 品種」「名前（品種）」の形式にも対応します',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _parsePastedText,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('読み取る'),
            ),
          ),

          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildStepHeader(context, 3, '内容を確認して登録'),
            const SizedBox(height: 8),
            _buildCommonSettings(context),
            const SizedBox(height: 8),
            ..._drafts.map(_buildDraftTile),
          ],
        ],
      ),
      bottomNavigationBar: _drafts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed:
                      (_isSaving || selectedCount == 0) ? null : _saveAll,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text('$selectedCount件を登録'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildStepHeader(BuildContext context, int step, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '$step',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }

  /// 登録するすべての植物に共通で適用する設定。
  Widget _buildCommonSettings(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.water_drop_outlined),
              title: const Text('水やり間隔（全件に適用）'),
              subtitle: Text(
                  _wateringInterval == null ? '未設定' : '$_wateringInterval日ごと'),
              trailing: _wateringInterval == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '水やり間隔をクリア',
                      onPressed: () => setState(() => _wateringInterval = null),
                    ),
              onTap: _showIntervalPicker,
            ),
            Consumer<LocationProvider>(
              builder: (context, locationProvider, _) {
                final locations = locationProvider.locations;
                if (locations.isEmpty) return const SizedBox.shrink();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('置き場所（全件に適用）'),
                  subtitle: Text(_locationName(locations) ?? '未設定'),
                  trailing: _locationId == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: '置き場所をクリア',
                          onPressed: () => setState(() => _locationId = null),
                        ),
                  onTap: () => _showLocationPicker(locations),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _locationName(List<Location> locations) {
    if (_locationId == null) return null;
    for (final location in locations) {
      if (location.id == _locationId) return location.name;
    }
    return null;
  }

  Future<void> _showIntervalPicker() async {
    var days = _wateringInterval ?? 7;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('水やり間隔'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.remove),
                tooltip: '1日減らす',
                onPressed: days <= 1
                    ? null
                    : () => setDialogState(() => days--),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  '$days日ごと',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add),
                tooltip: '1日増やす',
                onPressed: () => setDialogState(() => days++),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(days),
              child: const Text('設定'),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _wateringInterval = result);
  }

  Future<void> _showLocationPicker(List<Location> locations) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.not_interested),
              title: const Text('未設定'),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            ...locations.map((location) => ListTile(
                  leading: Icon(location.isOutdoor
                      ? Icons.wb_sunny_outlined
                      : Icons.home_outlined),
                  title: Text(location.name),
                  onTap: () => Navigator.of(ctx).pop(location.id),
                )),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _locationId = result.isEmpty ? null : result);
  }

  Widget _buildDraftTile(PlantDraft draft) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            Checkbox(
              value: draft.selected,
              onChanged: (v) => setState(() => draft.selected = v ?? false),
            ),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: draft.nameController,
                    decoration: const InputDecoration(
                      labelText: '植物名',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: draft.varietyController,
                    decoration: const InputDecoration(
                      labelText: '品種（任意）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 登録候補1件分の入力状態。
class PlantDraft {
  final TextEditingController nameController;
  final TextEditingController varietyController;
  bool selected;

  PlantDraft({required String name, String? variety, this.selected = true})
      : nameController = TextEditingController(text: name),
        varietyController = TextEditingController(text: variety ?? '');

  void dispose() {
    nameController.dispose();
    varietyController.dispose();
  }
}

/// 貼り付けテキストを植物の登録候補に変換する（Issue #66）。
///
/// 1行1植物とみなし、以下を取り除く/切り分ける:
/// - 行頭の箇条書き記号・番号（`- `, `* `, `1. `, `1) ` など）
/// - Markdown の強調記号（`**`）
/// - `名前 / 品種`、`名前（品種）`、`名前 (品種)` の区切り
///
/// 空行と、区切り線のような記号だけの行は無視する。
List<PlantDraft> parsePlantList(String raw) {
  final drafts = <PlantDraft>[];
  final seen = <String>{};

  for (final line in raw.split('\n')) {
    var text = line.trim();
    if (text.isEmpty) continue;

    // 行頭の箇条書き記号・番号を落とす
    text = text.replaceFirst(RegExp(r'^\s*(?:[-*・●○]|\d+[.)、]|\(\d+\))\s*'), '');
    // Markdown の強調記号を落とす
    text = text.replaceAll('**', '').trim();
    if (text.isEmpty) continue;
    // 区切り線など記号だけの行は無視する
    if (!RegExp(r'[0-9A-Za-z぀-ヿ一-鿿]').hasMatch(text)) {
      continue;
    }

    String name = text;
    String? variety;

    // 「名前 / 品種」形式
    final slash = RegExp(r'\s*[/／|｜]\s*');
    if (slash.hasMatch(name)) {
      final parts = name.split(slash);
      name = parts.first.trim();
      final rest = parts.skip(1).join(' ').trim();
      if (rest.isNotEmpty) variety = rest;
    } else {
      // 「名前（品種）」形式
      final paren = RegExp(r'^(.+?)\s*[（(]([^）)]*)[）)]\s*$').firstMatch(name);
      if (paren != null) {
        name = paren.group(1)!.trim();
        final inner = paren.group(2)!.trim();
        if (inner.isNotEmpty) variety = inner;
      }
    }

    if (name.isEmpty) continue;
    // 同じ名前が複数行に出てきた場合は1件にまとめる
    final key = '$name|${variety ?? ''}';
    if (!seen.add(key)) continue;

    drafts.add(PlantDraft(name: name, variety: variety));
  }

  return drafts;
}
