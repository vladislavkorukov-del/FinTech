import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

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

class _PaySheetState extends State<_PaySheet>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduced ? 1100 : 2100),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sheet = dark ? const Color(0xFF1C1C1E) : Colors.white;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
              curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          // In .0–.16 · spin .1–.42 · close .42–.52 · check .5–.66 ·
          // caption .56–.7 · out .86–1.
          final rise = widget.reduced ? 1.0 : seg(0, .16, Curves.easeOutQuart);
          final out = seg(.86, 1, Curves.easeInCubic);
          final close = widget.reduced ? 1.0 : seg(.42, .52);
          final check = widget.reduced ? 1.0 : seg(.5, .66);
          final caption = widget.reduced ? 1.0 : seg(.56, .7);
          final spin = t * math.pi * 5;
          return Stack(
            children: [
              // A light veil behind the sheet.
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .28 * rise * (1 - out)),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionalTranslation(
                  translation: Offset(0, (1 - rise) + out),
                  child: Container(
                    key: const ValueKey('pay-sheet'),
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      14,
                      22,
                      22 + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: BoxDecoration(
                      color: sheet,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x40000000), blurRadius: 30),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _MiniCard(color: scheme.primary),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.subtitle ?? widget.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Finora',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        SizedBox.square(
                          dimension: 78,
                          child: CustomPaint(
                            painter: _RingPainter(
                              color: scheme.primary,
                              track: scheme.onSurface.withValues(alpha: .1),
                              spin: spin,
                              close: close,
                              check: check,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Opacity(
                          opacity: caption,
                          child: Transform.translate(
                            offset: Offset(0, 6 * (1 - caption)),
                            child: Text(
                              widget.title,
                              key: const ValueKey('pay-sheet-title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
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

/// A small bank card: the theme colour with a soft sheen, a chip and two
/// lines of digits — a drawing, no real card data.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 40,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, .22)!,
          color,
          Color.lerp(color, Colors.black, .35)!,
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .35),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(7, 8, 7, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 11,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFE8C77A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          Container(
            width: 30,
            height: 2.5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The processing ring: an arc spins, then closes into a full circle and
/// a check is drawn inside it.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.color,
    required this.track,
    required this.spin,
    required this.close,
    required this.check,
  });
  final Color color, track;
  final double spin, close, check;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, stroke..color = track);
    // The arc grows from a quarter to the full circle as it closes.
    final sweep = math.pi * (.5 + 1.5 * close);
    final start = close >= 1 ? -math.pi / 2 : spin - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      stroke..color = color,
    );
    if (check <= 0) return;
    final a = c + Offset(-r * .4, r * .02);
    final b = c + Offset(-r * .1, r * .3);
    final e = c + Offset(r * .44, -r * .3);
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
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.spin != spin ||
      old.close != close ||
      old.check != check ||
      old.color != color;
}
