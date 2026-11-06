import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

/// The round voice button in the middle of the bottom bar (Finance 1.20):
/// a living orb in the theme colors, after ChatGPT's voice mode — soft color
/// clouds drift inside it and it breathes slightly.
///
/// Tap: voice entry. Long press: an ordinary new operation.
///
/// It moves only while the app is in use: any touch wakes it, and ten
/// seconds after the last touch it settles and stops, so an idle screen still
/// draws no frames (and it is still with «reduce motion» and in tests).
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.size = 56,
  });
  final VoidCallback onTap, onLongPress;
  final double size;

  /// Bumped by the app shell on every touch to wake the orb.
  static final activity = ValueNotifier<int>(0);

  static const idle = Duration(seconds: 10);

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  Timer? _rest;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    VoiceOrb.activity.addListener(_wake);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wake();
  }

  void _wake() {
    if (!mounted) return;
    if (!Motion.ambient(context)) {
      _flow.stop();
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    _rest?.cancel();
    _rest = Timer(VoiceOrb.idle, () {
      if (!mounted) return;
      // Settle at the end of the current loop instead of freezing mid-swirl.
      final left = (1 - _flow.value) * _flow.duration!.inMilliseconds;
      _flow
          .animateTo(
            1,
            duration: Duration(milliseconds: left.round().clamp(1, 7000)),
          )
          .whenComplete(() {
            if (mounted && !_flow.isAnimating) _flow.value = 0;
          });
    });
  }

  @override
  void dispose() {
    VoiceOrb.activity.removeListener(_wake);
    _rest?.cancel();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    return Semantics(
      label: 'Голосовой ввод операции',
      hint: 'Удерживайте, чтобы добавить операцию вручную',
      button: true,
      child: Tooltip(
        message: 'Голосом · удерживайте для ручного ввода',
        child: GestureDetector(
          key: const ValueKey('nav-voice'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onLongPress: () {
            setState(() => _pressed = false);
            HapticFeedback.mediumImpact();
            widget.onLongPress();
          },
          child: AnimatedScale(
            scale: _pressed ? .92 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _flow,
                builder: (context, _) => CustomPaint(
                  size: Size.square(size),
                  painter: _OrbPainter(
                    t: _flow.value,
                    base: scheme.primary,
                    accent: scheme.tertiary,
                    light: Colors.white,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                  child: SizedBox.square(
                    dimension: size,
                    child: Icon(
                      Icons.mic_rounded,
                      size: size * .38,
                      // Readable on a light orb (light themes) and a dark one.
                      color: scheme.primary.computeLuminance() > .45
                          ? Colors.black.withValues(alpha: .75)
                          : Colors.white.withValues(alpha: .92),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A matte sphere of soft color: a deep base and three drifting clouds,
/// clipped to the circle.
class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.t,
    required this.base,
    required this.accent,
    required this.light,
    required this.dark,
  });
  final double t;
  final Color base, accent, light;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final a = t * 2 * math.pi;
    final breathe = 1 + .035 * math.sin(a * 2);
    final radius = r * breathe;

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
    // Base: deep at the bottom, lighter at the top.
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
    // Drifting clouds.
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

    // Matte, cloud-like (no gloss): three soft clouds drift and overlap.
    cloud(accent, .9, .45, 0, 1.0);
    cloud(Color.lerp(base, light, .6)!, .8, .40, 2.4, .85);
    cloud(light, .55, .34, 4.2, .6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.base != base ||
      old.accent != accent ||
      old.dark != dark;
}
