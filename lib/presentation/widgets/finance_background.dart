import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Paints the theme's [FinanceBackdrop] behind the whole app: a tinted
/// vertical gradient and four soft color orbs that the glass cards show
/// through.
///
/// 1.11.1: the orbs stand still. A drifting backdrop redrew every frame, and
/// with it every glass blur on screen, which made the app lag on phones.
/// Static, an idle screen draws no frames at all, and the whole backdrop is
/// one cached layer.
class FinanceBackground extends StatelessWidget {
  const FinanceBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = FinanceBackdrop.of(context);
    final base = Theme.of(context).colorScheme.surfaceContainerLowest;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest.shortestSide;
              // Orbs with a defined body and a soft rim: shapes the glass
              // cards visibly soften as they scroll over them.
              Widget glow(Color color, double scale) => Container(
                width: size * scale,
                height: size * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    stops: const [0, .55, .72, 1],
                    colors: [
                      color,
                      color.withValues(alpha: color.a * .85),
                      color.withValues(alpha: color.a * .3),
                      color.withValues(alpha: 0),
                    ],
                  ),
                ),
              );
              final a = glow(b.glowA, 1.15);
              final c = glow(b.glowB, 1.0);
              final small = glow(b.glowA, .55);
              final tiny = glow(b.glowB, .42);
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
                    Positioned(top: -size * .35, right: -size * .30, child: a),
                    Positioned(
                      top: box.maxHeight * .70,
                      right: -size * .12,
                      child: small,
                    ),
                    Positioned(
                      top: box.maxHeight * .16,
                      left: size * .08,
                      child: tiny,
                    ),
                    Positioned(
                      top: box.maxHeight * .42,
                      left: -size * .45,
                      child: c,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Glass panes share one snapshot of the backdrop.
        BackdropGroup(child: child),
      ],
    );
  }
}
