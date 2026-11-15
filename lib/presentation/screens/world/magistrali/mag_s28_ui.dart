import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Stage S28 in the sheets: interchanges at a crossing (JCT-02) and taking
/// a whole curve away (VIS-07).

/// The road sheet: interchanges, when the tapped cell is a crossing.
List<Widget> junctionSection(MagistraliScreenState state, int cell) {
  final w = state.world;
  final crossing =
      !(w
              .junctionBlocker(cell, MagJunction.overpass)
              ?.contains('перекрёсток') ??
          false);
  final kinds = crossing ? MagJunction.values : const <MagJunction>[];
  if (kinds.isEmpty) return const [];
  String name(MagJunction k) => switch (k) {
    MagJunction.overpass => 'Эстакада',
    MagJunction.clover => 'Клевер',
    MagJunction.turbine => 'Турбина',
    MagJunction.stack => 'Стек (3 уровня)',
    MagJunction.roundabout => 'Кольцо',
  };
  IconData icon(MagJunction k) => switch (k) {
    MagJunction.overpass => Icons.u_turn_left_rounded,
    MagJunction.clover => Icons.filter_vintage_rounded,
    MagJunction.turbine => Icons.cyclone_rounded,
    MagJunction.stack => Icons.layers_rounded,
    MagJunction.roundabout => Icons.roundabout_right_rounded,
  };
  return [
    const SizedBox(height: 10),
    const Text(
      'Развязка на перекрёстке',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    const Text(
      'Эстакада — одна дорога над другой, без съезда; клевер — эстакада и четыре петли; турбина — эстакада и закрученные съезды; стек — съезды третьим уровнем над эстакадой; кольцо — круговое движение. Клеверу, турбине и стеку нужны дороги на 4 клетки во все стороны.',
      style: magMuted,
    ),
    const SizedBox(height: 6),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final k in kinds)
          OutlinedButton.icon(
            key: ValueKey('mag-junction-${k.name}'),
            icon: Icon(icon(k), size: 18),
            onPressed: w.junctionBlocker(cell, k) != null
                ? () => state.say(w.junctionBlocker(cell, k)!)
                : () => state.report(w.buildJunction(cell, k)),
            label: Text('${name(k)} · ${magMoney(w.junctionPrice(k))}'),
          ),
      ],
    ),
  ];
}

/// The road or rail sheet: the whole curve through the cell comes off.
List<Widget> curveSection(
  MagistraliScreenState state,
  int cell, {
  bool rail = false,
}) {
  final w = state.world;
  if (w.wayAt(cell, rail: rail) == null) return const [];
  return [
    const SizedBox(height: 8),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('mag-curve-remove'),
        icon: const Icon(Icons.timeline_rounded),
        onPressed: () {
          if (state.report(
            w.removeWayAt(cell, rail: rail),
            'Кривая снесена целиком',
          )) {
            Navigator.pop(state.context);
          }
        },
        label: const Text('Снести всю кривую'),
      ),
    ),
  ];
}
