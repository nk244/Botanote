import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/light_meter_service.dart';
import '../utils/error_utils.dart';

/// カメラで撮影した写真から明るさの目安を測定する画面（Issue #181）。
class LightMeterScreen extends StatefulWidget {
  const LightMeterScreen({super.key});

  @override
  State<LightMeterScreen> createState() => _LightMeterScreenState();
}

class _LightMeterScreenState extends State<LightMeterScreen> {
  String? _imagePath;
  LightMeterResult? _result;
  bool _isProcessing = false;

  Future<void> _captureAndMeasure() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (pickedFile == null) return;

      setState(() {
        _isProcessing = true;
        _imagePath = pickedFile.path;
        _result = null;
      });

      final bytes = await File(pickedFile.path).readAsBytes();
      final result = LightMeterService.analyze(bytes);

      if (!mounted) return;
      if (result == null) {
        messenger.showSnackBar(const SnackBar(content: Text('画像の解析に失敗しました')));
      }
      setState(() => _result = result);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('撮影に失敗しました: ${describeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  IconData _iconFor(LightLevel level) {
    switch (level) {
      case LightLevel.dark:
        return Icons.dark_mode_outlined;
      case LightLevel.dimShade:
        return Icons.cloud_outlined;
      case LightLevel.brightShade:
        return Icons.wb_cloudy_outlined;
      case LightLevel.bright:
        return Icons.wb_sunny_outlined;
      case LightLevel.directSun:
        return Icons.wb_sunny;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('光量メーター')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'カメラで置き場所を撮影すると、写真の明るさから目安を表示します。'
              'カメラの自動露出の影響を受けるため、絶対的な照度値ではなく相対的な目安としてご利用ください。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_imagePath!),
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            if (_isProcessing) const CircularProgressIndicator(),
            if (!_isProcessing && _result != null) _buildResultCard(_result!),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isProcessing ? null : _captureAndMeasure,
              icon: const Icon(Icons.camera_alt),
              label: const Text('撮影して測定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(LightMeterResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              _iconFor(result.level),
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              LightMeterService.labelFor(result.level),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '輝度値: ${result.luminance.round()} / 255',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
