import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/plant.dart';

/// 植物画像を表示する共通ウィジェット。
/// [plant] または [imagePath] のどちらか一方を指定する。
class PlantImageWidget extends StatelessWidget {
  final Plant? plant;
  final String? imagePath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const PlantImageWidget({
    super.key,
    this.plant,
    this.imagePath,
    this.width = 56,
    this.height = 56,
    this.borderRadius,
  }) : assert(
         plant != null || imagePath != null,
         'Either plant or imagePath must be provided',
       );

  String? get _effectiveImagePath => imagePath ?? plant?.imagePath;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(8);

    if (_effectiveImagePath == null) {
      return _buildPlaceholder(context, effectiveBorderRadius);
    }

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: _effectiveImagePath!.startsWith('data:')
          ? _buildDataUrlImage(context, effectiveBorderRadius)
          : _buildFileImage(context, effectiveBorderRadius),
    );
  }

  /// Base64 data URL を Image.memory() で表示する。
  Widget _buildDataUrlImage(BuildContext context, BorderRadius borderRadius) {
    try {
      final comma = _effectiveImagePath!.indexOf(',');
      if (comma < 0) return _buildPlaceholder(context, borderRadius);
      final bytes = base64Decode(_effectiveImagePath!.substring(comma + 1));
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: width.isFinite ? (width * 3).toInt() : null,
        cacheHeight: height.isFinite ? (height * 3).toInt() : null,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context, borderRadius),
      );
    } catch (_) {
      return _buildPlaceholder(context, borderRadius);
    }
  }

  /// ファイルパスから画像を表示する。
  Widget _buildFileImage(BuildContext context, BorderRadius borderRadius) {
    final file = File(_effectiveImagePath!);
    if (!file.existsSync()) {
      return _buildPlaceholder(context, borderRadius);
    }

    return Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: width.isFinite ? (width * 3).toInt() : null,
      cacheHeight: height.isFinite ? (height * 3).toInt() : null,
      errorBuilder: (context, error, stackTrace) =>
          _buildPlaceholder(context, borderRadius),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _buildPlaceholder(context, borderRadius);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context, BorderRadius borderRadius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.eco,
        color: Theme.of(context).colorScheme.primary,
        size: width * 0.5,
      ),
    );
  }
}
