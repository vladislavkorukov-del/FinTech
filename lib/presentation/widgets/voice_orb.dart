import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import 'finora_orb.dart';
import 'motion.dart';

/// Finora in the middle of the bottom bar (1.20; her own face since 1.26,
/// her own look and moods since 1.27).
///
/// Tap: she is glad to be called, then listens. Long press: an ordinary new
/// operation. She reacts to what happens in the app ([Finora.react]) with a
/// face, a hop and a short line above her; ten seconds after the last touch
/// she dozes off («Ожидание») and stops drawing frames. Still with «reduce
/// motion» and in tests.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.size = 56,
  });
  final VoidCallback onTap, onLongPress;
  final double size;

  /// Bumped by the app shell on every touch to wake her.
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

  /// The hop: when called, and with every reaction.
  late final AnimationController _joy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final _bubble = OverlayPortalController();
  final _link = LayerLink();
  Timer? _rest, _call, _clear;
  bool _pressed = false, _asleep = false, _called = false;
  FinoraReaction? _reaction;

  /// Time the hop is seen before the speech dialog covers the screen.
  static const _lead = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    VoiceOrb.activity.addListener(_wake);
    Finora.reactions.addListener(_react);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wake();
  }

  void _activate() {
    Haptics.light();
    VoiceOrb.activity.value++;
    // Still with «reduce motion» (and in tests): straight to listening.
    if (!Motion.ambient(context)) {
      widget.onTap();
      return;
    }
    setState(() => _called = true);
    _joy.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _called = false);
    });
    _call?.cancel();
    _call = Timer(_lead, () {
      if (mounted) widget.onTap();
    });
  }

  void _react() {
    final reaction = Finora.reactions.value;
    if (!mounted || reaction == null) return;
    _clear?.cancel();
    setState(() {
      _reaction = reaction;
      _asleep = false;
    });
    if (reaction.text != null) {
      _bubble.show();
    } else {
      _bubble.hide();
    }
    if (!Motion.reduced(context)) _joy.forward(from: 0);
    _wake();
    _clear = Timer(reaction.hold, () {
      if (!mounted) return;
      _bubble.hide();
      setState(() => _reaction = null);
    });
  }

  void _wake() {
    if (!mounted) return;
    if (_asleep) setState(() => _asleep = false);
    if (!Motion.ambient(context)) {
      _flow.stop();
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    _rest?.cancel();
    _rest = Timer(VoiceOrb.idle, () {
      if (!mounted) return;
      // Settle at the end of the current loop, then doze off.
      final left = (1 - _flow.value) * _flow.duration!.inMilliseconds;
      _flow
          .animateTo(
            1,
            duration: Duration(milliseconds: left.round().clamp(1, 7000)),
          )
          .whenComplete(() {
            if (mounted && !_flow.isAnimating) {
              _flow.value = 0;
              setState(() => _asleep = true);
            }
          });
    });
  }

  @override
  void dispose() {
    VoiceOrb.activity.removeListener(_wake);
    Finora.reactions.removeListener(_react);
    _rest?.cancel();
    _call?.cancel();
    _clear?.cancel();
    _flow.dispose();
    _joy.dispose();
    super.dispose();
  }

  FinoraMood get _mood {
    if (_called) return FinoraMood.delight;
    if (_reaction != null) return _reaction!.mood;
    if (_pressed) return FinoraMood.surprised;
    if (_asleep) return FinoraMood.sleep;
    return FinoraMood.idle;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Финора: голосовой ввод операции',
      hint: 'Удерживайте, чтобы добавить операцию вручную',
      button: true,
      child: Tooltip(
        message: 'Финора · удерживайте для ручного ввода',
        child: OverlayPortal(
          controller: _bubble,
          overlayChildBuilder: (context) {
            final text = _reaction?.text;
            if (text == null) return const SizedBox.shrink();
            return CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -16),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_reaction),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (context, v, child) => Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: .85 + .15 * v,
                        alignment: Alignment.bottomCenter,
                        child: child,
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        key: const ValueKey('finora-says'),
                        constraints: const BoxConstraints(maxWidth: 260),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: FinoraOrbPainter.mint.withValues(alpha: .7),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.25,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: CompositedTransformTarget(
            link: _link,
            child: GestureDetector(
              key: const ValueKey('nav-voice'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: _activate,
              onLongPress: () {
                setState(() => _pressed = false);
                Haptics.medium();
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
                      final hopping = j > 0 && j < 1;
                      // Blinks once in each drift loop while awake.
                      final loop = _flow.value;
                      final blink = loop > .46 && loop < .5
                          ? math.sin((loop - .46) / .04 * math.pi)
                          : 0.0;
                      final angry = _mood == FinoraMood.angry;
                      return Transform.translate(
                        offset: Offset(
                          // Angry: a shake instead of a hop.
                          angry ? wiggle(j) * size * .08 : 0,
                          angry ? 0 : -hopHeight(j) * size * .2,
                        ),
                        child: Transform.rotate(
                          angle: angry ? 0 : wiggle(j) * .16,
                          child: Transform.scale(
                            scale: bounce(j),
                            child: CustomPaint(
                              size: Size.square(size),
                              painter: FinoraOrbPainter(
                                t: _flow.value,
                                mood: _mood,
                                blink: hopping ? 0 : blink,
                                joy: _called && hopping ? j : 0,
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
        ),
      ),
    );
  }
}
