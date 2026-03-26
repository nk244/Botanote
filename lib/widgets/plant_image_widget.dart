import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../models/plant.dart';

/// Reusable widget for displaying plant images
/// Can accept either a Plant object or a direct imagePath string
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
  }) : assert(plant != null || imagePath != null, 'Either plant or imagePath must be provided');

  String? get _effectiveImagePath => imagePath ?? plant?.imagePath;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(8);

    if (_effectiveImagePath == null) {
      return _buildPlaceholder(context, effectiveBorderRadius);
    }

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: kIsWeb
          ? _buildWebImage(context, effectiveBorderRadius)
          : _buildMobileImage(context, effectiveBorderRadius),
    );
  }

  Widget _buildWebImage(BuildContext context, BorderRadius borderRadius) {
    return Image.network(
      _effectiveImagePath!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _buildPlaceholder(context, borderRadius),
    );
  }

  Widget _buildMobileImage(BuildContext context, BorderRadius borderRadius) {
    final file = File(_effectiveImagePath!);
    if (!file.existsSync()) {
      return _buildPlaceholder(context, borderRadius);
    }

    // cacheWidth/cacheHeightで縮小デコードし、frameBuilderでフェードイン表示する。
    // プレースホルダーを先に出してテキスト表示をブロックしないようにする。
    return Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      // リスト表示サイズに合わせて縮小デコードし、メモリ・描画負荷を削減。
      // double.infinity など有限値以外の場合はキャッシュサイズを省略する。
      cacheWidth: width.isFinite ? (width * 3).toInt() : null,
      cacheHeight: height.isFinite ? (height * 3).toInt() : null,
      errorBuilder: (context, error, stackTrace) =>
          _buildPlaceholder(context, borderRadius),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          // キャッシュ済みまたは読み込み完了: そのまま表示
          return child;
        }
        // 読み込み中: プレースホルダーを表示
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
