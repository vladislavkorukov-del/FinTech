import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S20 (1.92): big orders split on assignment, quick refusal of
/// impossible roads and remembered ways, simple growth, the error journal
/// (CORE-10), the chain check (MAP-04), mountain ranges (MAP-07), the map
/// editor (MAP-11), demand by population (CITY-07), transport access
/// (CITY-10), export (LOG-13), multimodal terminals (SEA-06), regions
/// (BIZ-12, FIN-10), eras (TECH-05), jams (ROAD-09); saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  void give(MagWorld w, Map<MagCargo, int> into, MagCargo c, int n) {
    into[c] = (into[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  test('a road path: refused at once when cut off, remembered when found', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(w.connected(f, p), isFalse);
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    final a = w.roadPath(w.accessCells(f), p);
    expect(a, isNotNull);
    // The same leg again: the same way (a copy, safe to change).
    final b = w.roadPath(w.accessCells(f), p)!;
    expect(b, a);
    b.clear();
    expect(w.roadPath(w.accessCells(f), p), a);
    // A cut road: no way at once.
    w.roads[plan.cells[plan.cells.length ~/ 2]] = 0;
    w.roadVersion++;
    expect(w.connected(f, p), isFalse);
  });

  test('growth: bring what it asks for and the settlement grows', () {
    final w = MagWorld.start();
    final hamlet = w.settlements.firstWhere((t) => t.town!.level == 1);
    final t = hamlet.town!;
    expect(w.growthProgress(hamlet), 0);
    final asks = w.developmentAsks(hamlet);
    final first = asks.entries.first;
    give(w, t.devStock, first.key, first.value);
    final part = w.growthProgress(hamlet);
    expect(part, greaterThan(0));
    expect(part, lessThan(1));
    for (final e in asks.entries.skip(1)) {
      give(w, t.devStock, e.key, e.value);
    }
    expect(w.growthProgress(hamlet), 1);
    w.step(MagRules.ticksPerDay);
    expect(t.level, 2);
    expect(t.population, greaterThanOrEqualTo(MagTowns.of(2).population));
  });

  test('the error journal puts a broken ledger right and is saved', () {
    final w = motorStart();
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 7;
    w.step(MagRules.ticksPerDay);
    expect(w.simErrors, isNotEmpty);
    expect(w.simErrors.last.$2, contains('исправлено'));
    final total = w.totalCargo();
    expect(
      total[MagCargo.grain] ?? 0,
      (w.created[MagCargo.grain] ?? 0) - (w.destroyed[MagCargo.grain] ?? 0),
    );
    final back = reload(w);
    expect(back.simErrors.length, w.simErrors.length);
  });

  test('every chain can be built on new maps', () {
    for (final seed in [MagRules.defaultSeed, 11, 222, 3333, 44444]) {
      final w = MagWorld.start(seed);
      final report = w.chainReport();
      expect(report, isNotEmpty);
      expect(w.mapViable, isTrue, reason: 'seed $seed: $report');
    }
  });

  test('mountain ranges: named, and mines there dig more', () {
    final w = MagWorld.start();
    expect(w.mountains, isNotEmpty);
    expect(
      w.mountains.first.cells,
      greaterThanOrEqualTo(MagRules.mountainCells),
    );
    final miner = w.map.industries.where(
      (i) => i.kind == MagIndustryKind.quarry && w.mountainOf(i) != null,
    );
    if (miner.isNotEmpty) {
      expect(w.mountainFactor(miner.first), MagRules.mountainYield);
    }
    expect(w.mountainFactor(w.map.startFarm), 1);
  });

  test('the map editor: sandbox only, saved, never under roads', () {
    final w = MagWorld.start();
    final f = w.map.startFarm;
    final x = f.x - 3, y = f.y - 3;
    expect(w.editTerrain(x, y, MagTerrain.lake), contains('песочнице'));
    final s = MagWorld.start(MagRules.defaultSeed, MagScenario.sandbox);
    final v = s.map.terrainVersion;
    expect(s.editTerrain(x, y, MagTerrain.hill), isNull);
    expect(s.map.at(x, y), MagTerrain.hill);
    expect(s.map.terrainVersion, greaterThan(v));
    expect(s.editTerrain(f.x, f.y, MagTerrain.lake), contains('предприятие'));
    final plan = s.planRoad(
      f.x + f.size,
      f.y,
      f.x + f.size + 4,
      f.y,
      MagRoad.dirt,
    );
    expect(s.buildRoad(plan), isNull);
    final c = plan.cells[2];
    expect(
      s.editTerrain(s.cx(c), s.cy(c), MagTerrain.lake),
      contains('дорогу'),
    );
    final back = reload(s);
    expect(back.map.at(x, y), MagTerrain.hill);
    expect(back.terrainEdits, s.terrainEdits);
  });

  test('needs grow with people; more ways in bring people faster', () {
    final w = motorStart();
    final v = w.settlements.first;
    final t = v.town!;
    final base = Map.of(w.needsOf(v));
    t.population = t.spec.population * 3;
    for (final e in w.needsOf(v).entries) {
      expect(e.value, (base[e.key]! * 1.5).round());
    }
    expect(w.accessFactor(v), 1);
  });

  test('export of surplus, unit cost, regions, era, jams', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm;
    expect(w.setAutoExport(f.id, true), isNotNull); // not the company's
    expect(w.buyIndustry(f.id), isNull);
    expect(w.setAutoExport(f.id, true), isNull);
    final c = f.supplies.first;
    give(w, f.stock, c, w.outputCapOf(f));
    final money = w.money;
    w.step(MagRules.ticksPerDay);
    expect(f.stock[c]!, lessThanOrEqualTo((w.outputCapOf(f) * .8).floor()));
    expect(w.month.income['export'] ?? 0, greaterThan(0));
    expect(w.money, isNot(money));
    expect(reload(w).autoExport, {f.id});
    w.step(MagRules.ticksPerDay); // room again: it makes goods
    expect(w.unitCost(f), isNotNull);
    final stats = w.regionStats();
    expect(stats.length, 9);
    expect(stats.fold(0, (a, r) => a + r.$2), w.map.industries.length);
    expect(w.regionSpecialization(w.regionOf(f.x, f.y)), isNotNull);
    expect(w.eraName, contains('III'));
    expect(w.jams, isEmpty);
    expect(w.simErrors, isEmpty);
  });
}
