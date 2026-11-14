import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage P1 (1.83): the big map split by a big river (generator 5),
/// modern trucks opened by technologies (VEH-04), recipes opened by
/// technologies (TECH-10), part of the price back on demolition (ROAD-05).
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test('new games: a map three times bigger, split by a big river', () {
    for (final seed in [MagRules.defaultSeed, 3, 77, 2026]) {
      final m = MagMap.generate(seed, version: 5);
      expect(m.size, MagRules.bigMapSize);
      expect(m.size * m.size, greaterThanOrEqualTo(3 * 64 * 64));
      // Every row has a stretch of river at least three cells wide, east
      // of the start; the start line itself needs no bridge.
      for (var y = 0; y < m.size; y++) {
        var run = 0, best = 0;
        for (var x = m.size ~/ 2 + 10; x < m.size; x++) {
          run = m.at(x, y) == MagTerrain.river ? run + 1 : 0;
          if (run > best) best = run;
        }
        expect(best, greaterThanOrEqualTo(3), reason: 'seed $seed row $y');
      }
      final f = m.startFarm, p = m.startPlant;
      for (var x = f.x; x <= p.x + p.size; x++) {
        expect(m.at(x, f.y), isNot(MagTerrain.river), reason: 'seed $seed');
      }
      // Settlements and businesses on both banks.
      final split = m.size * .7;
      expect(m.industries.where((i) => i.x > split + 6), isNotEmpty);
      expect(m.industries.length, greaterThan(100));
    }
    // A save keeps the big map; older maps stay 64 cells.
    final w = MagWorld.start();
    expect(w.map.version, 5);
    expect(reload(w).map.size, MagRules.bigMapSize);
    expect(MagMap.generate(MagRules.defaultSeed, version: 4).size, 64);
  });

  test('modern trucks open with technologies', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(14)
      ..techs.add('combustion');
    expect(w.buyTruck('semi'), contains('Сцепка-полуприцеп'));
    expect(w.buyTruck('electric'), contains('Гибридная тяга'));
    w.techs.addAll(['trailer', 'hybrid']);
    expect(w.buyTruck('semi'), isNull);
    expect(w.buyTruck('electric'), isNull);
    final semi = MagRules.truck('semi')!, volt = MagRules.truck('electric')!;
    final tractor = MagRules.truck('tractor')!;
    expect(semi.capacity, greaterThan(tractor.capacity));
    expect(volt.runningCost, lessThan(tractor.runningCost));
    expect(semi.motorGoods && volt.motorGoods, isTrue);
  });

  test('recipes open with technologies; old companies keep theirs', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(10);
    final c = w.map.startPlant;
    expect(
      w.buildBlocker(MagIndustryKind.mill, c.x + 5, c.y + 5),
      contains('Мукомольное дело'),
    );
    expect(
      w.techBlocker(MagTechTree.byId('machinery')!),
      contains('Металлургия'),
    );
    expect(w.research('milling'), isNull);
    var built = false;
    for (var r = 3; r < 20 && !built; r++) {
      for (var d = -r; d <= r && !built; d++) {
        if (w.buildBlocker(MagIndustryKind.mill, c.x + d, c.y + r) == null) {
          built =
              w.buildIndustry(MagIndustryKind.mill, c.x + d, c.y + r) == null;
        }
      }
    }
    expect(built, isTrue);
    // Kept in the save; a save from before 1.83 gets what its level allowed.
    expect(reload(w).techs, contains('milling'));
    final old = w.toJson()..remove('recipes');
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(old)) as Map<String, dynamic>,
    );
    expect(
      b.techs,
      containsAll(['milling', 'carpentry', 'kilns', 'metallurgy', 'machinery']),
    );
  });

  test('demolition returns 30% of the price; bridges return more', () {
    final w = MagWorld.start()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    final cells = plan.cells.take(3).toList();
    final value = cells.fold(0, (s, c) => s + w.roadValue(c));
    expect(w.demolishRefund(cells), (value * .3).round());
    final before = w.money;
    expect(w.removeRoad(cells), isNull);
    expect(w.money, before + (value * .3).round());
    final e = w.journal.entries.last;
    expect((e.category, e.kind), ('demolition', MagEntryKind.assetSale));
    // A bridge cost nine plain cells, and so is its refund.
    int find(MagTerrain t) {
      for (var c = 0; c < w.size * w.size; c++) {
        if (w.map.at(w.cx(c), w.cy(c)) == t &&
            w.map.industryAt(w.cx(c), w.cy(c)) == null) {
          return c;
        }
      }
      fail('no $t');
    }

    final river = find(MagTerrain.river), grass = find(MagTerrain.grass);
    w.roads[river] = MagRoad.dirt.index;
    w.roads[grass] = MagRoad.dirt.index;
    expect(w.demolishRefund([river]), w.demolishRefund([grass]) * 9);
    // Track too.
    w.rails[grass] = 1;
    expect(w.railValue(grass), MagRules.railCost);
    final m = w.money;
    expect(w.removeRail([grass]), isNull);
    expect(w.money, m + (MagRules.railCost * .3).round());
  });
}
