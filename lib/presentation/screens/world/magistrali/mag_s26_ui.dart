import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Stage S26 in the sheets: the metro (METRO-01), a marshalling yard
/// (HUB-01), a freight hub (HUB-02), cargo futures (FUT-01), an excursion
/// route (TOUR-03).

Widget _buy(
  MagistraliScreenState state,
  String key,
  IconData icon,
  String? why,
  String label,
  String? Function() act,
  String done,
) => SizedBox(
  width: double.infinity,
  child: FilledButton.icon(
    key: ValueKey(key),
    style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
    onPressed: why != null ? null : () => state.report(act(), done),
    icon: Icon(icon),
    label: Text(why ?? label),
  ),
);

/// The town sheet: the metro.
List<Widget> metroSection(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  if (i.town == null) return const [];
  final has = w.metros.contains(i.id);
  return [
    const SizedBox(height: 10),
    Container(
      key: const ValueKey('mag-metro-card'),
      padding: const EdgeInsets.all(12),
      decoration: magCard(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFD64B5C),
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  'M',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Метрополитен',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (has) ...[
            Text(
              'Работает: пассажиров ×${MagRules.metroPassengers}, рост ×${MagRules.metroGrowth}, проезд +${magMoney(w.metroFares(i))} кр в день',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: MagPalette.teal,
              ),
            ),
            // S29: lines to other cities with a metro.
            for (final o in w.settlements.where(
              (o) => o.id != i.id && w.metros.contains(o.id),
            ))
              if (w.metroLineBlocker(i.id, o.id) case final why)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    key: ValueKey('mag-metro-line-${o.id}'),
                    icon: const Icon(Icons.linear_scale_rounded, size: 18),
                    onPressed: why != null
                        ? null
                        : () => state.report(
                            w.buildMetroLine(i.id, o.id),
                            'Линия открыта',
                          ),
                    label: Text(
                      why == 'Линия уже есть'
                          ? 'Линия до «${o.name}» работает'
                          : why ??
                                'Линия до «${o.name}» · ${magMoney(w.metroLinePrice(i, o))} кр',
                    ),
                  ),
                ),
          ] else ...[
            const Text(
              'Подземка для большого города: больше людей едут, город растёт быстрее, а проезд приносит деньги каждый день.',
              style: magMuted,
            ),
            const SizedBox(height: 6),
            _buy(
              state,
              'mag-metro-build',
              Icons.subway_rounded,
              w.metroBlocker(i),
              'Построить метро · ${magMoney(MagRules.metroPrice)} кр',
              () => w.buildMetro(i.id),
              'Метро открыто',
            ),
          ],
        ],
      ),
    ),
  ];
}

/// The station sheet: a marshalling yard.
List<Widget> yardSection(MagistraliScreenState state, int cell) {
  final w = state.world;
  if (w.yards.contains(cell)) {
    return const [
      SizedBox(height: 8),
      Text(
        'Сортировочная горка: поезда грузятся вдвое быстрее',
        key: ValueKey('mag-yard-on'),
        style: TextStyle(fontWeight: FontWeight.w700, color: MagPalette.teal),
      ),
    ];
  }
  return [
    const SizedBox(height: 8),
    _buy(
      state,
      'mag-yard-build',
      Icons.merge_type_rounded,
      w.yardBlocker(cell),
      'Сортировочная горка · ${magMoney(MagRules.yardPrice)} кр',
      () => w.buildYard(cell),
      'Сортировочная построена',
    ),
    const Text(
      'Горка и маневровый тепловоз: поезда на этой станции грузятся вдвое быстрее.',
      style: magMuted,
    ),
  ];
}

/// The warehouse sheet: a freight hub.
List<Widget> hubSection(MagistraliScreenState state, MagIndustry wh) {
  final w = state.world;
  if (w.hubs.contains(wh.id)) {
    return const [
      SizedBox(height: 6),
      Text(
        'Грузовой хаб: места +50%, погрузка вдвое быстрее',
        key: ValueKey('mag-hub-on'),
        style: TextStyle(fontWeight: FontWeight.w700, color: MagPalette.teal),
      ),
    ];
  }
  return [
    const SizedBox(height: 6),
    _buy(
      state,
      'mag-hub-build',
      Icons.hub_rounded,
      w.hubBlocker(wh),
      'Сделать грузовым хабом · ${magMoney(MagRules.hubPrice)} кр',
      () => w.buildHub(wh.id),
      'Хаб открыт',
    ),
  ];
}

/// The exchange tab: cargo futures.
List<Widget> futuresCards(MagistraliScreenState state) {
  final w = state.world;
  final goods = [
    for (final c in MagCargo.values)
      if (!c.people && w.cargoAvailable(c)) c,
  ];
  return [
    const SizedBox(height: 14),
    Container(
      key: const ValueKey('mag-futures-card'),
      padding: const EdgeInsets.all(14),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Фьючерсы на грузы',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Залог ${(MagRules.futureMargin * 100).round()}% цены груза: доставьте объём за ${MagRules.futureDays} дн. — получите ${(MagRules.futurePremium * 100).round()}% цены. Не успели — залог сгорает.',
            style: magMuted,
          ),
          const SizedBox(height: 6),
          if (!w.futuresOpen)
            const Text(
              'Откроются на ${MagRules.futuresLevel} уровне компании',
              style: magMuted,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in goods.take(6))
                  ActionChip(
                    key: ValueKey('mag-future-${c.name}'),
                    label: Text(
                      '${cargoName(c)} 100 · ${magMoney(w.futureMarginOf(c, 100))}',
                    ),
                    onPressed: () =>
                        state.report(w.buyFuture(c, 100), 'Фьючерс куплен'),
                  ),
              ],
            ),
          for (final f in w.futures)
            magRow(
              '${cargoName(f.cargo)}: ${f.done} из ${f.units}',
              '+${magMoney(f.payout)} кр · ${((f.until - w.tick) / MagRules.ticksPerDay).ceil()} дн.',
            ),
        ],
      ),
    ),
  ];
}

/// The route card: an excursion.
Widget excursionTile(MagistraliScreenState state, MagRoute r) {
  final w = state.world;
  final on = w.excursions.contains(r.id);
  final why = w.excursionBlocker(r.id);
  return Material(
    type: MaterialType.transparency,
    child: SwitchListTile(
      key: ValueKey('mag-excursion-${r.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: on,
      activeThumbColor: MagPalette.mint,
      title: const Text('Экскурсия'),
      subtitle: Text(
        on
            ? 'Туристы платят ×${MagRules.excursionPay}'
            : why ?? 'Туристы платят ×${MagRules.excursionPay}',
        style: magMuted,
      ),
      onChanged: (v) => state.report(w.setExcursion(r.id, v)),
    ),
  );
}
