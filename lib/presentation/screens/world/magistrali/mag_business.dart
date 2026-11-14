import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Owning a business: who owns it, its level and figures, and the buttons
/// to buy, modernise or sell it.
class MagOwnershipPanel extends StatelessWidget {
  const MagOwnershipPanel({
    super.key,
    required this.state,
    required this.place,
  });
  final MagistraliScreenState state;
  final MagIndustry place;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    final i = place;
    if (!w.forSale(i)) return const SizedBox.shrink();
    final up = w.upgradePrice(i);
    final profit = i.revenue - i.costs;
    return Container(
      key: ValueKey('mag-business-${i.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                i.owned ? Icons.flag_rounded : Icons.storefront_rounded,
                color: i.owned ? MagPalette.mint : const Color(0xFF8A9599),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i.owned
                      ? 'Ваше предприятие · уровень ${i.level} из ${MagRules.maxIndustryLevel}'
                      : 'Независимое · уровень ${i.level}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            i.owned
                ? 'Свой товар, проданный внешним покупателям, приносит его цену сверх оплаты перевозки. Перевозки между своими предприятиями — внутренние, без выручки.'
                : 'Можно возить его груз за плату или купить предприятие: тогда его продукция станет вашей, а сырьё для него придётся покупать.',
            style: magMuted,
          ),
          if (i.owned) ...[
            const SizedBox(height: 6),
            magRow('Выпущено', '${i.produced} ед.'),
            magRow('Продано внешним покупателям', '${i.sold} ед.'),
            magRow(
              'Выручка',
              '${magMoney(i.revenue)} кр',
              color: MagPalette.teal,
            ),
            magRow(
              'Расходы (сырьё, переработка, содержание)',
              '${magMoney(i.costs)} кр',
            ),
            magRow(
              'Операционная прибыль',
              '${magMoney(profit)} кр',
              color: profit >= 0 ? MagPalette.teal : const Color(0xFFD64B5C),
            ),
            magRow(
              'Вложено (покупка и модернизация)',
              '${magMoney(i.invested)} кр',
            ),
            magRow('Содержание', '${w.upkeepOfIndustry(i)} кр/день'),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!i.owned)
                FilledButton.icon(
                  key: const ValueKey('mag-business-buy'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MagPalette.mint,
                  ),
                  onPressed: () => state.report(
                    w.buyIndustry(i.id),
                    '${i.name} теперь ваше',
                  ),
                  icon: const Icon(Icons.handshake_rounded),
                  label: Text('Купить · ${magMoney(w.buyPrice(i))} кр'),
                ),
              if (i.owned && up != null)
                FilledButton.icon(
                  key: const ValueKey('mag-business-upgrade'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MagPalette.mint,
                  ),
                  onPressed: () => state.report(
                    w.upgradeIndustry(i.id),
                    'Уровень ${i.level + 1}',
                  ),
                  icon: const Icon(Icons.trending_up_rounded),
                  label: Text('Модернизировать · ${magMoney(up)} кр'),
                ),
              if (i.owned)
                TextButton(
                  key: const ValueKey('mag-business-sell'),
                  onPressed: () => state.report(
                    w.sellIndustry(i.id),
                    'Продано за ${magMoney(w.sellPrice(i))} кр',
                  ),
                  child: Text('Продать · ${magMoney(w.sellPrice(i))} кр'),
                ),
            ],
          ),
          if (i.owned && up != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Модернизация: выпуск +${(MagRules.levelOutput * 100).round()}% и склад +${(MagRules.levelStorage * 100).round()}% за уровень, содержание растёт.',
                style: magMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Picks what to build (then a tap on the map places it).
Future<MagIndustryKind?> showBuildPicker(MagistraliScreenState state) {
  final w = state.world;
  final kinds = MagIndustryKind.values.where((k) {
    final s = MagRules.industries[k]!;
    return s.price > 0 && !s.stores;
  });
  return showModalBottomSheet<MagIndustryKind>(
    context: state.context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(state.context).size.height * .8,
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Построить предприятие', style: magTitle),
            Text(
              w.level < 2
                  ? 'Строить можно со 2 уровня компании. Купить готовое можно уже сейчас — в карточке предприятия.'
                  : 'Строить дороже, чем покупать, зато место выбираете вы.',
              style: magMuted,
            ),
            for (final k in kinds)
              ListTile(
                key: ValueKey('mag-build-${k.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(kindIcon(k), color: MagPalette.teal),
                title: Text(
                  kindName(k),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_recipe(k), style: magMuted),
                trailing: Text('${magMoney(w.buildPrice(k))} кр'),
                onTap: () => Navigator.pop(context, k),
              ),
          ],
        ),
      ),
    ),
  );
}

String _recipe(MagIndustryKind k) {
  final s = MagRules.industries[k]!;
  final parts = [
    for (final e in s.produces.entries) '${cargoName(e.key)} ${e.value} в день',
    for (final e in s.converts.entries)
      '${s.ratio[e.key] ?? 1} ${cargoName(e.key).toLowerCase()} → 1 ${cargoName(e.value).toLowerCase()}',
    if (s.near == MagTerrain.forest) 'у леса',
    if (s.near == MagTerrain.hill) 'у холмов',
    '${s.size}×${s.size}',
  ];
  return parts.join(' · ');
}

String entryKindName(MagEntryKind k) => switch (k) {
  MagEntryKind.revenue => 'Выручка',
  MagEntryKind.opex => 'Операционные расходы',
  MagEntryKind.capex => 'Вложения',
  MagEntryKind.transfer => 'Внутренние передачи',
  MagEntryKind.assetSale => 'Продажа активов',
};

/// The journal: this month by kind (revenue, running costs, investments,
/// asset sales kept apart) and the latest entries with their ids.
class MagJournalPanel extends StatelessWidget {
  const MagJournalPanel({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world;
    final from = w.month.index * MagRules.daysPerMonth * MagRules.ticksPerDay;
    final revenue = w.journal.total(MagEntryKind.revenue, fromTick: from);
    final opex = w.journal.total(MagEntryKind.opex, fromTick: from);
    final capex = w.journal.total(MagEntryKind.capex, fromTick: from);
    final assets = w.journal.total(MagEntryKind.assetSale, fromTick: from);
    final transfers = w.journal.entries
        .where((e) => e.kind == MagEntryKind.transfer && e.tick >= from)
        .fold(0, (n, e) => n + e.units);
    return Container(
      key: const ValueKey('mag-journal'),
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Журнал операций · этот месяц',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          magRow('Выручка', magMoney(revenue), color: MagPalette.teal),
          magRow('Операционные расходы', magMoney(opex)),
          magRow(
            'Операционная прибыль',
            magMoney(revenue + opex),
            color: revenue + opex >= 0
                ? MagPalette.teal
                : const Color(0xFFD64B5C),
          ),
          magRow('Вложения (не в прибыли)', magMoney(capex)),
          if (assets != 0) magRow('Продажа активов', magMoney(assets)),
          if (transfers > 0) magRow('Внутренние передачи, ед.', '$transfers'),
          const Divider(),
          for (final e in w.journal.entries.reversed.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text('№${e.id}', style: magMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        magIncomeNames[e.category] ??
                            magExpenseNames[e.category] ??
                            (e.category == 'transfer'
                                ? 'Внутренняя передача'
                                : e.category),
                        if (e.cargo != null)
                          '${cargoName(e.cargo!).toLowerCase()} ${e.units}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    e.amount == 0
                        ? '—'
                        : (e.amount > 0
                              ? '+${magMoney(e.amount)}'
                              : magMoney(e.amount)),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: e.amount > 0 ? MagPalette.teal : MagPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
          if (w.journal.entries.isEmpty)
            const Text('Записей пока нет.', style: magMuted),
        ],
      ),
    );
  }
}

/// Names of money categories (the journal and finances).
const magExpenseNames = {
  'purchase': 'Закупка сырья',
  'production': 'Переработка',
  'industry_upkeep': 'Содержание предприятий',
  'industry_buy': 'Покупка предприятий',
  'industry_build': 'Строительство предприятий',
  'industry_upgrade': 'Модернизация предприятий',
  'vehicles': 'Покупка транспорта',
  'roads': 'Строительство дорог',
  'upgrades': 'Модернизация',
  'upkeep': 'Обслуживание машин',
  'running': 'Топливо и пробег',
  'service': 'Ремонт',
  'roads_upkeep': 'Содержание дорог',
  'contracts': 'Замена контрактов',
  'research': 'Исследования',
  'warehouses': 'Строительство складов',
};
const magIncomeNames = {
  'goods_sale': 'Продажа продукции',
  'industry_sale': 'Продажа предприятий',
  'warehouse_sale': 'Снос складов',
  'delivery': 'Перевозки',
  'contracts': 'Контракты',
  'bonus': 'Задания и премии',
  'sales': 'Продажа техники',
};
