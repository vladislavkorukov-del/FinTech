import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_route_create.dart';
import 'mag_routes.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_stop_orders.dart';

/// A line being made by taps on the map (S19): the stops in order and
/// what to do at each.
class MagRouteDraft {
  final stops = <int>[];
  final orders = <StopOrder>[];

  void clear() {
    stops.clear();
    orders.clear();
  }
}

/// The main way to make a line (S19): the map stays open, taps on places
/// add them in order (a tap on the last one takes it back), the next good
/// stops are pointed at by arrows, a bar below shows the plan.
void startRouteOnMap(MagistraliScreenState state, {int? first}) {
  state.routeDraft.clear();
  if (first != null) {
    state.routeDraft.stops.add(first);
    state.routeDraft.orders.add(const StopOrder());
  }
  state.setTool(MagTool.route);
  state.say('Коснитесь объектов на карте по порядку');
}

/// A tap in route mode.
void routeTap(MagistraliScreenState state, int cell) {
  final w = state.world;
  final place = w.map.industryAt(w.cx(cell), w.cy(cell));
  if (place == null) {
    state.say('Коснитесь предприятия, поселения или склада');
    return;
  }
  final d = state.routeDraft;
  if (d.stops.isNotEmpty && d.stops.last == place.id) {
    d.stops.removeLast();
    d.orders.removeLast();
  } else {
    d.stops.add(place.id);
    d.orders.add(const StopOrder());
  }
  state.changed();
}

/// Where the next stop could be: places that take the last stop's cargo.
List<int> routeSuggestions(MagWorld w, MagRouteDraft d) {
  if (d.stops.isEmpty) return const [];
  final last = w.map.industry(d.stops.last);
  if (last == null) return const [];
  return [for (final (i, _) in routeDestinations(w, last).take(5)) i.id];
}

/// The bar of route mode: the stops (a tap — what to do there), the plan
/// step by step, and making the line.
final _compact = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 8),
);

class MagRouteBar extends StatelessWidget {
  const MagRouteBar({super.key, required this.state});
  final MagistraliScreenState state;

  @override
  Widget build(BuildContext context) {
    final w = state.world, d = state.routeDraft;
    final steps = d.stops.length >= 2
        ? routeSteps(w, d.stops, d.orders)
        : const <String>[];
    return Container(
      key: const ValueKey('mag-route-bar'),
      decoration: magCard(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            d.stops.isEmpty
                ? 'Новый маршрут: коснитесь первого объекта на карте'
                : 'Коснитесь следующего — стрелки покажут, кому нужен груз',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (state.message != null)
            Text(
              state.message!,
              style: const TextStyle(fontSize: 12, color: MagPalette.teal),
            ),
          if (d.stops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var k = 0; k < d.stops.length; k++)
                    InputChip(
                      key: ValueKey('mag-draft-stop-$k'),
                      label: Text(
                        '${k + 1}. ${w.map.industry(d.stops[k])!.name.split(' «').first}',
                      ),
                      avatar: Icon(
                        d.orders[k].auto
                            ? Icons.tune_rounded
                            : Icons.rule_rounded,
                        size: 16,
                      ),
                      onPressed: () async {
                        final o = await pickStopOrder(
                          context,
                          w.map.industry(d.stops[k])!,
                          d.orders[k],
                        );
                        if (o != null) {
                          d.orders[k] = o;
                          state.changed();
                        }
                      },
                      onDeleted: () {
                        d.stops.removeAt(k);
                        d.orders.removeAt(k);
                        state.changed();
                      },
                    ),
                ],
              ),
            ),
          for (final s in steps)
            Text(
              s,
              style: const TextStyle(fontSize: 12, color: MagPalette.teal),
            ),
          Row(
            children: [
              IconButton(
                key: const ValueKey('mag-route-map-cancel'),
                tooltip: 'Отмена',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  d.clear();
                  state.setTool(MagTool.view);
                },
                icon: const Icon(Icons.close_rounded),
              ),
              TextButton(
                style: _compact,
                key: const ValueKey('mag-route-map-list'),
                onPressed: () {
                  final first = d.stops.isEmpty ? null : d.stops.first;
                  d.clear();
                  state.setTool(MagTool.view);
                  unawaited(showCreateRouteSheet(state, first: first));
                },
                child: const Text('Списком'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('mag-route-map-create'),
                style: FilledButton.styleFrom(
                  backgroundColor: MagPalette.mint,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: d.stops.length < 2
                    ? null
                    : () {
                        final why = w.createRoute(List.of(d.stops));
                        if (why == null) {
                          final r = w.routes.values.last;
                          for (var k = 0; k < d.orders.length; k++) {
                            final o = d.orders[k];
                            if (o.auto) continue;
                            w.setStopOrder(
                              r.id,
                              k,
                              pick: o.pick,
                              noPick: o.noPick,
                              noDrop: o.noDrop,
                              ifCargo: o.ifCargo,
                            );
                          }
                          d.clear();
                          state.setTool(MagTool.view);
                          state.say(
                            'Маршрут создан — назначьте на него машину',
                          );
                          unawaited(showRoutesSheet(state));
                        } else {
                          state.say(why);
                        }
                      },
                child: const Text('Создать'),
              ),
            ],
          ),
          const Text(
            'Повторное касание последнего объекта убирает его; касание остановки в списке — что забирать.',
            style: magMuted,
          ),
        ],
      ),
    );
  }
}
