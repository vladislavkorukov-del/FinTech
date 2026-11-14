import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// The whole fleet at once (VEH-11, VEH-12): repair everyone, send the
/// free vehicles to a line, replace the outdated ones by newer models.
class MagFleetBulk extends StatelessWidget {
  const MagFleetBulk({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    if (w.vehicles.isEmpty) return const SizedBox.shrink();
    final repair = w.repairAllCost;
    final idle = w.vehicles.values
        .where((v) => v.routeId == null && v.orderId == null)
        .length;
    final old = w.vehicles.values.where((v) => w.newerModelFor(v) != null);
    final replace = old.fold(0, (s, v) => s + w.replaceCost(v)!);
    Widget chip(String key, IconData icon, String label, VoidCallback? tap) =>
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: OutlinedButton.icon(
            key: ValueKey(key),
            onPressed: tap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        children: [
          chip(
            'mag-repair-all',
            Icons.build_rounded,
            repair == 0
                ? 'Все исправны'
                : 'Ремонт всех · ${magMoney(repair)} кр',
            repair == 0
                ? null
                : () => state.report(null, 'Отремонтировано: ${w.repairAll()}'),
          ),
          if (idle > 0 && w.routes.isNotEmpty)
            chip(
              'mag-assign-idle',
              Icons.alt_route_rounded,
              'Свободные ($idle) — на маршрут',
              () async {
                final id = await showModalBottomSheet<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in w.routes.values)
                          ListTile(
                            key: ValueKey('mag-idle-route-${r.id}'),
                            title: Text(r.name),
                            onTap: () => Navigator.pop(c, r.id),
                          ),
                      ],
                    ),
                  ),
                );
                if (id != null) {
                  state.report(null, 'На маршрут вышли: ${w.assignIdle(id)}');
                }
              },
            ),
          if (old.isNotEmpty)
            chip(
              'mag-replace-all',
              Icons.autorenew_rounded,
              'Заменить устаревшие (${old.length}) · ${magMoney(replace)} кр',
              () => state.report(
                null,
                'Заменено машин: ${w.replaceAllOutdated()}',
              ),
            ),
          if (old.isNotEmpty)
            const Text(
              'Замена: старая машина продаётся, новая модель того же вида встаёт на её маршрут.',
              style: magMuted,
            ),
        ],
      ),
    );
  }
}

/// A vehicle's own paint (VEH-13): the model's colour or one of five.
class MagPaintChips extends StatelessWidget {
  const MagPaintChips({super.key, required this.state, required this.v});
  final MagistraliScreenState state;
  final MagVehicle v;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    return Wrap(
      spacing: 6,
      children: [
        for (final (k, c) in [
          (0, null),
          (1, 0xFFD64B5C),
          (2, 0xFF2E5E8C),
          (3, 0xFF2BB59A),
          (4, 0xFFE8B23E),
          (5, 0xFF3B3F44),
        ])
          InkWell(
            key: ValueKey('mag-paint-$k'),
            onTap: () => state.report(w.paintVehicle(v.id, c)),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Color(c ?? v.spec.color),
                shape: BoxShape.circle,
                border: Border.all(
                  width: v.paint == c ? 3 : 1,
                  color: v.paint == c
                      ? const Color(0xFF2BB59A)
                      : const Color(0x33000000),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
