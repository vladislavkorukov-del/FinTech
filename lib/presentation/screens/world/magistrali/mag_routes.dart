import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_fleet.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';

/// What moves between consecutive stops of a line (for the preview).
List<String> routeFlows(MagWorld w, List<int> stops) {
  final out = <String>[];
  for (var k = 0; k < stops.length; k++) {
    final a = w.map.industry(stops[k])!;
    final others = [
      for (final id in stops)
        if (id != a.id) w.map.industry(id)!,
    ];
    for (final c in a.supplies) {
      final to = others.where((o) => o.spec.accepts.contains(c)).toList();
      if (to.isNotEmpty) {
        out.add(
          '${cargoName(c)}: ${a.name.split(' «').first} → ${to.first.name.split(' «').first}',
        );
      }
    }
  }
  return out;
}

Future<void> showRoutesSheet(
  MagistraliScreenState state,
) => magSheet(state, 'mag-routes', (context) {
  final w = state.world;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Маршруты', style: magTitle)),
          FilledButton.icon(
            key: const ValueKey('mag-new-route'),
            style: FilledButton.styleFrom(backgroundColor: MagPalette.mint),
            onPressed: () {
              Navigator.pop(context);
              unawaited(showCreateRouteSheet(state));
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новый'),
          ),
        ],
      ),
      if (w.routes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Маршрут — это остановки, между которыми ездят ваши машины. Создайте первый: ферма → пищевой завод.',
            style: magMuted,
          ),
        ),
      for (final r in w.routes.values) _routeCard(state, r, context),
    ],
  );
});

Widget _routeCard(
  MagistraliScreenState state,
  MagRoute r,
  BuildContext context,
) {
  final w = state.world;
  final trucks = w.vehicles.values.where((v) => v.routeId == r.id).toList();
  final garage = w.vehicles.values.where((v) => v.routeId == null).toList();
  final linked = [
    for (var k = 0; k < r.stops.length; k++)
      w.connected(
        w.map.industry(r.stops[k])!,
        w.map.industry(r.stops[(k + 1) % r.stops.length])!,
      ),
  ];
  final flows = routeFlows(w, r.stops);
  return Container(
    key: ValueKey('mag-route-${r.id}'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: magCard(16),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (var k = 0; k < r.stops.length; k++)
            Row(
              children: [
                Icon(
                  linked[k]
                      ? Icons.radio_button_checked_rounded
                      : Icons.link_off_rounded,
                  size: 16,
                  color: linked[k] ? MagPalette.mint : const Color(0xFFE0566B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    w.map.industry(r.stops[k])!.name,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (!linked[k])
                  const Text(
                    'нет дороги дальше',
                    style: TextStyle(fontSize: 11, color: Color(0xFFE0566B)),
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            flows.isEmpty
                ? 'Грузы: нечего возить между этими остановками'
                : 'Грузы: ${flows.join('; ')}',
            style: magMuted,
          ),
          magRow(
            'Доход маршрута',
            '${magMoney(r.income)} кр',
            color: MagPalette.teal,
          ),
          magRow('Доставок', '${r.deliveries}'),
          for (final v in trucks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.local_shipping_rounded,
                color: Color(v.spec.color),
              ),
              title: Text(v.name),
              subtitle: Text(
                [
                  stateName(w, v),
                  if (v.load > 0) '${cargoName(v.cargo!)} ${v.load}',
                ].join(' · '),
                style: magMuted,
              ),
              onTap: () {
                Navigator.pop(context);
                unawaited(showVehicleSheet(state, v.id));
              },
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: ValueKey('mag-route-add-truck-${r.id}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MagPalette.mint,
                  ),
                  onPressed: garage.isEmpty
                      ? () => state.say(
                          'Свободных машин нет — купите в «Транспорте»',
                        )
                      : () => state.report(
                          w.assign(garage.first.id, r.id),
                          '${garage.first.name} вышел на маршрут',
                        ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    garage.isEmpty ? 'Нет свободных машин' : 'Назначить машину',
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('mag-route-delete-${r.id}'),
                tooltip: 'Удалить маршрут',
                onPressed: () {
                  w.deleteRoute(r.id);
                  state.changed();
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Building a line: tap places in order; the preview says what will move.
Future<void> showCreateRouteSheet(MagistraliScreenState state, {int? first}) {
  final stops = <int>[?first];
  return showModalBottomSheet<void>(
    context: state.context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7FAF8),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(state.context).size.height * .85,
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final w = state.world;
        final last = stops.isEmpty ? null : w.map.industry(stops.last);
        final list = [...w.map.industries]
          ..sort((a, b) {
            if (last == null) {
              return (a.centerX - state.camera.x).abs() +
                          (a.centerY - state.camera.y).abs() <
                      (b.centerX - state.camera.x).abs() +
                          (b.centerY - state.camera.y).abs()
                  ? -1
                  : 1;
            }
            return a.distanceTo(last).compareTo(b.distanceTo(last));
          });
        final flows = stops.length >= 2
            ? routeFlows(w, stops)
            : const <String>[];
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Новый маршрут', style: magTitle),
                Text(
                  stops.isEmpty
                      ? 'Выберите первую остановку'
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
                Expanded(
                  child: ListView(
                    children: [
                      for (final i in list)
                        if (stops.isEmpty || i.id != stops.last)
                          ListTile(
                            key: ValueKey('mag-stop-${i.id}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              kindIcon(i.kind),
                              color: MagPalette.teal,
                            ),
                            title: Text(
                              i.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (i.supplies.isNotEmpty)
                                  'даёт: ${i.supplies.map(cargoName).join(', ')}',
                                if (i.spec.accepts.isNotEmpty)
                                  'берёт: ${i.spec.accepts.map(cargoName).join(', ')}',
                                if (last != null) '${i.distanceTo(last)} кл.',
                                if (last != null && !w.connected(last, i))
                                  'нет дороги',
                              ].join(' · '),
                              style: magMuted,
                            ),
                            onTap: () => setSheet(() => stops.add(i.id)),
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
