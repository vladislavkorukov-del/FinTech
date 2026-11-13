part of 'flow_board.dart';

/// 1.62: the paper-plane drone. Its art (Finora_Match3_Drone) points its
/// nose up and to the right, so a heading along a path is that path's
/// angle plus a quarter turn back.
abstract final class _Drone {
  static const art = 'match3_drone';
  static const noseAngle = -math.pi / 4;

  /// Where a plane on a flight is at [t] (0..1), its heading and its size.
  static ({Offset at, double angle, double scale}) pose(
    Offset from,
    Offset to,
    double pitch,
    double t,
  ) {
    final d = to - from;
    final length = math.max(1.0, d.distance);
    // The arc always bows upward, more on long flights.
    var normal = Offset(-d.dy, d.dx) / length;
    if (normal.dy > 0) normal = -normal;
    final control =
        (from + to) / 2 + normal * math.max(pitch * 1.3, length * .38);
    final u = 1 - t;
    final at = from * (u * u) + control * (2 * u * t) + to * (t * t);
    final tangent = (control - from) * (2 * u) + (to - control) * (2 * t);
    // Lift-off, a little larger in the air, a dive into the target.
    final scale = t < .25
        ? 1 + .32 * Curves.easeOut.transform(t / .25)
        : t < .8
        ? 1.32
        : 1.32 - .5 * Curves.easeIn.transform((t - .8) / .2);
    return (
      at: at,
      angle: math.atan2(tangent.dy, tangent.dx) - noseAngle,
      scale: scale,
    );
  }
}

/// The drone resting on the board: it hovers and tilts a little, as if
/// held by air; still under reduced motion.
class _DroneIdle extends StatefulWidget {
  const _DroneIdle({required this.seed});
  final int seed;
  @override
  State<_DroneIdle> createState() => _DroneIdleState();
}

class _DroneIdleState extends State<_DroneIdle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(
      animation: _c,
      // Neighbouring drones do not move in step.
      builder: (context, child) {
        final a = (_c.value + widget.seed * .137) * math.pi * 2;
        return Transform.translate(
          offset: Offset(0, math.sin(a) * box.maxHeight * .045),
          child: Transform.rotate(angle: math.sin(a + .9) * .07, child: child),
        );
      },
      child: const FlowSprite(_Drone.art, trim: false),
    ),
  );
}

/// A plane in flight: soft sparkles left behind along the arc.
class _TrailPainter extends CustomPainter {
  const _TrailPainter(this.points);
  final List<(Offset, double)> points;
  @override
  void paint(Canvas canvas, Size size) {
    for (final (at, k) in points) {
      canvas.drawCircle(
        at,
        2.6 * k + .8,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF7AE0C8),
            Colors.white,
            k,
          )!.withValues(alpha: .85 * k)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => true;
}
