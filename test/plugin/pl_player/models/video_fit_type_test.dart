import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoFitType mpv mapping', () {
    test('maps crop behavior without Flutter fitting', () {
      expect(VideoFitType.contain.mpvPanscan(16 / 9, 4 / 3), '0.0');
      expect(VideoFitType.cover.mpvPanscan(16 / 9, 4 / 3), '1.0');
      expect(VideoFitType.fitWidth.mpvPanscan(4 / 3, 16 / 9), '1.0');
      expect(VideoFitType.fitWidth.mpvPanscan(16 / 9, 4 / 3), '0.0');
      expect(VideoFitType.fitHeight.mpvPanscan(16 / 9, 4 / 3), '1.0');
      expect(VideoFitType.fitHeight.mpvPanscan(4 / 3, 16 / 9), '0.0');
    });

    test('maps unscaled modes', () {
      expect(VideoFitType.none.mpvVideoUnscaled, 'yes');
      expect(VideoFitType.scaleDown.mpvVideoUnscaled, 'downscale-big');
      expect(VideoFitType.contain.mpvVideoUnscaled, 'no');
    });

    test('uses mpv aspect override for stretch and fixed ratios', () {
      expect(VideoFitType.fill.mpvAspectOverride(2), '2.0');
      expect(VideoFitType.ratio_4x3.mpvAspectOverride(2), '4:3');
      expect(VideoFitType.ratio_16x9.mpvAspectOverride(2), '16:9');
      expect(VideoFitType.contain.mpvAspectOverride(2), 'no');
    });
  });

  group('resolveVideoBoxAspect', () {
    test('follows the media display size for automatic fits', () {
      for (final fit in [
        VideoFitType.contain,
        VideoFitType.cover,
        VideoFitType.fitWidth,
        VideoFitType.fitHeight,
        VideoFitType.none,
        VideoFitType.scaleDown,
        VideoFitType.fill,
      ]) {
        expect(resolveVideoBoxAspect(fit, 1080, 1920), 1080 / 1920);
        expect(resolveVideoBoxAspect(fit, 1920, 1080), 1920 / 1080);
      }
    });

    test('keeps a portrait video portrait when the surface rect is stale', () {
      // Landscape box (1080x1920 rotated) would come from a stale rect; the
      // media size must win.
      expect(
        resolveVideoBoxAspect(VideoFitType.contain, 1080, 1920),
        closeTo(0.5625, 1e-9),
      );
    });

    test('keeps fixed ratios regardless of the media size', () {
      expect(resolveVideoBoxAspect(VideoFitType.ratio_4x3, 1080, 1920), 4 / 3);
      expect(resolveVideoBoxAspect(VideoFitType.ratio_16x9, 1080, 1920), 16 / 9);
      expect(resolveVideoBoxAspect(VideoFitType.ratio_4x3, 0, 0), 4 / 3);
    });

    test('falls back to the rect when the display size is unknown', () {
      expect(resolveVideoBoxAspect(VideoFitType.contain, 0, 0), isNull);
      expect(resolveVideoBoxAspect(VideoFitType.contain, 1920, 0), isNull);
      expect(resolveVideoBoxAspect(VideoFitType.contain, 0, 1080), isNull);
    });
  });
}
