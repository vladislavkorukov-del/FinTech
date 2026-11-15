import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_mega_ui.dart';
import 'mag_art.dart';
import 'mag_city.dart';
import 'mag_finish_ui.dart';
import 'mag_hud.dart';
import 'mag_route_map.dart';
import 'mag_s25_ui.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// A settlement: its level and people, what it needs every day, what its
/// growth asks for, what the next level opens, and its own history.
Future<void> showTownSheet(
  MagistraliScreenState state,
  int id,
) => magSheet(state, 'mag-town-$id', (context) {
  final w = state.world;
  final i = w.map.industry(id)!;
  final t = i.town!;
  final next = t.level < MagTowns.maxLevel ? MagTowns.of(t.level + 1) : null;
  final served = w.accessCells(i).isNotEmpty;
  final needs = w.needsOf(i);
  final missing = w.missingForGrowth(i);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x1F2BB59A),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${t.level}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: MagPalette.teal,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.name, style: magTitle),
                Text(
                  '${t.spec.name} · ${MagTowns.specializationName(t.specialization)} · ${t.cells.length} кл.',
                  style: magMuted,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // S20: growth is one bar — bring what it asks for, it grows.
      Text(
        next == null
            ? 'Высший уровень'
            : 'Рост до «${next.name}»: ${(w.growthProgress(i) * 100).round()}%',
        key: const ValueKey('mag-town-growth'),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: w.growthProgress(i),
        minHeight: 10,
        borderRadius: BorderRadius.circular(5),
        color: MagPalette.mint,
        backgroundColor: const Color(0x1F2BB59A),
      ),
      if (next != null) ...[
        const SizedBox(height: 6),
        Text(
          missing.isEmpty
              ? (t.blocked ?? 'Всё привезено — город растёт')
              : 'Привезите: ${missing.entries.map((e) => '${cargoName(e.key)} ${e.value}').join(', ')}',
          key: const ValueKey('mag-town-bring'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: t.blocked != null
                ? const Color(0xFFD64B5C)
                : MagPalette.teal,
          ),
        ),
        const Text(
          'Всё, что нужно для роста, засчитывается первым. Привезли всё — город растёт сам, жители приходят вместе с уровнем.',
          style: magMuted,
        ),
      ],
      const SizedBox(height: 4),
      Text(
        'Население ${magMoney(t.population)} · снабжение за неделю ${(t.averageSatisfaction * 100).round()}% · репутация ${t.reputation}'
        '${served ? '' : ' · нет дороги'}',
        key: const ValueKey('mag-town-population'),
        style: magMuted,
      ),
      ...townAccessInfo(w, i),
      ...cityInfo(w, i),
      ...marketInfo(w, i),
      ...megaprojectSection(state, i),
      ...mortgageSection(state, i), // MORT-01
      const SizedBox(height: 10),
      const Text(
        'Каждый день нужно',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      for (final e in needs.entries)
        magRow(
          '${cargoName(e.key)} · ${e.value} в день',
          'в кладовой ${t.pantry[e.key] ?? 0}',
          color: (t.pantry[e.key] ?? 0) >= e.value
              ? MagPalette.teal
              : const Color(0xFFD64B5C),
        ),
      const Text(
        'Ежедневные поставки держат жителей довольными: это звёзды, репутация и пассажиры.',
        style: magMuted,
      ),
      if (next != null) ...[
        const SizedBox(height: 10),
        const Text(
          'Контракт развития',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        Text(
          t.devPaid
              ? 'Контракт развития выполнен: +${magMoney(w.developmentReward(i))} кр получено'
              : 'Контракт развития: +${magMoney(w.developmentReward(i))} кр, когда всё доставлено',
          key: const ValueKey('mag-town-dev-reward'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: MagPalette.teal,
          ),
        ),
        for (final e in t.spec.development.entries)
          magRow(
            cargoName(e.key),
            w.cargoAvailable(e.key)
                ? '${t.devStock[e.key] ?? 0} из ${e.value}'
                : 'не требуется (никто не производит)',
            color: missing.containsKey(e.key) ? null : MagPalette.teal,
          ),
        const SizedBox(height: 6),
        Text(
          'Уровень «${next.name}» откроет',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final o in next.opens)
          Text('• $o', style: const TextStyle(fontSize: 13)),
        Text(
          'Нужно в день: ${next.needs.entries.map((e) => '${cargoName(e.key)} ${e.value}').join(', ')} · надбавка рынка +${(next.payBonus * 100).round()}%',
          style: magMuted,
        ),
      ],
      const SizedBox(height: 10),
      const Text(
        'Сейчас здесь можно',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      for (final o in t.spec.opens)
        Text('• $o', style: const TextStyle(fontSize: 13)),
      if (t.spec.payBonus > 0)
        Text(
          '• Доставка сюда оплачивается на ${(t.spec.payBonus * 100).round()}% выше',
          style: const TextStyle(fontSize: 13),
        ),
      const SizedBox(height: 10),
      const Text('История', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final e in t.history.reversed.take(8))
        Text(
          'День ${e.tick ~/ MagRules.ticksPerDay + 1}: ${e.text}',
          style: magMuted,
        ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('mag-town-route'),
          style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
          onPressed: () {
            Navigator.pop(context);
            startRouteOnMap(state, first: id);
          },
          icon: const Icon(Icons.alt_route_rounded),
          label: const Text('Маршрут с этим поселением'),
        ),
      ),
    ],
  );
});
