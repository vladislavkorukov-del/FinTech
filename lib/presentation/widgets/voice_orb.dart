import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../haptics.dart';
import 'finora_orb.dart';
import 'motion.dart';
import '../l10n_widgets.dart';

/// Finora in the middle of the bottom bar (1.20; 2.2: a sphere of light, no
/// face and no moods).
///
/// Tap: her light swells, then she listens. Long press: an ordinary new
/// operation. When something happens in the app ([Finora.react]) her light
/// swells and a short line appears above her; ten seconds after the last
/// touch she rests and stops drawing frames. Still with «reduce motion» and
/// in tests.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.onLongPressMove,
    this.onLongPressEnd,
    this.size = 56,
  });
  final VoidCallback onTap, onLongPress;

  /// 1.37: the finger slides / is lifted after a long press (the wheel).
  final ValueChanged<Offset>? onLongPressMove, onLongPressEnd;
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

  /// How lively her light is: swelling when called or answering, a little
  /// livelier under the finger, calm at rest.
  double _energy(double swellT) {
    if (_called || _reaction != null) return .35 + .65 * swell(swellT);
    if (_pressed) return .5;
    return _asleep ? 0 : .1;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Финора: голосовой ввод операции',
      hint: 'Удерживайте, чтобы открыть колесо действий',
      button: true,
      child: Tooltip(
        message: 'Финора · удерживайте для колеса действий',
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
                          borderRadius: BorderRadius.circular(14),
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
              onLongPressMoveUpdate: (d) =>
                  widget.onLongPressMove?.call(d.globalPosition),
              onLongPressEnd: (d) =>
                  widget.onLongPressEnd?.call(d.globalPosition),
              child: AnimatedScale(
                scale: _pressed ? .92 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_flow, _joy]),
                    builder: (context, _) {
                      final j = _joy.value;
                      return CustomPaint(
                        size: Size.square(size),
                        painter: FinoraOrbPainter(
                          t: _flow.value,
                          energy: _energy(j),
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
