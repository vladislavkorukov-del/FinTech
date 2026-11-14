import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_tools.dart';

/// A tapped road: its stretch is lit on the map; the sheet tells the
/// surface, speed and upkeep, and offers a better surface for the whole
/// stretch or just this cell, or taking the stretch away.
Future<void> showRoadSheet(MagistraliScreenState state, int cell) async {
  final w = state.world;
  var segment = w.roadSegment(cell);
  void light() {
    state.overlay
      ..plan = segment
      ..planOk = true;
  }

  light();
  await magSheet<void>(state, 'mag-road', (context) {
    if (w.roads[cell] == 0) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Дороги здесь больше нет', style: magMuted),
      );
    }
    final type = MagRoad.values[w.roads[cell]];
    final spec = MagRules.roads[type]!;
    final all = w.upgradePlan(segment), one = w.upgradePlan([cell]);
    final next = w.nextRoad(type);
    Widget upgrade(String key, String label, MagRoadPlan plan) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: ValueKey(key),
        style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
        onPressed: plan.error != null || plan.cost > w.money
            ? null
            : () {
                if (state.report(w.buildRoad(plan), 'Дорога улучшена')) {
                  segment = w.roadSegment(cell);
                  light();
                }
              },
        child: Text('$label · ${magMoney(plan.cost)} кр'),
      ),
    );
    return Column(
      key: const ValueKey('mag-road-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${roadName(type)} дорога', style: magTitle),
        Text(
          'Участок ${segment.length} кл. — до ближайшего перекрёстка или смены покрытия',
          style: magMuted,
        ),
        const SizedBox(height: 8),
        magRow('Скорость машин', '×${spec.speed.toStringAsFixed(2)}'),
        magRow(
          'Содержание участка',
          '${magMoney((segment.length * spec.upkeep / 10).ceil())} кр в день',
        ),
        const SizedBox(height: 10),
        if (next == null)
          const Text('Это лучшее покрытие.', style: magMuted)
        else ...[
          Text(
            'Улучшить до «${roadName(next)}»: скорость ×${MagRules.roads[next]!.speed.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (all.error != null)
            Text(
              all.error!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
            )
          else ...[
            const SizedBox(height: 6),
            upgrade(
              'mag-road-upgrade',
              'Весь участок (${segment.length} кл.)',
              all,
            ),
            const SizedBox(height: 6),
            upgrade('mag-road-upgrade-cell', 'Только эта клетка', one),
            if (all.cost > w.money)
              const Text('Не хватает кредитов', style: magMuted),
          ],
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('mag-road-remove'),
            onPressed: () {
              if (state.report(w.removeRoad(segment), 'Участок снесён')) {
                Navigator.pop(context);
              }
            },
            child: const Text('Снести участок'),
          ),
        ),
      ],
    );
  });
  state.overlay
    ..plan = const []
    ..planOk = true;
  state.changed();
}
