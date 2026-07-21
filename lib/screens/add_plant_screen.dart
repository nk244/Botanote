import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'image_crop_screen.dart';
import '../providers/plant_provider.dart';
import '../providers/location_provider.dart';
import '../models/plant.dart';
import '../services/claude_share_service.dart';
import '../widgets/plant_image_widget.dart';

class AddPlantScreen extends StatefulWidget {
  final Plant? plant;

  const AddPlantScreen({super.key, this.plant});

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
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
      final pickedFile = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048);
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
        SnackBar(content: Text('画像の取得に失敗しました: $e')),
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
          SnackBar(content: Text('再トリミングに失敗しました: $e')),
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
      messenger.showSnackBar(SnackBar(content: Text('共有に失敗しました: $e')));
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
          dormantSeasonIntervalMultiplier:
              _seasonalAdjustmentEnabled ? _dormantSeasonIntervalMultiplier : null,
        );
      } else {
        // 既存植物の更新。nullable フィールドを明示的に null にできるよう
        // sentinel パターンを用いて copyWith を呼び出す。
        final updatedPlant = widget.plant!.copyWith(
          name: _nameController.text.trim(),
          variety: _varietyController.text.trim().isEmpty
              ? null  // sentinel により null として保存される
              : _varietyController.text.trim(),
          purchaseDate: _purchaseDate,  // null なら null として保存される
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
          dormantSeasonIntervalMultiplier:
              _seasonalAdjustmentEnabled ? _dormantSeasonIntervalMultiplier : null,
        );
        await plantProvider.updatePlant(updatedPlant);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
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
                  label: const Text('Claudeで植物名を推定'),
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
                final validValue =
                    locations.any((l) => l.id == _locationId) ? _locationId : null;
                return DropdownButtonFormField<String?>(
                  initialValue: validValue,
                  decoration: const InputDecoration(
                    labelText: '置き場所（任意）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未設定'),
                    ),
                    ...locations.map((location) => DropdownMenuItem<String?>(
                          value: location.id,
                          child: Text(location.name),
                        )),
                  ],
                  onChanged: (value) {
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
                _wateringInterval == null
                    ? '未設定'
                    : '$_wateringInterval日ごと',
              ),
              trailing: _wateringInterval != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
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
                  builder: (context) => _WateringIntervalDialog(
                    initialValue: _wateringInterval,
                  ),
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
                      .map((multiplier) => DropdownMenuItem(
                            value: multiplier,
                            child: Text('$multiplier倍'),
                          ))
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
  State<_WateringIntervalDialog> createState() => _WateringIntervalDialogState();
}

class _WateringIntervalDialogState extends State<_WateringIntervalDialog> {
  late int _days;

  @override
  void initState() {
    super.initState();
    _days = widget.initialValue ?? 3;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('水やり間隔'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_days日ごと', style: Theme.of(context).textTheme.headlineSmall),
          Slider(
            value: _days.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '$_days日',
            onChanged: (value) {
              setState(() {
                _days = value.toInt();
              });
            },
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
  // 0 = 日数指定, 1 = 水やりN回に1回
  late int _modeIndex;
  late int _days;
  late int _everyN;

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
            Text('$_days日ごと',
                style: Theme.of(context).textTheme.headlineSmall),
            Slider(
              value: _days.toDouble(),
              min: 1,
              max: 60,
              divisions: 59,
              label: '$_days日',
              onChanged: (v) => setState(() => _days = v.toInt()),
            ),
          ] else ...[
            Text('水やり$_everyN回に1回',
                style: Theme.of(context).textTheme.headlineSmall),
            Slider(
              value: _everyN.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
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
