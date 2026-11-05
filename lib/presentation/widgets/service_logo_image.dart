import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Render at twice the physical display resolution, then downsample smoothly.
/// The original artwork stays unchanged; Flutter's ImageCache owns the frames.
int serviceLogoDecodeSize(double logicalSize, double devicePixelRatio) =>
    (logicalSize * devicePixelRatio * 2).ceil().clamp(32, 1024);

@immutable
class ServiceSvgImage extends ImageProvider<ServiceSvgImage> {
  const ServiceSvgImage(this.assetPath, {required this.pixels, this.bundle});
  final String assetPath;
  final int pixels;
  final AssetBundle? bundle;

  @override
  Future<ServiceSvgImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(
        ServiceSvgImage(
          assetPath,
          pixels: pixels,
          bundle: bundle ?? configuration.bundle ?? rootBundle,
        ),
      );

  @override
  ImageStreamCompleter loadImage(
    ServiceSvgImage key,
    ImageDecoderCallback decode,
  ) {
    final rendered = key._renderWithEviction();
    final completer = OneFrameImageStreamCompleter(rendered);
    // A scroll or memory-pressure eviction can remove the last consumer while
    // the native raster is pending. Keep ownership until setImage has run.
    final handle = completer.keepAlive();
    unawaited(
      rendered.then<void>(
        (_) => handle.dispose(),
        onError: (Object _, StackTrace _) => handle.dispose(),
      ),
    );
    return completer;
  }

  Future<ImageInfo> _renderWithEviction() async {
    try {
      return await _render();
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  Future<ImageInfo> _render() async {
    final source = await vg.loadPicture(
      SvgAssetLoader(assetPath, assetBundle: bundle),
      null,
    );
    try {
      if (source.size.isEmpty || pixels < 4 || pixels > 1024) {
        throw StateError('Invalid service artwork dimensions');
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // A transparent physical-pixel gutter keeps boundary curves off a hard
      // clipping edge. Centering preserves non-square brand marks as well.
      const gutter = 1.0;
      final scale = math.min(
        (pixels - 2 * gutter) / source.size.width,
        (pixels - 2 * gutter) / source.size.height,
      );
      canvas.translate(
        (pixels - source.size.width * scale) / 2,
        (pixels - source.size.height * scale) / 2,
      );
      canvas.scale(scale);
      canvas.drawPicture(source.picture);
      final picture = recorder.endRecording();
      try {
        return ImageInfo(image: await picture.toImage(pixels, pixels));
      } finally {
        picture.dispose();
      }
    } finally {
      source.picture.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceSvgImage &&
      other.assetPath == assetPath &&
      other.pixels == pixels &&
      other.bundle == bundle;

  @override
  int get hashCode => Object.hash(assetPath, pixels, bundle);
}
