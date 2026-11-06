import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// Paints the theme's [FinanceBackdrop] behind the whole app: a tinted
/// vertical gradient and two soft color glows that slowly drift ("breathe")
/// when ambient motion is allowed. The glows move as separate layers, so
/// the app content above is never repainted by this animation.
class FinanceBackground extends StatefulWidget {
  const FinanceBackground({super.key, required this.child});
  final Widget child;
  @override
  State<FinanceBackground> createState() => _FinanceBackgroundState();
}

class _FinanceBackgroundState extends State<FinanceBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambient(context)) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

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
              Widget glow(Color color, double scale) => RepaintBoundary(
                child: Container(
                  width: size * scale,
                  height: size * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color, color.withValues(alpha: 0)],
                    ),
                  ),
                ),
              );
              final a = glow(b.glowA, 1.15);
              final c = glow(b.glowB, 1.0);
              return Stack(
                key: const ValueKey('finance-backdrop'),
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: DecoratedBox(
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
                  ),
                  AnimatedBuilder(
                    animation: _breath,
                    builder: (context, _) {
                      final t = _breath.value * 2 * math.pi;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            top: -size * .35,
                            right: -size * .30,
                            child: Transform.translate(
                              offset: Offset(
                                math.sin(t) * size * .06,
                                math.cos(t) * size * .05,
                              ),
                              child: Transform.scale(
                                scale: 1 + .06 * math.sin(t * 2),
                                child: a,
                              ),
                            ),
                          ),
                          Positioned(
                            top: box.maxHeight * .42,
                            left: -size * .45,
                            child: Transform.translate(
                              offset: Offset(
                                math.cos(t) * size * .07,
                                math.sin(t) * size * .08,
                              ),
                              child: Transform.scale(
                                scale: 1 + .08 * math.cos(t * 2),
                                child: c,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }
}
