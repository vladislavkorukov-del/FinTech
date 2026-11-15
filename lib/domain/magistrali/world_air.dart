part of 'world.dart';

/// Stage S22: aviation. An airport is a strip on land within 3 cells of a
/// place (like a port on water); aircraft fly the straight line between
/// airports, over rivers, hills and towns.
extension MagWorldAir on MagWorld {
  bool get aviationUnlocked => techs.contains('aviation');

  /// Places an airport on [cell] would serve (within 3 cells).
  List<MagIndustry> airportTargets(int cell) {
    final x = cx(cell), y = cy(cell);
    return [
      for (final i in map.industries)
        if (i.kind != MagIndustryKind.megaproject &&
            math.max(
                  math.max(0, math.max(i.left - x, x - i.right)),
                  math.max(0, math.max(i.top - y, y - i.bottom)),
                ) <=
                3)
          i,
    ];
  }

  String? airportBlocker(int cell, int placeId) {
    if (!aviationUnlocked) return 'Аэропорты открывает технология «Авиация»';
    if (cell < 0 || cell >= size * size) return 'За краем карты';
    final x = cx(cell), y = cy(cell);
    if (!regionOpen(x, y)) return 'Регион ещё не открыт';
    final t = map.at(x, y);
    if (t == MagTerrain.river || t == MagTerrain.lake || t == MagTerrain.hill) {
      return 'Аэропорт ставится на ровную землю';
    }
    if (map.industryAt(x, y) != null) return 'Здесь стоит предприятие';
    if (roads[cell] != 0 || rails[cell] != 0) return 'Здесь дорога или путь';
    if (airports.containsKey(cell) ||
        ports.containsKey(cell) ||
        stations.containsKey(cell)) {
      return 'Клетка уже занята';
    }
    if (!airportTargets(cell).any((i) => i.id == placeId)) {
      return 'Аэропорт должен быть в 3 клетках от места';
    }
    return null;
  }

  String? buildAirport(int cell, int placeId) {
    final why = airportBlocker(cell, placeId);
    if (why != null) return why;
    if (money < MagRules.airportPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.airportPrice}';
    }
    _spend(
      MagRules.airportPrice,
      'airports',
      source: 'industry',
      sourceId: placeId,
    );
    airports[cell] = placeId;
    roadVersion++;
    _say('Аэропорт у «${map.industry(placeId)?.name}» построен');
    return null;
  }

  String? removeAirport(int cell) {
    if (!airports.containsKey(cell)) return 'Здесь нет аэропорта';
    if (vehicles.values.any((v) => v.spec.air && v.onMap && v.cell == cell)) {
      return 'На полосе самолёт';
    }
    airports.remove(cell);
    roadVersion++;
    return null;
  }

  List<int> airportCells(MagIndustry i) => [
    for (final e in airports.entries)
      if (e.value == i.id) e.key,
  ]..sort();

  /// The straight line from the first of [from] to an airport of [to]:
  /// every cell on the way (diagonal steps allowed).
  List<int>? airPath(List<int> from, MagIndustry to) {
    final goals = airportCells(to);
    if (from.isEmpty || goals.isEmpty) return null;
    final start = from.first, goal = goals.first;
    if (start == goal) return [start];
    var x = cx(start), y = cy(start);
    final gx = cx(goal), gy = cy(goal);
    final path = <int>[start];
    while (x != gx || y != gy) {
      x += (gx - x).sign;
      y += (gy - y).sign;
      path.add(cellOf(x, y));
    }
    return path;
  }

  /// Why an aircraft cannot fly [routeId] (null: it can).
  String? airRouteBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return null;
    for (final id in r.stops) {
      final i = map.industry(id);
      if (i == null || airportCells(i).isEmpty) {
        return 'У «${i?.name ?? '—'}» нет аэропорта';
      }
    }
    return null;
  }

  Map<String, Object> _saveAir() => {
    if (airports.isNotEmpty)
      'airports': [
        for (final e
            in (airports.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          [e.key, e.value],
      ],
  };

  void loadAir(Map<String, dynamic> j) {
    for (final raw in j['airports'] as List? ?? const []) {
      final l = raw as List;
      final cell = l[0] as int, place = l[1] as int;
      if (cell < 0 || cell >= size * size || map.industry(place) == null) {
        throw const FormatException('Broken airport in Magistrali save');
      }
      airports[cell] = place;
    }
  }
}
