import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Paints the theme's [FinanceBackdrop] behind the whole app: a quiet tinted
/// vertical gradient and two faint glows (1.16).
///
/// 1.11.1: the orbs stand still; an idle screen draws no frames at all, and
/// the whole backdrop is one layer that scrolling never repaints.
class FinanceBackground extends StatelessWidget {
  const FinanceBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const FinanceBackdropLayer(),
      GlassGroup(child: child),
    ],
  );
}

/// 1.42: the painted backdrop alone. Pages opened on top of another page
/// carry their own copy, so a page is never see-through while it slides in.
class FinanceBackdropLayer extends StatelessWidget {
  const FinanceBackdropLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final b = FinanceBackdrop.of(context);
    final base = Theme.of(context).colorScheme.surfaceContainerLowest;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest.shortestSide;
          // Liquid glass: vivid colour bodies with a soft edge — under
          // the frosted cards they blur into glowing colour, as in iOS.
          Widget orb(Color color, double scale) => Container(
            width: size * scale,
            height: size * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                stops: const [0, .5, 1],
                colors: [
                  color,
                  color.withValues(alpha: color.a * .7),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          );
          final hue = HSLColor.fromColor(b.glowA);
          Color shift(double by, double alpha) => hue
              .withHue((hue.hue + by) % 360)
              .withSaturation(.8)
              .withLightness(.58)
              .toColor()
              .withValues(alpha: alpha);
          final a = orb(b.glowA, 1.05);
          final c = orb(b.glowB, .95);
          final third = orb(shift(180, b.glowA.a * .45), .85);
          return RepaintBoundary(
            child: Stack(
              key: const ValueKey('finance-backdrop'),
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: base,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .45, 1],
                      colors: [b.top, b.middle, b.bottom],
                    ),
                  ),
                ),
                Positioned(top: -size * .3, right: -size * .25, child: a),
                Positioned(
                  top: box.maxHeight * .42,
                  left: -size * .45,
                  child: c,
                ),
                Positioned(
                  top: box.maxHeight * .7,
                  right: -size * .3,
                  child: third,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
