import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import 'common.dart' show money;
import '../l10n_widgets.dart';

/// Motion rules for Finance 1.9: short, eased, never blocking input, and off
/// when the system asks to reduce motion. Endless ambient loops stay off in widget
/// tests, which wait for all animations to finish. Since 1.11.1 the app has
/// none: every animation runs once and then the screen goes quiet.
abstract final class Motion {
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static final bool _testing = Platform.environment.containsKey('FLUTTER_TEST');

  /// Tests may force ambient motion on to verify it, then switch it off.
  @visibleForTesting
  static bool debugForceAmbient = false;

  /// Whether endless decorative animations may run.
  static bool ambient(BuildContext context) =>
      (!_testing || debugForceAmbient) &&
      !reduced(context) &&
      TickerMode.valuesOf(context).enabled;

  static const curve = Cubic(.2, .8, .2, 1);
}

/// Fades and lifts its child into place once, after `index × 55 ms`.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _run = 520;
  late final int _delay = 55 * math.min(widget.index, 8);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _run + _delay),
  );
  // The delay is part of one continuous animation (no timers), so the
  // first frame is already animating and tests can wait for it to finish.
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay / (_run + _delay), 1, curve: Motion.curve),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
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
    animation: _t,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - _t.value)),
        child: Transform.scale(scale: .98 + .02 * _t.value, child: child),
      ),
    ),
  );
}

/// A money amount that counts up to its value on first show and glides
/// between values when it changes. The final frame is exactly [money].
class AnimatedMoney extends StatefulWidget {
  const AnimatedMoney(
    this.minor, {
    super.key,
    this.currency = 'RUB',
    this.style,
    this.textKey,
  });
  final int minor;
  final String currency;
  final TextStyle? style;
  final Key? textKey;
  @override
  State<AnimatedMoney> createState() => _AnimatedMoneyState();
}

class _AnimatedMoneyState extends State<AnimatedMoney> {
  int _from = 0;
  @override
  void didUpdateWidget(covariant AnimatedMoney old) {
    super.didUpdateWidget(old);
    if (old.minor != widget.minor) _from = old.minor;
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return Text(
        money(widget.minor, widget.currency),
        key: widget.textKey,
        style: widget.style,
      );
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.minor),
      tween: Tween(begin: _from.toDouble(), end: widget.minor.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutExpo,
      builder: (context, value, _) => Text(
        money(value.round(), widget.currency),
        key: widget.textKey,
        style: widget.style,
      ),
    );
  }
}

/// A soft diagonal light sweep over its child, once when shown.
class Sheen extends StatefulWidget {
  const Sheen({super.key, required this.child, required this.borderRadius});
  final Widget child;
  final BorderRadius borderRadius;
  @override
  State<Sheen> createState() => _SheenState();
}

class _SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || Motion.reduced(context)) return;
    _started = true;
    // Once only: a repeating sweep would redraw the whole screen (and every
    // glass blur on it) every few seconds.
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                if (_c.value == 0 || _c.value == 1) {
                  return const SizedBox.shrink();
                }
                final x = -1.6 + 3.2 * Curves.easeInOut.transform(_c.value);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(x - .5, -1),
                      end: Alignment(x + .5, 1),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: .16),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}

/// Shrinks slightly while pressed, springing back on release.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? .97 : 1,
        duration: Duration(milliseconds: _down ? 90 : 260),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}
