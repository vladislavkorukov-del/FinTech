import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import 'motion.dart';

/// Finora's emotions (1.27), after the owner's sheet: a glossy mint bubble
/// with dark shiny eyes, a pink blush, and a small sign beside her.
enum FinoraMood {
  /// Open eyes, a small smile — at rest.
  idle,

  /// Приветствие: smile and sparkle lines.
  greeting,

  /// Радость: an open smile.
  happy,

  /// Удовольствие: blush «///» and a heart.
  pleasure,

  /// Уверенность: a wink and a star.
  wink,

  /// Восторг: a wide open smile and sparkles.
  delight,

  /// Размышление: a small «o» and a question mark.
  thinking,

  /// Сомнение: worried brows, a frown.
  doubt,

  /// Обработка: eyes closed, «…».
  processing,

  /// Идея: an open smile and a bulb.
  idea,

  /// Готово: a smile and a green check.
  done,

  /// Спокойствие: eyes closed in a smile.
  calm,

  /// Поддержка: blush and a heart.
  support,

  /// Внимание: «o» mouth and «!!».
  attention,

  /// Ошибка: sad brows and a warning sign.
  error,

  /// Ожидание: asleep, «Zzz».
  sleep,

  /// Удивление: round eyes, «o», «!» — a big expense.
  surprised,

  /// Злость: angry brows and a red mark — an overdue payment or a limit.
  angry,
}

/// Russian names of the emotions, as on the owner's sheet.
const finoraMoodNames = <FinoraMood, String>{
  FinoraMood.idle: 'Обычное',
  FinoraMood.greeting: 'Приветствие',
  FinoraMood.happy: 'Радость',
  FinoraMood.pleasure: 'Удовольствие',
  FinoraMood.wink: 'Уверенность',
  FinoraMood.delight: 'Восторг',
  FinoraMood.thinking: 'Размышление',
  FinoraMood.doubt: 'Сомнение',
  FinoraMood.processing: 'Обработка',
  FinoraMood.idea: 'Идея',
  FinoraMood.done: 'Готово',
  FinoraMood.calm: 'Спокойствие',
  FinoraMood.support: 'Поддержка',
  FinoraMood.attention: 'Внимание',
  FinoraMood.error: 'Ошибка',
  FinoraMood.sleep: 'Ожидание',
  FinoraMood.surprised: 'Удивление',
  FinoraMood.angry: 'Злость',
};

/// Finora herself: the same mint bubble on every theme.
class FinoraOrbPainter extends CustomPainter {
  FinoraOrbPainter({
    required this.t,
    this.mood = FinoraMood.idle,
    this.blink = 0,
    this.joy = 0,
    this.face = true,
    this.sign = true,
    // Kept for callers from 1.26; the theme color is [theme] (1.36).
    Color? base,
    Color? accent,
    bool? dark,
  }) : _painted = _theme;

  /// The theme color this painter draws with.
  final Color _painted;

  /// Position in the drift loop, 0…1.
  final double t;
  final FinoraMood mood;

  /// 0 open … 1 closed.
  final double blink;

  /// Rings of joy spreading out, 0 (none) … 1 (gone).
  final double joy;
  final bool face;

  /// The small sign beside her (heart, «?», «Zzz»…).
  final bool sign;

  /// Her own color: mint.
  static const original = Color(0xFF3FE0C2);

  /// 1.36: Finora takes the theme's color (set by the app from the accent;
  /// [original] when the person keeps her mint).
  static Color get theme => _theme;
  static set theme(Color value) {
    if (value == _theme) return;
    _theme = value;
    _palette = _derive(value);
  }

  static Color _theme = original;
  static _Palette _palette = _derive(original);

  static _Palette _derive(Color base) {
    final h = HSLColor.fromColor(base);
    final s = h.saturation.clamp(.5, .9);
    HSLColor at(double sat, double light) =>
        HSLColor.fromAHSL(1, h.hue, sat.clamp(0.0, 1.0), light);
    return _Palette(
      mint: at(s, .56).toColor(),
      deep: at(s, .35).toColor(),
      light: at(s, .9).toColor(),
      mid: at(s, .68).toColor(),
      shade: at(s, .3).toColor(),
    );
  }

  static Color get mint => _palette.mint;
  static Color get _deep => _palette.deep;
  static Color get _light => _palette.light;
  static const _pink = Color(0xFFFF7FB0);
  static const _ink = Color(0xFF0A2730);

  @override
  void paint(Canvas canvas, Size size) {
    final r0 = size.width / 2;
    final c = Offset(r0, r0);
    final a = t * 2 * math.pi;
    final r = r0 * (1 + .025 * math.sin(a * 2));

    if (joy > 0 && joy < 1) {
      for (final delay in [0.0, .22]) {
        final p = ((joy - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (p <= 0 || p >= 1) continue;
        canvas.drawCircle(
          c,
          r * (1 + .75 * Curves.easeOutCubic.transform(p)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .08 * (1 - p)
            ..color = mint.withValues(alpha: .55 * (1 - p)),
        );
      }
    }

    // 1.28: a soft glow that pulses with her breath (three times a loop).
    final pulse = .5 + .5 * math.sin(a * 3);
    canvas.drawCircle(
      c,
      r * (1.06 + .1 * pulse),
      Paint()
        ..color = mint.withValues(alpha: .28 + .24 * pulse)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          r * (.22 + .12 * pulse),
        ),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    // Body: light at the upper right, deep at the lower edge.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.3, -.35),
          radius: 1.05,
          colors: [_light, _palette.mid, mint, _deep],
          stops: [0, .32, .7, 1],
        ).createShader(rect),
    );
    // Pink and lilac blush drifting on the upper left.
    void cloud(Offset at, double radius, Color color, double alpha) {
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: radius)),
      );
    }

    final drift = Offset(math.cos(a), math.sin(a * 1.3)) * r * .05;
    cloud(c + Offset(-r * .55, -r * .25) + drift, r * .66, _pink, .95);
    cloud(
      c + Offset(-r * .15, -r * .62) - drift,
      r * .45,
      const Color(0xFFC6A4FF),
      .35,
    );
    cloud(c + Offset(r * .35, r * .55), r * .7, _palette.shade, .35);
    // Gloss.
    final gloss = Rect.fromCenter(
      center: c + Offset(r * .08, -r * .6),
      width: r * 1.1,
      height: r * .5,
    );
    canvas.drawOval(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(gloss),
    );
    canvas.restore();
    // Rim light and a bright spot.
    canvas.drawCircle(
      c,
      r * .985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .035
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: .05),
            Colors.white.withValues(alpha: .6),
            Colors.white.withValues(alpha: .05),
            Colors.white.withValues(alpha: .25),
            Colors.white.withValues(alpha: .05),
          ],
        ).createShader(rect),
    );
    canvas.save();
    canvas.translate(c.dx + r * .5, c.dy - r * .48);
    canvas.rotate(.7);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * .22, height: r * .1),
      Paint()..color = Colors.white.withValues(alpha: .8),
    );
    canvas.restore();

    if (face) _face(canvas, c, r);
    if (sign) _sign(canvas, c, r);
  }

  void _face(Canvas canvas, Offset c, double r) {
    final ink = Paint()..color = _ink;
    Paint stroke(double w) => Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * w;
    final look = switch (mood) {
      FinoraMood.thinking => Offset(r * .06, -r * .06),
      FinoraMood.doubt || FinoraMood.error => Offset(0, r * .02),
      _ => Offset(math.sin(t * 2 * math.pi) * r * .025, 0),
    };
    final eyeY = c.dy - r * .06;
    final left = Offset(c.dx - r * .3, eyeY) + look;
    final right = Offset(c.dx + r * .3, eyeY) + look;

    void open(Offset at, {double scale = 1}) {
      final h = r * .3 * scale * (1 - blink * .9);
      final w = r * .23 * scale;
      canvas.drawOval(Rect.fromCenter(center: at, width: w, height: h), ink);
      if (h > r * .1) {
        final hl = Paint()..color = Colors.white.withValues(alpha: .95);
        canvas.drawCircle(at + Offset(w * .2, -h * .22), w * .26, hl);
        canvas.drawCircle(
          at + Offset(-w * .2, h * .22),
          w * .12,
          Paint()..color = Colors.white.withValues(alpha: .7),
        );
      }
    }

    void closed(Offset at) {
      final w = r * .13;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx - w, at.dy)
          ..quadraticBezierTo(at.dx, at.dy + r * .11, at.dx + w, at.dy),
        stroke(.055),
      );
    }

    void squint(Offset at) {
      final w = r * .12;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx - w, at.dy + r * .03)
          ..quadraticBezierTo(
            at.dx,
            at.dy - r * .1,
            at.dx + w,
            at.dy + r * .03,
          ),
        stroke(.055),
      );
    }

    void smile({double width = .13, double depth = .11}) {
      final y = c.dy + r * .24;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * width, y)
          ..quadraticBezierTo(c.dx, y + r * depth, c.dx + r * width, y),
        stroke(.05),
      );
    }

    void openSmile({double width = .16, double depth = .22}) {
      final y = c.dy + r * .2;
      final mouth = Path()
        ..moveTo(c.dx - r * width, y)
        ..quadraticBezierTo(c.dx, y - r * .02, c.dx + r * width, y)
        ..quadraticBezierTo(
          c.dx + r * width * .9,
          y + r * depth,
          c.dx,
          y + r * depth,
        )
        ..quadraticBezierTo(
          c.dx - r * width * .9,
          y + r * depth,
          c.dx - r * width,
          y,
        )
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xFF3B0F1F));
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, y + r * depth * .95),
          width: r * width * 1.3,
          height: r * depth * .8,
        ),
        Paint()..color = const Color(0xFFFF6F8F),
      );
      canvas.restore();
    }

    void frown() {
      final y = c.dy + r * .33;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * .12, y)
          ..quadraticBezierTo(c.dx, y - r * .12, c.dx + r * .12, y),
        stroke(.05),
      );
    }

    void oMouth({double scale = 1}) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + r * .3),
          width: r * .09 * scale,
          height: r * .11 * scale,
        ),
        ink,
      );
    }

    void brows({required bool angry}) {
      for (final s in [-1.0, 1.0]) {
        final outer = Offset(c.dx + s * r * .44, eyeY - r * (angry ? .3 : .22));
        final inner = Offset(c.dx + s * r * .17, eyeY - r * (angry ? .19 : .3));
        canvas.drawLine(outer + look, inner + look, stroke(angry ? .055 : .04));
      }
    }

    void blush({bool lines = false}) {
      for (final s in [-1.0, 1.0]) {
        final at = Offset(c.dx + s * r * .47, c.dy + r * .14);
        if (lines) {
          for (var i = -1; i <= 1; i++) {
            canvas.drawLine(
              at + Offset(i * r * .07 - r * .03, r * .04),
              at + Offset(i * r * .07 + r * .03, -r * .04),
              Paint()
                ..color = const Color(0xFFFF5C8A)
                ..strokeWidth = r * .03
                ..strokeCap = StrokeCap.round,
            );
          }
        } else {
          canvas.drawOval(
            Rect.fromCenter(center: at, width: r * .24, height: r * .12),
            Paint()
              ..color = const Color(0xFFFF6B95).withValues(alpha: .45)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .04),
          );
        }
      }
    }

    switch (mood) {
      case FinoraMood.idle || FinoraMood.greeting || FinoraMood.done:
        open(left);
        open(right);
        smile();
      case FinoraMood.happy || FinoraMood.idea:
        open(left);
        open(right);
        openSmile();
      case FinoraMood.delight:
        open(left, scale: 1.08);
        open(right, scale: 1.08);
        openSmile(width: .2, depth: .27);
      case FinoraMood.pleasure:
        open(left);
        open(right);
        smile(width: .11, depth: .09);
        blush(lines: true);
      case FinoraMood.wink:
        open(left);
        squint(right);
        smile();
      case FinoraMood.thinking:
        open(left, scale: .95);
        open(right, scale: .95);
        oMouth(scale: .8);
      case FinoraMood.doubt:
        open(left, scale: .95);
        open(right, scale: .95);
        brows(angry: false);
        frown();
      case FinoraMood.processing || FinoraMood.sleep:
        closed(left);
        closed(right);
        oMouth(scale: .8);
      case FinoraMood.calm:
        closed(left);
        closed(right);
        smile(width: .1, depth: .08);
      case FinoraMood.support:
        open(left);
        open(right);
        smile(width: .11, depth: .08);
        blush();
      case FinoraMood.attention:
        open(left, scale: .95);
        open(right, scale: .95);
        oMouth(scale: .85);
      case FinoraMood.error:
        open(left, scale: .95);
        open(right, scale: .95);
        brows(angry: false);
        frown();
      case FinoraMood.surprised:
        open(left, scale: 1.2);
        open(right, scale: 1.2);
        oMouth(scale: 1.5);
      case FinoraMood.angry:
        open(left, scale: .9);
        open(right, scale: .9);
        brows(angry: true);
        frown();
    }
  }

  /// The small neon sign beside her.
  void _sign(Canvas canvas, Offset c, double r) {
    final top = c + Offset(r * .86, -r * .86);
    final bottom = c + Offset(r * .78, r * .72);
    void neon(Path path, Color color, {bool fill = false, double width = .07}) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .55)
          ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = r * width * 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .06),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(color, Colors.white, .25)!
          ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = r * width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Signs are drawn as lines, never with a font.
    Path bang(Offset at, double s) => Path()
      ..moveTo(at.dx, at.dy - s)
      ..lineTo(at.dx, at.dy + s * .35)
      ..moveTo(at.dx, at.dy + s * .85)
      ..lineTo(at.dx, at.dy + s * .86);
    Path question(Offset at, double s) => Path()
      ..moveTo(at.dx - s * .55, at.dy - s * .45)
      ..cubicTo(
        at.dx - s * .55,
        at.dy - s * 1.15,
        at.dx + s * .6,
        at.dy - s * 1.15,
        at.dx + s * .55,
        at.dy - s * .45,
      )
      ..cubicTo(
        at.dx + s * .5,
        at.dy - s * .05,
        at.dx,
        at.dy,
        at.dx,
        at.dy + s * .35,
      )
      ..moveTo(at.dx, at.dy + s * .85)
      ..lineTo(at.dx, at.dy + s * .86);
    Path zed(Offset at, double s) => Path()
      ..moveTo(at.dx - s * .5, at.dy - s * .5)
      ..lineTo(at.dx + s * .5, at.dy - s * .5)
      ..lineTo(at.dx - s * .5, at.dy + s * .5)
      ..lineTo(at.dx + s * .5, at.dy + s * .5);
    Path heart(Offset at, double s) => Path()
      ..moveTo(at.dx, at.dy + s * .35)
      ..cubicTo(
        at.dx - s * .9,
        at.dy - s * .2,
        at.dx - s * .35,
        at.dy - s * .75,
        at.dx,
        at.dy - s * .3,
      )
      ..cubicTo(
        at.dx + s * .35,
        at.dy - s * .75,
        at.dx + s * .9,
        at.dy - s * .2,
        at.dx,
        at.dy + s * .35,
      );
    Path sparks() {
      final p = Path();
      for (final angle in [-1.35, -.95, -.55]) {
        final d = Offset(math.cos(angle), math.sin(angle));
        p
          ..moveTo(c.dx + d.dx * r * 1.12, c.dy + d.dy * r * 1.12)
          ..lineTo(c.dx + d.dx * r * 1.38, c.dy + d.dy * r * 1.38);
      }
      return p;
    }

    const red = Color(0xFFFF4D6D);
    const yellow = Color(0xFFFFD43B);
    const white = Color(0xFFDFFFF8);
    switch (mood) {
      case FinoraMood.greeting:
        neon(sparks(), white);
      case FinoraMood.delight:
        neon(sparks(), yellow);
      case FinoraMood.pleasure:
        neon(heart(top, r * .42), red);
      case FinoraMood.wink:
        final s = r * .26;
        neon(
          Path()
            ..moveTo(top.dx, top.dy - s)
            ..quadraticBezierTo(top.dx, top.dy, top.dx + s, top.dy)
            ..quadraticBezierTo(top.dx, top.dy, top.dx, top.dy + s)
            ..quadraticBezierTo(top.dx, top.dy, top.dx - s, top.dy)
            ..quadraticBezierTo(top.dx, top.dy, top.dx, top.dy - s)
            ..close(),
          yellow,
          width: .05,
        );
      case FinoraMood.thinking:
        neon(question(top, r * .32), white, width: .075);
      case FinoraMood.processing:
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            top + Offset(i * r * .2 - r * .05, r * .1),
            r * .065,
            Paint()..color = white,
          );
        }
      case FinoraMood.idea:
        final s = r * .2;
        neon(
          Path()
            ..addOval(Rect.fromCircle(center: top, radius: s))
            ..moveTo(top.dx - s * .45, top.dy + s * 1.35)
            ..lineTo(top.dx + s * .45, top.dy + s * 1.35)
            ..moveTo(top.dx - s * .35, top.dy + s * 1.7)
            ..lineTo(top.dx + s * .35, top.dy + s * 1.7),
          yellow,
          width: .045,
        );
        for (final angle in [-2.4, -1.57, -.75, 0.0, -3.14]) {
          final d = Offset(math.cos(angle), math.sin(angle));
          neon(
            Path()
              ..moveTo(top.dx + d.dx * s * 1.5, top.dy + d.dy * s * 1.5)
              ..lineTo(top.dx + d.dx * s * 2, top.dy + d.dy * s * 2),
            yellow,
            width: .04,
          );
        }
      case FinoraMood.done:
        final s = r * .26;
        canvas.drawCircle(
          bottom,
          s * 1.1,
          Paint()..color = const Color(0xFF103B35),
        );
        neon(
          Path()..addOval(Rect.fromCircle(center: bottom, radius: s)),
          const Color(0xFF34D399),
          width: .05,
        );
        neon(
          Path()
            ..moveTo(bottom.dx - s * .45, bottom.dy)
            ..lineTo(bottom.dx - s * .1, bottom.dy + s * .35)
            ..lineTo(bottom.dx + s * .5, bottom.dy - s * .35),
          const Color(0xFF34D399),
          width: .055,
        );
      case FinoraMood.support:
        neon(heart(bottom, r * .4), red);
      case FinoraMood.attention:
        neon(
          bang(top + Offset(-r * .1, 0), r * .3)
            ..addPath(bang(top + Offset(r * .12, 0), r * .3), Offset.zero),
          yellow,
          width: .075,
        );
      case FinoraMood.surprised:
        neon(bang(top, r * .34), yellow, width: .085);
      case FinoraMood.error:
        final s = r * .3;
        neon(
          Path()
            ..moveTo(bottom.dx, bottom.dy - s)
            ..lineTo(bottom.dx + s * 1.05, bottom.dy + s * .75)
            ..lineTo(bottom.dx - s * 1.05, bottom.dy + s * .75)
            ..close(),
          red,
          width: .05,
        );
        neon(bang(bottom + Offset(0, s * .15), s * .45), red, width: .045);
      case FinoraMood.sleep:
        const blue = Color(0xFF5AA9FF);
        neon(zed(top + Offset(-r * .32, r * .18), r * .16), blue, width: .045);
        neon(zed(top + Offset(-r * .04, -r * .02), r * .22), blue, width: .05);
        neon(zed(top + Offset(r * .3, -r * .28), r * .28), blue, width: .055);
      case FinoraMood.angry:
        final s = r * .14;
        final mark = Path();
        for (final q in [
          const Offset(-1, -1),
          const Offset(1, -1),
          const Offset(1, 1),
          const Offset(-1, 1),
        ]) {
          final at = top + Offset(q.dx * s, q.dy * s);
          mark
            ..moveTo(at.dx, at.dy + q.dy * s * .8)
            ..quadraticBezierTo(at.dx, at.dy, at.dx + q.dx * s * .8, at.dy);
        }
        neon(mark, red, width: .06);
      case FinoraMood.idle ||
          FinoraMood.calm ||
          FinoraMood.doubt ||
          FinoraMood.happy:
        break;
    }
  }

  @override
  bool shouldRepaint(FinoraOrbPainter old) =>
      old._painted != _theme ||
      old.t != t ||
      old.mood != mood ||
      old.blink != blink ||
      old.joy != joy ||
      old.face != face ||
      old.sign != sign;
}

/// A still Finora, for headers and «О приложении».
class FinoraMark extends StatelessWidget {
  const FinoraMark({super.key, this.size = 56, this.mood = FinoraMood.idle});
  final double size;
  final FinoraMood mood;
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: FinoraOrbPainter(t: 0, mood: mood),
    );
  }
}

/// Finora as a character (welcome screens): floats, blinks, drifts and
/// changes mood with a little hop; a tap makes it glad.
class FinoraCharacter extends StatefulWidget {
  const FinoraCharacter({
    super.key,
    this.size = 120,
    this.moods = const [FinoraMood.idle],
    this.step = const Duration(milliseconds: 1600),
    this.loop = false,
    this.rings = true,
  });
  final double size;

  /// Moods shown one after another; the last one stays unless [loop].
  final List<FinoraMood> moods;
  final Duration step;
  final bool loop;

  /// 1.36: the rings of joy around her on a hop (off on the loading screen).
  final bool rings;

  @override
  State<FinoraCharacter> createState() => FinoraCharacterState();
}

class FinoraCharacterState extends State<FinoraCharacter>
    with TickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Timer? _moods, _blinks;
  int _i = 0;
  FinoraMood? _override;

  FinoraMood get mood => _override ?? widget.moods[_i];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(FinoraCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moods != widget.moods) {
      _i = 0;
      _override = null;
      _start();
    }
  }

  void _start() {
    _moods?.cancel();
    _blinks?.cancel();
    // Pops in.
    if (!Motion.reduced(context)) _hop.forward(from: 0);
    if (!Motion.ambient(context)) {
      _flow.stop();
      // Without motion it shows the mood it ends on.
      _i = widget.moods.length - 1;
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    if (widget.moods.length > 1) {
      _moods = Timer.periodic(widget.step, (timer) {
        if (!mounted) return;
        if (_i == widget.moods.length - 1 && !widget.loop) {
          timer.cancel();
          return;
        }
        setState(() => _i = (_i + 1) % widget.moods.length);
        _hop.forward(from: 0);
      });
    }
    _blinks = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!mounted || mood != FinoraMood.idle) return;
      _blink.forward(from: 0).then((_) {
        if (mounted) _blink.reverse();
      });
    });
  }

  /// A glad hop, as when it is tapped.
  void cheer() {
    setState(() => _override = FinoraMood.happy);
    _hop.forward(from: 0);
    Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _override = null);
    });
  }

  @override
  void dispose() {
    _moods?.cancel();
    _blinks?.cancel();
    _flow.dispose();
    _hop.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return GestureDetector(
      onTap: cheer,
      child: AnimatedBuilder(
        animation: Listenable.merge([_flow, _hop, _blink]),
        builder: (context, _) {
          final h = _hop.value;
          final float = math.sin(_flow.value * 2 * math.pi * 2) * size * .03;
          return Transform.translate(
            offset: Offset(0, float - hopHeight(h) * size * .16),
            child: Transform.rotate(
              angle: wiggle(h) * .14,
              child: Transform.scale(
                scale: bounce(h),
                child: CustomPaint(
                  size: Size.square(size),
                  painter: FinoraOrbPainter(
                    t: _flow.value,
                    mood: mood,
                    blink: _blink.value,
                    joy: h == 0 || !widget.rings ? 0 : h,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Squash and stretch over a hop, 0…1 → scale.
double bounce(double t) {
  if (t <= 0 || t >= 1) return 1;
  if (t < .18) return 1 + .2 * Curves.easeOut.transform(t / .18);
  if (t < .38) return 1.2 - .3 * Curves.easeInOut.transform((t - .18) / .2);
  if (t < .58) return .9 + .16 * Curves.easeInOut.transform((t - .38) / .2);
  if (t < .78) return 1.06 - .09 * Curves.easeInOut.transform((t - .58) / .2);
  return .97 + .03 * Curves.easeOut.transform((t - .78) / .22);
}

/// Height of the hop, 0…1.
double hopHeight(double t) =>
    t <= 0 || t >= .5 ? 0 : math.sin(t / .5 * math.pi);

/// A shake that fades out.
double wiggle(double t) =>
    t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi * 5) * (1 - t);

/// One of Finora's reactions: a mood for a few seconds and, maybe, a line.
class FinoraReaction {
  const FinoraReaction(this.mood, {this.text, required this.hold});
  final FinoraMood mood;
  final String? text;
  final Duration hold;
}

/// Finora reacts to what happens in the app (1.27): her face in the bottom
/// bar changes, she hops (or shakes when angry), says a short line above
/// herself and the phone answers with a matching tap.
abstract final class Finora {
  static final reactions = ValueNotifier<FinoraReaction?>(null);

  static void react(
    FinoraMood mood, {
    String? text,
    Duration hold = const Duration(milliseconds: 3600),
  }) {
    reactions.value = FinoraReaction(mood, text: text, hold: hold);
    switch (mood) {
      case FinoraMood.angry || FinoraMood.error || FinoraMood.attention:
        unawaited(Haptics.warning());
      case FinoraMood.surprised:
        Haptics.heavy();
      case FinoraMood.happy ||
          FinoraMood.delight ||
          FinoraMood.done ||
          FinoraMood.pleasure:
        unawaited(Haptics.success());
      default:
        Haptics.light();
    }
  }
}

class _Palette {
  const _Palette({
    required this.mint,
    required this.deep,
    required this.light,
    required this.mid,
    required this.shade,
  });
  final Color mint, deep, light, mid, shade;
}
