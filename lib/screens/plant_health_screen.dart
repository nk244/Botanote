import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/plant.dart';
import '../providers/ai_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ai_service.dart';

/// 植物の健康診断画面
class PlantHealthScreen extends StatefulWidget {
  final Plant plant;

  /// 最終水やり日（PlantDetailScreenから渡す）
  final DateTime? lastWateredAt;

  const PlantHealthScreen({
    super.key,
    required this.plant,
    this.lastWateredAt,
  });

  @override
  State<PlantHealthScreen> createState() => _PlantHealthScreenState();
}

class _PlantHealthScreenState extends State<PlantHealthScreen> {
  final _symptomController = TextEditingController();
  String? _imageBase64;
  bool _isLoading = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _symptomController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBase64 = base64Encode(bytes);
    });
  }

  Future<void> _diagnose() async {
    final apiKey =
        context.read<SettingsProvider>().settings.claudeApiKey;
    if (apiKey.isEmpty) {
      _showApiKeyNotSetError();
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
      _error = null;
    });

    try {
      final result = await context.read<AiProvider>().diagnoseHealth(
            apiKey: apiKey,
            plantName: widget.plant.name,
            variety: widget.plant.variety,
            symptomText: _symptomController.text,
            wateringIntervalDays: widget.plant.wateringIntervalDays,
            lastWateredAt: widget.lastWateredAt,
            imageBase64: _imageBase64,
          );
      setState(() => _result = result);
    } on AiServiceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'エラーが発生しました: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showApiKeyNotSetError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('設定からClaude APIキーを設定してください')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('健康診断'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPlantInfo(),
            const SizedBox(height: 16),
            _buildSymptomInput(),
            const SizedBox(height: 16),
            _buildImageSection(),
            const SizedBox(height: 24),
            _buildDiagnoseButton(),
            if (_isLoading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('診断中...')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlantInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.plant.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.plant.variety != null)
              Text(
                widget.plant.variety!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSymptomInput() {
    return TextField(
      controller: _symptomController,
      maxLines: 4,
      decoration: const InputDecoration(
        labelText: '症状・気になること',
        hintText: '例: 葉が黄色くなってきた、元気がなさそう',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('写真（任意）',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (_imageBase64 != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              Uint8List.fromList(base64Decode(_imageBase64!)),
              height: 160,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(_imageBase64 == null ? '写真を選択' : '写真を変更'),
        ),
      ],
    );
  }

  Widget _buildDiagnoseButton() {
    return FilledButton.icon(
      onPressed: _isLoading ? null : _diagnose,
      icon: const Icon(Icons.medical_services_outlined),
      label: const Text('診断する'),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('診断結果',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(_result!),
          ],
        ),
      ),
    );
  }
}
