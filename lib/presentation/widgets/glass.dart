import 'package:flutter/material.dart';

/// Finance 1.10 "liquid glass" surface: a translucent tinted fill that lets
/// the theme backdrop and its glows show through, a light rim that is bright
/// at the top-left and fades around the edge, a soft specular band at the
/// top and a rounded shadow underneath.
///
/// Everything is painted inside one rounded clip except the shadow, which
/// sits outside it, so no rectangular corners of shadow or ink ever show.
/// No backdrop blur is used: it would cost a full-screen pass per card while
/// the blurred backdrop already looks the same.
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

  /// Glass body color; defaults to the color scheme surface.
  final Color? base;

  /// Color the glass is tinted with toward the top-left (accent by default).
  final Color? tint;
  final double tintStrength;
  final VoidCallback? onTap;

  /// Opacity of the glass body. High enough that text keeps the contrast of
  /// the opaque surface, low enough that the backdrop color reads through.
  static double bodyAlpha(Brightness b) => b == Brightness.dark ? .80 : .74;

  /// Fill colors from the top-left to the bottom-right corner.
  static List<Color> fill(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    final glow = tint ?? theme.colorScheme.primary;
    final a = bodyAlpha(theme.brightness);
    Color layer(double white, double tinted, double alpha) => Color.alphaBlend(
      glow.withValues(alpha: tinted * k),
      Color.alphaBlend(Colors.white.withValues(alpha: white), body),
    ).withValues(alpha: alpha);
    return [
      layer(dark ? .07 : .35, dark ? .16 : .12, a),
      layer(dark ? .02 : .12, dark ? .05 : .04, a - .04),
      layer(0, dark ? .10 : .07, a),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return CustomPaint(
      // Rounded shadow outside the clip, cut out under the glass so it does
      // not darken the translucent body.
      painter: GlassShadowPainter(
        radius: radius,
        shadow: BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .32 : .09),
          blurRadius: 24,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(borderRadius: r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, .5, 1],
                colors: fill(theme, base, tint, tintStrength),
              ),
            ),
            child: CustomPaint(
              foregroundPainter: GlassRimPainter(radius: radius, dark: dark),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [shadow] around a rounded rect but never inside it.
class GlassShadowPainter extends CustomPainter {
  const GlassShadowPainter({required this.radius, required this.shadow});
  final double radius;
  final BoxShadow shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final reach = shadow.blurRadius * 2 + shadow.offset.distance;
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(body.outerRect.inflate(reach)),
        Path()..addRRect(body),
      ),
    );
    canvas.drawRRect(
      body.shift(shadow.offset).inflate(shadow.spreadRadius),
      shadow.toPaint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassShadowPainter old) =>
      old.radius != radius || old.shadow != shadow;
}

/// The glass edge: a specular band at the top and a 1.2 px rim whose light
/// falls from the top-left corner and catches again at the bottom-right.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .32],
          colors: [
            Colors.white.withValues(alpha: dark ? .07 : .22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    const w = 1.2;
    canvas.drawRRect(
      outer.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .35, .7, 1],
          colors: [
            Colors.white.withValues(alpha: dark ? .38 : .85),
            Colors.white.withValues(alpha: dark ? .06 : .25),
            Colors.white.withValues(alpha: dark ? .03 : .15),
            Colors.white.withValues(alpha: dark ? .18 : .55),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.dark != dark;
}
