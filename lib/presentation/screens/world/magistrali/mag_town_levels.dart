import 'package:flutter/material.dart';

import 'mag_shapes.dart';

/// CITY-06 (S20): every level of a settlement looks its own. On top of the
/// buildings of its group each level adds what is new there: a vegetable
/// bed, fences, shop awnings, courtyard trees, water tanks, antennas, lit
/// crowns.
void paintLevelDetail(Canvas c, double x, double y, int level, double h) {
  switch (level) {
    case 1:
      break;
    case 2:
      // A vegetable bed behind the cottage.
      MagShapes.box(
        c,
        x: x + .25,
        y: y + .82,
        length: .3,
        width: .14,
        h: 1.2,
        color: const Color(0xFF7DA34E),
        outline: false,
      );
    case 3:
      // A low stone fence.
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .95,
        length: .9,
        width: .05,
        h: 2.5,
        color: const Color(0xFFB9B2A6),
        outline: false,
      );
    case 4:
      // A shop's striped awning.
      MagShapes.box(
        c,
        x: x + .78,
        y: y + .3,
        length: .22,
        width: .18,
        z0: 6,
        h: 1.5,
        color: h > .5 ? const Color(0xFFD64B5C) : const Color(0xFF2BB59A),
        outline: false,
      );
    case 5:
    case 6:
      // Courtyard trees (two at level 6).
      for (var k = 0; k < level - 4; k++) {
        MagShapes.cylinder(
          c,
          x: x + .12 + k * .76,
          y: y + .88,
          r: .09,
          z0: 3,
          h: 6,
          color: const Color(0xFF4C9444),
          dome: true,
        );
      }
    case 7:
      // A water tank on the roof line.
      MagShapes.cylinder(
        c,
        x: x + .85,
        y: y + .15,
        r: .07,
        z0: 2,
        h: 6,
        color: const Color(0xFF8E9AA0),
      );
    case 8:
    case 9:
      // A rooftop antenna, taller at level 9.
      MagShapes.box(
        c,
        x: x + .15,
        y: y + .85,
        length: .04,
        width: .04,
        h: level == 8 ? 10 : 18,
        color: const Color(0xFFD6DDE0),
        outline: false,
      );
    default:
      // A megalopolis: a little park with a golden lamp.
      MagShapes.cylinder(
        c,
        x: x + .12,
        y: y + .88,
        r: .1,
        z0: 2,
        h: 6,
        color: const Color(0xFF3E8240),
        dome: true,
      );
      MagShapes.cylinder(
        c,
        x: x + .9,
        y: y + .9,
        r: .03,
        h: 9,
        color: const Color(0xFFD4A017),
      );
  }
}

/// What a settlement's centre adds at each level: a well, a bell, a market
/// roof, a clock, a dome, a spire, a crown.
void paintLandmarkDetail(Canvas c, double x, double y, int level) {
  switch (level) {
    case 2:
    case 3:
      // A bell under the chapel tower (bigger in a large village).
      MagShapes.cylinder(
        c,
        x: x + .25,
        y: y + .5,
        r: level == 2 ? .05 : .07,
        z0: 24,
        h: 4,
        color: const Color(0xFFD4A017),
        dome: true,
      );
    case 4:
      // A market roof by the hall.
      MagShapes.roof(
        c,
        x: x + .8,
        y: y + .82,
        length: .3,
        width: .3,
        z0: 6,
        h: 4,
        color: const Color(0xFFD9B95A),
        ridge: .2,
      );
    case 5:
    case 6:
      // A clock face on the town hall tower (and flags at level 6).
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .4,
        length: .1,
        width: .02,
        z0: 24,
        h: 5,
        color: const Color(0xFFFFFFFF),
        outline: false,
      );
      if (level == 6) {
        MagShapes.box(
          c,
          x: x + .9,
          y: y + .1,
          length: .03,
          width: .03,
          h: 20,
          color: const Color(0xFFD64B5C),
          outline: false,
        );
      }
    case 7:
      // A theatre dome.
      MagShapes.cylinder(
        c,
        x: x + .82,
        y: y + .82,
        r: .14,
        h: 10,
        color: const Color(0xFF6FA3B5),
        dome: true,
      );
    case 9:
    case 10:
      // A spire; a megalopolis crowns it with gold.
      MagShapes.box(
        c,
        x: x + .5,
        y: y + .5,
        length: .05,
        width: .05,
        z0: 108 + 6.0 * level,
        h: 26,
        color: level == 10 ? const Color(0xFFD4A017) : const Color(0xFFD6DDE0),
        outline: false,
      );
    default:
      break;
  }
}
