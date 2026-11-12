import 'package:flutter/material.dart';

/// The app's card, after an iOS grouped table section: one solid surface
/// with continuous corners, set apart from the flat background by color
/// alone — no rim, no shadow, no gradient. No blur or clip layer, so
/// scrolling stays cheap (1.11.2).
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

  /// The card color: the solid surface, with a faint wash of [tint] for
  /// colored tiles.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    // Apple polish: a solid card, like a grouped table section.
    var c = body;
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          customBorder: RoundedSuperellipseBorder(borderRadius: r),
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
    // Apple polish: one flat fill with continuous corners; no shadow and
    // no rim — the card is separated from the background by color alone.
    final body = RSuperellipse.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRSuperellipse(body, Paint()..color = color);
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      old.radius != radius || old.color != color || old.dark != dark;
}
