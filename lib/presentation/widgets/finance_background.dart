import 'dart:math' as math;

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
///
/// Release: one quiet light — the base colour, and a wide soft glow of
/// [FinanceBackdrop.glowA] falling from the top centre (no orbs).
class FinanceBackdropLayer extends StatelessWidget {
  const FinanceBackdropLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final b = FinanceBackdrop.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('finance-backdrop'),
          painter: _BackdropPainter(b),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.b);
  final FinanceBackdrop b;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .4, 1],
          colors: [b.top, b.middle, b.bottom],
        ).createShader(rect),
    );
    // The glow: an ellipse wider than the screen, centred just above the
    // top edge, fading out by about a third of the height.
    final w = size.width * 1.5;
    final h = math.min(size.height * .42, size.width * 1.1);
    final glow = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .02),
      width: w,
      height: h,
    );
    canvas
      ..save()
      ..translate(glow.center.dx, glow.center.dy)
      ..scale(1, h / w)
      ..drawCircle(
        Offset.zero,
        w / 2,
        Paint()
          ..shader = RadialGradient(
            stops: const [0, .45, 1],
            colors: [
              b.glowA,
              b.glowA.withValues(alpha: b.glowA.a * .45),
              b.glowA.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: w / 2)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.b != b;
}
