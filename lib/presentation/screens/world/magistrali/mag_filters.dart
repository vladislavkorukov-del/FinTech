import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';

/// A row of filter chips for the long lists of the game (1.83): the fleet
/// and the shop, the places of the map. [selected] is an index of
/// [labels]; [keyPrefix] names the chips for tests.
class MagFilterChips extends StatelessWidget {
  const MagFilterChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.keyPrefix,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: InkWell(
              key: ValueKey('$keyPrefix-$i'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: i == selected
                      ? MagPalette.mint
                      : const Color(0x0F233238),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: i == selected ? Colors.white : MagPalette.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The groups of places in lists (0: all, 1: settlements, 2: raw, 3:
/// processing, 4: warehouses, centres and the rest).
bool placeOfKind(MagIndustry i, int k) => switch (k) {
  1 => i.town != null,
  2 => i.town == null && i.spec.produces.isNotEmpty,
  3 => i.spec.converts.isNotEmpty,
  4 => i.town == null && i.spec.produces.isEmpty && i.spec.converts.isEmpty,
  _ => true,
};
