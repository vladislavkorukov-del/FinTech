part of 'world.dart';

/// A mountain range (MAP-07): a large connected stretch of hills.
class MagMountain {
  MagMountain(this.id, this.name, this.cells, this.x, this.y);
  final int id, cells;
  final String name;

  /// Its middle, for the name on the map.
  final double x, y;
}

/// Stage S20: the journal of simulation errors (CORE-10), the check of
/// production chains (MAP-04), mountain ranges (MAP-07), the map editor
/// (MAP-11), and the finish of partial mechanics: demand by population
/// (CITY-07), transport access (CITY-10), regional specialisation
/// (BIZ-12), multimodal terminals (SEA-06), automatic export (LOG-13),
/// unit cost (FIN-06), regional statistics (FIN-10), jams (ROAD-09).
extension MagWorldFinish on MagWorld {
  // ---- CORE-10 ----

  void _logError(String text) {
    simErrors.add((tick, text));
    if (simErrors.length > 50) simErrors.removeAt(0);
  }

  /// Runs one vehicle's step; an error stops only that vehicle, is written
  /// to the journal, and the game goes on.
  void _safely(MagVehicle v, void Function() run) {
    try {
      run();
    } on Object catch (e) {
      _logError('${v.name}: ${e.runtimeType} — машина остановлена');
      v
        ..path = const []
        ..pathIndex = 0
        ..progress = 0
        ..state = v.onMap ? MagVehicleState.idle : MagVehicleState.garage;
    }
  }

  /// Once a day: the cargo ledger must add up; if not, it is put right
  /// and written down (so a save always loads).
  void _checkLedger() {
    final total = totalCargo();
    for (final c in MagCargo.values) {
      final have = total[c] ?? 0;
      final want = (created[c] ?? 0) - (destroyed[c] ?? 0);
      if (have == want) continue;
      _logError(
        'Учёт груза «${magCargoWord(c)}» сбился на ${have - want} — исправлено',
      );
      created[c] = have + (destroyed[c] ?? 0);
    }
  }

  // ---- MAP-04 ----

  /// For every kind of plant and each of its inputs: the shortest distance
  /// from such a plant to a place that supplies the input (null: none on
  /// the map).
  List<(MagIndustryKind, MagCargo, int?)> chainReport() {
    final out = <(MagIndustryKind, MagCargo, int?)>[];
    final plants = <MagIndustryKind, List<MagIndustry>>{};
    for (final i in map.industries) {
      if (i.town != null || i.spec.stores || i.spec.converts.isEmpty) continue;
      if (i.kind == MagIndustryKind.megaproject) continue;
      (plants[i.kind] ??= []).add(i);
    }
    for (final e in plants.entries) {
      final spec = e.value.first.spec;
      for (final c in {...spec.converts.keys, ...spec.extra.keys}) {
        num? best;
        for (final p in e.value) {
          for (final s in map.industries) {
            if (s == p || s.town != null || s.spec.stores) continue;
            if (!s.supplies.contains(c)) continue;
            final d = p.distanceTo(s);
            if (best == null || d < best) best = d;
          }
        }
        out.add((e.key, c, best?.round()));
      }
    }
    return out;
  }

  /// Every chain can be built: each input has a supplier within reach.
  bool get mapViable =>
      chainReport().every((r) => r.$3 != null && r.$3! <= MagRules.chainReach);

  // ---- MAP-07 ----

  static const _rangeNames = [
    'Каменный хребет',
    'Синие горы',
    'Медвежий кряж',
    'Орлиные скалы',
    'Седой хребет',
    'Гранитный кряж',
    'Волчьи горы',
    'Туманный хребет',
  ];

  List<MagMountain> get mountains {
    _mountainsFor();
    return _mountains!;
  }

  void _mountainsFor() {
    if (_mountains != null && _mountainKey == map.terrainVersion) return;
    _mountainKey = map.terrainVersion;
    final comp = magComponents(
      size,
      size,
      (c) => map.at(c % size, c ~/ size) == MagTerrain.hill,
    );
    final count = <int, int>{}, sx = <int, int>{}, sy = <int, int>{};
    for (var c = 0; c < comp.length; c++) {
      final k = comp[c];
      if (k < 0) continue;
      count[k] = (count[k] ?? 0) + 1;
      sx[k] = (sx[k] ?? 0) + c % size;
      sy[k] = (sy[k] ?? 0) + c ~/ size;
    }
    final list = <MagMountain>[];
    for (final k in (count.keys.toList()..sort())) {
      final n = count[k]!;
      if (n < MagRules.mountainCells) continue;
      list.add(
        MagMountain(
          k,
          _rangeNames[list.length % _rangeNames.length],
          n,
          sx[k]! / n + .5,
          sy[k]! / n + .5,
        ),
      );
    }
    _mountainComp = comp;
    _mountains = list;
  }

  /// The range a place stands at (by a hill cell next to it).
  MagMountain? mountainOf(MagIndustry i) {
    _mountainsFor();
    final comp = _mountainComp!;
    for (var y = i.top - 1; y <= i.bottom + 1; y++) {
      for (var x = i.left - 1; x <= i.right + 1; x++) {
        if (!map.inside(x, y)) continue;
        final k = comp[cellOf(x, y)];
        if (k < 0) continue;
        for (final m in _mountains!) {
          if (m.id == k) return m;
        }
      }
    }
    return null;
  }

  /// Mines, quarries and pits in the mountains dig more.
  double mountainFactor(MagIndustry i) =>
      _miners.contains(i.kind) && mountainOf(i) != null
      ? MagRules.mountainYield
      : 1;

  static const _miners = {
    MagIndustryKind.mine,
    MagIndustryKind.quarry,
    MagIndustryKind.coalMine,
    MagIndustryKind.clayPit,
  };

  // ---- MAP-11 ----

  /// The map editor works in the sandbox.
  bool get editorOpen => scenario == MagScenario.sandbox;

  String? editTerrain(int x, int y, MagTerrain t) {
    if (!editorOpen) return 'Редактор карты открыт в песочнице';
    if (!map.inside(x, y) || x == 0 || y == 0) return 'За краем карты';
    if (map.industryAt(x, y) != null) return 'Здесь стоит предприятие';
    final c = cellOf(x, y);
    final water = t == MagTerrain.river || t == MagTerrain.lake;
    if (water && (roads[c] != 0 || rails[c] != 0)) {
      return 'Сначала снесите дорогу';
    }
    if (stations.containsKey(c) || ports.containsKey(c)) {
      return 'Здесь станция или порт';
    }
    if (map.at(x, y) == t) return null;
    map.setTerrain(x, y, t);
    terrainEdits[c] = t.index;
    roadVersion++;
    return null;
  }

  // ---- CITY-07 / CITY-10 ----

  /// More people want more: needs grow with the population over its
  /// level's figure, up to half as much again.
  double populationFactor(MagSettlement t) =>
      (t.population / math.max(1, t.spec.population)).clamp(1.0, 1.5);

  /// Ways to reach a settlement: road, rail, water.
  int accessModes(MagIndustry i) =>
      (accessCells(i).isNotEmpty ? 1 : 0) +
      (stationCells(i).isNotEmpty ? 1 : 0) +
      (portCells(i).isNotEmpty ? 1 : 0);

  /// People come faster to a settlement reached more ways (+25% each).
  double accessFactor(MagIndustry i) =>
      1 + .25 * math.max(0, accessModes(i) - 1);

  // ---- BIZ-12 ----

  /// What a region mostly makes: the kind of raw producer it has most of.
  String? regionSpecialization(int region) {
    final count = <String, int>{};
    for (final i in map.industries) {
      if (i.spec.produces.isEmpty || i.town != null) continue;
      if (regionOf(i.x, i.y) != region) continue;
      final k = _sector(i.kind);
      count[k] = (count[k] ?? 0) + 1;
    }
    if (count.isEmpty) return null;
    final best = count.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return best.first.key;
  }

  static String _sector(MagIndustryKind k) => switch (k) {
    MagIndustryKind.farm => 'аграрный',
    MagIndustryKind.sawmill => 'лесной',
    MagIndustryKind.oilWell => 'нефтяной',
    _ => 'горный',
  };

  /// The company's own producers of the region's speciality make +10%.
  double regionFactor(MagIndustry i) =>
      i.owned &&
          i.spec.produces.isNotEmpty &&
          regionSpecialization(regionOf(i.x, i.y)) == _sector(i.kind)
      ? MagRules.regionYield
      : 1;

  // ---- SEA-06 ----

  /// A warehouse with both a station and a pier: a multimodal terminal,
  /// half as much room again.
  bool isMultimodal(MagIndustry w) =>
      w.spec.stores && stationCells(w).isNotEmpty && portCells(w).isNotEmpty;

  // ---- LOG-13 ----

  String? setAutoExport(int id, bool on) {
    final i = map.industry(id);
    if (i == null || !i.owned || i.supplies.isEmpty) {
      return 'Только для своих предприятий';
    }
    if (on) {
      autoExport.add(id);
    } else {
      autoExport.remove(id);
    }
    return null;
  }

  /// Own plants with export on sell what lies above 80% of their store at
  /// half the market price.
  void _dayExport() {
    for (final id in autoExport.toList()) {
      final i = map.industry(id);
      if (i == null || !i.owned) {
        autoExport.remove(id);
        continue;
      }
      final keep = (outputCapOf(i) * .8).floor();
      for (final c in i.supplies) {
        final n = (i.stock[c] ?? 0) - keep - orders.reservedOut(i.id, c);
        if (n <= 0) continue;
        i.stock[c] = i.stock[c]! - n;
        destroyed[c] = (destroyed[c] ?? 0) + n;
        final pay = (n * (MagRules.cargoValue[c] ?? 1) * .5).round();
        if (pay <= 0) continue;
        i.revenue += pay;
        _earn(pay, 'export', source: 'industry', sourceId: i.id);
      }
    }
  }

  // ---- FIN-06 / FIN-10 ----

  /// What one unit made by an own place cost (credits; null: nothing made).
  double? unitCost(MagIndustry i) =>
      i.produced == 0 ? null : i.costs / i.produced;

  /// Per region: places, own places, the company's revenue from them.
  List<(int, int, int, int)> regionStats() => [
    for (var r = 0; r < 9; r++)
      (
        r,
        map.industries.where((i) => regionOf(i.x, i.y) == r).length,
        map.industries.where((i) => i.owned && regionOf(i.x, i.y) == r).length,
        map.industries
            .where((i) => regionOf(i.x, i.y) == r)
            .fold(0, (a, i) => a + i.revenue + (i.town?.revenue ?? 0)),
      ),
  ];

  // ---- TECH-05 ----

  /// The company's era: horses, rail, motors, modern logistics (dispatch
  /// and fast roads), the future (driverless and maglev).
  String get eraName {
    if (techs.contains('autopilot') || techs.contains('maglev')) {
      return 'Эпоха V — транспорт будущего';
    }
    if (techs.contains('dispatch') &&
        level >= MagRules.roads[MagRoad.highway]!.level) {
      return 'Эпоха IV — современная логистика';
    }
    if (motorUnlocked) return 'Эпоха III — моторы';
    if (railsUnlocked) return 'Эпоха II — железная дорога';
    return 'Эпоха I — гужевой транспорт';
  }

  // ---- ROAD-09 ----

  /// Road cells jammed today (over twice their capacity).
  List<int> get jams => [
    for (final c in traffic.keys)
      if (loadOf(c) > 2) c,
  ]..sort();

  // ---- Saves ----

  Map<String, Object> _saveFinish() => {
    if (simErrors.isNotEmpty)
      'simErrors': [
        for (final (t, s) in simErrors) [t, s],
      ],
    if (terrainEdits.isNotEmpty)
      'terrainEdits': {
        for (final e
            in (terrainEdits.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          '${e.key}': e.value,
      },
    if (autoExport.isNotEmpty) 'autoExport': autoExport.toList()..sort(),
    if (!dayNight) 'dayNight': false,
  };

  void loadFinish(Map<String, dynamic> j) {
    for (final e in j['simErrors'] as List? ?? const []) {
      final l = e as List;
      simErrors.add((l[0] as int, l[1] as String));
    }
    for (final e in (j['terrainEdits'] as Map? ?? const {}).entries) {
      final c = int.parse('${e.key}');
      final t = e.value as int;
      if (c < 0 || c >= size * size || t < 0 || t >= MagTerrain.values.length) {
        continue;
      }
      terrainEdits[c] = t;
      map.setTerrain(cx(c), cy(c), MagTerrain.values[t]);
    }
    dayNight = j['dayNight'] as bool? ?? true;
    autoExport.addAll([
      for (final x in j['autoExport'] as List? ?? const []) x as int,
    ]);
  }
}
