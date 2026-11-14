import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S11: passengers (PASS-01…PASS-04) — people wanting to travel,
/// from population and only where something stops, carried by coach, bus,
/// train or vessel and never by a lorry; market prices (BIZ-09, BIZ-11) — a
/// flooded market pays less and recovers, a shortage pays more; tunnels and
/// bridges cost far more than a road on the flat; saves.
void main() {
  void expectBalanced(MagWorld w) {
    final total = w.totalCargo();
    for (final c in MagCargo.values) {
      expect(
        total[c] ?? 0,
        (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
        reason: '$c at tick ${w.tick}',
      );
    }
  }

  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  List<(int, int)> sides(MagWorld w, MagIndustry i) => [
    for (var y = i.top - 1; y <= i.bottom + 1; y++)
      for (var x = i.left - 1; x <= i.right + 1; x++)
        if (w.map.roadable(x, y) &&
            List.generate(
              4,
              (d) => i.covers(x + MagDir.dx[d], y + MagDir.dy[d]),
            ).any((e) => e))
          (x, y),
  ];

  void connect(MagWorld w, MagIndustry a, MagIndustry b) {
    for (final (ax, ay) in sides(w, a)) {
      for (final (bx, by) in sides(w, b)) {
        final plan = w.planRoad(ax, ay, bx, by, MagRoad.dirt);
        if (plan.error == null && w.buildRoad(plan) == null) {
          if (w.connected(a, b)) return;
        }
      }
    }
    fail('cannot join ${a.name} and ${b.name}');
  }

  MagWorld rich() => MagWorld.start()
    ..money = 1000000
    ..xp = MagWorldProgress.xpFor(8)
    ..techs.add('combustion');

  test('people want to travel where something stops, by population', () {
    final w = rich();
    final v = w.settlements.firstWhere((i) => i.name == 'Луговое');
    final other = w.settlements.firstWhere((i) => i != v);
    w.step(MagRules.ticksPerDay * 2);
    expect(v.stock[MagCargo.passengers], isNull); // nothing stops there
    connect(w, v, other);
    w.step(MagRules.ticksPerDay * 10);
    final daily = v.town!.population ~/ MagRules.peoplePerTraveller;
    expect(
      v.stock[MagCargo.passengers],
      daily.clamp(1, 1 << 20) * MagRules.passengerDays,
    );
    expect(v.supplies, contains(MagCargo.passengers));
    expect(other.accepts, contains(MagCargo.passengers));
    // Warehouses never take people; plants neither.
    expect(w.map.startPlant.accepts, isNot(contains(MagCargo.passengers)));
    expectBalanced(w);
  });

  test('a bus takes people between settlements; a lorry never does', () {
    final w = rich();
    final v = w.settlements.firstWhere((i) => i.name == 'Луговое');
    final other = w.settlements
        .where((i) => i != v)
        .reduce((a, b) => a.distanceTo(v) < b.distanceTo(v) ? a : b);
    connect(w, v, other);
    w.createRoute([v.id, other.id]);
    final r = w.routes.values.single;
    expect(w.buyTruck('bus'), isNull);
    final bus = w.vehicles.values.last;
    expect(w.buyTruck('lorry'), isNull);
    final lorry = w.vehicles.values.last;
    expect(w.canCarry(bus, MagCargo.passengers), isTrue);
    expect(w.canCarry(bus, MagCargo.grain), isFalse);
    expect(w.canCarry(lorry, MagCargo.passengers), isFalse);
    w.assign(bus.id, r.id);
    w.assign(lorry.id, r.id);
    for (var k = 0; k < MagRules.ticksPerDay * 20 && bus.trips < 2; k++) {
      w.step();
      expect(lorry.cargo, isNot(MagCargo.passengers));
      if (bus.load > 0) expect(bus.cargo, MagCargo.passengers);
    }
    expect(bus.trips, greaterThanOrEqualTo(1));
    expect(bus.income, greaterThan(0));
    expect(w.delivered[MagCargo.passengers], greaterThan(0));
    // Coaches in era I; trains and vessels take both.
    final coach = MagRules.truck('coach')!;
    expect((coach.horse, coach.passengers), (true, true));
    final steam = MagVehicle(id: 999, model: 'steam', name: 't');
    expect(w.canCarry(steam, MagCargo.passengers), isTrue);
    expect(w.canCarry(steam, MagCargo.grain), isTrue);
    expectBalanced(w);
  });

  test('a flooded market pays less and recovers; a shortage pays more', () {
    final w = rich();
    final v = w.settlements.firstWhere((i) => i.name == 'Луговое');
    final t = v.town!;
    // A shortage of food (needed, none in the pantry): +25%.
    expect(w.deficitBonusOf(v, MagCargo.food), MagRules.deficitBonus);
    t.pantry[MagCargo.food] = 10;
    w.created[MagCargo.food] = (w.created[MagCargo.food] ?? 0) + 10;
    expect(w.deficitBonusOf(v, MagCargo.food), 0);
    // Flood it with planks: the price falls, never below 70%.
    expect(w.glutFactor(v, MagCargo.planks), 1);
    t.glut[MagCargo.planks] = 30;
    final mid = w.glutFactor(v, MagCargo.planks);
    expect(mid, lessThan(1));
    t.glut[MagCargo.planks] = 10000;
    expect(
      w.glutFactor(v, MagCargo.planks),
      closeTo(1 - MagRules.glutDiscount, 1e-9),
    );
    // It is kept in the save and fades day by day.
    final b = reload(w);
    expect(b.map.industry(v.id)!.town!.glut[MagCargo.planks], 10000);
    t.glut[MagCargo.planks] = 60;
    final before = w.glutFactor(v, MagCargo.planks);
    w.step(MagRules.ticksPerDay * 12);
    expect(w.glutFactor(v, MagCargo.planks), greaterThan(before));
    // A real delivery floods the market.
    expect(w.marketFactor(v, MagCargo.planks), greaterThan(0));
    expectBalanced(w);
  });

  test('tunnels and bridges cost far more than a road on the flat', () {
    final w = rich();
    int find(MagTerrain t) {
      for (var c = 0; c < w.size * w.size; c++) {
        if (w.map.at(w.cx(c), w.cy(c)) == t &&
            w.map.industryAt(w.cx(c), w.cy(c)) == null) {
          return c;
        }
      }
      fail('no $t');
    }

    final grass = w.cellCost(find(MagTerrain.grass), MagRoad.dirt);
    expect(w.cellCost(find(MagTerrain.hill), MagRoad.dirt), grass * 7);
    expect(w.cellCost(find(MagTerrain.river), MagRoad.dirt), grass * 9);
    expect(w.railCellCost(find(MagTerrain.hill)), MagRules.railCost * 7);
  });
}
