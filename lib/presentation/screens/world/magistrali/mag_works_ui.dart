import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Special contracts in the contracts sheet (CONT-04…07): what, where,
/// how far along, until when; give one up without a fine.
List<Widget> dealCards(MagistraliScreenState state) {
  final w = state.world;
  if (w.dealSlots == 0) {
    return const [
      Text(
        'Особые контракты — с 3 уровня: производственные заказы, снабжение, многоэтапные и региональные.',
        style: magMuted,
      ),
      SizedBox(height: 10),
    ];
  }
  String days(int t) => '${((t - w.tick) / MagRules.ticksPerDay).ceil()} дн.';
  return [
    Text(
      'Особые контракты · ${w.deals.length} из ${w.dealSlots}',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    if (w.deals.isEmpty) const Text('Новые появятся завтра.', style: magMuted),
    for (final d in w.deals)
      Container(
        key: ValueKey('mag-deal-${d.id}'),
        margin: const EdgeInsets.only(top: 8, bottom: 2),
        padding: const EdgeInsets.all(12),
        decoration: magCard(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (d.kind) {
                  MagDealKind.production => Icons.precision_manufacturing,
                  MagDealKind.supply => Icons.event_repeat_rounded,
                  MagDealKind.stages => Icons.linear_scale_rounded,
                  MagDealKind.region => Icons.travel_explore_rounded,
                }, color: MagPalette.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    w.dealTitle(d),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '+${magMoney(d.reward)} кр',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: MagPalette.teal,
                  ),
                ),
              ],
            ),
            Text(switch (d.kind) {
              MagDealKind.production =>
                'Произведите на своём заводе: ${cargoName(d.cargo).toLowerCase()} ${d.delivered}/${d.amount}',
              MagDealKind.supply =>
                'Каждые ${d.period} дн.: ${cargoName(d.cargo).toLowerCase()} ${d.delivered}/${d.amount} · осталось периодов ${d.periodsLeft} · до конца периода ${days(d.periodEnd)}',
              MagDealKind.stages =>
                'Этап ${d.stage + 1} из ${d.stages.length}: ${cargoName(d.cargo).toLowerCase()} → «${w.map.industry(d.to)?.name}» ${d.delivered}/${d.amount}',
              MagDealKind.region =>
                '${d.radius == 0
                    ? 'Только «${w.map.industry(d.to)?.name}»'
                    : d.radius >= 9999
                    ? 'Любому поселению'
                    : 'Любым поселениям в ${d.radius} клетках'}: ${cargoName(d.cargo).toLowerCase()} ${d.delivered}/${d.amount}',
            }, style: magMuted),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: d.amount == 0 ? 0 : d.delivered / d.amount,
              color: MagPalette.mint,
              backgroundColor: const Color(0x222BB59A),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.deadline == null
                        ? 'Без срока'
                        : 'Срок: ${days(d.deadline!)}',
                    style: magMuted,
                  ),
                ),
                TextButton(
                  key: ValueKey('mag-deal-drop-${d.id}'),
                  onPressed: () => state.report(w.dropDeal(d.id)),
                  child: const Text('Отказаться'),
                ),
              ],
            ),
          ],
        ),
      ),
    const SizedBox(height: 10),
  ];
}

/// A business sheet's S16 lines: a rich deposit (MAP-10) and, for an own
/// plant with several recipes, what to process first (BIZ-06).
List<Widget> worksInfo(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  return [
    if (w.isRich(i))
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(Icons.diamond_rounded, size: 18, color: Color(0xFF3FA7D6)),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Богатое месторождение: добыча +50%',
                key: ValueKey('mag-rich'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    if (MagRules.byProducts[i.kind] case final b?)
      Text(
        'Побочная продукция: ${cargoName(b.$1).toLowerCase()} — ${(b.$2 * 100).round()}% от выпуска',
        key: const ValueKey('mag-byproduct'),
        style: magMuted,
      ),
    if (w.complexPartner(i) case final p?)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'Промышленный комплекс с «${p.name}»: выработка +${(MagRules.complexBonus * 100).round()}%, до ${MagRules.conveyorPerDay} ед. в день идут напрямую',
          key: const ValueKey('mag-complex'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    if (i.owned && i.spec.converts.length > 1) ...[
      const Text('Сначала перерабатывать', style: magMuted),
      Wrap(
        spacing: 6,
        children: [
          for (final c in [null, ...i.spec.converts.keys])
            ChoiceChip(
              key: ValueKey('mag-first-${c?.name ?? 'any'}'),
              label: Text(c == null ? 'Как придётся' : cargoName(c)),
              selected: w.firstInput[i.id] == c,
              selectedColor: const Color(0x332BB59A),
              onSelected: (_) => state.report(w.setFirstInput(i.id, c)),
            ),
        ],
      ),
      const SizedBox(height: 6),
    ],
  ];
}

/// Opening a closed region of the map (MAP-08).
Future<void> showRegionSheet(
  MagistraliScreenState state,
  int region,
) => magSheet(state, 'mag-region', (context) {
  final w = state.world;
  final price = w.regionPrice;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Закрытый регион', style: magTitle),
      Text(
        'Чтобы строить здесь дороги, пути и предприятия, купите право на регион. Открыто ${w.openRegions.length} из 9, каждый следующий дороже.',
        style: magMuted,
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('mag-region-open'),
          style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
          onPressed: price > w.money
              ? null
              : () {
                  if (state.report(w.openRegion(region), 'Регион открыт')) {
                    Navigator.pop(context);
                  }
                },
          child: Text(
            price > w.money
                ? 'Нужно ${magMoney(price)} кр'
                : 'Открыть регион · ${magMoney(price)} кр',
          ),
        ),
      ),
    ],
  );
});

/// The auction lot (BIZ-13): rivals raise the price every day.
List<Widget> auctionCards(MagistraliScreenState state) {
  final w = state.world;
  final a = w.auction;
  if (a == null) return const [];
  final i = w.map.industry(a.industry)!;
  final days = ((a.end - w.tick) / MagRules.ticksPerDay).ceil();
  return [
    Container(
      key: const ValueKey('mag-auction'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Аукцион: ${i.name}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Цена ${magMoney(a.price)} кр вместо ${magMoney(w.buyPrice(i))} · соперники поднимают её на ${(MagRules.auctionRise * 100).round()}% в день · осталось $days дн.',
            style: magMuted,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('mag-auction-buy'),
              style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
              onPressed: a.price > w.money
                  ? null
                  : () => state.report(w.buyAuction(), 'Куплено на аукционе'),
              child: const Text('Купить сейчас'),
            ),
          ),
        ],
      ),
    ),
  ];
}
