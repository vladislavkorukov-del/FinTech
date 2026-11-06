import 'package:flutter/material.dart';

/// Finance «liquid glass», after iOS: the card is a clear pane over the theme
/// backdrop and its color orbs, with a thin light rim and a light band just
/// inside the edge that reads as the thickness of the glass. Flat: no drop
/// shadow, no gradient body.
///
/// 1.11.2, for smooth scrolling: no backdrop blur and no clip layer at all.
/// A blur under every card re-ran on every scroll frame; over the soft
/// backdrop a translucent pane looks almost the same and costs only two
/// rounded rects and two strokes per card, like the opaque cards of 1.9.
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

  /// The pane's own color over the backdrop: thin, so the backdrop reads
  /// through, but enough to keep text contrast on any part of it.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    // Dark glass is smoky (a touch darker than the surface), light glass
    // milky; either keeps secondary text at ≥ 4.5:1 over the brightest orb.
    // 1.15: a little denser — reads as thicker, calmer glass.
    var c = dark
        ? Color.lerp(body, Colors.black, .35)!.withValues(alpha: .64)
        : body.withValues(alpha: .66);
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: (dark ? .10 : .08) * k), c);
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return CustomPaint(
      painter: GlassPanePainter(
        radius: radius,
        color: pane(theme, base, tint, tintStrength),
        dark: dark,
      ),
      foregroundPainter: GlassRimPainter(radius: radius, dark: dark),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          customBorder: RoundedRectangleBorder(borderRadius: r),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
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
    // 1.15: depth instead of shine — the body is a touch lighter at the top
    // and settles darker at the bottom; one soft light band under the top
    // edge. Plain gradients, no blur.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: dark ? .035 : .18),
              color,
            ),
            color,
            Color.alphaBlend(
              Colors.black.withValues(alpha: dark ? .10 : .03),
              color,
            ),
          ],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      body.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: dark ? .05 : .22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
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
    const w = .8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // 1.15: restrained — a fine highlight along the top, the sides
          // almost bare, a faint catch at the bottom-right.
          stops: const [0, .35, .75, 1],
          colors: [
            Colors.white.withValues(alpha: dark ? .30 : .90),
            Colors.white.withValues(alpha: dark ? .07 : .40),
            Colors.white.withValues(alpha: dark ? .04 : .35),
            Colors.white.withValues(alpha: dark ? .12 : .65),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.dark != dark;
}
