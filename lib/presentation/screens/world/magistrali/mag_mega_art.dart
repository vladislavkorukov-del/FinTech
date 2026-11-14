import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_shapes.dart';

/// A megaproject on its 3×3 site: while it is built — foundations, the
/// part already standing (growing with the deliveries), scaffolding and a
/// tower crane; when done — its own landmark.
void paintMegaproject(Canvas c, MagIndustry i, double x, double y) {
  final need = i.projectNeeds.values.fold(0, (a, b) => a + b);
  final got = i.projectNeeds.entries.fold(
    0,
    (a, e) => a + (i.projectProgress[e.key] ?? 0).clamp(0, e.value),
  );
  final k = i.projectDone ? 1.0 : (need == 0 ? 0.0 : got / need);
  if (!i.projectDone) {
    // Foundation slab, the rising core and scaffolding round it.
    MagShapes.box(
      c,
      x: x + 1.5,
      y: y + 1.5,
      length: 2.2,
      width: 2.2,
      h: 2,
      color: const Color(0xFFBDB6A8),
    );
    MagShapes.box(
      c,
      x: x + 1.5,
      y: y + 1.5,
      length: 1.5,
      width: 1.5,
      z0: 2,
      h: 6 + 34 * k,
      color: const Color(0xFFD9CFC0),
    );
    for (final (dx, dy) in [(.6, .6), (2.4, .6), (.6, 2.4), (2.4, 2.4)]) {
      MagShapes.box(
        c,
        x: x + dx,
        y: y + dy,
        length: .05,
        width: .05,
        h: 10 + 36 * k,
        color: const Color(0xFF9C7A54),
        outline: false,
      );
    }
    // The tower crane.
    MagShapes.box(
      c,
      x: x + 2.6,
      y: y + 1.5,
      length: .1,
      width: .1,
      h: 62,
      color: const Color(0xFFE8B23E),
      outline: false,
    );
    MagShapes.box(
      c,
      x: x + 2,
      y: y + 1.5,
      length: 1.6,
      width: .08,
      z0: 60,
      h: 2.5,
      color: const Color(0xFFE8B23E),
      outline: false,
    );
    return;
  }
  switch (i.project) {
    case 'bridge':
      // A steel arch on stone piers.
      for (final dx in [.6, 2.4]) {
        MagShapes.box(
          c,
          x: x + dx,
          y: y + 1.5,
          length: .4,
          width: 1.2,
          h: 14,
          color: const Color(0xFFA7A9AC),
        );
      }
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + 1.5,
        length: 2.6,
        width: .9,
        z0: 14,
        h: 3,
        color: const Color(0xFF5E666C),
      );
      for (var n = 0; n < 7; n++) {
        final t = n / 6;
        final h = 14 + 26 * (1 - (2 * t - 1) * (2 * t - 1));
        MagShapes.box(
          c,
          x: x + .4 + t * 2.2,
          y: y + 1.5,
          length: .08,
          width: .08,
          z0: 17,
          h: h - 14,
          color: const Color(0xFFC0473F),
          outline: false,
        );
      }
    case 'station':
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + 1.6,
        length: 2.4,
        width: 1.4,
        h: 18,
        color: const Color(0xFFB4533E),
      );
      MagShapes.roof(
        c,
        x: x + 1.5,
        y: y + 1.6,
        length: 2.5,
        width: 1.5,
        z0: 18,
        h: 10,
        color: const Color(0xFF51707A),
        ridge: 1.8,
      );
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + .8,
        length: .4,
        width: .4,
        h: 44,
        color: const Color(0xFFC8664E),
      );
      MagShapes.cylinder(
        c,
        x: x + 1.5,
        y: y + .8,
        r: .16,
        z0: 44,
        h: 6,
        color: const Color(0xFFE8B23E),
        dome: true,
      );
    case 'exchange':
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + 1.5,
        length: 2.2,
        width: 1.6,
        h: 24,
        color: const Color(0xFFEDE6D6),
      );
      for (var n = 0; n < 6; n++) {
        MagShapes.cylinder(
          c,
          x: x + .55 + n * .38,
          y: y + 2.4,
          r: .07,
          h: 22,
          color: const Color(0xFFF7F3EA),
        );
      }
      MagShapes.roof(
        c,
        x: x + 1.5,
        y: y + 1.5,
        length: 2.3,
        width: 1.7,
        z0: 24,
        h: 8,
        color: const Color(0xFFD9CFC0),
        ridge: 1.6,
      );
    case 'tower':
      for (var n = 0; n < 5; n++) {
        MagShapes.cylinder(
          c,
          x: x + 1.5,
          y: y + 1.5,
          r: .34 - n * .06,
          z0: n * 22.0,
          h: 22,
          color: n.isEven ? const Color(0xFFE9EEF0) : const Color(0xFFD64B5C),
        );
      }
      MagShapes.cylinder(
        c,
        x: x + 1.5,
        y: y + 1.5,
        r: .4,
        z0: 60,
        h: 6,
        color: const Color(0xFF8FB8C9),
      );
      MagShapes.box(
        c,
        x: x + 1.5,
        y: y + 1.5,
        length: .04,
        width: .04,
        z0: 110,
        h: 30,
        color: const Color(0xFF51707A),
        outline: false,
      );
    default:
      // The exhibition: pavilions round a fountain.
      MagShapes.cylinder(
        c,
        x: x + 1.5,
        y: y + 1.5,
        r: .35,
        h: 3,
        color: const Color(0xFF63B9DA),
      );
      for (final (dx, dy, col) in [
        (.6, .6, const Color(0xFFE8B23E)),
        (2.4, .6, const Color(0xFF4FB3C9)),
        (.6, 2.4, const Color(0xFFE86A5A)),
        (2.4, 2.4, const Color(0xFF2BB59A)),
      ]) {
        MagShapes.box(
          c,
          x: x + dx,
          y: y + dy,
          length: .7,
          width: .7,
          h: 14,
          color: const Color(0xFFF1E3C8),
        );
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + dy,
          r: .3,
          z0: 14,
          h: 8,
          color: col,
          dome: true,
        );
      }
  }
}
