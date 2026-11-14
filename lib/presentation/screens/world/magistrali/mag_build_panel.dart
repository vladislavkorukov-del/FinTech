import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_business.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_tools.dart';

/// The groups of the build tools (1.83): one row of groups, one row of the
/// chosen group's tools, and a line about what the tool does.
enum MagBuildGroup { roads, rail, water, buildings, remove }

MagBuildGroup groupOf(MagTool t) => switch (t) {
  MagTool.rail || MagTool.station => MagBuildGroup.rail,
  MagTool.port => MagBuildGroup.water,
  MagTool.warehouse || MagTool.industry => MagBuildGroup.buildings,
  MagTool.remove => MagBuildGroup.remove,
  _ => MagBuildGroup.roads,
};

class MagBuildPanel extends StatelessWidget {
  const MagBuildPanel({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    final group = groupOf(state.tool);
    Widget tab(
      MagBuildGroup g,
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool locked = false,
    }) => Expanded(
      child: InkWell(
        key: ValueKey('mag-cat-${g.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: g == group ? const Color(0x1F2BB59A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked ? Icons.lock_rounded : icon,
                size: 18,
                color: g == group
                    ? MagPalette.teal
                    : locked
                    ? const Color(0xFF8A9599)
                    : MagPalette.ink,
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: g == group ? FontWeight.w800 : FontWeight.w600,
                  color: g == group ? MagPalette.teal : MagPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final tools = switch (group) {
      MagBuildGroup.roads => [
        for (final r in MagRoad.values.skip(1))
          MagToolChip(
            key: ValueKey('mag-road-${r.name}'),
            label: roadName(r),
            locked: !w.roadUnlocked(r),
            lockLevel: MagRules.roads[r]!.level,
            on: state.tool == MagTool.road && state.roadType == r,
            color: roadColor(r),
            onTap: () => w.roadUnlocked(r)
                ? state.setTool(MagTool.road, r)
                : state.say(
                    '${roadName(r)} откроется на ${MagRules.roads[r]!.level} уровне',
                  ),
          ),
      ],
      MagBuildGroup.rail => railChips(state).take(2).toList(),
      MagBuildGroup.water => railChips(state).skip(2).toList(),
      MagBuildGroup.buildings => [
        MagToolChip(
          key: const ValueKey('mag-tool-warehouse'),
          label: 'Склад',
          locked: w.warehouseSlots == 0,
          lockLevel: 2,
          on: state.tool == MagTool.warehouse,
          color: MagPalette.mint,
          icon: Icons.warehouse_rounded,
          onTap: () => w.warehouseSlots == 0
              ? state.say('Склады открывает технология «Складское дело»')
              : state.setTool(MagTool.warehouse),
        ),
        MagToolChip(
          key: const ValueKey('mag-tool-industry'),
          label: state.tool == MagTool.industry && state.buildKind != null
              ? kindName(state.buildKind!)
              : 'Предприятие',
          locked: w.level < 2,
          lockLevel: 2,
          on: state.tool == MagTool.industry,
          color: MagPalette.teal,
          icon: Icons.factory_outlined,
          onTap: () async {
            final k = await showBuildPicker(state);
            if (k != null) state.chooseBuild(k);
          },
        ),
      ],
      MagBuildGroup.remove => const <Widget>[],
    };

    return Container(
      decoration: magCard(),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tab(
                MagBuildGroup.roads,
                'Дороги',
                Icons.add_road_rounded,
                () => state.setTool(MagTool.road),
              ),
              tab(
                MagBuildGroup.rail,
                'Ж/д',
                Icons.train_rounded,
                () => w.railsUnlocked
                    ? state.setTool(MagTool.rail)
                    : state.say(
                        'Железные дороги открывает технология «Паровая тяга»',
                      ),
                locked: !w.railsUnlocked,
              ),
              tab(
                MagBuildGroup.water,
                'Вода',
                Icons.anchor_rounded,
                () => w.shippingUnlocked
                    ? state.setTool(MagTool.port)
                    : state.say(
                        'Порты открывает технология «Речное судоходство»',
                      ),
                locked: !w.shippingUnlocked,
              ),
              tab(
                MagBuildGroup.buildings,
                'Здания',
                Icons.domain_rounded,
                () => state.setTool(
                  w.warehouseSlots > 0 ? MagTool.warehouse : MagTool.industry,
                ),
              ),
              tab(
                MagBuildGroup.remove,
                'Снос',
                Icons.delete_outline_rounded,
                () => state.setTool(MagTool.remove),
              ),
            ],
          ),
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: tools),
            ),
          ],
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              toolHint(state),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF52646A)),
            ),
          ),
        ],
      ),
    );
  }
}
