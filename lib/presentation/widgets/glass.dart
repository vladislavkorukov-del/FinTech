import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Finance «liquid glass», after iOS: the card is a clear pane over the theme
/// backdrop and its color orbs, with a thin light rim and a light band just
/// inside the edge that reads as the thickness of the glass. Flat: no drop
/// shadow, no gradient body.
///
/// 1.11.1, for speed on real phones:
///  * a [frosted] pane blurs and saturates what lies behind it, and all panes
///    share one backdrop snapshot through the app's [BackdropGroup];
///  * rows of long lists are clear (`frosted: false`): over the soft
///    backdrop they look the same and cost nothing extra per frame;
///  * no refraction shader pass and no blurred mask in the painters;
///  * the backdrop does not animate, so an idle screen draws no frames.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.base,
    this.tint,
    this.tintStrength = 1,
    this.onTap,
    this.frosted = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Color the pane is tinted toward; defaults to the color scheme surface.
  final Color? base;

  /// Optional colored tint (income/expense tiles).
  final Color? tint;
  final double tintStrength;
  final VoidCallback? onTap;

  /// Whether the pane blurs the backdrop behind it.
  final bool frosted;

  static const blurSigma = 12.0;

  /// Saturation boost of what is seen through frosted glass.
  static const saturation = 1.5;

  /// The pane's own color over the backdrop: thin, so the backdrop reads
  /// through, but enough to keep text contrast on any part of it.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    // Dark glass is smoky (a touch darker than the surface), light glass
    // milky; either keeps secondary text at ≥ 4.5:1 over the brightest orb.
    var c = dark
        ? Color.lerp(body, Colors.black, .35)!.withValues(alpha: .56)
        : body.withValues(alpha: .58);
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: (dark ? .10 : .08) * k), c);
    }
    return c;
  }

  static List<double> _saturate(double s) {
    const r = .2126, g = .7152, b = .0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0,
      r * i, g * i, b * i + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// Blur, then the saturation boost; one shared instance.
  static final ui.ImageFilter filter = ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(_saturate(saturation)),
    inner: ui.ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
      tileMode: TileMode.clamp,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget glass = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: GlassPanePainter(
            radius: radius,
            color: pane(theme, base, tint, tintStrength),
            dark: dark,
          ),
          foregroundPainter: GlassRimPainter(radius: radius, dark: dark),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (frosted) {
      glass = BackdropFilter.grouped(filter: filter, child: glass);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: glass);
  }
}

/// The pane color plus a light band just inside the edge, brighter at the
/// top where the light falls. Two plain strokes, no blur mask.
class GlassPanePainter extends CustomPainter {
  const GlassPanePainter({
    required this.radius,
    required this.color,
    required this.dark,
  });
  final double radius;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final body = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(body, Paint()..color = color);
    Shader band(double top, double bottom) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: top),
        Colors.white.withValues(alpha: bottom),
      ],
    ).createShader(rect);
    for (final (inset, width, top, bottom) in [
      (3.0, 6.0, dark ? .05 : .22, dark ? .015 : .08),
      (1.5, 3.0, dark ? .07 : .28, dark ? .02 : .10),
    ]) {
      canvas.drawRRect(
        body.deflate(inset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = band(top, bottom),
      );
    }
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      old.radius != radius || old.color != color || old.dark != dark;
}

/// A hairline rim: bright where the light hits (top-left), almost gone along
/// the sides and catching again at the bottom-right corner.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const w = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .3, .7, 1],
          colors: [
            Colors.white.withValues(alpha: dark ? .55 : .95),
            Colors.white.withValues(alpha: dark ? .10 : .35),
            Colors.white.withValues(alpha: dark ? .06 : .30),
            Colors.white.withValues(alpha: dark ? .30 : .80),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.dark != dark;
}
