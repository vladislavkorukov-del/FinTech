import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Paints the theme's [FinanceBackdrop] behind the whole app: a tinted
/// vertical gradient and two soft color glows. Purely decorative.
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
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest.shortestSide;
                Widget glow(Color color, double scale) => Container(
                  width: size * scale,
                  height: size * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color, color.withValues(alpha: 0)],
                    ),
                  ),
                );
                return Stack(
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
                    Positioned(
                      top: -size * .35,
                      right: -size * .30,
                      child: glow(b.glowA, 1.15),
                    ),
                    Positioned(
                      top: box.maxHeight * .42,
                      left: -size * .45,
                      child: glow(b.glowB, 1.0),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        child,
      ],
    );
  }
}
