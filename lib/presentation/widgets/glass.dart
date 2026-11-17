import 'package:flutter/material.dart';

/// The card surface (the name stays from the glass years). Release: matte
/// — a solid panel a shade off the backdrop, a whisper of gradient from top
/// to bottom, no blur, no outline, no shine. In the light theme a very soft
/// shadow lifts it off the page.
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

  /// Color of the panel; defaults to the color scheme surface.
  final Color? base;

  /// Optional colored tint.
  final Color? tint;
  final double tintStrength;
  final VoidCallback? onTap;

  /// The panel colour: solid (matte), with a faint wash of [tint].
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    var c = base ?? theme.colorScheme.surface;
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: (dark ? .08 : .06) * k), c);
    }
    return c.withValues(alpha: 1);
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
          // Release: the content is its own layer, so a counter or ring
          // animating inside does not repaint the card and its shadow.
          child: RepaintBoundary(
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// One shared backdrop pass for all the glass on a page (see
/// [BackdropFilter.grouped]); keeps its key across rebuilds.
class GlassGroup extends StatefulWidget {
  const GlassGroup({super.key, required this.child});
  final Widget child;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final _key = BackdropKey();

  @override
  Widget build(BuildContext context) =>
      BackdropGroup(backdropKey: _key, child: widget.child);
}

/// The matte panel: a soft top-to-bottom gradient of one colour; in the
/// light theme, a wide faint shadow under it.
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
    final body = RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius));
    // Light: a flat white panel, nothing else (strict, iOS grouped).
    if (!dark) {
      canvas.drawRSuperellipse(body, Paint()..color = color);
      return;
    }
    canvas.drawRSuperellipse(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, dark ? .035 : 0)!,
            Color.lerp(
              color,
              dark ? Colors.black : const Color(0xFFF4F5F2),
              dark ? .12 : .6,
            )!,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      old.radius != radius || old.color != color || old.dark != dark;
}
