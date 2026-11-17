import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../l10n_widgets.dart';
import 'motion.dart';

/// A short, quiet celebration over the screen when something is done —
/// a payment confirmed, paid early, a transfer made: a disc blooms, a check
/// draws itself, a ring spreads out, a caption fades in; then it all fades
/// away by itself (about 1.4 s). It never blocks touches.
abstract final class SuccessBurst {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String title, {String? subtitle}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Burst(
        title: title,
        subtitle: subtitle,
        reduced: Motion.reduced(context),
        onDone: () {
          if (_entry == entry) _entry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _Burst extends StatefulWidget {
  const _Burst({
    required this.title,
    required this.subtitle,
    required this.reduced,
    required this.onDone,
  });
  final String title;
  final String? subtitle;
  final bool reduced;
  final VoidCallback onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduced ? 900 : 1500),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
              curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          // In: 0–.25 bloom, .2–.5 check, .15–.6 ring; out: .8–1.
          final bloom = widget.reduced ? 1.0 : seg(0, .25, Curves.easeOutBack);
          final check = widget.reduced ? 1.0 : seg(.2, .5);
          final ring = seg(.15, .65);
          final out = 1 - seg(.8, 1, Curves.easeIn);
          final caption = seg(.3, .55) * out;
          return Opacity(
            opacity: out,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 150,
                    child: CustomPaint(
                      painter: _BurstPainter(
                        color: scheme.primary,
                        ink: scheme.onPrimary,
                        bloom: bloom,
                        check: check,
                        ring: widget.reduced ? 0 : ring,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: caption,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - caption)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: ShapeDecoration(
                          color: scheme.surface,
                          shape: const StadiumBorder(),
                          shadows: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({
    required this.color,
    required this.ink,
    required this.bloom,
    required this.check,
    required this.ring,
  });
  final Color color, ink;
  final double bloom, check, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .3;
    // The spreading ring.
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        c,
        r * (1 + ring * .9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - ring) + .5
          ..color = color.withValues(alpha: .5 * (1 - ring)),
      );
    }
    // The disc, with a soft glow.
    final disc = r * bloom;
    if (disc <= 0) return;
    canvas
      ..drawCircle(
        c,
        disc * 1.15,
        Paint()
          ..color = color.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      )
      ..drawCircle(
        c,
        disc,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.3, -.4),
            colors: [Color.lerp(color, Colors.white, .25)!, color],
          ).createShader(Rect.fromCircle(center: c, radius: disc)),
      );
    // The check, drawn stroke by stroke.
    if (check <= 0) return;
    final a = c + Offset(-r * .42, r * .02);
    final b = c + Offset(-r * .12, r * .32);
    final e = c + Offset(r * .46, -r * .3);
    final first = (b - a).distance, second = (e - b).distance;
    final len = (first + second) * check;
    final path = Path()..moveTo(a.dx, a.dy);
    if (len <= first) {
      final p = a + (b - a) * (len / first);
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = b + (e - b) * math.min(1, (len - first) / second);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.bloom != bloom ||
      old.check != check ||
      old.ring != ring ||
      old.color != color;
}
