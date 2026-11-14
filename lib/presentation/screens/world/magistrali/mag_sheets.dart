import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_development.dart';
import 'mag_hud.dart';
import 'mag_business.dart';
import 'mag_lore.dart';
import 'mag_orders.dart';
import 'mag_town.dart';
import 'mag_warehouse.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';

String cargoName(MagCargo c) => switch (c) {
  MagCargo.grain => 'Зерно',
  MagCargo.wood => 'Древесина',
  MagCargo.ore => 'Железная руда',
  MagCargo.food => 'Продукты',
  MagCargo.goods => 'Промтовары',
  MagCargo.stone => 'Камень',
  MagCargo.planks => 'Доски',
  MagCargo.flour => 'Мука',
  MagCargo.bread => 'Хлеб',
  MagCargo.coal => 'Уголь',
  MagCargo.clay => 'Глина',
  MagCargo.bricks => 'Кирпич',
  MagCargo.steel => 'Сталь',
  MagCargo.parts => 'Детали',
};

String kindName(MagIndustryKind k) => switch (k) {
  MagIndustryKind.farm => 'Ферма',
  MagIndustryKind.sawmill => 'Лесозаготовка',
  MagIndustryKind.mine => 'Рудник',
  MagIndustryKind.foodPlant => 'Пищевой завод',
  MagIndustryKind.factory => 'Завод',
  MagIndustryKind.city => 'Город',
  MagIndustryKind.village => 'Деревня',
  MagIndustryKind.warehouse => 'Склад',
  MagIndustryKind.quarry => 'Каменоломня',
  MagIndustryKind.mill => 'Мельница',
  MagIndustryKind.bakery => 'Пекарня',
  MagIndustryKind.lumbermill => 'Лесопилка',
  MagIndustryKind.coalMine => 'Угольная шахта',
  MagIndustryKind.clayPit => 'Глиняный карьер',
  MagIndustryKind.brickworks => 'Кирпичный завод',
  MagIndustryKind.steelMill => 'Сталелитейный завод',
  MagIndustryKind.partsFactory => 'Завод деталей',
};

IconData kindIcon(MagIndustryKind k) => switch (k) {
  MagIndustryKind.farm => Icons.agriculture_rounded,
  MagIndustryKind.sawmill => Icons.forest_rounded,
  MagIndustryKind.mine => Icons.landscape_rounded,
  MagIndustryKind.foodPlant => Icons.bakery_dining_rounded,
  MagIndustryKind.factory => Icons.precision_manufacturing_rounded,
  MagIndustryKind.city => Icons.location_city_rounded,
  MagIndustryKind.village => Icons.cottage_rounded,
  MagIndustryKind.warehouse => Icons.warehouse_rounded,
  MagIndustryKind.quarry => Icons.terrain_rounded,
  MagIndustryKind.mill => Icons.wind_power_rounded,
  MagIndustryKind.bakery => Icons.breakfast_dining_rounded,
  MagIndustryKind.lumbermill => Icons.carpenter_rounded,
  MagIndustryKind.coalMine => Icons.fireplace_rounded,
  MagIndustryKind.clayPit => Icons.water_rounded,
  MagIndustryKind.brickworks => Icons.foundation_rounded,
  MagIndustryKind.steelMill => Icons.factory_rounded,
  MagIndustryKind.partsFactory => Icons.settings_rounded,
};

const magMuted = TextStyle(fontSize: 12, color: Color(0xFF5B6B70));
const magTitle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w800,
  color: MagPalette.ink,
);

/// A bottom sheet of the game that refreshes as the simulation runs.
Future<T?> magSheet<T>(
  MagistraliScreenState state,
  String key,
  Widget Function(BuildContext context) build,
) => showModalBottomSheet<T>(
  context: state.context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: const Color(0xFFF7FAF8),
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(state.context).size.height * .82,
  ),
  builder: (context) => ValueListenableBuilder<int>(
    key: ValueKey(key),
    valueListenable: state.ticks,
    builder: (context, _, _) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: build(context),
      ),
    ),
  ),
);

Widget magRow(String label, String value, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(child: Text(label, style: magMuted.copyWith(fontSize: 13))),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color ?? MagPalette.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  ),
);

Widget cargoChip(MagCargo c, [int? n]) => Container(
  margin: const EdgeInsets.only(right: 6, bottom: 6),
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
  decoration: BoxDecoration(
    color: MagPalette.cargo(c).withValues(alpha: .16),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: MagPalette.cargo(c),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        n == null ? cargoName(c) : '${cargoName(c)}: $n',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ],
  ),
);

/// A place: what it makes and takes, its stocks, its road link.
Future<void> showIndustrySheet(
  MagistraliScreenState state,
  int id,
) => magSheet(state, 'mag-industry-$id', (context) {
  final w = state.world;
  final i = w.map.industry(id)!;
  final served = w.accessCells(i).isNotEmpty;
  final spec = i.spec;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(kindIcon(i.kind), color: MagPalette.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(i.name, style: magTitle)),
        ],
      ),
      Text(kindName(i.kind), style: magMuted),
      const SizedBox(height: 4),
      Text(
        industryLore(i.kind),
        style: magMuted.copyWith(fontStyle: FontStyle.italic),
      ),
      const SizedBox(height: 10),
      if (spec.produces.isNotEmpty) ...[
        const Text('Производит в день', style: magMuted),
        Wrap(
          children: [
            for (final e in spec.produces.entries)
              cargoChip(e.key, (e.value * w.outputFactor(i)).round()),
          ],
        ),
      ],
      if (spec.converts.isNotEmpty) ...[
        const Text('Перерабатывает', style: magMuted),
        for (final e in spec.converts.entries)
          Text(
            '${recipeLine(spec, e.key)} · до ${(MagRules.processPerDay * w.outputFactor(i)).round()} в день',
            style: const TextStyle(fontSize: 13),
          ),
        const SizedBox(height: 6),
      ],
      if (spec.accepts.isNotEmpty) ...[
        const Text('Принимает', style: magMuted),
        Wrap(children: [for (final c in spec.accepts) cargoChip(c)]),
      ],
      const Text('На складе', style: magMuted),
      Wrap(
        children: [
          for (final c in i.supplies) cargoChip(c, i.stock[c] ?? 0),
          for (final c in i.supplies)
            if (w.orders.reservedOut(i.id, c) > 0)
              Text(
                'В заказах: ${cargoName(c)} ${w.orders.reservedOut(i.id, c)}',
                style: magMuted,
              ),
          for (final e in i.input.entries)
            if (e.value > 0) cargoChip(e.key, e.value),
          if (i.supplies.isEmpty && i.input.values.every((v) => v == 0))
            const Text('Пусто', style: TextStyle(fontSize: 13)),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(
            served ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
            color: served ? MagPalette.mint : const Color(0xFFE09A3E),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              served
                  ? 'Подключено к дорогам'
                  : 'Нет дороги: проведите дорогу вплотную к территории',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      MagOwnershipPanel(state: state, place: i),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('mag-route-from'),
          style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
          onPressed: () {
            Navigator.pop(context);
            unawaited(showCreateRouteSheet(state, first: id));
          },
          icon: const Icon(Icons.alt_route_rounded),
          label: const Text('Маршрут отсюда'),
        ),
      ),
      if (i.supplies.isNotEmpty)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('mag-order-from'),
            onPressed: () {
              Navigator.pop(context);
              unawaited(showNewOrderSheet(state, from: id));
            },
            icon: const Icon(Icons.assignment_add),
            label: const Text('Заказ на перевозку отсюда'),
          ),
        ),
    ],
  );
});

/// All places, nearest to the view first.
Future<void> showIndustriesSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-industries', (context) {
  final w = state.world, cam = state.camera;
  final list = [...w.map.industries]
    ..sort((a, b) {
      double d(MagIndustry i) =>
          (i.centerX - cam.x).abs() + (i.centerY - cam.y).abs();
      return d(a).compareTo(d(b));
    });
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Предприятия', style: magTitle),
      const SizedBox(height: 6),
      for (final i in list)
        ListTile(
          key: ValueKey('mag-place-${i.id}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(kindIcon(i.kind), color: MagPalette.teal),
          title: Text(
            i.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              i.town != null
                  ? "${i.town!.spec.name}, ${magMoney(i.town!.population)} жит."
                  : kindName(i.kind),
              if (w.accessCells(i).isEmpty) 'нет дороги',
              for (final c in i.supplies) '${cargoName(c)} ${i.stock[c] ?? 0}',
            ].join(' · '),
            style: magMuted,
          ),
          trailing: const Icon(Icons.my_location_rounded, size: 20),
          onTap: () {
            Navigator.pop(context);
            state.centerOn(i.centerX, i.centerY);
            state.overlay.industry = i.id;
            unawaited(
              i.town != null
                  ? showTownSheet(state, i.id)
                  : i.spec.stores
                  ? showWarehouseSheet(state, i.id)
                  : showIndustrySheet(state, i.id),
            );
          },
        ),
    ],
  );
});

Future<void> showContractsSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-contracts', (context) {
  final w = state.world;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Контракты', style: magTitle),
      Text(
        'Доставьте груз в указанное место — награда сверх оплаты рейсов. Слотов: ${w.contractSlots}.',
        style: magMuted,
      ),
      const SizedBox(height: 10),
      ...cityOrderCards(state, context),
      for (final c in w.regularContracts)
        Container(
          key: ValueKey('mag-contract-${c.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: magCard(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  cargoChip(c.cargo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '+${magMoney(c.reward)} кр · ${c.xp} оп.',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: MagPalette.teal,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${c.amount} ед. → ${w.map.industry(c.to)?.name ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: c.delivered / c.amount,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: MagPalette.mint,
                backgroundColor: const Color(0x1F2BB59A),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.delivered} из ${c.amount}',
                      style: magMuted,
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.report(
                      w.replaceContract(c.id),
                      'Контракт заменён',
                    ),
                    child: const Text('Заменить · 150 кр'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ...developmentCards(state, context),
    ],
  );
});

/// The company: level, what is open and what opens next.
Future<void> showCompanySheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-company', (context) {
  final w = state.world;
  final lvl = w.level;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Компания · уровень $lvl', style: magTitle),
      Text(
        'Опыт ${magMoney(w.xp)} из ${magMoney(MagWorldProgress.xpFor(lvl + 1))} · улучшения до ${w.maxUpgradeLevel} ур.',
        style: magMuted,
      ),
      const SizedBox(height: 8),
      magRow('Машин', '${w.vehicles.length}'),
      magRow('Маршрутов', '${w.routes.length}'),
      magRow('Дорог, клеток', '${w.roads.where((r) => r != 0).length}'),
      magRow(
        'Перевезено, ед.',
        '${w.delivered.values.fold(0, (a, b) => a + b)}',
      ),
      const SizedBox(height: 10),
      const Text('Развитие', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final u in MagWorldProgress.unlocks)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            lvl >= u.level && !u.soon
                ? Icons.check_circle_rounded
                : u.soon
                ? Icons.schedule_rounded
                : Icons.lock_outline_rounded,
            color: lvl >= u.level && !u.soon
                ? MagPalette.mint
                : const Color(0xFF9AA6AA),
          ),
          title: Text(u.title),
          trailing: Text(
            u.soon ? 'ур. ${u.level} · скоро' : 'ур. ${u.level}',
            style: magMuted,
          ),
        ),
    ],
  );
});
