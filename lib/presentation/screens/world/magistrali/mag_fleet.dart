import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_dispatch.dart';
import 'mag_hud.dart';
import 'mag_lore.dart';
import 'mag_orders.dart';
import 'mag_rail_ui.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

String stateName(MagWorld w, MagVehicle v) {
  final r = w.routes[v.routeId];
  final o = v.orderId == null ? null : w.orders.byId(v.orderId!);
  if (o != null) {
    return 'Заказ №${o.id}: ${orderStatusName(o.status).toLowerCase()}';
  }
  return switch (v.state) {
    MagVehicleState.idle =>
      v.auto ? 'Автопарк: ждёт заявку' : 'Свободен, ждёт заказ',
    MagVehicleState.garage => 'В гараже',
    MagVehicleState.noRoad => 'Нет дороги до остановки',
    MagVehicleState.driving =>
      'Едет: ${w.map.industry(r?.stops[v.stop % r.stops.length] ?? -1)?.name ?? ''}',
    MagVehicleState.atStop => v.load > 0 ? 'Загружается' : 'Ждёт груз',
  };
}

String upgradeName(MagUpgrade u, [bool horse = false]) => horse
    ? switch (u) {
        MagUpgrade.engine => 'Порода лошадей',
        MagUpgrade.body => 'Повозка побольше',
        MagUpgrade.economy => 'Корм и упряжь',
        MagUpgrade.reliability => 'Подковы и колёса',
      }
    : switch (u) {
        MagUpgrade.engine => 'Двигатель',
        MagUpgrade.body => 'Кузов',
        MagUpgrade.economy => 'Экономичность',
        MagUpgrade.reliability => 'Надёжность',
      };

IconData upgradeIcon(MagUpgrade u) => switch (u) {
  MagUpgrade.engine => Icons.speed_rounded,
  MagUpgrade.body => Icons.inventory_2_rounded,
  MagUpgrade.economy => Icons.local_gas_station_rounded,
  MagUpgrade.reliability => Icons.build_circle_rounded,
};

Widget _truckTile(
  MagistraliScreenState state,
  MagVehicle v,
  BuildContext context,
) {
  final w = state.world;
  return ListTile(
    key: ValueKey('mag-truck-${v.id}'),
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: Color(v.spec.color).withValues(alpha: .18),
      child: Icon(
        v.spec.rail ? Icons.train_rounded : Icons.local_shipping_rounded,
        color: Color(v.spec.color),
      ),
    ),
    title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      [
        if (v.auto) 'автопарк',
        stateName(w, v),
        if (v.load > 0) '${cargoName(v.cargo!)} ${v.load}',
        'износ ${v.wear.round()}%',
      ].join(' · '),
      style: magMuted,
    ),
    trailing: Text(
      '+${magMoney(v.income)}',
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: MagPalette.teal,
      ),
    ),
    onTap: () {
      Navigator.pop(context);
      unawaited(showVehicleSheet(state, v.id));
    },
  );
}

/// The fleet and the truck shop.
Future<void> showFleetSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-fleet', (context) {
  final w = state.world;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Транспорт · ${w.vehicles.length}', style: magTitle),
      const SizedBox(height: 6),
      MagDispatchPanel(state: state),
      for (final v in w.vehicles.values) _truckTile(state, v, context),
      const SizedBox(height: 10),
      const Text(
        'Купить грузовик',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      const Text('Эпоха I — гужевой транспорт', style: magMuted),
      for (final m in MagRules.trucks.where((m) => m.horse))
        _shopCard(state, m),
      Text(
        w.motorUnlocked
            ? 'Грузовики'
            : 'Грузовики — после технологии «Двигатель внутреннего сгорания»',
        style: magMuted,
      ),
      for (final m in MagRules.trucks.where((m) => !m.horse && !m.rail))
        _shopCard(state, m),
      Text(
        w.railsUnlocked
            ? 'Эпоха II — железная дорога: локомотив и вагоны'
            : 'Железная дорога — после технологии «Паровая тяга»',
        style: magMuted,
      ),
      for (final m in MagRules.trucks.where((m) => m.rail)) _shopCard(state, m),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        key: const ValueKey('mag-open-orders'),
        onPressed: () {
          Navigator.pop(context);
          unawaited(showOrdersSheet(state));
        },
        icon: const Icon(Icons.assignment_turned_in_rounded),
        label: Text('Логистические заказы · ${w.orders.active.length}'),
      ),
      const SizedBox(height: 4),
      const Text(
        'Корабли появятся на следующих этапах развития.',
        style: magMuted,
      ),
    ],
  );
});

Widget _shopCard(MagistraliScreenState state, MagTruckModel m) {
  final w = state.world;
  final open =
      w.level >= m.level &&
      (m.rail
          ? w.railsUnlocked && (m.id != 'diesel' || w.dieselUnlocked)
          : m.horse || w.motorUnlocked);
  return Container(
    key: ValueKey('mag-shop-${m.id}'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: magCard(16),
    child: Row(
      children: [
        Icon(
          m.rail
              ? Icons.train_rounded
              : m.horse
              ? Icons.agriculture_rounded
              : Icons.local_shipping_rounded,
          size: 34,
          color: open ? Color(m.color) : const Color(0xFFB6BEC1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                m.rail
                    ? 'Скорость ${m.speed.toStringAsFixed(2)} · вагон ${m.wagonCapacity} ед., до ${m.maxWagons} вагонов · расход ${m.runningCost}/кл. + ${MagRules.wagonRunning} за вагон'
                    : 'Скорость ${m.speed.toStringAsFixed(2)} · груз ${m.capacity} · ${m.horse ? 'корм' : 'расход'} ${m.runningCost}/кл.',
                style: magMuted,
              ),
              const SizedBox(height: 2),
              Text(
                truckLore(m.id),
                style: magMuted.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          key: ValueKey('mag-buy-${m.id}'),
          style: FilledButton.styleFrom(
            backgroundColor: MagPalette.mint,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: open
              ? () => state.report(
                  w.buyTruck(m.id),
                  'Куплен ${m.name} — назначьте его на маршрут',
                )
              : null,
          child: Text(
            open
                ? magMoney(m.price + m.wagonPrice)
                : w.level < m.level
                ? 'ур. ${m.level}'
                : m.rail
                ? 'техн.'
                : 'мотор',
          ),
        ),
      ],
    ),
  );
}

/// One truck: what it does, its stats, the four upgrade lines, route,
/// repair and sale.
Future<void> showVehicleSheet(MagistraliScreenState state, int id) => magSheet(
  state,
  'mag-vehicle-$id',
  (context) {
    final w = state.world;
    final v = w.vehicles[id];
    if (v == null) return const Text('Машина продана');
    final route = w.routes[v.routeId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(v.name, style: magTitle),
        Text('${v.spec.name} · ${stateName(w, v)}', style: magMuted),
        const SizedBox(height: 8),
        magRow('Скорость', '${w.speedOf(v).toStringAsFixed(2)} кл./с'),
        magRow('Грузоподъёмность', '${w.capacityOf(v)} ед.'),
        magRow('Расход', '${w.runningCostOf(v).toStringAsFixed(2)} кр/кл.'),
        magRow('Обслуживание', '${w.upkeepOf(v)} кр/день'),
        magRow(
          'Износ',
          '${v.wear.round()}% (−${(35 * v.wear / 100).round()}% скорости)',
        ),
        magRow(
          'Груз',
          v.load > 0 ? '${cargoName(v.cargo!)} · ${v.load}' : 'пусто',
        ),
        magRow('Пробег', '${v.odometer.round()} кл.'),
        magRow('Рейсов', '${v.trips}'),
        magRow(
          'Доход за всё время',
          '${magMoney(v.income)} кр',
          color: MagPalette.teal,
        ),
        magRow('Маршрут', route?.name ?? 'нет'),
        if (v.spec.rail) ...trainPanel(state, v),
        if (!v.spec.rail)
          SwitchListTile(
            key: const ValueKey('mag-auto-toggle'),
            contentPadding: EdgeInsets.zero,
            value: v.auto,
            activeThumbColor: MagPalette.mint,
            title: const Text('Автопарк'),
            subtitle: Text(
              w.dispatcherUnlocked
                  ? 'Диспетчер сам даёт машине заявки. Маршрут снимается.'
                  : 'Откроет технология «Диспетчерская»',
              style: magMuted,
            ),
            onChanged: (on) => state.report(
              w.setAuto(v.id, on),
              on
                  ? '${v.name} в автопарке'
                  : '${v.name} снова под вашим управлением',
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Улучшения · доступно до ${w.maxUpgradeLevel} ур.',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        for (final u in MagUpgrade.values) _upgradeRow(state, v, u),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('mag-assign'),
              style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
              onPressed: () => unawaited(_pickRoute(state, v, context)),
              icon: const Icon(Icons.alt_route_rounded),
              label: Text(
                route == null ? 'Назначить маршрут' : 'Сменить маршрут',
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('mag-service'),
              onPressed: w.serviceCost(v) == 0
                  ? null
                  : () =>
                        state.report(w.service(v.id), 'Машина отремонтирована'),
              icon: const Icon(Icons.build_rounded),
              label: Text('Ремонт · ${magMoney(w.serviceCost(v))} кр'),
            ),
            if (route != null)
              OutlinedButton(
                key: const ValueKey('mag-unassign'),
                onPressed: () =>
                    state.report(w.assign(v.id, null), 'Машина в гараже'),
                child: const Text('В гараж'),
              ),
            TextButton(
              key: const ValueKey('mag-sell'),
              onPressed: () {
                final value = w.valueOf(v);
                if (state.report(
                  w.sellTruck(v.id),
                  'Продано за ${magMoney(value)} кр',
                )) {
                  Navigator.pop(context);
                }
              },
              child: Text('Продать · ${magMoney(w.valueOf(v))} кр'),
            ),
          ],
        ),
      ],
    );
  },
);

Widget _upgradeRow(MagistraliScreenState state, MagVehicle v, MagUpgrade u) {
  final w = state.world;
  final level = v.level(u);
  final cost = w.upgradeCost(v, u);
  final capped = level >= w.maxUpgradeLevel;
  final effect = switch (u) {
    MagUpgrade.engine => '+8% скорости за уровень',
    MagUpgrade.body => '+10% груза за уровень',
    MagUpgrade.economy => '−6% расхода за уровень',
    MagUpgrade.reliability => '−7% износа за уровень',
  };
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
    decoration: magCard(16),
    child: Row(
      children: [
        Icon(upgradeIcon(u), color: MagPalette.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${upgradeName(u, v.spec.horse)} · $level/${MagRules.maxUpgrade}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(effect, style: magMuted),
              const SizedBox(height: 5),
              Row(
                children: [
                  for (var k = 0; k < MagRules.maxUpgrade; k++)
                    Expanded(
                      child: Container(
                        height: 5,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: k < level
                              ? MagPalette.mint
                              : k < w.maxUpgradeLevel
                              ? const Color(0x332BB59A)
                              : const Color(0x14233238),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: ValueKey('mag-upgrade-${u.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: MagPalette.mint,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: cost == null || capped
              ? null
              : () => state.report(
                  w.upgrade(v.id, u),
                  '${upgradeName(u, v.spec.horse)}: уровень ${level + 1}',
                ),
          child: Text(
            cost == null
                ? 'макс.'
                : capped
                ? 'ур. комп.'
                : magMoney(cost),
          ),
        ),
      ],
    ),
  );
}

Future<void> _pickRoute(
  MagistraliScreenState state,
  MagVehicle v,
  BuildContext context,
) async {
  final w = state.world;
  if (w.routes.isEmpty) {
    state.say('Сначала создайте маршрут в разделе «Маршруты»');
    return;
  }
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final r in w.routes.values)
            ListTile(
              key: ValueKey('mag-pick-route-${r.id}'),
              leading: const Icon(
                Icons.alt_route_rounded,
                color: MagPalette.teal,
              ),
              title: Text(r.name),
              subtitle: Text(
                '${r.stops.length} остановки · машин: ${w.vehicles.values.where((o) => o.routeId == r.id).length}',
              ),
              onTap: () => Navigator.pop(c, r.id),
            ),
        ],
      ),
    ),
  );
  if (picked != null) {
    state.report(w.assign(v.id, picked), 'Машина вышла на маршрут');
  }
}

/// Upgrades: pick a truck to improve.
Future<void> showUpgradesSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-upgrades', (context) {
  final w = state.world;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Улучшения', style: magTitle),
      Text(
        'Двигатель, кузов, экономичность и надёжность — по 10 уровней. Сейчас открыто до ${w.maxUpgradeLevel}.',
        style: magMuted,
      ),
      const SizedBox(height: 6),
      for (final v in w.vehicles.values) _truckTile(state, v, context),
      if (w.vehicles.isEmpty)
        const Text('Купите грузовик в разделе «Транспорт».'),
    ],
  );
});
