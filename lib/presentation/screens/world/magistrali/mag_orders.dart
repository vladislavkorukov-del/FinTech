import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

String orderStatusName(MagOrderStatus s) => switch (s) {
  MagOrderStatus.pending => 'Ожидает',
  MagOrderStatus.assigned => 'Назначена',
  MagOrderStatus.toPickup => 'Едет на погрузку',
  MagOrderStatus.loading => 'Загрузка',
  MagOrderStatus.inTransit => 'В пути',
  MagOrderStatus.unloading => 'Разгрузка',
  MagOrderStatus.done => 'Выполнена',
  MagOrderStatus.cancelled => 'Отменена',
  MagOrderStatus.failed => 'Ошибка',
};

Color orderStatusColor(MagOrderStatus s) => switch (s) {
  MagOrderStatus.pending => const Color(0xFFE09A3E),
  MagOrderStatus.done => MagPalette.mint,
  MagOrderStatus.cancelled => const Color(0xFF8A9599),
  MagOrderStatus.failed => const Color(0xFFD64B5C),
  _ => MagPalette.teal,
};

const priorityNames = ['Низкий', 'Обычный', 'Высокий'];

/// Logistics orders (a technical panel for stage 1): what waits, what is
/// on its way, what is done; assign a free truck or cancel.
Future<void> showOrdersSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-orders', (context) {
  final w = state.world;
  final active = w.orders.active.toList()
    ..sort((a, b) {
      final p = b.priority.compareTo(a.priority);
      return p != 0 ? p : a.createdTick.compareTo(b.createdTick);
    });
  final history = w.orders.orders.where((o) => !o.status.active).toList()
    ..sort((a, b) => (b.finishedTick ?? 0).compareTo(a.finishedTick ?? 0));
  final free = w.vehicles.values.where(w.isFree).length;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Логистические заказы', style: magTitle)),
          FilledButton.icon(
            key: const ValueKey('mag-new-order'),
            style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
            onPressed: () {
              Navigator.pop(context);
              unawaited(showNewOrderSheet(state));
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новый'),
          ),
        ],
      ),
      Text(
        'Заказ резервирует груз у поставщика и место у получателя. Оплата — после доставки. Свободных машин: $free.',
        style: magMuted,
      ),
      if (active.any((o) => o.status == MagOrderStatus.pending) && free > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            key: const ValueKey('mag-assign-free'),
            onPressed: () {
              final n = w.assignFreeTrucks();
              state.report(
                null,
                n == 0 ? 'Нет подходящих машин' : 'Назначено заказов: $n',
              );
            },
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Раздать свободным машинам'),
          ),
        ),
      const SizedBox(height: 8),
      if (active.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Активных заказов нет.'),
        ),
      for (final o in active) _orderCard(state, o, context),
      if (history.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('История', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final o in history.take(10))
          ListTile(
            key: ValueKey('mag-order-done-${o.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.circle,
              size: 10,
              color: orderStatusColor(o.status),
            ),
            title: Text(
              '№${o.id} · ${cargoName(o.cargo)} ${o.amount} → ${w.map.industry(o.receiver)?.name ?? ''}',
            ),
            subtitle: Text(
              [
                orderStatusName(o.status),
                if (o.error != null) o.error!,
                if (o.income > 0) '+${magMoney(o.income)} кр',
              ].join(' · '),
              style: magMuted,
            ),
          ),
      ],
    ],
  );
});

Widget _orderCard(
  MagistraliScreenState state,
  MagOrder o,
  BuildContext context,
) {
  final w = state.world;
  final truck = o.vehicle == null ? null : w.vehicles[o.vehicle];
  final from = w.map.industry(o.supplier)!, to = w.map.industry(o.receiver)!;
  return Container(
    key: ValueKey('mag-order-${o.id}'),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: magCard(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '№${o.id}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            cargoChip(o.cargo, o.amount),
            Text(
              orderStatusName(o.status),
              key: ValueKey('mag-order-status-${o.id}'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: orderStatusColor(o.status),
              ),
            ),
          ],
        ),
        Text('${from.name} → ${to.name}', style: const TextStyle(fontSize: 13)),
        Text(
          [
            'приоритет: ${priorityNames[o.priority].toLowerCase()}',
            if (o.reserved > 0) 'в резерве ${o.reserved}',
            'машина: ${truck?.name ?? 'не назначена'}',
            if (o.noRoadTicks > 0) 'нет дороги',
          ].join(' · '),
          style: magMuted,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (o.status == MagOrderStatus.pending)
              FilledButton.icon(
                key: ValueKey('mag-order-assign-${o.id}'),
                style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
                onPressed: () => unawaited(_pickTruck(state, o, context)),
                icon: const Icon(Icons.local_shipping_rounded, size: 18),
                label: const Text('Назначить машину'),
              ),

            if (o.status != MagOrderStatus.unloading)
              TextButton(
                key: ValueKey('mag-order-cancel-${o.id}'),
                onPressed: () =>
                    state.report(w.cancelOrder(o.id), 'Заказ №${o.id} отменён'),
                child: const Text('Отменить'),
              ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _pickTruck(
  MagistraliScreenState state,
  MagOrder o,
  BuildContext context,
) async {
  final w = state.world;
  final free = w.vehicles.values.where(w.isFree).toList();
  if (free.isEmpty) {
    state.say(
      'Свободных машин нет: снимите машину с маршрута или купите новую',
    );
    return;
  }
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final v in free)
            ListTile(
              key: ValueKey('mag-order-truck-${v.id}'),
              enabled: w.capacityOf(v) >= o.amount,
              leading: Icon(
                Icons.local_shipping_rounded,
                color: Color(v.spec.color),
              ),
              title: Text(v.name),
              subtitle: Text(
                'груз до ${w.capacityOf(v)} · ${v.onMap ? 'на карте' : 'в гараже'}',
              ),
              onTap: () => Navigator.pop(c, v.id),
            ),
        ],
      ),
    ),
  );
  if (picked != null) {
    state.report(
      w.assignOrder(o.id, picked),
      'Машина назначена на заказ №${o.id}',
    );
  }
}

/// A new order: supplier, cargo, receiver, amount and priority.
Future<void> showNewOrderSheet(MagistraliScreenState state, {int? from}) {
  int? supplier = from, receiver;
  MagCargo? cargo;
  var amount = 1, priority = 1;
  return showModalBottomSheet<void>(
    context: state.context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(state.context).size.height * .85,
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final w = state.world;
        final a = supplier == null ? null : w.map.industry(supplier!);
        if (a != null && (cargo == null || !a.supplies.contains(cargo))) {
          cargo = a.supplies.isEmpty ? null : a.supplies.first;
        }
        final available = a == null || cargo == null
            ? 0
            : math.max(0, w.availableOf(a, cargo!));
        final b = receiver == null ? null : w.map.industry(receiver!);
        final room = b == null || cargo == null ? null : w.roomOf(b, cargo!);
        final biggest = w.vehicles.values.fold(
          0,
          (m, v) => math.max(m, w.capacityOf(v)),
        );
        final limit = [available, room ?? available, biggest].reduce(math.min);
        amount = amount.clamp(1, math.max(1, limit));
        Widget pickList(
          String keyPrefix,
          Iterable<MagIndustry> list,
          int? chosen,
          void Function(int) pick,
        ) => Column(
          children: [
            for (final i in list)
              ListTile(
                key: ValueKey('$keyPrefix${i.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: chosen == i.id,
                selectedColor: MagPalette.teal,
                leading: Icon(kindIcon(i.kind), color: MagPalette.teal),
                title: Text(
                  i.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  keyPrefix == 'mag-order-from-'
                      ? i.supplies
                            .map(
                              (c) =>
                                  '${cargoName(c)} ${math.max(0, w.availableOf(i, c))}',
                            )
                            .join(', ')
                      : [
                          if (a != null) '${i.distanceTo(a)} кл.',
                          if (a != null && !w.connected(a, i)) 'нет дороги',
                        ].join(' · '),
                  style: magMuted,
                ),
                trailing: chosen == i.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => setSheet(() => pick(i.id)),
              ),
          ],
        );
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Новый заказ', style: magTitle),
                const SizedBox(height: 6),
                const Text(
                  '1. Поставщик',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                if (a != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      a.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: TextButton(
                      onPressed: () => setSheet(() {
                        supplier = null;
                        receiver = null;
                      }),
                      child: const Text('Сменить'),
                    ),
                  )
                else
                  pickList(
                    'mag-order-from-',
                    w.map.industries.where((i) => i.supplies.isNotEmpty),
                    supplier,
                    (id) => supplier = id,
                  ),
                if (a != null && a.supplies.length > 1)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final c in a.supplies)
                        ChoiceChip(
                          label: Text(cargoName(c)),
                          selected: cargo == c,
                          onSelected: (_) => setSheet(() {
                            cargo = c;
                            receiver = null;
                          }),
                        ),
                    ],
                  ),
                if (a != null && cargo != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '2. Получатель груза «${cargoName(cargo!)}»',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  pickList(
                    'mag-order-to-',
                    (w.map.industries
                        .where(
                          (i) => i.id != a.id && i.spec.accepts.contains(cargo),
                        )
                        .toList()
                      ..sort(
                        (x, y) => x.distanceTo(a).compareTo(y.distanceTo(a)),
                      )),
                    receiver,
                    (id) => receiver = id,
                  ),
                ],
                if (b != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '3. Количество: $amount (свободно $available${room != null && room < (1 << 20) ? ', место $room' : ''}, машина до $biggest)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (limit > 1)
                    Slider(
                      key: const ValueKey('mag-order-amount'),
                      value: amount.toDouble(),
                      min: 1,
                      max: limit.toDouble(),
                      divisions: limit - 1,
                      activeColor: MagPalette.mint,
                      onChanged: (v) => setSheet(() => amount = v.round()),
                    ),
                  const Text(
                    '4. Приоритет',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var p = 0; p < 3; p++)
                        ChoiceChip(
                          key: ValueKey('mag-order-priority-$p'),
                          label: Text(priorityNames[p]),
                          selected: priority == p,
                          onSelected: (_) => setSheet(() => priority = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('mag-create-order'),
                      style: FilledButton.styleFrom(
                        backgroundColor: MagPalette.mint,
                      ),
                      onPressed: limit < 1
                          ? null
                          : () {
                              final err = w.createOrder(
                                cargo: cargo!,
                                from: a!.id,
                                to: b.id,
                                amount: amount,
                                priority: priority,
                              );
                              if (state.report(
                                err,
                                'Заказ создан — назначьте машину',
                              )) {
                                Navigator.pop(context);
                                unawaited(showOrdersSheet(state));
                              }
                            },
                      child: Text(limit < 1 ? 'Нечего везти' : 'Создать заказ'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
