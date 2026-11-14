import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S18 (1.90): transfers (PASS-06), trams (PASS-08), the look of
/// vehicles (VEH-13), by-products (PROD-20), auctions (BIZ-13),
/// historical contracts (META-07), regions (MAP-08); saves.
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

  test('a hub: passengers brought there partly ride on', () {
    final w = motorStart()..money = 1000000;
    final [a, b, c] = w.settlements.take(3).toList();
    w.createRoute([a.id, b.id]);
    expect(w.isHub(b), isFalse);
    w.createRoute([b.id, c.id]);
    expect(w.isHub(b), isTrue);
    final before = b.stock[MagCargo.passengers] ?? 0;
    // 20 passengers brought to the hub: 6 stay to ride on; none at a
    // settlement only one line serves.
    expect(w.transferAt(b, 20), 6);
    expect(b.stock[MagCargo.passengers], before + 6);
    expect(w.transferAt(a, 20), 0);
  });

  test('trams: people only, between settlements only', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(12)
      ..techs.addAll([
        'combustion',
        'metallurgy',
        'kilns',
        'machinery',
        'petroleum',
      ]);
    expect(w.buyTruck('tram'), contains('Электротранспорт'));
    w.techs.addAll(['electronics', 'electrotransport']);
    expect(w.buyTruck('tram'), isNull);
    final tram = w.vehicles.values.last;
    expect(w.canCarry(tram, MagCargo.passengers), isTrue);
    expect(w.canCarry(tram, MagCargo.grain), isFalse);
    expect(tram.spec.comfort, 1.25);
    w.createRoute([w.map.startFarm.id, w.map.startPlant.id]);
    expect(w.assign(tram.id, w.routes.keys.last), contains('поселениями'));
    final [a, b] = w.settlements.take(2).toList();
    w.createRoute([a.id, b.id]);
    expect(w.assign(tram.id, w.routes.keys.last), isNull);
  });

  test('paint and upgrade stripes; saved', () {
    final w = motorStart()..money = 100000;
    final v = w.vehicles.values.single;
    expect(w.visualTier(v), 0);
    expect(w.paintVehicle(v.id, 0xFFD64B5C), isNull);
    expect(v.paint, 0xFFD64B5C);
    expect(w.money, 100000 - MagRules.paintPrice);
    for (final u in MagUpgrade.values) {
      v.upgrades[u.index] = 4;
    }
    expect(w.visualTier(v), 2);
    expect(reload(w).vehicles[v.id]!.paint, 0xFFD64B5C);
    expect(w.paintVehicle(v.id, null), isNull);
    expect(v.paint, isNull);
  });

  test('by-products: steel mills give stone too', () {
    final w = MagWorld.start();
    final mill = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.steelMill,
    );
    expect(mill.supplies, contains(MagCargo.stone));
    mill.input[MagCargo.ore] = 40;
    mill.input[MagCargo.coal] = 20;
    w.created[MagCargo.ore] = (w.created[MagCargo.ore] ?? 0) + 40;
    w.created[MagCargo.coal] = (w.created[MagCargo.coal] ?? 0) + 20;
    w.step(MagRules.ticksPerDay);
    final steel = mill.stock[MagCargo.steel]!;
    expect(mill.stock[MagCargo.stone], (steel * .25).floor());
    expectBalanced(w);
  });

  test('auctions: a lot, a daily rise, bought or gone; saved', () {
    final w = motorStart()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(6);
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    for (var k = 0; k < 12 && w.auction == null; k++) {
      w.step(MagRules.ticksPerDay);
    }
    final a = w.auction!;
    final lot = w.map.industry(a.industry)!;
    expect(a.price, lessThan(w.buyPrice(lot)));
    final start = a.price;
    w.step(MagRules.ticksPerDay);
    expect(w.auction!.price, greaterThan(start));
    expect(reload(w).auction!.industry, lot.id);
    expect(w.buyAuction(), isNull);
    expect(lot.owned, isTrue);
    expect(w.auction, isNull);
  });

  test('historical contracts open once by level', () {
    final w = motorStart()..xp = MagWorldProgress.xpFor(8);
    w.step(MagRules.ticksPerDay);
    final hist = w.deals.where((d) => d.story != null).toList();
    expect(hist.map((d) => d.story), contains('Хлеб для губернской ярмарки'));
    expect(w.historicOffered, containsAll(['fair', 'school']));
    w.step(MagRules.ticksPerDay * 2);
    expect(w.deals.where((d) => d.story != null).length, hist.length);
    final b = reload(w);
    expect(b.historicOffered, w.historicOffered);
    expect(b.deals.where((d) => d.story != null).length, hist.length);
    expect(w.dealTitle(hist.first), startsWith('Исторический контракт'));
  });

  test('regions: a new company builds only where it is open', () {
    final w = MagWorld.start(MagRules.defaultSeed, MagScenario.classic, true)
      ..money = 1000000;
    final f = w.map.startFarm;
    final home = w.regionOf(f.x, f.y);
    expect(w.openRegions, {home});
    // A far corner is closed: no road, no building there.
    final far = home == 0 ? (w.size - 3, w.size - 3) : (2, 2);
    expect(w.regionOpen(far.$1, far.$2), isFalse);
    expect(
      w.planRoad(f.x + f.size, f.y, far.$1, far.$2, MagRoad.dirt).error,
      isNotNull,
    );
    expect(
      w.buildBlocker(MagIndustryKind.farm, far.$1, far.$2),
      contains('Регион'),
    );
    final price = w.regionPrice;
    expect(w.openRegion(w.regionOf(far.$1, far.$2)), isNull);
    expect(w.money, 1000000 - price);
    expect(w.regionOpen(far.$1, far.$2), isTrue);
    expect(w.regionPrice, greaterThan(price));
    expect(reload(w).openRegions, w.openRegions);
    // Older companies have every region open.
    expect(MagWorld.start().regionsLocked, isFalse);
  });
}
