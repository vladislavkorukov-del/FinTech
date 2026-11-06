import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'finora_orb.dart';
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

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  /// 1.26: Finora is glad to be called — a hop, a wiggle, rings and a smile
  /// before the microphone opens.
  late final AnimationController _joy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _rest, _call;
  bool _pressed = false;

  /// Time the hop is seen before the speech dialog covers the screen.
  static const _lead = Duration(milliseconds: 380);

  void _activate() {
    HapticFeedback.lightImpact();
    VoiceOrb.activity.value++;
    // Still with «reduce motion» (and in tests): straight to listening.
    if (!Motion.ambient(context)) {
      widget.onTap();
      return;
    }
    _joy.forward(from: 0);
    _call?.cancel();
    _call = Timer(_lead, () {
      if (mounted) widget.onTap();
    });
  }

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
    _call?.cancel();
    _flow.dispose();
    _joy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    return Semantics(
      label: 'Финора: голосовой ввод операции',
      hint: 'Удерживайте, чтобы добавить операцию вручную',
      button: true,
      child: Tooltip(
        message: 'Финора · удерживайте для ручного ввода',
        child: GestureDetector(
          key: const ValueKey('nav-voice'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: _activate,
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
                animation: Listenable.merge([_flow, _joy]),
                builder: (context, _) {
                  final j = _joy.value;
                  final joyful = j > 0 && j < 1;
                  // Blinks once in each drift loop while awake.
                  final loop = _flow.value;
                  final blink = loop > .46 && loop < .5
                      ? math.sin((loop - .46) / .04 * math.pi)
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -hopHeight(j) * size * .2),
                    child: Transform.rotate(
                      angle: wiggle(j) * .16,
                      child: Transform.scale(
                        scale: bounce(j),
                        child: CustomPaint(
                          size: Size.square(size),
                          painter: FinoraOrbPainter(
                            t: _flow.value,
                            base: scheme.primary,
                            accent: scheme.tertiary,
                            dark:
                                Theme.of(context).brightness == Brightness.dark,
                            mood: joyful
                                ? FinoraMood.happy
                                : _pressed
                                ? FinoraMood.surprised
                                : FinoraMood.calm,
                            blink: joyful ? 0 : blink,
                            joy: joyful ? j : 0,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
