part of 'flow_dialogs.dart';

/// 1.61: a short shower of confetti in the game's colors behind a victory.
class FlowConfetti extends StatefulWidget {
  const FlowConfetti({super.key});
  @override
  State<FlowConfetti> createState() => _FlowConfettiState();
}

class _FlowConfettiState extends State<FlowConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => _c.value >= 1
        ? const SizedBox.shrink()
        : CustomPaint(painter: _ConfettiPainter(_c.value)),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.t);
  final double t;
  static const _colors = [
    Color(0xFFFFC93C),
    Color(0xFF3FD6EA),
    Color(0xFFFF7FB0),
    Color(0xFF7AE0B8),
    Color(0xFFA77BF6),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final origin = Offset(size.width / 2, size.height * .32);
    for (var i = 0; i < 46; i++) {
      final angle = -math.pi / 2 + (rng.nextDouble() - .5) * math.pi * 1.1;
      final speed = size.width * (.45 + rng.nextDouble() * .55);
      final spin = rng.nextDouble() * math.pi * 6;
      final delay = rng.nextDouble() * .12;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final x = origin.dx + math.cos(angle) * speed * p;
      final y =
          origin.dy + math.sin(angle) * speed * p + size.height * 1.1 * p * p;
      final fade = (1 - p).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 4.5),
          const Radius.circular(1.5),
        ),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
