import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Rivals in the company sheet (META-09, META-10): who they are, how many
/// places they serve, what buying them out costs.
List<Widget> rivalCards(MagistraliScreenState state) {
  final w = state.world;
  if (w.rivals.isEmpty) {
    return [
      Text(
        w.rivalsMet
            ? 'Конкурентов не осталось — рынок ваш.'
            : 'Конкуренты появятся, когда компания дорастёт до ${MagRules.rivalLevel} уровня.',
        style: magMuted,
      ),
    ];
  }
  return [
    Text(
      'Там, где работает конкурент, оплата доставок на ${(MagRules.rivalCut * 100).round()}% ниже. Поглотите его — его предприятия станут вашими.',
      style: magMuted,
    ),
    const SizedBox(height: 6),
    for (var k = 0; k < w.rivals.length; k++)
      Container(
        key: ValueKey('mag-rival-$k'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: magCard(14),
        child: Row(
          children: [
            CircleAvatar(radius: 8, backgroundColor: Color(w.rivals[k].color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.rivals[k].name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Обслуживает ${w.rivals[k].claims.length} предприятий',
                    style: magMuted,
                  ),
                ],
              ),
            ),
            FilledButton(
              key: ValueKey('mag-rival-buy-$k'),
              style: FilledButton.styleFrom(
                backgroundColor: MagPalette.mint,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: w.rivalValue(w.rivals[k]) > w.money
                  ? null
                  : () => state.report(w.acquireRival(k)),
              child: Text('Купить ${magMoney(w.rivalValue(w.rivals[k]))}'),
            ),
          ],
        ),
      ),
  ];
}

/// The vehicle collection (VEH-14, META-08): every model, owned or not.
List<Widget> collectionCards(MagistraliScreenState state) {
  final w = state.world;
  final have = w.collected;
  return [
    Text(
      'Коллекция: ${have.length} из ${MagRules.trucks.length}. За 5, 10 и 15 моделей — награды; с ${MagRules.veteranAfter} моделей открывается «Полуторка «Ветеран»» (+10% к оплате).',
      style: magMuted,
    ),
    const SizedBox(height: 6),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in MagRules.trucks)
          Chip(
            key: ValueKey('mag-collection-${m.id}'),
            avatar: Icon(
              have.contains(m.id)
                  ? Icons.check_circle_rounded
                  : Icons.lock_outline_rounded,
              size: 16,
              color: have.contains(m.id)
                  ? MagPalette.mint
                  : const Color(0xFF9AA6AA),
            ),
            label: Text(m.name.split(' «').first),
          ),
      ],
    ),
  ];
}
