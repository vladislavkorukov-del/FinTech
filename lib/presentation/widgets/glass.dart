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

  /// The card color: nearly solid surface (1.16), with a faint wash of
  /// [tint] for colored tiles.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    // Dark glass is smoky (a touch darker than the surface), light glass
    // milky; either keeps secondary text at ≥ 4.5:1 over the brightest orb.
    // 1.16: nearly solid — the card reads as one calm surface; the faint
    // backdrop no longer shows through as color.
    var c = dark
        ? Color.lerp(body, Colors.black, .2)!.withValues(alpha: .9)
        : body.withValues(alpha: .92);
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: (dark ? .06 : .05) * k), c);
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

/// The card body: one flat rounded fill.
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
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    // 1.37: a soft shadow under light cards lifts them off the tinted
    // backdrop (one blurred rect — no extra layer).
    if (!dark) {
      canvas.drawRRect(
        body.shift(const Offset(0, 3)),
        Paint()
          ..color = Colors.black.withValues(alpha: .05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    // 1.16: one flat fill; no bands or gradients.
    canvas.drawRRect(body, Paint()..color = color);
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      old.radius != radius || old.color != color || old.dark != dark;
}

/// The card edge: one even hairline.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // 1.37: the hairline catches light at the top edge, like glass.
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Colors.white.withValues(alpha: .16),
                  Colors.white.withValues(alpha: .04),
                ]
              : [
                  Colors.white.withValues(alpha: .9),
                  Colors.black.withValues(alpha: .06),
                ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.dark != dark;
}
