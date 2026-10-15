import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../models/app_theme_pack.dart';

/// A new pack instance gets new image keys after replacement/restoration.
/// Unrelated avatars, stickers and backgrounds retain their cached images.
class _ThemeFileImage extends FileImage {
  const _ThemeFileImage(super.file, this.revision, {super.scale});
  final Object revision;
  @override
  bool operator ==(Object other) =>
      other is _ThemeFileImage &&
      super == other &&
      identical(revision, other.revision);
  @override
  int get hashCode => Object.hash(super.hashCode, revision);
}

/// Bounds the longest decoded edge without upscaling small source artwork.
/// Keeping the original logical image size via scale also preserves nine-slice
/// coordinates: centerSlice continues to use source pixels / sourceScale.
ImageProvider themeImageProvider(AppThemePack pack, ThemeImageAsset asset,
    {required int maxDimension, double sourceScale = 1}) {
  final longest = math.max(asset.width, asset.height);
  final target = math.min(longest, maxDimension);
  final ratio = target / longest;
  final image = _ThemeFileImage(File(pack.path(asset.file)), pack,
      scale: sourceScale * ratio);
  return ResizeImage.resizeIfNeeded(asset.width >= asset.height ? target : null,
      asset.height > asset.width ? target : null, image);
}

ImageProvider themePreviewProvider(AppThemePack pack) =>
    ResizeImage(_ThemeFileImage(File(pack.path(pack.preview!)), pack),
        width: 800, height: 450, policy: ResizeImagePolicy.fit);
