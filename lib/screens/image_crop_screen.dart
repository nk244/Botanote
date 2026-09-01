import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/error_utils.dart';

/// トリミング結果のファイルパスを保持するクラス。
class CropResult {
  final String filePath;
  const CropResult(this.filePath);
}

class ImageCropScreen extends StatefulWidget {
  final String imagePath;

  const ImageCropScreen({super.key, required this.imagePath});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _controller = CropController();
  bool _isCropping = false;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    if (mounted) setState(() => _imageBytes = bytes);
  }

  Future<void> _onCropped(Uint8List cropped) async {
    setState(() => _isCropping = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'crop_${path.basename(widget.imagePath)}';
      final outFile = File('${dir.path}/$fileName');
      await outFile.writeAsBytes(cropped);
      if (mounted) Navigator.of(context).pop(CropResult(outFile.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: ${describeError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('画像をトリミング'),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'トリミングを確定',
            onPressed: (_isCropping || _imageBytes == null)
                ? null
                : () => _controller.crop(),
          ),
        ],
      ),
      body: _imageBytes == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Crop(
                  controller: _controller,
                  image: _imageBytes!,
                  onCropped: _onCropped,
                  aspectRatio: 1,
                  withCircleUi: false,
                  interactive: true,
                ),
                if (_isCropping)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
