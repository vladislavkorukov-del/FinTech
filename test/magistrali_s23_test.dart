import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S23 (1.95): disasters and repairs, shares and the exchange,
/// resorts and tourists; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test('a broken road closes the way until it is mended', () {
    final w = motorStart()..money = 1000000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    expect(w.connected(f, p), isTrue);
    final c = plan.cells[plan.cells.length ~/ 2];
    w.damaged[c] = w.tick + 3 * MagRules.ticksPerDay;
    w.roadVersion++;
    expect(w.roadOpen(c), isFalse);
    expect(w.connected(f, p), isFalse);
    expect(reload(w).damaged, w.damaged);
    final money = w.money;
    expect(w.repairRoad(c), isNull);
    expect(w.money, money - w.repairPrice(c));
    expect(w.connected(f, p), isTrue);
    // Mended by the crew in time.
    w.damaged[c] = w.tick + MagRules.ticksPerDay;
    w.roadVersion++;
    w.step(MagRules.ticksPerDay * 2);
    expect(w.damaged, isEmpty);
    expect(w.connected(f, p), isTrue);
  });

  test('storms and floods break roads in a living world', () {
    final w = MagWorld.start(MagRules.defaultSeed, MagScenario.classic, true)
      ..money = 10000000
      ..xp = MagWorldProgress.xpFor(8)
      ..regionsLocked = false;
    final inds = w.map.industries.toList();
    for (final a in inds.take(20)) {
      final b = inds[(inds.indexOf(a) + 1) % inds.length];
      final p = w.planRoad(a.x + a.size, a.y, b.x - 1, b.y, MagRoad.dirt);
      if (p.error == null) w.buildRoad(p);
    }
    var broke = 0;
    for (var d = 0; d < 120; d++) {
      final before = w.damaged.length;
      w.step(MagRules.ticksPerDay);
      if (w.damaged.length > before) broke++;
    }
    expect(broke, greaterThan(0));
    expect(w.simErrors, isEmpty);
    expect(MagWorld.start().livingWorld, isFalse); // test worlds stay calm
  });

  test('shares: issue, buy back, keep control, pay dividends', () {
    final w = motorStart()..money = 500000;
    final price = w.sharePrice;
    expect(price, greaterThan(0));
    final money = w.money;
    expect(w.issueShares(), isNull);
    expect(w.ownShares, 900);
    expect(w.money, greaterThan(money));
    for (var k = 0; k < 3; k++) {
      w.issueShares();
    }
    expect(w.ownShares, 600);
    expect(w.issueShares(), contains('контроль'));
    expect(w.buybackShares(), isNull);
    expect(w.ownShares, 700);
    expect(reload(w).ownShares, 700);
    w.step(MagRules.ticksPerDay * 2);
    expect(w.priceHistory, isNotEmpty);
  });

  test('rival stakes: past half the rival is the company’s', () {
    final w = motorStart()..money = 100000000;
    w.xp = MagWorldProgress.xpFor(MagRules.rivalLevel);
    w.step(MagRules.ticksPerDay * MagRules.rivalEvery * 2);
    expect(w.rivals, isNotEmpty);
    final name = w.rivals.first.name;
    for (var k = 0; k < 5; k++) {
      expect(w.buyRivalShares(0), isNull);
    }
    expect(w.rivals.first.name, name);
    expect(w.stakeIn(w.rivals.first), 500);
    expect(reload(w).rivalStakes[name], 500);
    expect(w.buyRivalShares(0), isNull);
    expect(w.rivals.any((r) => r.name == name), isFalse);
  });

  test('resorts: tourists pay more, most in their season', () {
    final w = motorStart()..livingWorld = true;
    final spec = MagRules.industries[MagIndustryKind.lakeResort]!;
    expect(spec.accepts, contains(MagCargo.passengers));
    expect(spec.produces[MagCargo.passengers], greaterThan(0));
    final lake = MagIndustry(
      id: -5,
      kind: MagIndustryKind.lakeResort,
      x: 1,
      y: 1,
      name: '',
    );
    final ski = MagIndustry(
      id: -6,
      kind: MagIndustryKind.skiResort,
      x: 1,
      y: 1,
      name: '',
    );
    w.tick = 30 * MagRules.ticksPerDay; // summer
    expect(
      w.tourismFactor(lake, MagCargo.passengers),
      MagRules.touristPay * MagRules.touristPeak,
    );
    expect(w.tourismFactor(ski, MagCargo.passengers), MagRules.touristPay);
    expect(w.tourismFactor(lake, MagCargo.grain), 1);
    w.tick = 90 * MagRules.ticksPerDay; // winter
    expect(
      w.tourismFactor(ski, MagCargo.passengers),
      MagRules.touristPay * MagRules.touristPeak,
    );
  });
}
