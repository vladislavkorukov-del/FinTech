import 'package:flutter/material.dart';

/// The bottom bar's own symbols (Release). Each is drawn as a thin outline
/// and, when its tab is chosen, fills in with a little life of its own: the
/// house fills and its door opens, the list fills, the chart's bars grow
/// one after another, the four tiles turn and fill.
enum NavGlyphKind { home, operations, analytics, more }

class NavGlyph extends StatelessWidget {
  const NavGlyph({
    super.key,
    required this.kind,
    required this.active,
    required this.activeColor,
    required this.color,
    this.size = 24,
  });
  final NavGlyphKind kind;
  final bool active;
  final Color activeColor, color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1 : 0),
      duration: still ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // A small pop as the tab is chosen.
        final pop = active ? 1 + .12 * (4 * t * (1 - t)) : 1.0;
        return Transform.scale(
          scale: pop,
          child: CustomPaint(
            size: Size.square(size),
            painter: _NavPainter(
              kind: kind,
              t: t,
              color: Color.lerp(color, activeColor, t)!,
            ),
          ),
        );
      },
    );
  }
}

class _NavPainter extends CustomPainter {
  const _NavPainter({required this.kind, required this.t, required this.color});
  final NavGlyphKind kind;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24;
    canvas
      ..save()
      ..scale(k);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color.withValues(alpha: t);
    final cut = Paint()..blendMode = BlendMode.dstOut;
    switch (kind) {
      case NavGlyphKind.home:
        final body = Path()
          ..moveTo(3.2, 11.2)
          ..lineTo(12, 3.6)
          ..lineTo(20.8, 11.2)
          ..moveTo(5.6, 9.6)
          ..lineTo(5.6, 18.4)
          ..quadraticBezierTo(5.6, 20.6, 7.8, 20.6)
          ..lineTo(16.2, 20.6)
          ..quadraticBezierTo(18.4, 20.6, 18.4, 18.4)
          ..lineTo(18.4, 9.6);
        final solid = Path()
          ..moveTo(5.6, 9.4)
          ..lineTo(12, 3.9)
          ..lineTo(18.4, 9.4)
          ..lineTo(18.4, 18.4)
          ..quadraticBezierTo(18.4, 20.6, 16.2, 20.6)
          ..lineTo(7.8, 20.6)
          ..quadraticBezierTo(5.6, 20.6, 5.6, 18.4)
          ..close();
        // The door opens a little as the house fills.
        final door = RRect.fromLTRBAndCorners(
          10,
          14.4 - t * .6,
          14,
          20.6,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        );
        canvas
          ..saveLayer(Offset.zero & const Size(24, 24), Paint())
          ..drawPath(solid, fill)
          ..drawRRect(door, cut)
          ..restore()
          ..drawPath(body, line);
        if (t < .5) {
          canvas.drawRRect(
            door,
            line..color = color.withValues(alpha: 1 - 2 * t),
          );
        }
      case NavGlyphKind.operations:
        final sheet = RRect.fromLTRBR(5, 3, 19, 21, const Radius.circular(3.4));
        canvas
          ..saveLayer(Offset.zero & const Size(24, 24), Paint())
          ..drawRRect(sheet, fill);
        final ink = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round;
        // Lines: knocked out of the filled sheet, drawn on the outline.
        for (final (y, w) in [(8.4, 7.0), (12.2, 7.0), (16.0, 4.4)]) {
          canvas.drawLine(
            Offset(8.5, y),
            Offset(8.5 + w, y),
            ink..blendMode = BlendMode.dstOut,
          );
        }
        canvas.restore();
        canvas.drawRRect(sheet, line);
        if (t < 1) {
          for (final (y, w) in [(8.4, 7.0), (12.2, 7.0), (16.0, 4.4)]) {
            canvas.drawLine(
              Offset(8.5, y),
              Offset(8.5 + w, y),
              Paint()
                ..strokeWidth = 1.7
                ..strokeCap = StrokeCap.round
                ..color = color.withValues(alpha: 1 - t),
            );
          }
        }
      case NavGlyphKind.analytics:
        // Three bars; when chosen they grow in turn to new heights.
        const base = 20.6;
        final heights = [8.5, 13.5, 10.5];
        final grown = [11.0, 16.5, 13.5];
        for (var i = 0; i < 3; i++) {
          final local = ((t - i * .15) / .7).clamp(0.0, 1.0);
          final h = heights[i] + (grown[i] - heights[i]) * local;
          final x = 4.4 + i * 6.0;
          final bar = RRect.fromLTRBR(
            x,
            base - h,
            x + 3.6,
            base,
            const Radius.circular(1.8),
          );
          canvas
            ..drawRRect(bar, fill)
            ..drawRRect(bar, line);
        }
      case NavGlyphKind.more:
        // Four tiles; the top-right one turns into a circle when chosen.
        for (final (x, y) in [
          (3.8, 3.8),
          (13.2, 3.8),
          (3.8, 13.2),
          (13.2, 13.2),
        ]) {
          final topRight = x > 10 && y < 10;
          final r = topRight ? 2.4 + 1.1 * t : 2.4;
          final tile = RRect.fromLTRBR(x, y, x + 7, y + 7, Radius.circular(r));
          canvas
            ..drawRRect(tile, fill)
            ..drawRRect(tile, line);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavPainter old) =>
      old.t != t || old.color != color || old.kind != kind;
}
