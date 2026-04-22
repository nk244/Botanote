import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'image_crop_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../models/plant.dart';
import '../widgets/plant_image_widget.dart';
import '../services/ai_service.dart';

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
  Uint8List? _imageBytes; // Web用: トリミング後のバイト列
  bool _isLoading = false;

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
    // 既存画像がある場合は「再トリミング」選択肢も表示
    final hasExistingImage = _imagePath != null || _imageBytes != null;

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

      // Web・モバイル共通でトリミング画面へ遷移
      final cropResult = await Navigator.of(context).push<CropResult?>(
        MaterialPageRoute(
          builder: (_) => kIsWeb
              ? ImageCropScreen.web(xFile: pickedFile)
              : ImageCropScreen.mobile(imagePath: pickedFile.path),
        ),
      );

      // ユーザーが「戻る」を押した場合はキャンセル扱い
      if (cropResult == null) return;

      if (kIsWeb && cropResult.bytes != null) {
        // Web: バイト列をメモリに保持。表示はUint8Listから行う
        setState(() {
          _imagePath = pickedFile.path; // XFileのpathはBlob URLとして使用可
          _imageBytes = cropResult.bytes;
        });
      } else if (cropResult.filePath != null) {
        // モバイル: 保存済みファイルパスを使用
        setState(() => _imagePath = cropResult.filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像の取得に失敗しました: $e')),
        );
      }
    }
  }

  /// 登録済み画像をそのままトリミング画面に渡して再トリミングする
  Future<void> _reCropExistingImage() async {
    try {
      CropResult? cropResult;
      if (kIsWeb && _imageBytes != null) {
        // Web: メモリ上のバイト列を XFile 経由で渡す
        final tmpFile = XFile.fromData(_imageBytes!, mimeType: 'image/jpeg');
        cropResult = await Navigator.of(context).push<CropResult?>(
          MaterialPageRoute(
            builder: (_) => ImageCropScreen.web(xFile: tmpFile),
          ),
        );
        if (cropResult?.bytes != null) {
          setState(() => _imageBytes = cropResult!.bytes);
        }
      } else if (_imagePath != null) {
        // モバイル: 既存ファイルパスを渡す
        cropResult = await Navigator.of(context).push<CropResult?>(
          MaterialPageRoute(
            builder: (_) => ImageCropScreen.mobile(imagePath: _imagePath!),
          ),
        );
        if (cropResult?.filePath != null) {
          setState(() => _imagePath = cropResult!.filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再トリミングに失敗しました: $e')),
        );
      }
    }
  }

  /// 現在選択中の画像をAIに送り植物名・品種名を識別して入力欄に反映する。
  Future<void> _identifyWithAi() async {
    // 画像バイト列を取得する
    Uint8List? bytes;
    if (_imageBytes != null) {
      bytes = _imageBytes;
    } else if (_imagePath != null && !kIsWeb) {
      try {
        bytes = await File(_imagePath!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }

    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('識別する画像がありません')),
        );
      }
      return;
    }

    final apiKey = context.read<SettingsProvider>().geminiApiKey;
    setState(() => _isLoading = true);
    try {
      final result = await AiService().identifyPlant(
        imageBytes: bytes,
        apiKey: apiKey,
      );
      if (!mounted) return;
      if (result.isSuccessful) {
        // 識別結果をフォームに反映（上書き確認あり）
        final apply = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI識別結果'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('植物名: ${result.name}'),
                if (result.variety.isNotEmpty) Text('品種: ${result.variety}'),
                Text('信頼度: ${result.confidenceLabel}'),
                if (result.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(result.notes,
                      style: Theme.of(ctx).textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                const Text('この結果をフォームに反映しますか？'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('反映する'),
              ),
            ],
          ),
        );
        if (apply == true && mounted) {
          setState(() {
            _nameController.text = result.name;
            if (result.variety.isNotEmpty) {
              _varietyController.text = result.variety;
            }
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.notes.isNotEmpty ? result.notes : '植物を識別できませんでした')),
          );
        }
      }
    } on AiServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('識別中にエラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePlant() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final plantProvider = context.read<PlantProvider>();

      // Web: トリミング済みバイト列を Base64 data URL に変換して imagePath として保存
      String? effectiveImagePath = _imagePath;
      if (kIsWeb && _imageBytes != null) {
        final base64 = base64Encode(_imageBytes!);
        effectiveImagePath = 'data:image/jpeg;base64,$base64';
      }
      
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
        );
      } else {
        // Update existing plant
        final updatedPlant = widget.plant!.copyWith(
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
                  child: (_imageBytes != null || _imagePath != null)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _imageBytes != null
                              // Web: トリミング済みバイト列から直接表示
                              ? Image.memory(
                                  _imageBytes!,
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                )
                              : PlantImageWidget(
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
            // 画像が設定されている場合はAI識別ボタンを表示する
            if (_imageBytes != null || _imagePath != null) ...[
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _identifyWithAi,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AIで植物を識別'),
                ),
              ),
            ],
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
