import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_lore.dart';
import 'mag_orders.dart';
import 'mag_route_create.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// A warehouse: what it holds, how full it is, and its rules per cargo —
/// minimum, target, maximum, priority and mode.
Future<void> showWarehouseSheet(
  MagistraliScreenState state,
  int id,
) => magSheet(state, 'mag-warehouse-$id', (context) {
  final w = state.world;
  final wh = w.map.industry(id);
  if (wh == null) return const Text('Склад снесён');
  final cap = w.warehouseCapacityOf(wh);
  final upgrade = w.warehouseUpgradePrice(wh);
  final stored = w.storedIn(wh);
  final served = w.accessCells(wh).isNotEmpty;
  final open = w.orders.active
      .where((o) => o.supplier == id || o.receiver == id)
      .toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.warehouse_rounded, color: MagPalette.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(wh.name, style: magTitle)),
        ],
      ),
      Text(industryLore(MagIndustryKind.warehouse), style: magMuted),
      const SizedBox(height: 10),
      Text(
        'Заполнено $stored из $cap',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: stored / cap,
        minHeight: 8,
        borderRadius: BorderRadius.circular(4),
        color: stored >= cap ? const Color(0xFFD64B5C) : MagPalette.mint,
        backgroundColor: const Color(0x1F2BB59A),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: Text(
              upgrade == null
                  ? 'Уровень ${wh.level} — максимальный'
                  : 'Уровень ${wh.level} · следующий: место ${(w.warehouseCapacity * (1 + MagRules.levelStorage * wh.level)).round()}',
              style: magMuted,
            ),
          ),
          if (upgrade != null)
            TextButton(
              key: const ValueKey('mag-warehouse-upgrade'),
              onPressed: w.money < upgrade
                  ? null
                  : () =>
                        state.report(w.upgradeWarehouse(id), 'Склад расширен'),
              child: Text('Расширить · ${magMoney(upgrade)} кр'),
            ),
        ],
      ),
      if (!served)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Нет дороги: проведите дорогу вплотную к складу.',
            style: TextStyle(fontSize: 13, color: Color(0xFFE09A3E)),
          ),
        ),
      const SizedBox(height: 10),
      const Text(
        'Правила по грузам',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      for (final c in MagCargo.values) _ruleCard(state, wh, c, cap),
      if (open.isNotEmpty) ...[
        Text(
          'Заказы склада · ${open.length}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        for (final o in open)
          Text(
            '№${o.id} ${cargoName(o.cargo)} ${o.amount}: ${o.supplier == id ? 'отсюда' : 'сюда'} · ${orderStatusName(o.status).toLowerCase()}',
            style: magMuted,
          ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
            onPressed: () {
              Navigator.pop(context);
              unawaited(showCreateRouteSheet(state, first: id));
            },
            icon: const Icon(Icons.alt_route_rounded),
            label: const Text('Маршрут отсюда'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              unawaited(showOrdersSheet(state));
            },
            icon: const Icon(Icons.assignment_rounded),
            label: const Text('Заказы'),
          ),
          TextButton(
            key: const ValueKey('mag-warehouse-remove'),
            onPressed: () {
              if (state.report(w.removeWarehouse(id), 'Склад снесён')) {
                Navigator.pop(context);
              }
            },
            child: const Text('Снести склад'),
          ),
        ],
      ),
    ],
  );
});

Widget _ruleCard(
  MagistraliScreenState state,
  MagIndustry wh,
  MagCargo c,
  int cap,
) {
  final w = state.world;
  final r = w.ruleOf(wh, c);
  final have = wh.stock[c] ?? 0;
  final incoming = w.orders.reservedIn(wh.id, c);
  final max = r.max ?? cap;
  void apply(MagStockRule next) => state.report(w.setRule(wh.id, c, next));
  Widget stepper(
    String label,
    int value,
    int lo,
    int hi,
    MagStockRule Function(int) make,
    String key,
  ) => Row(
    children: [
      Expanded(
        child: Text('$label: $value', style: const TextStyle(fontSize: 13)),
      ),
      IconButton(
        key: ValueKey('$key-minus'),
        visualDensity: VisualDensity.compact,
        onPressed: value <= lo
            ? null
            : () => apply(make(math.max(lo, value - 10))),
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
      IconButton(
        key: ValueKey('$key-plus'),
        visualDensity: VisualDensity.compact,
        onPressed: value >= hi
            ? null
            : () => apply(make(math.min(hi, value + 10))),
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
    ],
  );
  return Container(
    key: ValueKey('mag-rule-${c.name}'),
    margin: const EdgeInsets.only(top: 8, bottom: 2),
    padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
    decoration: magCard(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            cargoChip(c, have),
            if (incoming > 0) Text('едет +$incoming', style: magMuted),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final m in MagStockMode.values)
              ChoiceChip(
                key: ValueKey('mag-rule-${c.name}-${m.name}'),
                label: Text(
                  w.modeUnlocked(m)
                      ? stockModeName(m)
                      : '${stockModeName(m)} 🔒',
                ),
                selected: r.mode == m,
                onSelected: (_) => w.modeUnlocked(m)
                    ? apply(r.copyWith(mode: m))
                    : state.say(
                        'Режим «${stockModeName(m)}» откроет технология ветки «Склады»',
                      ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 6),
          child: Text(stockModeLore(r.mode), style: magMuted),
        ),
        if (r.mode != MagStockMode.manual) ...[
          if (r.mode == MagStockMode.autoSupply)
            stepper(
              'Минимум',
              r.min,
              0,
              r.target,
              (v) => r.copyWith(min: v),
              'mag-rule-${c.name}-min',
            ),
          stepper(
            'Желаемый запас',
            r.target,
            r.min,
            max,
            (v) => r.copyWith(target: v),
            'mag-rule-${c.name}-target',
          ),
        ],
        stepper(
          'Максимум',
          max,
          r.target,
          cap,
          (v) => v >= cap ? r.copyWith(clearMax: true) : r.copyWith(max: v),
          'mag-rule-${c.name}-max',
        ),
        if (r.mode != MagStockMode.manual)
          Wrap(
            spacing: 6,
            children: [
              for (var p = 0; p < 3; p++)
                ChoiceChip(
                  label: Text(priorityNames[p]),
                  selected: r.priority == p,
                  onSelected: (_) => apply(r.copyWith(priority: p)),
                ),
            ],
          ),
      ],
    ),
  );
}
