import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_town.dart';

/// Development contracts of the settlements: what each one's growth asks
/// for, how much has arrived, the reward, and whether a road reaches it.
/// Closest to completion first.
List<Widget> developmentCards(
  MagistraliScreenState state,
  BuildContext context,
) {
  final w = state.world;
  final towns = [
    for (final i in w.settlements)
      if (i.town!.level < MagTowns.maxLevel && w.developmentAsks(i).isNotEmpty)
        i,
  ];
  double progress(MagIndustry i) {
    final asks = w.developmentAsks(i);
    var got = 0, want = 0;
    for (final e in asks.entries) {
      want += e.value;
      got += (i.town!.devStock[e.key] ?? 0).clamp(0, e.value);
    }
    return want == 0 ? 1 : got / want;
  }

  towns.sort((a, b) => progress(b).compareTo(progress(a)));
  return [
    const SizedBox(height: 6),
    const Text(
      'Развитие поселений',
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    ),
    const Text(
      'Привезите поселению то, что просит его рост, — получите награду один раз за уровень. Рост откроет новый спрос и новые заказы.',
      style: magMuted,
    ),
    const SizedBox(height: 8),
    for (final i in towns) _card(state, context, w, i, progress(i)),
  ];
}

Widget _card(
  MagistraliScreenState state,
  BuildContext context,
  MagWorld w,
  MagIndustry i,
  double progress,
) {
  final t = i.town!;
  final next = MagTowns.of(t.level + 1);
  final served = w.accessCells(i).isNotEmpty;
  final missing = w.missingForGrowth(i);
  return InkWell(
    key: ValueKey('mag-dev-${i.id}'),
    borderRadius: BorderRadius.circular(16),
    onTap: () {
      Navigator.pop(context);
      state.centerOn(i.centerX, i.centerY);
      state.overlay.industry = i.id;
      unawaited(showTownSheet(state, i.id));
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: magCard(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${i.name} · ${t.spec.name} → ${next.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                t.devPaid
                    ? 'выплачено'
                    : '+${magMoney(w.developmentReward(i))} кр',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MagPalette.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: MagPalette.mint,
            backgroundColor: const Color(0x1F2BB59A),
          ),
          const SizedBox(height: 4),
          Text(
            missing.isEmpty
                ? 'Всё доставлено · население ${magMoney(t.population)} из ${magMoney(next.population)}'
                : 'Нужно: ${missing.entries.map((e) => '${cargoName(e.key)} ${e.value}').join(', ')}',
            style: magMuted,
          ),
          if (!served)
            const Text(
              'Нет дороги — постройте её к поселению',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
            ),
          if (t.blocked != null)
            Text(
              t.blocked!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
            ),
        ],
      ),
    ),
  );
}
