import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    children: [const FinanceBackdropLayer(), child],
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
          // 1.16: two faint, fully soft glows; no defined orbs.
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
          final a = glow(b.glowA, 1.15);
          final c = glow(b.glowB, 1.0);
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
                  top: box.maxHeight * .42,
                  left: -size * .45,
                  child: c,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
