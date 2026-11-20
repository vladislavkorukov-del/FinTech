import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart' show HapticFeedback;

import '../l10n_widgets.dart';
import 'motion.dart';

/// Confirmation of a payment, in the manner of a phone wallet: a sheet
/// rises from the bottom with a small card and the payment, a ring spins
/// while it «goes through», closes into a full circle and a check draws
/// itself, «Оплачено» appears — then the sheet slides away by itself
/// (about 2 s). It never blocks touches.
///
/// Get the overlay with [overlayOf] *before* awaiting the payment and pass
/// it to [show]: the widget that started the payment may be rebuilt away
/// by then (a paid row moves to its next date).
abstract final class SuccessBurst {
  static OverlayEntry? _entry;

  static OverlayState? overlayOf(BuildContext context) =>
      Overlay.maybeOf(context, rootOverlay: true);

  static void show(
    BuildContext? context,
    String title, {
    String? subtitle,
    OverlayState? overlay,
  }) {
    final target = overlay ?? (context == null ? null : overlayOf(context));
    if (target == null || !target.mounted) return;
    final reduced = context != null && context.mounted
        ? Motion.reduced(context)
        : MediaQuery.maybeDisableAnimationsOf(target.context) ?? false;
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PaySheet(
        title: title,
        subtitle: subtitle,
        reduced: reduced,
        onDone: () {
          if (_entry == entry) _entry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    target.insert(entry);
  }
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({
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
  State<_PaySheet> createState() => _PaySheetState();
}

/// The payment, Apple Pay style: a dark glass sheet rises over a blurred
/// screen; the card sits in it, tilted towards the reader, a light sweep
/// crosses it while contactless waves pulse; the card settles, a ring
/// draws round and fills, a bold check is drawn in it with a soft tap of
/// haptics; «Оплачено» and the sum fade in; the sheet goes away by itself.
class _PaySheetState extends State<_PaySheet>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduced ? 1100 : 2500),
  );
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_buzzed && _c.value >= .56) {
        _buzzed = true;
        HapticFeedback.mediumImpact();
      }
    });
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
    final accent = Theme.of(context).colorScheme.primary;
    const sheet = Color(0xF21C1C1E);
    const ink = Colors.white;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
              widget.reduced
              ? 1.0
              : curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          // Rise .0–.14 · card .06–.4 · sweep .14–.46 · waves .14–.5 ·
          // card settles .46–.58 · ring .5–.64 · fill .58–.68 · check
          // .6–.74 · caption .66–.8 · out .9–1.
          final rise = seg(0, .14, Curves.easeOutQuart);
          final out = widget.reduced ? 0.0 : seg(.9, 1, Curves.easeInCubic);
          final card = seg(.06, .4, Curves.easeOutBack);
          final sweep = widget.reduced
              ? 1.0
              : ((t - .14) / .32).clamp(0.0, 1.0);
          final waves = widget.reduced
              ? 0.0
              : ((t - .14) / .36).clamp(0.0, 1.0);
          final settle = seg(.46, .58, Curves.easeInOutCubic);
          final ring = seg(.5, .64);
          final fill = seg(.58, .68, Curves.easeOutBack);
          final check = seg(.6, .74);
          final caption = seg(.66, .8);
          final veil = rise * (1 - out);
          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8 * veil, sigmaY: 8 * veil),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .38 * veil),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionalTranslation(
                  translation: Offset(0, (1 - rise) + out),
                  child: Container(
                    key: const ValueKey('pay-sheet'),
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    padding: EdgeInsets.fromLTRB(
                      22,
                      12,
                      22,
                      26 + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: BoxDecoration(
                      color: sheet,
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(color: Colors.white10, width: .6),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66000000), blurRadius: 40),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.subtitle ?? widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ink,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 150,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // The card: tilted in, then settles and steps
                              // back for the check.
                              Opacity(
                                opacity: (card * (1 - settle * .85)).clamp(
                                  0.0,
                                  1.0,
                                ),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, .0015)
                                    ..rotateX(.5 * (1 - card))
                                    ..translateByDouble(
                                      0.0,
                                      24 * (1 - card) - 10 * settle,
                                      0.0,
                                      1.0,
                                    )
                                    ..scaleByDouble(
                                      .9 + .1 * card - .12 * settle,
                                      .9 + .1 * card - .12 * settle,
                                      1.0,
                                      1.0,
                                    ),
                                  child: _PayCard(color: accent, sweep: sweep),
                                ),
                              ),
                              if (waves > 0 && waves < 1)
                                Positioned(
                                  right: 6,
                                  child: CustomPaint(
                                    size: const Size(34, 60),
                                    painter: _WavesPainter(waves),
                                  ),
                                ),
                              if (ring > 0)
                                SizedBox.square(
                                  dimension: 86,
                                  child: CustomPaint(
                                    painter: _DonePainter(
                                      color: accent,
                                      ring: ring,
                                      fill: fill,
                                      check: check,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Opacity(
                          opacity: caption,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - caption)),
                            child: Text(
                              widget.title,
                              key: const ValueKey('pay-sheet-title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.4,
                                color: ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A bank card drawn in the theme colour: depth, a chip, a contactless
/// mark and a light sweep crossing it — no real card data.
class _PayCard extends StatelessWidget {
  const _PayCard({required this.color, required this.sweep});
  final Color color;
  final double sweep;

  @override
  Widget build(BuildContext context) => Container(
    width: 210,
    height: 132,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, .18)!,
          color,
          Color.lerp(color, Colors.black, .55)!,
        ],
        stops: const [0, .45, 1],
      ),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .45),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        // The light sweep.
        Positioned.fill(
          child: FractionalTranslation(
            translation: Offset(-1.2 + 2.4 * sweep, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .28),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF3DC9A), Color(0xFFC9A44E)],
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.contactless_rounded, color: Colors.white70),
                ],
              ),
              const Spacer(),
              const Text(
                'Finora',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 70,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Contactless waves pulsing out from the card.
class _WavesPainter extends CustomPainter {
  const _WavesPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(0, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final phase = (t * 2.2 - i * .22) % 1;
      if (phase < 0) continue;
      final r = 10 + phase * 26;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -.7,
        1.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .7 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.t != t;
}

/// The done mark: a thin ring draws round, fills with the accent, and a
/// bold white check is drawn in it.
class _DonePainter extends CustomPainter {
  const _DonePainter({
    required this.color,
    required this.ring,
    required this.fill,
    required this.check,
  });
  final Color color;
  final double ring, fill, check;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (fill > 0) {
      canvas.drawCircle(c, r * fill.clamp(0, 1.08), Paint()..color = color);
    }
    if (check <= 0) return;
    final a = c + Offset(-r * .38, r * .02);
    final b = c + Offset(-r * .1, r * .3);
    final e = c + Offset(r * .42, -r * .28);
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
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DonePainter old) =>
      old.ring != ring ||
      old.fill != fill ||
      old.check != check ||
      old.color != color;
}
