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

/// The campaign (S22): chapters with their goals and rewards, and what is
/// happening in the world now.
List<Widget> campaignCards(MagistraliScreenState state) {
  final w = state.world;
  if (!w.livingWorld) {
    return const [
      Text(
        'Кампания идёт в живом мире: в новой компании или в партии, начатой до 1.94.',
        style: magMuted,
      ),
    ];
  }
  String event(MagEvent e) {
    final place = e.place == null ? null : w.map.industry(e.place!)?.name;
    final cargo = e.cargo == null ? '' : cargoName(e.cargo!).toLowerCase();
    final days = ((e.until - w.tick) / MagRules.ticksPerDay).ceil();
    final what = switch (e.kind) {
      'festival' => 'Ярмарка в «$place»: $cargo +40%',
      'strike' => 'Забастовка: «$place» стоит',
      'boom' => 'Бум спроса: $cargo +30%',
      _ => 'Дорогое топливо: расходы в пути +40%',
    };
    return '$what · ещё $days дн.';
  }

  return [
    Text(
      '${MagWorldSeasons.seasonName(w.season)} · ${MagWorldSeasons.weatherName(w.weather)}',
      key: const ValueKey('mag-campaign-season'),
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    for (final e in w.events) Text('• ${event(e)}', style: magMuted),
    if (w.events.isEmpty) const Text('Событий сейчас нет', style: magMuted),
    const SizedBox(height: 10),
    for (var k = 0; k < magChapters.length; k++)
      Container(
        key: ValueKey('mag-chapter-$k'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: magCard(14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: k < w.chapterIndex
                    ? MagPalette.mint
                    : k == w.chapterIndex
                    ? const Color(0x332BB59A)
                    : const Color(0x14203A36),
              ),
              child: k < w.chapterIndex
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    )
                  : Text(
                      '${k + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    magChapters[k].title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(magChapters[k].goal, style: magMuted),
                ],
              ),
            ),
            Text(
              '+${magMoney(magChapters[k].reward)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: k < w.chapterIndex
                    ? const Color(0xFF9AA6AA)
                    : MagPalette.teal,
              ),
            ),
          ],
        ),
      ),
  ];
}
