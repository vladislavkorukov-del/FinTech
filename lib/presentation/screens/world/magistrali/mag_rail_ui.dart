import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../../../domain/magistrali/magistrali.dart';
import '../../../l10n_widgets.dart';
import 'mag_art.dart';
import 'mag_hud.dart';
import 'mag_screen.dart';
import 'mag_sheets.dart';
import 'mag_town.dart';

/// The train part of a vehicle's sheet: its wagons (couple or uncouple),
/// what the train is for, and a hint when it keeps giving way.
List<Widget> trainPanel(MagistraliScreenState state, MagVehicle v) {
  final w = state.world;
  final m = v.spec;
  return [
    const SizedBox(height: 6),
    Row(
      children: [
        Expanded(
          child: Text(
            'Вагоны: ${v.wagons} из ${m.maxWagons} · по ${m.wagonCapacity} ед.',
            key: const ValueKey('mag-wagons'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('mag-wagons-minus'),
          onPressed: v.wagons <= 1
              ? null
              : () => state.report(
                  w.setWagons(v.id, v.wagons - 1),
                  'Вагон отцеплен (+${magMoney((m.wagonPrice * .5).round())} кр)',
                ),
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        IconButton(
          key: const ValueKey('mag-wagons-plus'),
          onPressed: v.wagons >= m.maxWagons || w.money < m.wagonPrice
              ? null
              : () => state.report(
                  w.setWagons(v.id, v.wagons + 1),
                  'Вагон прицеплен',
                ),
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    ),
    Text(
      'Вагон ${magMoney(m.wagonPrice)} кр. Каждый вагон добавляет груза, но '
      'немного замедляет поезд. Поезд ходит по маршрутам между станциями; в '
      'автопарк его не взять.',
      style: magMuted,
    ),
    if (v.yields >= 2)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Уступал путь встречным уже ${v.yields} раз: проложите второй путь '
          'или второй перрон, чтобы поезда разъезжались.',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFFD64B5C)),
        ),
      ),
  ];
}

/// A tapped station: the place it serves, trains calling at it, removal.
Future<void> showStationSheet(MagistraliScreenState state, int cell) =>
    magSheet(state, 'mag-station-$cell', (context) {
      final w = state.world;
      final placeId = w.stations[cell];
      final place = placeId == null ? null : w.map.industry(placeId);
      if (place == null) return const Text('Станции здесь больше нет');
      final trains = w.vehicles.values.where((v) {
        final r = w.routes[v.routeId];
        return v.spec.rail && r != null && r.stops.contains(place.id);
      }).toList();
      return Column(
        key: const ValueKey('mag-station-sheet'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.train_rounded, color: MagPalette.teal),
              const SizedBox(width: 8),
              Expanded(child: Text('Станция «${place.name}»', style: magTitle)),
            ],
          ),
          Text(
            'Поезда, стоящие здесь, грузятся у «${place.name}» и разгружаются '
            'в него — так же, как машины у его ворот. Перронов: '
            '${w.stationCells(place).length}.',
            style: magMuted,
          ),
          const SizedBox(height: 8),
          magRow('Поездов на маршрутах через станцию', '${trains.length}'),
          for (final t in trains) magRow(t.name, t.spec.name),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('mag-station-place'),
                  onPressed: () {
                    Navigator.pop(context);
                    state.centerOn(place.centerX, place.centerY);
                    state.overlay.industry = place.id;
                    unawaited(
                      place.town != null
                          ? showTownSheet(state, place.id)
                          : showIndustrySheet(state, place.id),
                    );
                  },
                  child: Text(place.town != null ? 'Поселение' : 'Предприятие'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('mag-station-remove'),
                onPressed: () {
                  if (state.report(w.removeStation(cell), 'Станция снесена')) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Снести'),
              ),
            ],
          ),
        ],
      );
    });
