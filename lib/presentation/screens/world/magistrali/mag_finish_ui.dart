import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_icons.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// S20 in a business sheet: its mountain range (MAP-07), the region's
/// speciality (BIZ-12), the cost of a unit (FIN-06), export of surplus
/// (LOG-13).
List<Widget> finishInfo(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  final range = w.mountainOf(i);
  final sector = w.regionSpecialization(w.regionOf(i.x, i.y));
  final cost = i.owned ? w.unitCost(i) : null;
  return [
    if (range != null && w.mountainFactor(i) > 1)
      Text(
        '▲ ${range.name}: в горах добыча +${((MagRules.mountainYield - 1) * 100).round()}%',
        key: const ValueKey('mag-mountain'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    if (sector != null)
      Text(
        'Регион: $sector${w.regionFactor(i) > 1 ? ' — ваш выпуск здесь +${((MagRules.regionYield - 1) * 100).round()}%' : ''}',
        key: const ValueKey('mag-region-sector'),
        style: magMuted,
      ),
    if (cost != null)
      Text(
        'Себестоимость единицы: ${cost.toStringAsFixed(1)} кр',
        key: const ValueKey('mag-unit-cost'),
        style: magMuted,
      ),
    if (i.owned && i.supplies.isNotEmpty)
      SwitchListTile(
        key: const ValueKey('mag-export'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: w.autoExport.contains(i.id),
        activeThumbColor: MagPalette.mint,
        title: const Text('Автоэкспорт излишков'),
        subtitle: const Text(
          'Всё сверх 80% склада продаётся за полцены, выпуск не встаёт',
          style: magMuted,
        ),
        onChanged: (v) => state.report(w.setAutoExport(i.id, v)),
      ),
  ];
}

/// S20 in a settlement sheet: how many ways reach it (CITY-10).
List<Widget> townAccessInfo(MagWorld w, MagIndustry i) {
  final n = w.accessModes(i);
  return [
    Text(
      n == 0
          ? 'Транспорт: не подключено — жители приходят медленно'
          : 'Транспорт: ${[if (w.accessCells(i).isNotEmpty) 'дорога', if (w.stationCells(i).isNotEmpty) 'ж/д', if (w.portCells(i).isNotEmpty) 'вода'].join(', ')}'
                '${n > 1 ? ' — жители приходят на ${((w.accessFactor(i) - 1) * 100).round()}% быстрее' : ''}',
      key: const ValueKey('mag-town-access'),
      style: magMuted,
    ),
  ];
}

/// The map and its regions (S20): whether every chain can be built
/// (MAP-04), the mountain ranges (MAP-07), each region's speciality and
/// figures (BIZ-12, FIN-10), and the journal of simulation errors
/// (CORE-10).
Future<void> showMapReportSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-map-report', (context) {
  final w = state.world;
  final chains = w.chainReport();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Карта и регионы', style: magTitle),
      const SizedBox(height: 8),
      Text(
        w.mapViable
            ? 'Карта проверена: все цепочки можно построить'
            : 'Есть цепочки без сырья поблизости',
        key: const ValueKey('mag-map-viable'),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: w.mapViable ? MagPalette.teal : const Color(0xFFD64B5C),
        ),
      ),
      for (final (k, c, d) in chains)
        magRow(
          '${kindName(k)} ← ${cargoName(c).toLowerCase()}',
          d == null ? 'нет на карте' : '$d кл.',
          color: d != null && d <= MagRules.chainReach
              ? MagPalette.teal
              : const Color(0xFFD64B5C),
        ),
      const SizedBox(height: 10),
      const Text('Горы', style: TextStyle(fontWeight: FontWeight.w800)),
      if (w.mountains.isEmpty)
        const Text('Больших хребтов нет', style: magMuted),
      for (final m in w.mountains)
        magRow('▲ ${m.name}', '${m.cells} кл. · добыча +20%'),
      const SizedBox(height: 10),
      const Text('Регионы', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final (r, places, own, revenue) in w.regionStats())
        magRow(
          'Регион ${r + 1}${w.regionOpen((r % 3) * (w.size / 3).ceil(), (r ~/ 3) * (w.size / 3).ceil()) ? '' : ' (закрыт)'}'
              ' · ${w.regionSpecialization(r) ?? '—'}'
              '${w.biomesOn ? ' · ${MagWorldBiomes.biomeName(w.biomeOf(r))}: ${MagWorldBiomes.biomeBonus(w.biomeOf(r))}' : ''}',
          '$places мест · ваших $own · ${magMoney(revenue)} кр',
        ),
      const SizedBox(height: 10),
      const Text(
        'Журнал ошибок',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      if (w.simErrors.isEmpty)
        const Text(
          'Ошибок нет',
          key: ValueKey('mag-errors-none'),
          style: magMuted,
        ),
      for (final (t, s) in w.simErrors.reversed.take(20))
        Text(
          'День ${t ~/ MagRules.ticksPerDay + 1}: $s',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
        ),
    ],
  );
});

/// City subsidies (CONT-10): lines a city pays 40% more for, for a while.
List<Widget> subsidyCards(MagistraliScreenState state) {
  final w = state.world;
  if (w.subsidies.isEmpty) return const [];
  return [
    Text(
      'Субсидии городов · +${(MagRules.subsidyBonus * 100).round()}% к оплате',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 6),
    for (final s in w.subsidies)
      Container(
        key: ValueKey('mag-subsidy-${s.from}-${s.to}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: magCard(16),
        child: Row(
          children: [
            MagCargoIcon(s.cargo, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${w.map.industry(s.from)?.name ?? '?'} → ${w.map.industry(s.to)?.name ?? '?'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${cargoName(s.cargo)} · ещё ${((s.until - w.tick) / MagRules.ticksPerDay).ceil()} дн.',
                    style: magMuted,
                  ),
                ],
              ),
            ),
            FilledButton(
              key: ValueKey('mag-subsidy-route-${s.from}-${s.to}'),
              style: FilledButton.styleFrom(
                backgroundColor: MagPalette.mint,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                Navigator.pop(state.context);
                state.report(
                  w.createRoute([s.from, s.to]),
                  'Маршрут создан — назначьте машину',
                );
              },
              child: const Text('Маршрут'),
            ),
          ],
        ),
      ),
    const SizedBox(height: 6),
  ];
}
