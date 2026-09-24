import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../../core/theme/app_colors.dart';

class AppImage extends StatelessWidget {
  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const AppImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.neutralPill,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.photo,
        color: AppColors.textSecondary.withOpacity(0.4),
        size: (width != null && width! < 60) ? 20 : 36,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (imagePath.trim().isEmpty) {
      imageWidget = placeholder ?? _defaultPlaceholder();
    } else if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      imageWidget = Image.network(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder ?? _defaultPlaceholder(),
      );
    } else if (imagePath.startsWith('assets/')) {
      imageWidget = Image.asset(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder ?? _defaultPlaceholder(),
      );
    } else {
      // Local filesystem path (captured with camera or picked from gallery)
      final file = File(imagePath);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder ?? _defaultPlaceholder(),
        );
      } else {
        // Try asset fallback or placeholder
        imageWidget = Image.asset(
          imagePath,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder ?? _defaultPlaceholder(),
        );
      }
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
