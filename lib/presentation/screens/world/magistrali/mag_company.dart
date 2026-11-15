import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_filters.dart';
import 'mag_hud.dart';
import 'mag_rivals_ui.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Which part of the company sheet is open (kept while the game is open).
var _companyTab = 0;

/// The company: its level and what it opens, the achievements (META-02)
/// and the chronicle of the transport empire (META-05).
Future<void> showCompanySheet(MagistraliScreenState state) =>
    magSheet(state, 'mag-company', (context) {
      final w = state.world;
      return StatefulBuilder(
        builder: (context, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MagFilterChips(
              keyPrefix: 'mag-company-tab',
              labels: [
                'Компания',
                'Достижения ${w.achieved.length}/${MagAchievements.all.length}',
                'Летопись',
                'Конкуренты',
                'Коллекция',
                'Кампания',
              ],
              selected: _companyTab,
              onSelect: (i) => setLocal(() => _companyTab = i),
            ),
            ...switch (_companyTab) {
              1 => _achievements(w),
              2 => _chronicle(w),
              3 => rivalCards(state),
              4 => collectionCards(state),
              5 => campaignCards(state),
              _ => [_company(state, context)],
            },
          ],
        ),
      );
    });

List<Widget> _achievements(MagWorld w) => [
  const Text(
    'Каждое достижение платит один раз — деньги и опыт.',
    style: magMuted,
  ),
  const SizedBox(height: 6),
  for (final a in MagAchievements.all)
    Builder(
      builder: (context) {
        final done = w.achieved.containsKey(a.id);
        final p = w.achievementProgress(a.id).clamp(0, a.goal);
        return Container(
          key: ValueKey('mag-achievement-${a.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: magCard(14),
          child: Row(
            children: [
              Icon(
                done ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
                color: done ? const Color(0xFFD4A017) : const Color(0xFF9AA6AA),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(a.text, style: magMuted),
                    if (!done) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: p / a.goal,
                        color: MagPalette.mint,
                        backgroundColor: const Color(0x222BB59A),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                done ? 'получено' : '+${magMoney(a.reward)} кр',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: done ? MagPalette.teal : MagPalette.ink,
                ),
              ),
            ],
          ),
        );
      },
    ),
];

List<Widget> _chronicle(MagWorld w) => [
  const Text(
    'Летопись транспортной империи: главные события компании.',
    style: magMuted,
  ),
  const SizedBox(height: 6),
  if (w.chronicle.isEmpty)
    const Text('Пока событий нет — всё впереди.', style: magMuted),
  for (final (t, text) in w.chronicle.reversed)
    Padding(
      key: ValueKey('mag-chronicle-$t-${text.hashCode}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              'день ${t ~/ MagRules.ticksPerDay + 1}',
              style: magMuted,
            ),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    ),
];

Widget _company(MagistraliScreenState state, BuildContext context) {
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
}
