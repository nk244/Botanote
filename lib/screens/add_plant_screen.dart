import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'image_crop_screen.dart';
import '../providers/plant_provider.dart';
import '../providers/location_provider.dart';
import '../models/plant.dart';
import '../services/claude_share_service.dart';
import '../widgets/claude_share_hint_dialog.dart';
import '../widgets/plant_image_widget.dart';
import '../utils/error_utils.dart';

class AddPlantScreen extends StatefulWidget {
  final Plant? plant;

  const AddPlantScreen({super.key, this.plant});

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameReadingController = TextEditingController();
  final _varietyController = TextEditingController();
  final _purchaseLocationController = TextEditingController();

  DateTime? _purchaseDate;
  int? _wateringInterval;
  // 肥料間隔（どちらか一方のみ非null）
  int? _fertilizerIntervalDays;
  int? _fertilizerEveryNWaterings;
  // 活力剤間隔（どちらか一方のみ非null）
  int? _vitalizerIntervalDays;
  int? _vitalizerEveryNWaterings;
  String? _imagePath;
  bool _isOutdoor = false;
  String? _locationId;
  bool _isLoading = false;
  // 季節調整（Issue #173）: 冬季（12〜2月）の間隔延長
  bool _seasonalAdjustmentEnabled = false;
  double _dormantSeasonIntervalMultiplier = 1.5;

  @override
  void initState() {
    super.initState();
    if (widget.plant != null) {
      _nameController.text = widget.plant!.name;
      _nameReadingController.text = widget.plant!.nameReading ?? '';
      _varietyController.text = widget.plant!.variety ?? '';
      _purchaseLocationController.text = widget.plant!.purchaseLocation ?? '';
      _purchaseDate = widget.plant!.purchaseDate;
      _wateringInterval = widget.plant!.wateringIntervalDays;
      _fertilizerIntervalDays = widget.plant!.fertilizerIntervalDays;
      _fertilizerEveryNWaterings = widget.plant!.fertilizerEveryNWaterings;
      _vitalizerIntervalDays = widget.plant!.vitalizerIntervalDays;
      _vitalizerEveryNWaterings = widget.plant!.vitalizerEveryNWaterings;
      _imagePath = widget.plant!.imagePath;
      _isOutdoor = widget.plant!.isOutdoor;
      _locationId = widget.plant!.locationId;
      _seasonalAdjustmentEnabled = widget.plant!.seasonalAdjustmentEnabled;
      _dormantSeasonIntervalMultiplier =
          widget.plant!.dormantSeasonIntervalMultiplier ?? 1.5;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameReadingController.dispose();
    _varietyController.dispose();
    _purchaseLocationController.dispose();
    super.dispose();
  }

  Future<void> _showImageSourceOptions() async {
    // async ギャップ前に context 依存の参照を取得しておく
    final hasExistingImage = _imagePath != null;
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 選択肢の戻り値: ImageSource か 're-crop' か null（キャンセル）
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasExistingImage)
              ListTile(
                leading: const Icon(Icons.crop),
                title: const Text('登録済み画像を再トリミング'),
                onTap: () => Navigator.of(ctx).pop('re-crop'),
              ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリーから選択'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    // 既存画像を再トリミング
    if (choice == 're-crop') {
      await _reCropExistingImage();
      return;
    }

    final source = choice as ImageSource;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (pickedFile == null) return;

      // トリミング画面へ遷移
      final cropResult = await navigator.push<CropResult?>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(imagePath: pickedFile.path),
        ),
      );

      // ユーザーが「戻る」を押した場合はキャンセル扱い
      if (cropResult == null) return;

      setState(() => _imagePath = cropResult.filePath);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('画像の取得に失敗しました: ${describeError(e)}')),
      );
    }
  }

  /// 登録済み画像をそのままトリミング画面に渡して再トリミングする
  Future<void> _reCropExistingImage() async {
    if (_imagePath == null) return;
    try {
      final cropResult = await Navigator.of(context).push<CropResult?>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(imagePath: _imagePath!),
        ),
      );
      if (cropResult != null) {
        setState(() => _imagePath = cropResult.filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再トリミングに失敗しました: ${describeError(e)}')),
        );
      }
    }
  }

  /// 登録済みの写真を同定依頼文とともにClaudeアプリへ共有する（Issue #178）。
  ///
  /// Anthropic APIを直接呼び出す従量課金方式は使わず、OSの共有シート経由で
  /// Claudeアプリ（無料プラン・Proプランいずれでも利用可能）に画像と質問文を渡す。
  /// 応答はClaudeアプリ上で確認し、植物名・品種名欄に手動で入力する。
  Future<void> _shareImageForIdentification() async {
    if (_imagePath == null) return;

    // 共有シートが開くことを初回だけ説明する（Issue #261）
    if (!await confirmClaudeShare(context)) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ClaudeShareService.shareForIdentification(_imagePath!);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Claudeアプリでの推定結果を植物名・品種名欄に入力してください'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('共有に失敗しました: ${describeError(e)}')),
      );
    }
  }

  Future<void> _savePlant() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final plantProvider = context.read<PlantProvider>();

      final String? effectiveImagePath = _imagePath;

      if (widget.plant == null) {
        // Add new plant
        await plantProvider.addPlant(
          name: _nameController.text.trim(),
          nameReading: _nameReadingController.text.trim().isEmpty
              ? null
              : _nameReadingController.text.trim(),
          variety: _varietyController.text.trim().isEmpty
              ? null
              : _varietyController.text.trim(),
          purchaseDate: _purchaseDate,
          purchaseLocation: _purchaseLocationController.text.trim().isEmpty
              ? null
              : _purchaseLocationController.text.trim(),
          imagePath: effectiveImagePath,
          wateringIntervalDays: _wateringInterval,
          fertilizerIntervalDays: _fertilizerIntervalDays,
          fertilizerEveryNWaterings: _fertilizerEveryNWaterings,
          vitalizerIntervalDays: _vitalizerIntervalDays,
          vitalizerEveryNWaterings: _vitalizerEveryNWaterings,
          isOutdoor: _isOutdoor,
          locationId: _locationId,
          seasonalAdjustmentEnabled: _seasonalAdjustmentEnabled,
          dormantSeasonIntervalMultiplier: _seasonalAdjustmentEnabled
              ? _dormantSeasonIntervalMultiplier
              : null,
        );
      } else {
        // 既存植物の更新。nullable フィールドを明示的に null にできるよう
        // sentinel パターンを用いて copyWith を呼び出す。
        final updatedPlant = widget.plant!.copyWith(
          name: _nameController.text.trim(),
          nameReading: _nameReadingController.text.trim().isEmpty
              ? null
              : _nameReadingController.text.trim(),
          variety: _varietyController.text.trim().isEmpty
              ? null // sentinel により null として保存される
              : _varietyController.text.trim(),
          purchaseDate: _purchaseDate, // null なら null として保存される
          purchaseLocation: _purchaseLocationController.text.trim().isEmpty
              ? null
              : _purchaseLocationController.text.trim(),
          imagePath: effectiveImagePath,
          wateringIntervalDays: _wateringInterval,
          fertilizerIntervalDays: _fertilizerIntervalDays,
          fertilizerEveryNWaterings: _fertilizerEveryNWaterings,
          vitalizerIntervalDays: _vitalizerIntervalDays,
          vitalizerEveryNWaterings: _vitalizerEveryNWaterings,
          isOutdoor: _isOutdoor,
          locationId: _locationId,
          seasonalAdjustmentEnabled: _seasonalAdjustmentEnabled,
          dormantSeasonIntervalMultiplier: _seasonalAdjustmentEnabled
              ? _dormantSeasonIntervalMultiplier
              : null,
        );
        await plantProvider.updatePlant(updatedPlant);
      }

      if (mounted) {
        // 保存されたことを呼び出し元に伝える（キャンセル時は null が返る）
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: ${describeError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 置き場所を新規作成するダイアログを表示し、作成できたらそれを選択する。
  ///
  /// 置き場所が未登録のまま植物登録に入った利用者が、登録を中断せずに
  /// その場で置き場所を用意できるようにする（Issue #291）。
  Future<void> _createLocationAndSelect() async {
    final nameController = TextEditingController();
    var isOutdoor = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('置き場所を追加'),
          // 置き場所一覧の追加ダイアログと同じ理由で自動フォーカスしない（Issue #268）
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '場所名',
                    border: OutlineInputBorder(),
                    hintText: '例: リビング、ベランダ',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('屋外'),
                  subtitle: const Text('天気連動ケアアラートの対象になります'),
                  value: isOutdoor,
                  onChanged: (value) {
                    FocusScope.of(ctx).unfocus();
                    setDialogState(() => isOutdoor = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || name.isEmpty || !mounted) return;

    try {
      final created = await context.read<LocationProvider>().addLocation(
        name,
        isOutdoor,
      );
      if (!mounted) return;
      setState(() => _locationId = created.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('置き場所の作成に失敗しました: ${describeError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plant == null ? '植物を追加' : '植物を編集'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: FilledButton.icon(
                onPressed: _savePlant,
                icon: const Icon(Icons.check),
                label: const Text('保存'),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        // 入力を修正した時点でエラー表示を再評価し、赤枠・エラーメッセージを残さない
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image picker
            Center(
              child: GestureDetector(
                onTap: _showImageSourceOptions,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: PlantImageWidget(
                            imagePath: _imagePath,
                            width: 150,
                            height: 150,
                            borderRadius: BorderRadius.zero,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '写真を追加',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (_imagePath != null)
              Center(
                child: TextButton.icon(
                  onPressed: _shareImageForIdentification,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Claudeに送って推定'),
                ),
              ),
            const SizedBox(height: 24),

            // Plant name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '植物名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.eco),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '植物名を入力してください';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 読み仮名（五十音順の並び替え用、Issue #257）
            TextFormField(
              controller: _nameReadingController,
              decoration: const InputDecoration(
                labelText: '読み仮名（任意）',
                helperText: '入力すると「名前（あ→ん）」で五十音順に並びます',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sort_by_alpha),
              ),
            ),
            const SizedBox(height: 16),

            // Variety
            TextFormField(
              controller: _varietyController,
              decoration: const InputDecoration(
                labelText: '品種名（任意）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
            ),
            const SizedBox(height: 16),

            // Purchase date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('購入日'),
              subtitle: Text(
                _purchaseDate == null
                    ? '未設定'
                    : '${_purchaseDate!.year}年${_purchaseDate!.month}月${_purchaseDate!.day}日',
              ),
              trailing: _purchaseDate != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '購入日をクリア',
                      onPressed: () {
                        setState(() {
                          _purchaseDate = null;
                        });
                      },
                    )
                  : null,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _purchaseDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _purchaseDate = date;
                  });
                }
              },
            ),
            const Divider(),

            // Purchase location
            TextFormField(
              controller: _purchaseLocationController,
              decoration: const InputDecoration(
                labelText: '購入先（任意）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),

            // 屋外の植物（天気連動ケアアラート対象、Issue #176）
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.deck),
              title: const Text('屋外の植物'),
              subtitle: const Text('天気連動ケアアラートの対象になります'),
              value: _isOutdoor,
              onChanged: (value) {
                setState(() => _isOutdoor = value);
              },
            ),
            const SizedBox(height: 16),

            // 置き場所（Issue #180）
            Consumer<LocationProvider>(
              builder: (context, locationProvider, _) {
                final locations = locationProvider.locations;
                final validValue = locations.any((l) => l.id == _locationId)
                    ? _locationId
                    : null;
                return DropdownButtonFormField<String?>(
                  initialValue: validValue,
                  decoration: InputDecoration(
                    labelText: '置き場所（任意）',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.home_outlined),
                    // 置き場所が0件のときは新規作成の導線を見つけやすくする（Issue #291）
                    helperText: locations.isEmpty
                        ? 'まだ置き場所がありません。「新しい置き場所を作成」から追加できます'
                        : null,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未設定'),
                    ),
                    ...locations.map(
                      (location) => DropdownMenuItem<String?>(
                        value: location.id,
                        child: Text(location.name),
                      ),
                    ),
                    // 登録を中断せずにその場で置き場所を作れるようにする（Issue #291）
                    DropdownMenuItem<String?>(
                      value: _createLocationValue,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '新しい置き場所を作成',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == _createLocationValue) {
                      // ドロップダウンの表示値は元に戻し、作成できたら選択し直す
                      setState(() {});
                      _createLocationAndSelect();
                      return;
                    }
                    setState(() => _locationId = value);
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Watering interval
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.water_drop),
              title: const Text('水やり間隔'),
              subtitle: Text(
                _wateringInterval == null ? '未設定' : '$_wateringInterval日ごと',
              ),
              trailing: _wateringInterval != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '水やり間隔をクリア',
                      onPressed: () {
                        setState(() {
                          _wateringInterval = null;
                          // 水やり間隔削除時は「N回に1回」設定も連動して削除
                          if (_fertilizerEveryNWaterings != null) {
                            _fertilizerEveryNWaterings = null;
                          }
                          if (_vitalizerEveryNWaterings != null) {
                            _vitalizerEveryNWaterings = null;
                          }
                        });
                      },
                    )
                  : null,
              onTap: () async {
                final result = await showDialog<int>(
                  context: context,
                  builder: (context) =>
                      _WateringIntervalDialog(initialValue: _wateringInterval),
                );
                if (result != null) {
                  setState(() {
                    _wateringInterval = result;
                  });
                }
              },
            ),
            const Divider(),

            // Fertilizer interval
            _buildLogIntervalTile(
              icon: Icons.grass,
              label: '肥料間隔',
              intervalDays: _fertilizerIntervalDays,
              everyNWaterings: _fertilizerEveryNWaterings,
              onChanged: (days, every) => setState(() {
                _fertilizerIntervalDays = days;
                _fertilizerEveryNWaterings = every;
              }),
              wateringIntervalDays: _wateringInterval,
            ),

            // Vitalizer interval
            _buildLogIntervalTile(
              icon: Icons.favorite,
              label: '活力剤間隔',
              intervalDays: _vitalizerIntervalDays,
              everyNWaterings: _vitalizerEveryNWaterings,
              onChanged: (days, every) => setState(() {
                _vitalizerIntervalDays = days;
                _vitalizerEveryNWaterings = every;
              }),
              wateringIntervalDays: _wateringInterval,
            ),
            const Divider(),

            // 季節調整（Issue #173）: 冬季（12〜2月）の間隔延長
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.ac_unit),
              title: const Text('冬季は間隔を延長する'),
              subtitle: const Text('12〜2月は水やり・肥料・活力剤の間隔を自動で延ばす'),
              value: _seasonalAdjustmentEnabled,
              onChanged: (value) {
                setState(() {
                  _seasonalAdjustmentEnabled = value;
                });
              },
            ),
            if (_seasonalAdjustmentEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<double>(
                  initialValue: _dormantSeasonIntervalMultiplier,
                  decoration: const InputDecoration(
                    labelText: '冬季の延長倍率',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timelapse),
                  ),
                  items: const [1.2, 1.5, 2.0, 3.0]
                      .map(
                        (multiplier) => DropdownMenuItem(
                          value: multiplier,
                          child: Text('$multiplier倍'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _dormantSeasonIntervalMultiplier = value;
                    });
                  },
                ),
              ),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogIntervalTile({
    required IconData icon,
    required String label,
    required int? intervalDays,
    required int? everyNWaterings,
    required void Function(int? days, int? every) onChanged,
    int? wateringIntervalDays,
  }) {
    String subtitle;
    if (intervalDays != null) {
      subtitle = '$intervalDays日ごと';
    } else if (everyNWaterings != null) {
      subtitle = '水やり$everyNWaterings回に1回';
    } else {
      subtitle = '未設定';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: (intervalDays != null || everyNWaterings != null)
          ? IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '設定をクリア',
              onPressed: () => onChanged(null, null),
            )
          : null,
      onTap: () async {
        final result = await showDialog<_IntervalResult>(
          context: context,
          builder: (context) => _LogIntervalDialog(
            label: label,
            initialDays: intervalDays,
            initialEveryN: everyNWaterings,
            wateringIntervalDays: wateringIntervalDays,
          ),
        );
        if (result != null) {
          onChanged(result.days, result.everyN);
        }
      },
    );
  }
}

class _WateringIntervalDialog extends StatefulWidget {
  final int? initialValue;

  const _WateringIntervalDialog({this.initialValue});

  @override
  State<_WateringIntervalDialog> createState() =>
      _WateringIntervalDialogState();
}

class _WateringIntervalDialogState extends State<_WateringIntervalDialog> {
  late int _days;

  @override
  void initState() {
    super.initState();
    _days = widget.initialValue ?? 3;
  }

  /// 水やり間隔の下限・上限（日）。上限は多肉・サボテン等の長い間隔にも対応（Issue #235）。
  static const int _minDays = 1;
  static const int _maxDays = 90;

  /// 日数を範囲内に丸めて更新する。
  void _setDays(int value) {
    setState(() {
      _days = value.clamp(_minDays, _maxDays);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('水やり間隔'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ステッパーで厳密に日数を指定できるようにする（スライダーだけでは
          // 狙った日数に合わせにくいため。Issue #235）。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: '1日減らす',
                onPressed: _days > _minDays ? () => _setDays(_days - 1) : null,
              ),
              SizedBox(
                width: 120,
                child: Text(
                  '$_days日ごと',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '1日増やす',
                onPressed: _days < _maxDays ? () => _setDays(_days + 1) : null,
              ),
            ],
          ),
          Slider(
            value: _days.toDouble(),
            min: _minDays.toDouble(),
            max: _maxDays.toDouble(),
            divisions: _maxDays - _minDays,
            label: '$_days日',
            onChanged: (value) => _setDays(value.toInt()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_days),
          child: const Text('設定'),
        ),
      ],
    );
  }
}

/// 肥料・活力剤の間隔設定ダイアログの戻り値
class _IntervalResult {
  final int? days;
  final int? everyN;
  const _IntervalResult({this.days, this.everyN});
}

/// 肥料・活力剤の間隔設定ダイアログ
/// モード: 日数指定 / 水やりN回に1回
class _LogIntervalDialog extends StatefulWidget {
  final String label;
  final int? initialDays;
  final int? initialEveryN;
  final int? wateringIntervalDays;

  const _LogIntervalDialog({
    required this.label,
    this.initialDays,
    this.initialEveryN,
    this.wateringIntervalDays,
  });

  @override
  State<_LogIntervalDialog> createState() => _LogIntervalDialogState();
}

class _LogIntervalDialogState extends State<_LogIntervalDialog> {
  static const int _minDays = 1;
  static const int _maxDays = 60;
  static const int _minEveryN = 1;
  static const int _maxEveryN = 10;

  // 0 = 日数指定, 1 = 水やりN回に1回
  late int _modeIndex;
  late int _days;
  late int _everyN;

  /// −/+ ボタン付きのステッパーを構築する（Issue #260）。
  ///
  /// スライダーだけでは狙った値に合わせにくいため、水やり間隔ダイアログ
  /// （Issue #235 で対応済み）と同じ操作方法に揃える。
  Widget _buildStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required String decrementTooltip,
    required String incrementTooltip,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: decrementTooltip,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 150,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: incrementTooltip,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialEveryN != null) {
      _modeIndex = 1;
      _everyN = widget.initialEveryN!;
      _days = widget.initialDays ?? 7;
    } else {
      _modeIndex = 0;
      _days = widget.initialDays ?? 7;
      _everyN = widget.initialEveryN ?? 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // モード切り替え（水やり間隔未設定の場合はN回モードを非表示）
          if (widget.wateringIntervalDays != null)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('日数指定')),
                ButtonSegment(value: 1, label: Text('水やりN回に1回')),
              ],
              selected: {_modeIndex},
              onSelectionChanged: (s) => setState(() => _modeIndex = s.first),
            )
          else
            // 水やり間隔未設定時は日数指定のみ利用可能
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '日数指定',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          const SizedBox(height: 16),
          if (_modeIndex == 0) ...[
            // 水やり間隔ダイアログと操作を揃える（Issue #260）
            _buildStepper(
              label: '$_days日ごと',
              value: _days,
              min: _minDays,
              max: _maxDays,
              decrementTooltip: '1日減らす',
              incrementTooltip: '1日増やす',
              onChanged: (v) => setState(() => _days = v),
            ),
            Slider(
              value: _days.toDouble(),
              min: _minDays.toDouble(),
              max: _maxDays.toDouble(),
              divisions: _maxDays - _minDays,
              label: '$_days日',
              onChanged: (v) => setState(() => _days = v.toInt()),
            ),
          ] else ...[
            _buildStepper(
              label: '水やり$_everyN回に1回',
              value: _everyN,
              min: _minEveryN,
              max: _maxEveryN,
              decrementTooltip: '1回減らす',
              incrementTooltip: '1回増やす',
              onChanged: (v) => setState(() => _everyN = v),
            ),
            Slider(
              value: _everyN.toDouble(),
              min: _minEveryN.toDouble(),
              max: _maxEveryN.toDouble(),
              divisions: _maxEveryN - _minEveryN,
              label: '$_everyN回に1回',
              onChanged: (v) => setState(() => _everyN = v.toInt()),
            ),
            if (widget.wateringIntervalDays != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '≈ ${widget.wateringIntervalDays! * _everyN}日ごと',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _modeIndex == 0
                ? _IntervalResult(days: _days)
                : _IntervalResult(everyN: _everyN),
          ),
          child: const Text('設定'),
        ),
      ],
    );
  }
}

/// 置き場所ドロップダウンで「新しい置き場所を作成」を表すセンチネル値（Issue #291）。
///
/// 実際の置き場所IDは UUID v4 のため、この値と衝突しない。
const String _createLocationValue = '__create_new_location__';
