import 'package:flutter/material.dart' show BoxFit;

enum VideoFitType {
  fill('拉伸', boxFit: BoxFit.fill),
  contain('自动', boxFit: BoxFit.contain),
  cover('裁剪', boxFit: BoxFit.cover),
  fitWidth('等宽', boxFit: BoxFit.fitWidth),
  fitHeight('等高', boxFit: BoxFit.fitHeight),
  none('原始', boxFit: BoxFit.none),
  scaleDown('限制', boxFit: BoxFit.scaleDown),
  ratio_4x3('4:3', aspectRatio: 4 / 3),
  ratio_16x9('16:9', aspectRatio: 16 / 9),
  ;

  final String desc;
  final BoxFit boxFit;
  final double? aspectRatio;
  const VideoFitType(
    this.desc, {
    this.boxFit = BoxFit.contain,
    this.aspectRatio,
  });

  String mpvPanscan(double sourceAspectRatio, double viewportAspectRatio) {
    final crop = switch (this) {
      VideoFitType.cover => true,
      VideoFitType.fitWidth => sourceAspectRatio < viewportAspectRatio,
      VideoFitType.fitHeight => sourceAspectRatio > viewportAspectRatio,
      _ => false,
    };
    return crop ? '1.0' : '0.0';
  }

  String get mpvVideoUnscaled => switch (this) {
    VideoFitType.none => 'yes',
    VideoFitType.scaleDown => 'downscale-big',
    _ => 'no',
  };

  String mpvAspectOverride(double viewportAspectRatio) => switch (this) {
    VideoFitType.fill => viewportAspectRatio.toString(),
    VideoFitType.ratio_4x3 => '4:3',
    VideoFitType.ratio_16x9 => '16:9',
    _ => 'no',
  };
}

/// Aspect ratio the video box must have so the frame is never stretched.
///
/// Fixed ratios (4:3, 16:9) keep their ratio; every other fit follows the
/// media's real display size (already rotated), which is authoritative even
/// when [VideoController.rect] is stale. Returns null when the display size is
/// not known yet, which keeps the previous rect-based behavior.
double? resolveVideoBoxAspect(
  VideoFitType fit,
  int sourceWidth,
  int sourceHeight,
) {
  final fixed = fit.aspectRatio;
  if (fixed != null) return fixed;
  if (sourceWidth > 0 && sourceHeight > 0) {
    return sourceWidth / sourceHeight;
  }
  return null;
}
