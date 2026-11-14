import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S12 (1.83): one entrance to a business, the big map's balance
/// (start money, contract reach), the tutorial setting; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test('a business has one entrance: the first road; it can be moved', () {
    final w = MagWorld.start()..money = 100000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final first = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(first), isNull);
    final e = w.entranceOf(p)!;
    expect(w.accessCells(p), [e]);
    expect(e, first.cells.lastWhere((c) => w.edgeRoadsContains(p, c)));
    // A second road to another side of the plant is not a way in.
    final below = (p.x + 1, p.y + p.size);
    final other = w.planRoad(
      below.$1,
      below.$2,
      below.$1,
      below.$2 + 4,
      MagRoad.dirt,
    );
    expect(w.buildRoad(other), isNull);
    final side = w.cellOf(below.$1, below.$2);
    expect(w.edgeRoads(p), contains(side));
    expect(w.accessCells(p), [e]);
    // The player moves it there; it survives a save.
    expect(w.setEntrance(p.id, side), isNull);
    expect(w.accessCells(p), [side]);
    expect(reload(w).accessCells(reload(w).map.industry(p.id)!), [side]);
    expect(w.setEntrance(p.id, w.cellOf(p.x + 9, p.y + 9)), isNotNull);
    // Its road gone, the next road on its edge takes over.
    w.removeRoad([side]);
    expect(w.accessCells(p), isNotEmpty);
    // Settlements keep every road on their edge.
    final v = w.settlements.first;
    expect(w.entranceOf(v) == null || v.town != null, isTrue);
  });

  test('saves from before 1.83: the entrance on the biggest network', () {
    final w = MagWorld.start()..money = 100000;
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(
      w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt)),
      isNull,
    );
    final main = w.entranceOf(p)!;
    // A lone stub on another side.
    final lone = w.cellOf(p.x + 1, p.y + p.size);
    w.roads[lone] = MagRoad.dirt.index;
    final old = w.toJson()..remove('entrances');
    final b = magWorldFromJson(
      jsonDecode(jsonEncode(old)) as Map<String, dynamic>,
    );
    expect(b.accessCells(b.map.industry(p.id)!), [main]);
    expect(b.connected(b.map.industry(f.id)!, b.map.industry(p.id)!), isTrue);
  });

  test('the big map: more money to start, contracts within reach', () {
    final w = MagWorld.start();
    expect(w.money, MagRules.startMoneyBig);
    w
      ..xp = MagWorldProgress.xpFor(10)
      ..money = 100000;
    final f = w.map.startFarm;
    for (var k = 0; k < 20; k++) {
      w.replaceContract(w.regularContracts.first.id);
      for (final c in w.regularContracts) {
        final to = w.map.industry(c.to)!;
        final reach = MagRules.contractReach + w.level * 2;
        expect(to.distanceTo(f), lessThanOrEqualTo(reach), reason: to.name);
      }
    }
  });

  test('the tutorial can be turned off and stays off', () {
    final w = MagWorld.start();
    expect(w.tutorial, isTrue);
    w.tutorial = false;
    expect(reload(w).tutorial, isFalse);
    final old = w.toJson();
    (old['settings'] as Map).remove('tutorial');
    expect(
      magWorldFromJson(
        jsonDecode(jsonEncode(old)) as Map<String, dynamic>,
      ).tutorial,
      isTrue,
    );
  });
}
