import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_lore.dart';
import 'mag_orders.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// A logistics centre: whether it works and why not, its reach and its
/// open orders, what it supplies, what the places around it are short of,
/// its level. Its reach is lit on the map while the sheet is open.
Future<void> showCenterSheet(MagistraliScreenState state, int id) async {
  final w = state.world;
  void light() {
    final c = w.map.industry(id);
    if (c == null) return;
    final r = w.centerRadius(c);
    state.overlay
      ..plan = [
        for (var y = c.centerY.floor() - r; y <= c.centerY.floor() + r; y++)
          for (var x = c.centerX.floor() - r; x <= c.centerX.floor() + r; x++)
            if (w.map.inside(x, y) &&
                (x - c.centerX).abs() + (y - c.centerY).abs() <= r)
              w.cellOf(x, y),
      ]
      ..planOk = true;
  }

  light();
  await magSheet<void>(state, 'mag-center-$id', (context) {
    final c = w.map.industry(id);
    if (c == null) return const Text('Центр продан');
    final idle = w.centerIdle(c);
    final open = w.centerOrders(c);
    final area = w.centerArea(c).toList()
      ..sort((a, b) => a.distanceTo(c).compareTo(b.distanceTo(c)));
    final upgrade = w.upgradePrice(c);
    return Column(
      key: const ValueKey('mag-center-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_rounded, color: MagPalette.teal),
            const SizedBox(width: 8),
            Expanded(child: Text(c.name, style: magTitle)),
          ],
        ),
        Text(industryLore(c.kind), style: magMuted),
        const SizedBox(height: 8),
        Text(
          idle ?? 'Работает: заявки выполняют машины автопарка',
          key: const ValueKey('mag-center-status'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: idle == null ? MagPalette.teal : const Color(0xFFD64B5C),
          ),
        ),
        magRow('Уровень', '${c.level}'),
        magRow('Радиус', '${w.centerRadius(c)} кл.'),
        magRow('Открытых заявок', '${open.length} из ${w.centerOrderCap(c)}'),
        magRow('Заявок создано всего', '${c.ordersMade}'),
        magRow('Содержание', '${magMoney(w.upkeepOfIndustry(c))} кр в день'),
        SwitchListTile(
          key: const ValueKey('mag-center-plants'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Снабжать свои производства'),
          value: c.supplyPlants,
          onChanged: (v) => state.report(w.setCenterSupply(id, plants: v)),
        ),
        SwitchListTile(
          key: const ValueKey('mag-center-towns'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Снабжать поселения'),
          value: c.supplyTowns,
          onChanged: (v) => state.report(w.setCenterSupply(id, towns: v)),
        ),
        const SizedBox(height: 6),
        const Text('Рядом', style: TextStyle(fontWeight: FontWeight.w800)),
        if (area.isEmpty)
          const Text(
            'В радиусе нет своих производств и поселений.',
            style: magMuted,
          ),
        for (final i in area.take(12))
          magRow(i.name, () {
            final s = w.shortages(i);
            if (s.isEmpty) return 'всего хватает';
            return 'нужно: ${s.entries.map((e) => '${cargoName(e.key).toLowerCase()} ${e.value.$1}').join(', ')}';
          }()),
        if (open.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Заявки центра',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final o in open)
            Text(
              '№${o.id} ${cargoName(o.cargo)} ${o.amount}: ${w.map.industry(o.supplier)?.name ?? '—'} → ${w.map.industry(o.receiver)?.name ?? '—'} · ${orderStatusName(o.status).toLowerCase()}',
              style: magMuted,
            ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('mag-center-upgrade'),
                style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
                onPressed: upgrade == null || w.money < upgrade
                    ? null
                    : () {
                        if (state.report(
                          w.upgradeIndustry(id),
                          'Центр расширен',
                        )) {
                          light();
                        }
                      },
                child: Text(
                  upgrade == null
                      ? 'Высший уровень'
                      : 'Расширить · ${magMoney(upgrade)} кр',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('mag-center-sell'),
              onPressed: () {
                if (state.report(w.sellIndustry(id), 'Центр продан')) {
                  Navigator.pop(context);
                }
              },
              child: Text('Продать · ${magMoney(w.sellPrice(c))}'),
            ),
          ],
        ),
      ],
    );
  });
  state.overlay
    ..plan = const []
    ..planOk = true;
  state.changed();
}
