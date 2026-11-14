import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_shapes.dart';

/// The places of stage S17 (in iso space): an oil derrick with a pump, a
/// refinery with tanks and a column, an electronics plant with glass.
void paintOilBuilding(Canvas c, MagIndustryKind k, double x, double y) {
  switch (k) {
    case MagIndustryKind.oilWell:
      // A pad, a lattice derrick and a nodding pump.
      MagShapes.box(
        c,
        x: x + 1,
        y: y + 1,
        length: 1.6,
        width: 1.6,
        h: 1,
        color: const Color(0xFF8A8478),
      );
      MagShapes.box(
        c,
        x: x + .7,
        y: y + .8,
        length: .18,
        width: .18,
        z0: 1,
        h: 34,
        color: const Color(0xFF4A4F55),
      );
      MagShapes.box(
        c,
        x: x + 1.3,
        y: y + 1.2,
        length: .7,
        width: .16,
        z0: 6,
        h: 3,
        color: const Color(0xFF2E3338),
        top: const Color(0xFFE0B83E),
      );
      MagShapes.cylinder(
        c,
        x: x + 1.4,
        y: y + .6,
        r: .22,
        h: 7,
        color: const Color(0xFF6B4E2E),
      );
    case MagIndustryKind.refinery:
      // Round tanks, a cracking column with a flare.
      for (final (dx, dy) in [(.7, .7), (.7, 1.6), (1.6, .7)]) {
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + dy,
          r: .35,
          h: 9,
          color: const Color(0xFFDCE1E4),
          dome: true,
        );
      }
      MagShapes.box(
        c,
        x: x + 2.1,
        y: y + 2.1,
        length: 1.2,
        width: .9,
        h: 10,
        color: const Color(0xFF9AA4AB),
      );
      MagShapes.cylinder(
        c,
        x: x + 2.3,
        y: y + 1.2,
        r: .14,
        h: 42,
        color: const Color(0xFF6F7A82),
      );
      MagShapes.cylinder(
        c,
        x: x + 2.3,
        y: y + 1.2,
        r: .06,
        z0: 42,
        h: 6,
        color: const Color(0xFFE0743C),
      );
    default:
      // An electronics plant: white walls, a glass roof band, a mast.
      MagShapes.box(
        c,
        x: x + 1,
        y: y + 1,
        length: 1.5,
        width: 1.2,
        h: 14,
        color: const Color(0xFFF1F4F6),
      );
      MagShapes.box(
        c,
        x: x + 1,
        y: y + 1,
        length: 1.52,
        width: 1.22,
        z0: 14,
        h: 3,
        color: const Color(0xFF5BB0D6),
        top: const Color(0xFF9FD8E6),
      );
      MagShapes.cylinder(
        c,
        x: x + 1.55,
        y: y + .55,
        r: .05,
        h: 30,
        color: const Color(0xFFB0B8BE),
      );
  }
}
