import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../haptics.dart';
import 'finora_orb.dart';
import '../l10n_widgets.dart';

/// One choice on the wheel.
class WheelAction {
  const WheelAction(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;
}

/// 1.37: a long press on Finora opens a ring of actions around her, like a
/// weapon wheel in a game. Slide the finger to a sector and let go, or let
/// go and tap one. Tapping outside closes it.
class FinoraWheel {
  FinoraWheel._(this._entry, this._state);

  final OverlayEntry _entry;
  final GlobalKey<_WheelState> _state;
  bool _closed = false;

  static FinoraWheel show(
    BuildContext context, {
    required List<WheelAction> actions,
    required ValueChanged<String> onSelected,
  }) {
    final key = GlobalKey<_WheelState>();
    late FinoraWheel wheel;
    final entry = OverlayEntry(
      builder: (_) => _Wheel(
        key: key,
        actions: actions,
        onSelected: (id) {
          wheel.close();
          onSelected(id);
        },
        onDismiss: () => wheel.close(),
      ),
    );
    wheel = FinoraWheel._(entry, key);
    Overlay.of(context, rootOverlay: true).insert(entry);
    return wheel;
  }

  /// The finger moved (global position) while still pressing.
  void move(Offset global) => _state.currentState?.hover(global);

  /// The finger was lifted: a sector under it is chosen, otherwise the
  /// wheel stays for a tap.
  void release(Offset global) => _state.currentState?.release(global);

  void close() {
    if (_closed) return;
    _closed = true;
    final state = _state.currentState;
    if (state == null) {
      _entry.remove();
      return;
    }
    state.hide().whenComplete(_entry.remove);
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    super.key,
    required this.actions,
    required this.onSelected,
    required this.onDismiss,
  });
  final List<WheelAction> actions;
  final ValueChanged<String> onSelected;
  final VoidCallback onDismiss;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> with SingleTickerProviderStateMixin {
  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  int? _hovered;
  Offset _center = Offset.zero;
  static const _outer = 132.0, _inner = 58.0;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> hide() => _open.reverse();

  int? _sectorAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global) - _center;
    final d = local.distance;
    if (d < _inner * .8 || d > _outer * 1.35) return null;
    // 0 at the top, clockwise.
    var a = math.atan2(local.dx, -local.dy);
    if (a < 0) a += 2 * math.pi;
    final step = 2 * math.pi / widget.actions.length;
    return ((a + step / 2) ~/ step) % widget.actions.length;
  }

  void hover(Offset global) {
    final i = _sectorAt(global);
    if (i != _hovered) {
      if (i != null) Haptics.light();
      setState(() => _hovered = i);
    }
  }

  void release(Offset global) {
    final i = _sectorAt(global);
    if (i != null) widget.onSelected(widget.actions[i].id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    _center = Offset(size.width / 2, size.height - bottom - 250);
    final n = widget.actions.length;
    final step = 2 * math.pi / n;
    final label = _hovered == null ? null : widget.actions[_hovered!].label;
    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        // 1.56: a calm, premium opening — a slight zoom and fade on the iOS
        // curve, no overshoot or spin; the actions arrive around the ring.
        final fade = _open.value;
        final t = const Cubic(.32, .72, 0, 1).transform(fade.clamp(0.0, 1.0));
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            key: const ValueKey('finora-wheel'),
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 18 * fade,
                      sigmaY: 18 * fade,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(
                            0,
                            (_center.dy / size.height) * 2 - 1,
                          ),
                          radius: 1.1,
                          colors: [
                            Colors.black.withValues(alpha: .38 * fade),
                            Colors.black.withValues(alpha: .7 * fade),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _center.dx - _outer - 20,
                top: _center.dy - _outer - 20,
                width: (_outer + 20) * 2,
                height: (_outer + 20) * 2,
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: .88 + .12 * t,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RingPainter(
                              count: n,
                              hovered: _hovered,
                              outer: _outer,
                              inner: _inner,
                              accent: scheme.primary,
                            ),
                          ),
                        ),
                        for (var i = 0; i < n; i++)
                          _item(context, i, step, scheme, fade),
                        Center(
                          child: FinoraCharacter(
                            size: 62,
                            moods: [
                              _hovered == null
                                  ? FinoraMood.thinking
                                  : FinoraMood.delight,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: _center.dy - _outer - 86,
                child: Opacity(
                  opacity: fade,
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Text(
                          label ?? 'Что сделать?',
                          key: ValueKey(label),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Проведите к действию или коснитесь его',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _item(
    BuildContext context,
    int i,
    double step,
    ColorScheme scheme,
    double open,
  ) {
    final a = step * i;
    final r = (_outer + _inner) / 2;
    const c = Offset(_outer + 20, _outer + 20);
    final p = c + Offset(math.sin(a) * r, -math.cos(a) * r);
    final hovered = _hovered == i;
    final action = widget.actions[i];
    // Each action arrives a moment after the previous one, around the ring.
    final arrive = ((open - i * .04) / .6).clamp(0.0, 1.0);
    final onAccent =
        ThemeData.estimateBrightnessForColor(scheme.primary) == Brightness.dark
        ? Colors.white
        : const Color(0xFF14110D);
    return Positioned(
      left: p.dx - 36,
      top: p.dy - 34,
      width: 72,
      height: 68,
      child: GestureDetector(
        key: ValueKey('wheel-${action.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.medium();
          widget.onSelected(action.id);
        },
        child: Opacity(
          opacity: arrive,
          child: AnimatedScale(
            scale: hovered ? 1.1 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hovered
                        ? scheme.primary
                        : Colors.white.withValues(alpha: .1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: hovered ? 0 : .16),
                      width: .8,
                    ),
                    boxShadow: hovered
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: .5),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    action.icon,
                    size: 21,
                    color: hovered ? onAccent : Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .1,
                    color: Colors.white.withValues(alpha: hovered ? 1 : .78),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.56: one ring of dark glass with light catching its edges, thin
/// separators between the actions, and the chosen sector lit from within.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.count,
    required this.hovered,
    required this.outer,
    required this.inner,
    required this.accent,
  });
  final int count;
  final int? hovered;
  final double outer, inner;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = Path()
      ..addOval(Rect.fromCircle(center: c, radius: outer))
      ..addOval(Rect.fromCircle(center: c, radius: inner))
      ..fillType = PathFillType.evenOdd;
    final bounds = Rect.fromCircle(center: c, radius: outer);
    // A soft shadow under the ring lifts it off the blurred screen.
    canvas.drawPath(
      ring.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Smoky glass, lighter at the top.
    canvas.drawPath(
      ring,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x40FFFFFF), Color(0x1AFFFFFF), Color(0x26FFFFFF)],
          stops: [0, .55, 1],
        ).createShader(bounds),
    );
    // The chosen sector, lit from within with the accent.
    if (hovered != null) {
      final step = 2 * math.pi / count;
      final start = -math.pi / 2 + step * hovered! - step / 2;
      final sector = Path()
        ..arcTo(Rect.fromCircle(center: c, radius: outer), start, step, true)
        ..arcTo(
          Rect.fromCircle(center: c, radius: inner),
          start + step,
          -step,
          false,
        )
        ..close();
      canvas.drawPath(
        sector,
        Paint()
          ..color = accent.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
      canvas.drawPath(
        sector,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: .55),
              accent.withValues(alpha: .2),
            ],
          ).createShader(bounds),
      );
    }
    // Thin separators between the actions.
    final step = 2 * math.pi / count;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .1)
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + step * i - step / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (inner + 6), c + dir * (outer - 6), line);
    }
    // Light catching the outer and inner edges of the glass.
    for (final radius in [outer - .5, inner + .5]) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = SweepGradient(
            colors: [
              Colors.white.withValues(alpha: .08),
              Colors.white.withValues(alpha: .45),
              Colors.white.withValues(alpha: .08),
              Colors.white.withValues(alpha: .22),
              Colors.white.withValues(alpha: .08),
            ],
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hovered != hovered || old.accent != accent || old.count != count;
}
