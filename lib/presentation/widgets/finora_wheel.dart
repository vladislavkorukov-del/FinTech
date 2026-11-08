import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../controller.dart';
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
        final t = Curves.easeOutBack.transform(_open.value.clamp(0.0, 1.0));
        final fade = _open.value;
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
                      sigmaX: 6 * fade,
                      sigmaY: 6 * fade,
                    ),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .45 * fade),
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
                    scale: .6 + .4 * t,
                    child: Transform.rotate(
                      angle: (1 - t) * -.5,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RingPainter(
                                count: n,
                                hovered: _hovered,
                                outer: _outer,
                                inner: _inner,
                                fill: scheme.surface.withValues(alpha: .9),
                                accent: scheme.primary,
                                rim: scheme.onSurface.withValues(alpha: .12),
                              ),
                            ),
                          ),
                          for (var i = 0; i < n; i++)
                            _item(context, i, step, scheme),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FinoraCharacter(
                                  size: 62,
                                  // 1.46: in what she wears.
                                  capeSpread: .8,
                                  outfit:
                                      FinanceScope.maybeOf(
                                        context,
                                      )?.wornOutfit ??
                                      const [],
                                  moods: [
                                    _hovered == null
                                        ? FinoraMood.thinking
                                        : FinoraMood.delight,
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: _center.dy - _outer - 70,
                child: Opacity(
                  opacity: fade,
                  child: Text(
                    label ?? 'Что сделать?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _item(BuildContext context, int i, double step, ColorScheme scheme) {
    final a = step * i;
    final r = (_outer + _inner) / 2;
    const c = Offset(_outer + 20, _outer + 20);
    final p = c + Offset(math.sin(a) * r, -math.cos(a) * r);
    final hovered = _hovered == i;
    final action = widget.actions[i];
    return Positioned(
      left: p.dx - 34,
      top: p.dy - 30,
      width: 68,
      height: 60,
      child: GestureDetector(
        key: ValueKey('wheel-${action.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.medium();
          widget.onSelected(action.id);
        },
        child: AnimatedScale(
          scale: hovered ? 1.18 : 1,
          duration: const Duration(milliseconds: 140),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: 26,
                color: hovered ? scheme.onPrimary : scheme.onSurface,
              ),
              const SizedBox(height: 2),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hovered
                      ? scheme.onPrimary
                      : scheme.onSurface.withValues(alpha: .8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.count,
    required this.hovered,
    required this.outer,
    required this.inner,
    required this.fill,
    required this.accent,
    required this.rim,
  });
  final int count;
  final int? hovered;
  final double outer, inner;
  final Color fill, accent, rim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final step = 2 * math.pi / count;
    const gap = .035;
    for (var i = 0; i < count; i++) {
      final start = -math.pi / 2 + step * i - step / 2 + gap;
      final sweep = step - gap * 2;
      final lift = i == hovered ? 8.0 : 0.0;
      final mid = start + sweep / 2;
      final shift = Offset(math.cos(mid), math.sin(mid)) * lift;
      final o = outer + lift / 2;
      final path = Path()
        ..arcTo(
          Rect.fromCircle(center: c + shift, radius: o),
          start,
          sweep,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: c + shift, radius: inner),
          start + sweep,
          -sweep,
          false,
        )
        ..close();
      if (i == hovered) {
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: .55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
      canvas.drawPath(path, Paint()..color = i == hovered ? accent : fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = rim,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hovered != hovered || old.fill != fill || old.accent != accent;
}
