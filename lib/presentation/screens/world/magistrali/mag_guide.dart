import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_art.dart';
import 'mag_screen.dart';

/// The tutorial (S12): while the first tasks are open, the button the
/// next step needs pulses and arrows bounce over the places to use. It
/// follows the tasks — no separate script — and can be turned off in the
/// settings or from the task card.
class MagGuide {
  const MagGuide({this.key, this.places = const []});

  /// The key of the control to press now.
  final String? key;

  /// Places to point at on the map.
  final List<int> places;

  static const none = MagGuide();
}

MagGuide guideFor(MagistraliScreenState s) {
  final w = s.world;
  if (!w.tutorial) return MagGuide.none;
  final task = w.currentTask;
  if (task == null) return MagGuide.none;
  final farm = w.map.startFarm.id, plant = w.map.startPlant.id;
  final building = s.tool != MagTool.view;
  final village = w.settlements.isEmpty
      ? null
      : (w.settlements.toList()..sort(
              (a, b) => a
                  .distanceTo(w.map.startPlant)
                  .compareTo(b.distanceTo(w.map.startPlant)),
            ))
            .first
            .id;
  return switch (task.id) {
    1 when !building => const MagGuide(key: 'mag-tab-build'),
    1 when s.pendingRoad == null => MagGuide(places: [farm, plant]),
    1 => const MagGuide(key: 'mag-confirm-build'),
    6 when !building => MagGuide(key: 'mag-tab-build', places: [plant]),
    6 when s.pendingRoad == null => MagGuide(places: [plant, ?village]),
    6 => const MagGuide(key: 'mag-confirm-build'),
    _ when building => const MagGuide(key: 'mag-tab-build'),
    2 => MagGuide(key: 'mag-tab-routes', places: [farm, plant]),
    3 || 5 || 7 => const MagGuide(key: 'mag-tab-fleet'),
    4 => MagGuide(key: 'mag-speed-4', places: [plant]),
    _ => MagGuide.none,
  };
}

/// A soft ring pulsing around a control the tutorial points at.
class MagPulse extends StatefulWidget {
  const MagPulse({
    super.key,
    required this.active,
    required this.child,
    this.radius = 14,
  });
  final bool active;
  final Widget child;
  final double radius;

  @override
  State<MagPulse> createState() => _MagPulseState();
}

class _MagPulseState extends State<MagPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(MagPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_c.value);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: MagPalette.mint.withValues(alpha: 1 - t * .8),
              width: 2 + 3 * (1 - t),
            ),
          ),
          child: child,
        );
      },
    );
  }
}
