import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Finance «liquid glass», after iOS 26: the card is frosted glass over the
/// colourful backdrop — what lies under it is blurred and made a little more
/// vivid, a thin milky pane carries the text, and the edge catches light at
/// the top-left and bottom-right like a real slab of glass.
///
/// Performance: every card on a page shares one backdrop pass through the
/// page's [GlassGroup] ([BackdropFilter.grouped]), so a scrolling list of
/// cards costs about one blur per frame, not one per card.
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

  /// How strongly the backdrop under the glass is blurred.
  static const blurSigma = 22.0;

  /// The frosting over the blurred backdrop: thin enough for the colour
  /// under it to glow through, dense enough to keep text at ≥ 4.5:1.
  static Color pane(ThemeData theme, Color? base, Color? tint, double k) {
    final dark = theme.brightness == Brightness.dark;
    final body = base ?? theme.colorScheme.surface;
    var c = dark
        ? Color.lerp(body, Colors.black, .25)!.withValues(alpha: .58)
        : Color.lerp(body, Colors.white, .5)!.withValues(alpha: .52);
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: (dark ? .1 : .09) * k), c);
    }
    return c;
  }

  /// The blur under the glass, with the colour pushed up a little (Apple's
  /// «vibrancy»), so the frosted colour glows instead of going grey.
  static final ImageFilter _filter = ImageFilter.compose(
    outer: const ColorFilter.matrix(_saturate),
    inner: ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
      tileMode: TileMode.mirror,
    ),
  );

  // Saturation 1.5 (luminance weights after Rec. 709).
  static const _saturate = <double>[
    1.393, -.357, -.036, 0, 0, //
    -.107, 1.143, -.036, 0, 0, //
    -.107, -.357, 1.464, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final group = BackdropGroup.of(context);
    final glass = CustomPaint(
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
          customBorder: RoundedSuperellipseBorder(borderRadius: r),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return CustomPaint(
      painter: _GlassShadowPainter(radius: radius, dark: dark),
      child: ClipRSuperellipse(
        borderRadius: r,
        child: group == null
            ? BackdropFilter(filter: _filter, child: glass)
            : BackdropFilter.grouped(filter: _filter, child: glass),
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

/// A very soft shadow under the slab, outside its clip.
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RSuperellipse.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRSuperellipse(
      body.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .2 : .06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(_GlassShadowPainter old) =>
      old.radius != radius || old.dark != dark;
}

/// The frosted pane: a thin milky fill, brighter toward the top-left where
/// the light falls, and a soft glow just inside the edge — the thickness of
/// the glass.
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
    canvas
      ..drawRSuperellipse(body, Paint()..color = color)
      // Light falling from the top-left across the slab.
      ..drawRSuperellipse(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, .45, 1],
            colors: [
              Colors.white.withValues(alpha: dark ? .1 : .3),
              Colors.white.withValues(alpha: dark ? .02 : .06),
              Colors.white.withValues(alpha: dark ? .05 : .14),
            ],
          ).createShader(rect),
      )
      // The edge of the glass glows a little from inside.
      ..drawRSuperellipse(
        body.deflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: dark ? .07 : .3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
  }

  @override
  bool shouldRepaint(GlassPanePainter old) =>
      old.radius != radius || old.color != color || old.dark != dark;
}

/// The rim: a bright hairline where the light hits — the top-left and the
/// bottom-right corners — fading out along the sides.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        rect,
        Radius.circular(radius),
      ).deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .3, .7, 1],
          colors: dark
              ? [
                  Colors.white.withValues(alpha: .55),
                  Colors.white.withValues(alpha: .08),
                  Colors.white.withValues(alpha: .06),
                  Colors.white.withValues(alpha: .35),
                ]
              : [
                  Colors.white,
                  Colors.white.withValues(alpha: .4),
                  Colors.white.withValues(alpha: .3),
                  Colors.white.withValues(alpha: .9),
                ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.dark != dark;
}
