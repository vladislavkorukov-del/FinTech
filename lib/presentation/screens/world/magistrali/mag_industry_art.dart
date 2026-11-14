import 'package:flutter/material.dart';

import '../../../../domain/magistrali/magistrali.dart';
import 'mag_shapes.dart';

/// Buildings of master plan stage 5 (industry): a coal mine with its
/// headframe and heap, a clay pit with a pond, a brickworks with its kiln
/// chimney, a steel mill with blast furnaces, a parts factory with a saw
/// roof. [x], [y] is the top corner of the place.
void paintIndustryBuilding(Canvas c, MagIndustryKind k, double x, double y) {
  switch (k) {
    case MagIndustryKind.coalMine:
      // A dark heap, the winding house and the headframe over the shaft.
      MagShapes.cylinder(
        c,
        x: x + 1.5,
        y: y + 1.5,
        r: .38,
        h: 6,
        color: const Color(0xFF3B3F44),
        dome: true,
      );
      MagShapes.box(
        c,
        x: x + .7,
        y: y + .9,
        length: .9,
        width: .6,
        h: 9,
        color: const Color(0xFF8E6F5A),
      );
      MagShapes.roof(
        c,
        x: x + .7,
        y: y + .9,
        length: .96,
        width: .66,
        z0: 9,
        h: 5,
        color: const Color(0xFF4A5157),
        ridge: .6,
      );
      for (final (dx, dy) in [(.25, .25), (.55, .25), (.25, .55), (.55, .55)]) {
        MagShapes.box(
          c,
          x: x + dx,
          y: y + dy,
          length: .06,
          width: .06,
          h: 22,
          color: const Color(0xFF5B636B),
          outline: false,
        );
      }
      MagShapes.box(
        c,
        x: x + .4,
        y: y + .4,
        length: .4,
        width: .4,
        z0: 20,
        h: 3,
        color: const Color(0xFFC0473F),
      );
    case MagIndustryKind.clayPit:
      // A wet pit, a clay mound and a shed.
      MagShapes.box(
        c,
        x: x + .8,
        y: y + 1.2,
        length: 1,
        width: .8,
        h: 1,
        color: const Color(0xFF6FAFC4),
        outline: false,
      );
      MagShapes.cylinder(
        c,
        x: x + 1.5,
        y: y + .5,
        r: .3,
        h: 5,
        color: const Color(0xFFB8774A),
        dome: true,
      );
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .45,
        length: .6,
        width: .45,
        h: 7,
        color: const Color(0xFFD8C3A0),
      );
      MagShapes.roof(
        c,
        x: x + .5,
        y: y + .45,
        length: .66,
        width: .5,
        z0: 7,
        h: 4,
        color: const Color(0xFF7A5A44),
        ridge: .5,
      );
    case MagIndustryKind.brickworks:
      // A long brick kiln, its chimney, stacked bricks.
      MagShapes.box(
        c,
        x: x + .95,
        y: y + .75,
        length: 1.3,
        width: .7,
        h: 10,
        color: const Color(0xFFB4533E),
      );
      MagShapes.roof(
        c,
        x: x + .95,
        y: y + .75,
        length: 1.36,
        width: .76,
        z0: 10,
        h: 5,
        color: const Color(0xFF5A4A44),
        ridge: .9,
      );
      MagShapes.cylinder(
        c,
        x: x + .35,
        y: y + .35,
        r: .11,
        h: 30,
        color: const Color(0xFF9C4A3A),
      );
      for (var k = 0; k < 3; k++) {
        MagShapes.box(
          c,
          x: x + 1.55,
          y: y + 1.55,
          length: .45,
          width: .3,
          z0: 2.2 * k,
          h: 2.2,
          color: const Color(0xFFC8664E),
          outline: false,
        );
      }
    case MagIndustryKind.steelMill:
      // A big hall, two blast furnaces and tall stacks (3×3).
      MagShapes.box(
        c,
        x: x + 1.7,
        y: y + 1.9,
        length: 2,
        width: 1.1,
        h: 14,
        color: const Color(0xFF8A96A3),
      );
      MagShapes.roof(
        c,
        x: x + 1.7,
        y: y + 1.9,
        length: 2.06,
        width: 1.16,
        z0: 14,
        h: 6,
        color: const Color(0xFF4A5560),
        ridge: 1.4,
      );
      for (final (dx, dy) in [(.6, .6), (1.3, .5)]) {
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + dy,
          r: .26,
          h: 24,
          color: const Color(0xFF6D5B52),
        );
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + dy,
          r: .16,
          z0: 24,
          h: 6,
          color: const Color(0xFFE07A3E),
          dome: true,
        );
      }
      for (final dx in [2.2, 2.6]) {
        MagShapes.cylinder(
          c,
          x: x + dx,
          y: y + .5,
          r: .1,
          h: 40,
          color: const Color(0xFFD9DEE2),
        );
      }
    case MagIndustryKind.partsFactory:
      // A workshop with a saw-tooth roof and a crane at the yard.
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .85,
        length: 1.4,
        width: .9,
        h: 11,
        color: const Color(0xFFDCE3E6),
      );
      for (var k = 0; k < 3; k++) {
        MagShapes.roof(
          c,
          x: x + .55 + k * .45,
          y: y + .85,
          length: .45,
          width: .92,
          z0: 11,
          h: 4,
          color: const Color(0xFF4FB3C9),
          ridge: .1,
        );
      }
      MagShapes.box(
        c,
        x: x + 1.7,
        y: y + 1.65,
        length: .06,
        width: .06,
        h: 20,
        color: const Color(0xFFE8B23E),
        outline: false,
      );
      MagShapes.box(
        c,
        x: x + 1.45,
        y: y + 1.65,
        length: .6,
        width: .06,
        z0: 19,
        h: 1.5,
        color: const Color(0xFFE8B23E),
        outline: false,
      );
    case MagIndustryKind.logisticsCenter:
      // An office block with a mint band and a radio mast.
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .95,
        length: 1.3,
        width: .95,
        h: 18,
        color: const Color(0xFFE9EEF0),
      );
      MagShapes.box(
        c,
        x: x + 1,
        y: y + .95,
        length: 1.32,
        width: .97,
        z0: 12,
        h: 3,
        color: const Color(0xFF2BB59A),
        outline: false,
      );
      MagShapes.box(
        c,
        x: x + .55,
        y: y + .5,
        length: .05,
        width: .05,
        z0: 18,
        h: 22,
        color: const Color(0xFF51707A),
        outline: false,
      );
      MagShapes.cylinder(
        c,
        x: x + .55,
        y: y + .5,
        r: .06,
        z0: 40,
        h: 2,
        color: const Color(0xFFD64B5C),
        dome: true,
      );
    default:
      break;
  }
}
