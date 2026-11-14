import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_road.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_works_ui.dart';

/// The investment planner (FIN-14), a tab of the finance centre: what to
/// put money into next, with the cost, the profit a day and the days to
/// earn it back, quickest first — each with the button that does it.
List<Widget> investmentCards(
  MagistraliScreenState state,
  BuildContext context,
) {
  final w = state.world;
  final ideas = w.investmentIdeas;
  return [
    ...auctionCards(state),
    const Text(
      'Оценка по фактам: прибыль маршрутов и предприятий за время работы. Окупаемость — сколько дней вложение будет возвращаться.',
      style: magMuted,
    ),
    const SizedBox(height: 8),
    if (ideas.isEmpty)
      const Text(
        'Пока предложить нечего: пусть маршруты поработают пару дней.',
        key: ValueKey('mag-invest-empty'),
        style: magMuted,
      ),
    for (var k = 0; k < ideas.length; k++)
      Container(
        key: ValueKey('mag-invest-$k'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: magCard(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ideas[k].title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(ideas[k].detail, style: magMuted),
            magRow('Вложение', '${magMoney(ideas[k].cost)} кр'),
            if (ideas[k].daily != null)
              magRow(
                'Прибыль в день',
                '≈ ${magMoney(ideas[k].daily!.round())} кр',
                color: ideas[k].daily! > 0 ? MagPalette.teal : null,
              ),
            magRow(
              'Окупаемость',
              ideas[k].paybackDays == null
                  ? 'не оценивается'
                  : '${ideas[k].paybackDays} дн.',
              color: (ideas[k].paybackDays ?? 999) <= 30
                  ? MagPalette.teal
                  : null,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey('mag-invest-go-$k'),
                style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
                onPressed: ideas[k].cost > w.money
                    ? null
                    : () => _act(state, context, ideas[k]),
                child: Text(
                  ideas[k].cost > w.money
                      ? 'Не хватает кредитов'
                      : switch (ideas[k].kind) {
                          MagInvestmentKind.vehicle => 'Купить и назначить',
                          MagInvestmentKind.road => 'Открыть дорогу',
                          _ => 'Открыть предприятие',
                        },
                ),
              ),
            ),
          ],
        ),
      ),
  ];
}

void _act(MagistraliScreenState state, BuildContext context, MagInvestment i) {
  final w = state.world;
  switch (i.kind) {
    case MagInvestmentKind.vehicle:
      state.report(
        w.buyForRoute(i.model!, i.routeId!),
        'Куплено и назначено на маршрут',
      );
    case MagInvestmentKind.road:
      Navigator.pop(context);
      final c = i.cell!;
      state.centerOn(w.cx(c) + .5, w.cy(c) + .5);
      unawaited(showRoadSheet(state, c));
    case MagInvestmentKind.upgrade:
    case MagInvestmentKind.business:
      Navigator.pop(context);
      final place = w.map.industry(i.industryId!)!;
      state.centerOn(place.centerX, place.centerY);
      unawaited(showIndustrySheet(state, place.id));
  }
}
