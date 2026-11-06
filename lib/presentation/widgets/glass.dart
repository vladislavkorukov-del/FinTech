import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Finance 1.10 «liquid glass», after iOS: the card is a clear pane that
/// blurs and saturates whatever lies behind it (the theme backdrop and its
/// moving color blobs), with a thin light rim and a soft inner glow at the
/// edge that reads as the thickness of the glass. Flat: no drop shadow, no
/// gradient body.
///
/// The blur samples only inside the card (bounded blur), so colors from
/// outside never bleed in at the edges, and all panes share one backdrop
/// snapshot through the app's [BackdropGroup].
/// The edge-refraction shader (`shaders/liquid_glass.frag`). It runs only
/// with Impeller, which Android uses; elsewhere (and in widget tests) the
/// panes keep the blur without refraction.
abstract final class GlassShader {
  static ui.FragmentProgram? _program;
  static final _filters = <(double, double), ui.ImageFilter>{};

  static Future<void> load() async {
    if (!ui.ImageFilter.isShaderFilterSupported || _program != null) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
    } catch (_) {
      _program = null; // keep plain glass
    }
  }

  /// Refraction filter for a pane with [radius] at [dpr]; null when the
  /// shader is not available.
  static ui.ImageFilter? filter(double radius, double dpr) {
    final program = _program;
    if (program == null) return null;
    return _filters.putIfAbsent((radius, dpr), () {
      final shader = program.fragmentShader()
        ..setFloat(2, radius * dpr)
        ..setFloat(3, 16 * dpr)
        ..setFloat(4, 9 * dpr)
        ..setFloat(5, GlassSurface.saturation);
      return ui.ImageFilter.shader(shader);
    });
  }
}

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

  static const blurSigma = 9.0;

  /// Saturation boost of what is seen through the glass.
  static const saturation = 1.6;

  /// The pane's own color over the blurred backdrop: thin, so the backdrop
  /// reads through, but enough to keep text contrast on any part of it.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    // Dark glass is smoky (a touch darker than the surface), light glass
    // milky; either keeps secondary text at ≥ 4.5:1 over the brightest glow.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter.grouped(
        filterConfig: ImageFilterConfig.compose(
          outer: ImageFilterConfig(
            GlassShader.filter(
                  radius,
                  MediaQuery.devicePixelRatioOf(context),
                ) ??
                ui.ColorFilter.matrix(_saturate(saturation)),
          ),
          inner: const ImageFilterConfig.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            bounded: true,
          ),
        ),
        child: Material(
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
        ),
      ),
    );
  }
}

/// The pane color plus a soft glow just inside the edge, brighter at the top
/// where the light falls: the rounded thickness of real glass.
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
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: dark ? .16 : .55),
            Colors.white.withValues(alpha: dark ? .04 : .20),
          ],
        ).createShader(rect),
    );
    canvas.restore();
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
