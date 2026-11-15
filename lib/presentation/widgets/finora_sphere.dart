import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Finora without a face (2.2, a choice since 2.3): a sphere of light, like
/// a voice assistant. Soft colours flow inside a glass ball and drift round
/// each other; when she listens or answers they swell ([energy]).
class FinoraSpherePainter extends CustomPainter {
  FinoraSpherePainter({required this.t, this.energy = 0, required Color color})
    : _painted = color;

  /// The theme color this painter draws with.
  final Color _painted;

  /// Position in the drift loop, 0…1 (any value: it repeats).
  final double t;

  /// How lively the light is: 0 at rest … 1 listening or answering.
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final e = energy.clamp(0.0, 1.0);
    final a = t * 2 * math.pi;
    // Her own light first (the theme colour), then cool companions.
    final colors = [
      _painted,
      const Color(0xFF39B8FF),
      const Color(0xFF8C6CFF),
      const Color(0xFFFF5FC8),
    ];

    // A soft halo round the ball, larger when she is lively.
    final halo = r * (1.16 + .14 * e);
    canvas.drawCircle(
      c,
      halo,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _painted.withValues(alpha: .22 + .2 * e),
            _painted.withValues(alpha: 0),
          ],
          stops: const [.66, 1],
        ).createShader(Rect.fromCircle(center: c, radius: halo)),
    );

    final ball = Rect.fromCircle(center: c, radius: r);
    canvas
      ..save()
      ..clipPath(Path()..addOval(ball));
    // Deep blue glass.
    canvas.drawRect(
      ball,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.15, -.25),
          colors: [Color(0xFF16224A), Color(0xFF060A18)],
        ).createShader(ball),
    );
    // Lights drifting round each other inside.
    const motion = [(1.0, .9), (1.3, 2.1), (.8, 4.0), (1.7, 5.3)];
    for (var k = 0; k < colors.length; k++) {
      final (speed, phase) = motion[k];
      final orbit = r * (.3 + .12 * e);
      final p =
          c +
          Offset(
            math.cos(a * speed + phase) * orbit,
            math.sin(a * speed * 1.3 + phase) * orbit * .8,
          );
      final glow = r * (.56 + .16 * e + .05 * math.sin(a * 2 + phase));
      canvas.drawCircle(
        p,
        glow,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [
              colors[k].withValues(alpha: .7 + .2 * e),
              colors[k].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: p, radius: glow)),
      );
    }
    // Ribbons of light through the middle, waving more when lively.
    for (var k = 0; k < 3; k++) {
      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final f = i / 48;
        final wave =
            math.sin(f * math.pi * 2 + a * (1 + k * .4) + k * 2.1) *
            r *
            (.08 + .16 * e) *
            math.sin(f * math.pi);
        final p = c + Offset(-r + 2 * r * f, wave + (k - 1) * r * .05);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (.022 + .022 * e)
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.screen
          ..color = colors[(k + 1) % colors.length].withValues(
            alpha: .3 + .35 * e,
          ),
      );
    }
    // The glass catches the light: a small soft highlight above.
    final shine = Rect.fromCenter(
      center: c + Offset(-r * .3, -r * .5),
      width: r * .62,
      height: r * .26,
    );
    canvas.drawOval(
      shine,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: .34),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(shine),
    );
    canvas.restore();
    // A thin rim of light, turning slowly.
    canvas.drawCircle(
      c,
      r - .75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(
          transform: GradientRotation(a),
          colors: [
            colors[0].withValues(alpha: .75),
            colors[1].withValues(alpha: .25),
            colors[2].withValues(alpha: .7),
            colors[3].withValues(alpha: .25),
            colors[0].withValues(alpha: .75),
          ],
        ).createShader(ball),
    );
  }

  @override
  bool shouldRepaint(FinoraSpherePainter old) =>
      old.t != t || old.energy != energy || old._painted != _painted;
}
