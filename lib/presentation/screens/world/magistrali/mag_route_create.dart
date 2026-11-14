import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_filters.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// Places that take what [from] gives: (place, the cargo that matches),
/// connected by road first, then the nearest (S12, 1.84).
List<(MagIndustry, List<MagCargo>)> routeDestinations(
  MagWorld w,
  MagIndustry from,
) {
  final out = <(MagIndustry, List<MagCargo>)>[];
  for (final i in w.map.industries) {
    if (i.id == from.id) continue;
    final match = [
      for (final c in from.supplies)
        if (i.accepts.contains(c)) c,
    ];
    if (match.isNotEmpty) out.add((i, match));
  }
  out.sort((a, b) {
    final ca = w.connected(from, a.$1), cb = w.connected(from, b.$1);
    if (ca != cb) return ca ? -1 : 1;
    return a.$1.distanceTo(from).compareTo(b.$1.distanceTo(from));
  });
  return out;
}

/// Places that give what [to] takes (where to start a line to it).
List<(MagIndustry, List<MagCargo>)> routeSources(MagWorld w, MagIndustry to) {
  final out = <(MagIndustry, List<MagCargo>)>[];
  for (final i in w.map.industries) {
    if (i.id == to.id) continue;
    final match = [
      for (final c in i.supplies)
        if (to.accepts.contains(c)) c,
    ];
    if (match.isNotEmpty) out.add((i, match));
  }
  out.sort((a, b) => a.$1.distanceTo(to).compareTo(b.$1.distanceTo(to)));
  return out;
}

/// What a filter chip of the route list keeps (the same groups as the list
/// of places).
const _kinds = ['Все', 'Поселения', 'Сырьё', 'Переработка', 'Склады и центры'];

/// Building a line: search, groups and suggestions — from a sawmill it
/// offers the places that need its wood, connected ones first.
Future<void> showCreateRouteSheet(MagistraliScreenState state, {int? first}) {
  final stops = <int>[?first];
  var query = '';
  var kind = 0;
  var roadOnly = false;
  return showModalBottomSheet<void>(
    context: state.context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(state.context).size.height * .88,
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final w = state.world;
        final last = stops.isEmpty ? null : w.map.industry(stops.last);
        final q = query.trim().toLowerCase();
        bool keep(MagIndustry i) =>
            (stops.isEmpty || i.id != stops.last) &&
            placeOfKind(i, kind) &&
            (q.isEmpty ||
                i.name.toLowerCase().contains(q) ||
                [
                  ...i.supplies,
                  ...i.accepts,
                ].any((c) => cargoName(c).toLowerCase().contains(q))) &&
            (!roadOnly || last == null || w.connected(last, i));
        final list = [...w.map.industries.where(keep)]
          ..sort((a, b) {
            if (last == null) {
              double d(MagIndustry i) =>
                  (i.centerX - state.camera.x).abs() +
                  (i.centerY - state.camera.y).abs();
              return d(a).compareTo(d(b));
            }
            return a.distanceTo(last).compareTo(b.distanceTo(last));
          });
        final suggest = last == null
            ? const <(MagIndustry, List<MagCargo>)>[]
            : routeDestinations(
                w,
                last,
              ).where((e) => keep(e.$1)).take(6).toList();
        final flows = stops.length >= 2
            ? routeFlows(w, stops)
            : const <String>[];

        Widget tile(MagIndustry i, {List<MagCargo>? match}) => ListTile(
          key: ValueKey(
            match == null ? 'mag-stop-${i.id}' : 'mag-suggest-${i.id}',
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            kindIcon(i.kind),
            color: match == null ? MagPalette.teal : MagPalette.mint,
          ),
          title: Text(
            i.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              if (match != null)
                'возьмёт: ${match.map((c) => cargoName(c).toLowerCase()).join(', ')}'
              else ...[
                if (i.supplies.isNotEmpty)
                  'даёт: ${i.supplies.map(cargoName).join(', ')}',
                if (i.accepts.isNotEmpty)
                  'берёт: ${i.accepts.map(cargoName).join(', ')}',
              ],
              if (last != null) '${i.distanceTo(last)} кл.',
              if (last != null && !w.connected(last, i)) 'нет дороги',
            ].join(' · '),
            style: magMuted,
          ),
          trailing: match == null
              ? null
              : const Icon(Icons.add_circle_outline, color: MagPalette.mint),
          onTap: () => setSheet(() => stops.add(i.id)),
        );

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Новый маршрут', style: magTitle),
                Text(
                  stops.isEmpty
                      ? 'Выберите первую остановку — дальше подскажем, куда везти её груз'
                      : 'Добавьте следующую остановку',
                  style: magMuted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var k = 0; k < stops.length; k++)
                      InputChip(
                        label: Text(
                          '${k + 1}. ${w.map.industry(stops[k])!.name}',
                        ),
                        onDeleted: () => setSheet(() => stops.removeAt(k)),
                      ),
                  ],
                ),
                if (stops.length >= 2) ...[
                  const SizedBox(height: 6),
                  Text(
                    flows.isEmpty
                        ? 'Между этими остановками нечего возить'
                        : 'Повезут: ${flows.join('; ')}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: flows.isEmpty
                          ? const Color(0xFFD64B5C)
                          : MagPalette.teal,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('mag-route-search'),
                  onChanged: (v) => setSheet(() => query = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Поиск: название или груз',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                MagFilterChips(
                  keyPrefix: 'mag-route-kind',
                  labels: _kinds,
                  selected: kind,
                  onSelect: (i) => setSheet(() => kind = i),
                ),
                if (last != null)
                  FilterChip(
                    key: const ValueKey('mag-route-road'),
                    label: const Text('Только связанные дорогой'),
                    selected: roadOnly,
                    onSelected: (v) => setSheet(() => roadOnly = v),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      if (suggest.isNotEmpty) ...[
                        Text(
                          'Предложения: кому нужен груз «${last!.name}»',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        for (final (i, match) in suggest) tile(i, match: match),
                        const Divider(),
                      ] else if (last != null && last.supplies.isEmpty)
                        Text(
                          '«${last.name}» ничего не отдаёт — выберите, откуда везти к ней груз.',
                          style: magMuted,
                        ),
                      for (final i in list) tile(i),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Ничего не найдено', style: magMuted),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('mag-create-route'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MagPalette.mint,
                    ),
                    onPressed: stops.length < 2
                        ? null
                        : () {
                            if (state.report(
                              w.createRoute(stops),
                              'Маршрут создан — назначьте на него машину',
                            )) {
                              Navigator.pop(context);
                              unawaited(showRoutesSheet(state));
                            }
                          },
                    child: Text(
                      stops.length < 2
                          ? 'Нужно минимум 2 остановки'
                          : 'Создать маршрут',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
