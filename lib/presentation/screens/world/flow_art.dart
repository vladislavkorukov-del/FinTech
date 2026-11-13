import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

part 'flow_art_data.dart';

/// Source coordinates are retained separately from the presentation crop.
/// In particular, board pieces and both states of an obstacle use a full square.
class FlowAssetInfo {
  const FlowAssetInfo(
    this.path,
    this.width,
    this.height,
    this.trimBounds,
    this.nineSlice,
    this.capitalHeight,
    this.xHeight,
    this.preserveSquare,
  );
  final String path;
  final int width, height;
  final List<num> trimBounds;
  final List<num>? nineSlice;
  final int? capitalHeight, xHeight;
  final bool preserveSquare;

  Rect bounds({bool trim = true}) => trim && !preserveSquare
      ? _rect(trimBounds)
      : Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  static Rect _rect(List<num> v) => Rect.fromLTRB(
    v[0].toDouble(),
    v[1].toDouble(),
    v[2].toDouble(),
    v[3].toDouble(),
  );
}

/// One catalogue for originals, including byte-identical aliases between packs.
abstract final class FlowArt {
  static const mapLayoutAsset = 'assets/finora/match3/map/map_layout.json';
  static Iterable<String> get ids => _flowAssets.keys;
  static FlowAssetInfo info(String id) =>
      _flowAssets[id] ??
      (throw ArgumentError.value(id, 'id', 'Unknown Flow asset'));
  static String path(String id) => info(id).path;
  static Rect bounds(String id, {bool trim = true}) =>
      info(id).bounds(trim: trim);
  static double aspectRatio(String id, {bool trim = true}) {
    final b = bounds(id, trim: trim);
    return b.width / b.height;
  }

  /// Keep letters at the same size, rather than giving every word equal width.
  static double labelHeight(
    String id, {
    double capitalHeight = 14,
    double? xHeight,
  }) {
    final asset = info(id);
    final metric = xHeight != null ? asset.xHeight : asset.capitalHeight;
    final desired = xHeight ?? capitalHeight;
    return metric == null ? desired : bounds(id).height * desired / metric;
  }

  static final _visible = <ImageProvider, int>{};
  static void _retain(ImageProvider provider) =>
      _visible.update(provider, (value) => value + 1, ifAbsent: () => 1);
  static void _release(ImageProvider provider) {
    final count = _visible[provider] ?? 0;
    if (count <= 1) {
      _visible.remove(provider);
    } else {
      _visible[provider] = count - 1;
    }
  }

  /// Useful before capturing a scene or revealing an overlay: this waits for
  /// the exact resized providers currently used, without decoding all originals.
  static Future<void> precacheVisible(BuildContext context) => Future.wait(
    _visible.keys.toList().map((provider) => precacheImage(provider, context)),
  );
}

/// Draws the actual PNG, preserving aspect ratio. UI trim is a source rectangle,
/// not another raster file; the 86 source records therefore add only 80 PNGs.
class FlowSprite extends StatelessWidget {
  const FlowSprite(
    this.id, {
    super.key,
    this.width,
    this.height,
    this.trim = true,
    this.fit = BoxFit.contain,
  });
  final String id;
  final double? width, height;
  final bool trim;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final asset = FlowArt.info(id);
      final source = asset.bounds(trim: trim);
      final aspect = source.width / source.height;
      final w =
          width ??
          (height != null
              ? height! * aspect
              : constraints.hasBoundedWidth
              ? constraints.maxWidth
              : constraints.hasBoundedHeight
              ? constraints.maxHeight * aspect
              : 64.0);
      final h =
          height ??
          (width != null
              ? width! / aspect
              : constraints.hasBoundedHeight
              ? constraints.maxHeight
              : w / aspect);
      final size = constraints.constrain(Size(w, h));
      final fitted = applyBoxFit(fit, source.size, size);
      final rawDecode =
          fitted.destination.width /
          source.width *
          asset.width *
          MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = math.min(
        asset.width,
        math.max(32, (rawDecode / 32).ceil() * 32),
      );
      return SizedBox(
        width: w,
        height: h,
        child: _FlowImage(
          asset: asset,
          trim: trim,
          fit: fit,
          cacheWidth: cacheWidth,
        ),
      );
    },
  );
}

/// Static lettering with the cap/x-height specified by the supplied pack.
class FlowLabel extends StatelessWidget {
  const FlowLabel(this.id, {super.key, this.capitalHeight = 14, this.xHeight});
  final String id;
  final double capitalHeight;
  final double? xHeight;
  @override
  Widget build(BuildContext context) => FlowSprite(
    id,
    height: FlowArt.labelHeight(
      id,
      capitalHeight: capitalHeight,
      xHeight: xHeight,
    ),
  );
}

/// Nine-slice empty art supports a taller content area without stretching corners.
class FlowArtPanel extends StatelessWidget {
  const FlowArtPanel({
    super.key,
    required this.child,
    this.art = 'out_of_moves_panel_base',
    this.padding = const EdgeInsets.all(20),
    this.sliceByHeight = false,
    this.slice,
  });
  final Widget child;
  final String art;
  final EdgeInsetsGeometry padding;

  /// Scale the corners and rim by the panel's height instead of its width,
  /// so plates of one height match whatever their widths.
  final bool sliceByHeight;

  /// A tighter stretch rectangle (source pixels, LTRB) than the manifest's
  /// conservative one, for plates that hug their text.
  final List<num>? slice;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: _NineSliceArt(art, byHeight: sliceByHeight, slice: slice),
      ),
      Padding(padding: padding, child: child),
    ],
  );
}

/// An entire button has one accessible label and one hit target. Art containing
/// baked lettering does not receive a second visible text label.
class FlowArtButton extends StatelessWidget {
  const FlowArtButton({
    super.key,
    required this.art,
    required this.label,
    required this.onPressed,
    this.labelArt,
    this.child,
    this.width,
    this.height = 56,
    this.visualSize,
    this.visualAlignment = Alignment.center,
    this.labelCapHeight = 16,
  });
  final String art, label;
  final String? labelArt;
  final Widget? child;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double? visualSize;

  /// Where a small [visualSize] icon sits inside its (larger) hit target.
  final Alignment visualAlignment;

  /// Cap height (or x-height, when the label art has one) of [labelArt].
  final double labelCapHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final requestedWidth =
          width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : 240.0);
      final actualWidth = math.max(48.0, requestedWidth);
      final actualHeight = math.max(48.0, height);
      final textArt = labelArt;
      final content =
          child ??
          (textArt == null
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FlowSprite(
                    textArt,
                    height:
                        FlowArt.info(textArt).capitalHeight == null &&
                            FlowArt.info(textArt).xHeight == null
                        ? actualHeight * .5
                        : FlowArt.labelHeight(
                            textArt,
                            capitalHeight: labelCapHeight,
                            xHeight: FlowArt.info(textArt).xHeight == null
                                ? null
                                : labelCapHeight,
                          ),
                  ),
                ));
      return Semantics(
        container: true,
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: SizedBox(
            width: actualWidth,
            height: actualHeight,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(22),
                child: Opacity(
                  opacity: onPressed == null ? .65 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: visualSize != null
                            ? Align(
                                alignment: visualAlignment,
                                child: SizedBox.square(
                                  dimension: visualSize,
                                  child: FlowSprite(art),
                                ),
                              )
                            : FlowArt.info(art).nineSlice == null
                            ? FlowSprite(art)
                            : _NineSliceArt(art),
                      ),
                      ?content,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _NineSliceArt extends StatelessWidget {
  const _NineSliceArt(this.id, {this.byHeight = false, this.slice});
  final String id;
  final bool byHeight;
  final List<num>? slice;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final asset = FlowArt.info(id);
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
      // Decode at the corners' on-screen scale: by height for plates that
      // scale their corners by height (a narrow plate stays crisp, and its
      // resolution does not change while its width animates).
      final scale = byHeight && constraints.hasBoundedHeight
          ? constraints.maxHeight / asset.bounds().height
          : width / asset.bounds().width;
      final desired =
          scale * asset.width * MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = math.min(
        asset.width,
        math.max(64, (desired / 32).ceil() * 32),
      );
      return _FlowImage(
        asset: asset,
        trim: true,
        fit: BoxFit.fill,
        cacheWidth: cacheWidth,
        nineSlice: true,
        byHeight: byHeight,
        slice: slice,
      );
    },
  );
}

class _FlowImage extends StatefulWidget {
  const _FlowImage({
    required this.asset,
    required this.trim,
    required this.fit,
    required this.cacheWidth,
    this.nineSlice = false,
    this.byHeight = false,
    this.slice,
  });
  final FlowAssetInfo asset;
  final bool trim, nineSlice, byHeight;
  final List<num>? slice;
  final BoxFit fit;
  final int cacheWidth;
  @override
  State<_FlowImage> createState() => _FlowImageState();
}

class _FlowImageState extends State<_FlowImage> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageInfo? _image;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_FlowImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.path != widget.asset.path ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _resolve();
    }
  }

  void _resolve() {
    final provider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      AssetImage(widget.asset.path),
    );
    if (provider == _provider) return;
    if (_provider != null) FlowArt._release(_provider!);
    _stream?.removeListener(_listener);
    _provider = provider;
    FlowArt._retain(provider);
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = info);
    old?.dispose();
  }

  void _onError(Object error, StackTrace? stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'Finora Match-3 art',
      context: ErrorDescription('loading ${widget.asset.path}'),
    ),
  );
  @override
  void dispose() {
    _stream?.removeListener(_listener);
    if (_provider != null) FlowArt._release(_provider!);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _FlowImagePainter(
        _image?.image,
        widget.asset,
        widget.trim,
        widget.fit,
        widget.nineSlice,
        widget.byHeight,
        widget.slice,
      ),
    ),
  );
}

class _FlowImagePainter extends CustomPainter {
  const _FlowImagePainter(
    this.image,
    this.asset,
    this.trim,
    this.fit,
    this.nineSlice,
    this.byHeight,
    this.sliceOverride,
  );
  final ui.Image? image;
  final FlowAssetInfo asset;
  final bool trim, nineSlice, byHeight;
  final List<num>? sliceOverride;
  final BoxFit fit;
  @override
  void paint(Canvas canvas, Size size) {
    final im = image;
    if (im == null || size.isEmpty) return;
    final x = im.width / asset.width, y = im.height / asset.height;
    final raw = asset.bounds(trim: trim);
    final source = Rect.fromLTRB(
      raw.left * x,
      raw.top * y,
      raw.right * x,
      raw.bottom * y,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    final slice = sliceOverride ?? asset.nineSlice;
    if (nineSlice && slice != null) {
      paint.isAntiAlias = false;
      final center = FlowAssetInfo._rect(slice);
      var scale = byHeight ? size.height / raw.height : size.width / raw.width;
      // Corners never overlap across a narrow plate.
      final sides = (center.left - raw.left) + (raw.right - center.right);
      if (sides * scale > size.width) scale = size.width / sides;
      var top = (center.top - raw.top) * scale;
      var bottom = (raw.bottom - center.bottom) * scale;
      if (top + bottom > size.height) {
        final shrink = size.height / (top + bottom);
        top *= shrink;
        bottom *= shrink;
      }
      final sx = [source.left, center.left * x, center.right * x, source.right];
      final sy = [source.top, center.top * y, center.bottom * y, source.bottom];
      final dx = [
        0.0,
        (center.left - raw.left) * scale,
        size.width - (raw.right - center.right) * scale,
        size.width,
      ];
      final dy = [0.0, top, size.height - bottom, size.height];
      // Shared boundaries for all nine rectangles avoid gaps after scaling.
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          final src = Rect.fromLTRB(sx[col], sy[row], sx[col + 1], sy[row + 1]);
          final dst = Rect.fromLTRB(dx[col], dy[row], dx[col + 1], dy[row + 1]);
          if (!src.isEmpty && !dst.isEmpty) {
            canvas.drawImageRect(im, src, dst, paint);
          }
        }
      }
    } else {
      final fitted = applyBoxFit(fit, source.size, size);
      final src = Alignment.center.inscribe(fitted.source, source);
      final dst = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & size,
      );
      canvas.drawImageRect(im, src, dst, paint);
    }
  }

  @override
  bool shouldRepaint(_FlowImagePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.asset != asset ||
      oldDelegate.trim != trim ||
      oldDelegate.fit != fit ||
      oldDelegate.nineSlice != nineSlice ||
      oldDelegate.byHeight != byHeight ||
      oldDelegate.sliceOverride != sliceOverride;
}
