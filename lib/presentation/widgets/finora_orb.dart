import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Finora's moods (1.26): the face on the orb.
enum FinoraMood {
  /// Open eyes that blink now and then.
  calm,

  /// «^ ^» eyes, a smile and blush: glad to be called.
  happy,

  /// One eye closed.
  wink,

  /// Round eyes and an «o» mouth.
  surprised,

  /// Eyes looking up to the side, a small flat mouth.
  thinking,
}

/// Finora, the assistant: a matte orb of the theme colors with soft clouds
/// drifting inside and a small face. Used by the voice button, the welcome
/// screens and «О приложении».
class FinoraOrbPainter extends CustomPainter {
  const FinoraOrbPainter({
    required this.t,
    required this.base,
    required this.accent,
    required this.dark,
    this.mood = FinoraMood.calm,
    this.blink = 0,
    this.joy = 0,
    this.face = true,
  });

  /// Position in the drift loop, 0…1.
  final double t;
  final Color base, accent;
  final bool dark;
  final FinoraMood mood;

  /// 0 open … 1 closed.
  final double blink;

  /// Rings of joy spreading out, 0 (none) … 1 (gone).
  final double joy;
  final bool face;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final a = t * 2 * math.pi;
    final radius = r * (1 + .035 * math.sin(a * 2));
    const light = Colors.white;

    // Rings of joy.
    if (joy > 0 && joy < 1) {
      for (final delay in [0.0, .22]) {
        final p = ((joy - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (p <= 0 || p >= 1) continue;
        canvas.drawCircle(
          c,
          radius * (1 + .75 * Curves.easeOutCubic.transform(p)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .08 * (1 - p)
            ..color = Color.lerp(
              base,
              accent,
              .5,
            )!.withValues(alpha: .55 * (1 - p)),
        );
      }
    }

    // Soft halo.
    canvas.drawCircle(
      c,
      radius * 1.02,
      Paint()
        ..color = base.withValues(alpha: dark ? .35 : .28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .28),
    );
    final body = Path()..addOval(Rect.fromCircle(center: c, radius: radius));
    canvas.save();
    canvas.clipPath(body);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, light, .18)!,
            Color.lerp(base, Colors.black, .28)!,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    void cloud(
      Color color,
      double alpha,
      double orbit,
      double phase,
      double scale,
    ) {
      final p =
          c +
          Offset(math.cos(a + phase), math.sin(a * 1.3 + phase)) *
              (radius * orbit);
      canvas.drawCircle(
        p,
        radius * scale,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: p, radius: radius * scale)),
      );
    }

    cloud(accent, .9, .45, 0, 1.0);
    cloud(Color.lerp(base, light, .6)!, .8, .40, 2.4, .85);
    cloud(light, .55, .34, 4.2, .6);
    canvas.restore();

    if (face) _face(canvas, c, radius);
  }

  void _face(Canvas canvas, Offset c, double r) {
    // Readable on a light orb (light themes) and a dark one.
    final ink = base.computeLuminance() > .45
        ? Colors.black.withValues(alpha: .78)
        : Colors.white.withValues(alpha: .95);
    final fill = Paint()..color = ink;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * .085;
    // A gentle look around while drifting.
    final look = mood == FinoraMood.thinking
        ? Offset(r * .07, -r * .08)
        : Offset(math.sin(t * 2 * math.pi) * r * .03, 0);
    final eyeY = c.dy - r * .08;
    final dx = r * .27;

    void open(Offset at, {double scale = 1}) {
      final h = r * .25 * scale * (1 - blink * .88);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: r * .15 * scale, height: h),
          Radius.circular(r * .08),
        ),
        fill,
      );
    }

    void glad(Offset at) {
      final w = r * .12;
      final path = Path()
        ..moveTo(at.dx - w, at.dy + r * .05)
        ..quadraticBezierTo(at.dx, at.dy - r * .16, at.dx + w, at.dy + r * .05);
      canvas.drawPath(path, line);
    }

    void smile(double depth, {double width = .17}) {
      final y = c.dy + r * .24;
      final path = Path()
        ..moveTo(c.dx - r * width, y)
        ..quadraticBezierTo(c.dx, y + r * depth, c.dx + r * width, y);
      canvas.drawPath(path, line);
    }

    final left = Offset(c.dx - dx, eyeY) + look;
    final right = Offset(c.dx + dx, eyeY) + look;
    switch (mood) {
      case FinoraMood.calm:
        open(left);
        open(right);
        smile(.1, width: .1);
      case FinoraMood.happy:
        glad(left);
        glad(right);
        smile(.24);
        final blush = Paint()
          ..color = const Color(0xFFFF6B8B).withValues(alpha: .35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .05);
        for (final s in [-1, 1]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(c.dx + s * r * .45, c.dy + r * .14),
              width: r * .22,
              height: r * .12,
            ),
            blush,
          );
        }
      case FinoraMood.wink:
        open(left);
        glad(right);
        smile(.2);
      case FinoraMood.surprised:
        open(left, scale: 1.25);
        open(right, scale: 1.25);
        canvas.drawCircle(
          Offset(c.dx, c.dy + r * .32),
          r * .08,
          line..strokeWidth = r * .07,
        );
      case FinoraMood.thinking:
        open(left, scale: .9);
        open(right, scale: .9);
        canvas.drawLine(
          Offset(c.dx - r * .06, c.dy + r * .3),
          Offset(c.dx + r * .12, c.dy + r * .27),
          line,
        );
    }
  }

  @override
  bool shouldRepaint(FinoraOrbPainter old) =>
      old.t != t ||
      old.base != base ||
      old.accent != accent ||
      old.dark != dark ||
      old.mood != mood ||
      old.blink != blink ||
      old.joy != joy ||
      old.face != face;
}

/// A still Finora, for headers and «О приложении».
class FinoraMark extends StatelessWidget {
  const FinoraMark({super.key, this.size = 56, this.mood = FinoraMood.calm});
  final double size;
  final FinoraMood mood;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: FinoraOrbPainter(
        t: 0,
        base: scheme.primary,
        accent: scheme.tertiary,
        dark: Theme.of(context).brightness == Brightness.dark,
        mood: mood,
      ),
    );
  }
}

/// Finora as a character (welcome screens): floats, blinks, drifts and
/// changes mood with a little hop; a tap makes it glad.
class FinoraCharacter extends StatefulWidget {
  const FinoraCharacter({
    super.key,
    this.size = 120,
    this.moods = const [FinoraMood.calm],
    this.step = const Duration(milliseconds: 1600),
    this.loop = false,
  });
  final double size;

  /// Moods shown one after another; the last one stays unless [loop].
  final List<FinoraMood> moods;
  final Duration step;
  final bool loop;

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
      if (!mounted || mood != FinoraMood.calm) return;
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
    final scheme = Theme.of(context).colorScheme;
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
                    base: scheme.primary,
                    accent: scheme.tertiary,
                    dark: Theme.of(context).brightness == Brightness.dark,
                    mood: mood,
                    blink: _blink.value,
                    joy: h == 0 ? 0 : h,
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
