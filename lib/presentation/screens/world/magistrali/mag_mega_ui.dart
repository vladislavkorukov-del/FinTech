import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

const _gold = Color(0xFFD4A017);

/// The great works a city can commission, in its sheet: done, under way
/// (open the site) or ready to start; and the badge of the first
/// megalopolis.
List<Widget> megaprojectSection(MagistraliScreenState state, MagIndustry i) {
  final w = state.world;
  final t = i.town!;
  return [
    if (w.firstMegapolis == i.id)
      Container(
        key: const ValueKey('mag-megapolis-badge'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x22D4A017),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold),
        ),
        child: const Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: _gold),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'От хутора до мегаполиса — первый мегаполис вашей партии',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    if (t.level >= 6) ...[
      const SizedBox(height: 10),
      const Text('Мегапроекты', style: TextStyle(fontWeight: FontWeight.w800)),
      const Text(
        'Великие стройки города: вы платите за начало, везёте материалы (рейсы '
        'оплачиваются как обычно), город платит награду, а сооружение '
        'помогает компании всегда. Каждый — один раз за партию.',
        style: magMuted,
      ),
      for (final p in MagMegaprojects.all) _row(state, i, p),
    ],
  ];
}

Widget _row(MagistraliScreenState state, MagIndustry town, MagMegaproject p) {
  final w = state.world;
  final site = w.siteOf(p.id);
  final why = w.megaprojectBlocker(p.id, town.id);
  final String status;
  Widget? action;
  if (site != null && site.projectDone) {
    status = 'Построен (${w.map.industry(site.projectTown ?? -1)?.name ?? ''})';
  } else if (site != null) {
    status = 'Строится · ${w.map.industry(site.projectTown ?? -1)?.name ?? ''}';
    action = TextButton(
      key: ValueKey('mag-mega-open-${p.id}'),
      onPressed: () => unawaited(showMegaprojectSheet(state, site.id)),
      child: const Text('Стройка'),
    );
  } else {
    status = why ?? 'Можно начать · ${magMoney(p.fee)} кр';
    action = FilledButton(
      key: ValueKey('mag-mega-start-${p.id}'),
      style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
      onPressed: why != null
          ? null
          : () {
              if (state.report(
                w.startMegaproject(p.id, town.id),
                'Мегапроект «${p.name}» начат',
              )) {
                unawaited(showMegaprojectSheet(state, w.siteOf(p.id)!.id));
              }
            },
      child: Text(magMoney(p.fee)),
    );
  }
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: magCard(14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p.name} · с ${p.cityLevel} ур.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                p.effectText,
                style: const TextStyle(color: MagPalette.teal),
              ),
              Text(
                'Нужно: ${p.needs.entries.map((e) => '${cargoName(e.key).toLowerCase()} ${e.value}').join(', ')} · награда ${magMoney(p.reward)} кр',
                style: magMuted,
              ),
              Text(status, style: magMuted),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// A megaproject's site: progress by cargo, the reward and the effect.
Future<void> showMegaprojectSheet(
  MagistraliScreenState state,
  int id,
) => magSheet(state, 'mag-mega-$id', (context) {
  final w = state.world;
  final site = w.map.industry(id);
  final p = MagMegaprojects.byId(site?.project ?? '');
  if (site == null || p == null) return const Text('Стройки нет');
  final town = w.map.industry(site.projectTown ?? -1);
  final served = w.accessCells(site).isNotEmpty;
  return Column(
    key: const ValueKey('mag-mega-sheet'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.account_balance_rounded,
            color: site.projectDone ? _gold : MagPalette.teal,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(p.name, style: magTitle)),
        ],
      ),
      Text('Заказчик — ${town?.name ?? 'город'}. ${p.lore}', style: magMuted),
      const SizedBox(height: 8),
      Text(
        site.projectDone
            ? 'Построен. Действует: ${p.effectText}'
            : 'Когда всё привезут: +${magMoney(p.reward)} кр и навсегда — ${p.effectText.toLowerCase()}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: site.projectDone ? _gold : MagPalette.teal,
        ),
      ),
      if (!served && !site.projectDone)
        const Text(
          'Нет дороги — подведите её к стройке',
          style: TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
        ),
      const SizedBox(height: 6),
      for (final e in site.projectNeeds.entries) ...[
        magRow(
          cargoName(e.key),
          '${(site.projectProgress[e.key] ?? 0).clamp(0, e.value)} из ${e.value}',
        ),
        LinearProgressIndicator(
          value: ((site.projectProgress[e.key] ?? 0) / e.value).clamp(0, 1),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          color: MagPalette.mint,
          backgroundColor: const Color(0x1F2BB59A),
        ),
      ],
      if (p.needs.length > site.projectNeeds.length)
        const Text(
          'Груз, который в мире никто не делает, не требуется.',
          style: magMuted,
        ),
    ],
  );
});
