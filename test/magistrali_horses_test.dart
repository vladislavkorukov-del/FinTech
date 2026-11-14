import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master plan stage 2: horses and carts. A new company starts in era I
/// with a cart; carts carry real cargo on real roads and pay their way;
/// hooves care little for asphalt; horse and motor technologies are
/// separate; the combustion engine opens trucks; early contracts are
/// small and near; old companies keep their trucks.
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

  MagRoadPlan startRoad(MagWorld w, [MagRoad type = MagRoad.dirt]) {
    final f = w.map.startFarm, p = w.map.startPlant;
    return w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, type);
  }

  /// Ticks for the first delivery on the start line with [type] roads.
  int firstDelivery(MagWorld w, MagRoad type) {
    expect(w.buildRoad(startRoad(w, type)), isNull);
    w.createRoute([w.map.startFarm.id, w.map.startPlant.id]);
    w.assign(w.vehicles.values.first.id, w.routes.keys.first);
    for (var t = 0; t < 8000; t++) {
      w.step();
      if (w.deliveries > 0) return t;
    }
    fail('no delivery');
  }

  test('a new company starts with a cart; trucks wait for the engine', () {
    final w = MagWorld.start();
    final v = w.vehicles.values.single;
    expect(v.model, 'cart');
    expect(v.spec.horse, isTrue);
    expect(v.name, 'Телега №1');
    expect(w.motorUnlocked, isFalse);
    w.money = 100000;
    expect(w.buyTruck('pickup'), contains('Двигатель внутреннего сгорания'));
    expect(w.buyTruck('wagon'), contains('уровне'));
    expect(w.buyTruck('cart'), isNull);
    expect(w.vehicles.values.last.name, 'Телега №2');
    w.xp = MagWorldProgress.xpFor(2);
    expect(w.buyTruck('wagon'), isNull);
    expect(w.vehicles.values.last.name, 'Фургон №1');
  });

  test('a cart carries real cargo by road and pays its way', () {
    final w = MagWorld.start();
    final cart = w.vehicles.values.first;
    firstDelivery(w, MagRoad.dirt);
    expect(w.delivered[MagCargo.grain], w.capacityOf(cart));
    // A month of work: deliveries pay more than feed and upkeep.
    for (var t = 0; t < MagRules.ticksPerDay * MagRules.daysPerMonth; t++) {
      w.step();
      if (cart.onMap) expect(w.roads[cart.cell], isNot(0));
    }
    final m = w.months.last.index == 0
        ? w.month
        : w.months[w.months.length - 2];
    final income = m.income['delivery'] ?? 0;
    final costs = (m.expense['upkeep'] ?? 0) + (m.expense['running'] ?? 0);
    expect(income, greaterThan(costs * 3));
    expectBalanced(w);
  });

  test('hooves care little for asphalt; engines love it', () {
    final dirtCart = firstDelivery(MagWorld.start(), MagRoad.dirt);
    final asphaltWorld = MagWorld.start()..xp = MagWorldProgress.xpFor(2);
    asphaltWorld.money = 100000;
    final asphaltCart = firstDelivery(asphaltWorld, MagRoad.asphalt);
    // At most ~5% faster on asphalt.
    expect(asphaltCart, greaterThanOrEqualTo((dirtCart * .9).floor()));
    expect(asphaltCart, lessThanOrEqualTo(dirtCart));
    // A pickup gains a lot more.
    MagWorld motor() {
      final w = MagWorld.start()
        ..techs.add('combustion')
        ..money = 100000
        ..xp = MagWorldProgress.xpFor(2);
      w.vehicles.clear();
      w.buyTruck('pickup');
      return w;
    }

    final dirtPickup = firstDelivery(motor(), MagRoad.dirt);
    final asphaltPickup = firstDelivery(motor(), MagRoad.asphalt);
    expect(asphaltPickup, lessThan((dirtPickup * .85).round()));
  });

  test('horse and motor technologies are separate', () {
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(30)
      ..deliveries = 100;
    final cart = w.vehicles.values.single;
    final cartSpeed = w.speedOf(cart), cartLoad = w.capacityOf(cart);
    expect(w.research('stud'), isNull);
    expect(w.speedOf(cart), closeTo(cartSpeed * 1.12, 1e-9));
    expect(w.research('springs'), isNull);
    expect(w.capacityOf(cart), greaterThan(cartLoad));
    expect(w.research('combustion'), isNull);
    expect(w.motorUnlocked, isTrue);
    expect(w.buyTruck('pickup'), isNull);
    final pickup = w.vehicles.values.last;
    final pickupSpeed = w.speedOf(pickup), cartNow = w.speedOf(cart);
    expect(w.research('turbo'), isNull);
    expect(w.speedOf(pickup), greaterThan(pickupSpeed));
    expect(w.speedOf(cart), cartNow); // a turbo does nothing for a horse
  });

  test('the engine needs the stud, level 4 and 30 deliveries', () {
    final w = MagWorld.start()..money = 100000;
    final engine = MagTechTree.byId('combustion')!;
    expect(w.techBlocker(engine), contains('уровень'));
    w.xp = MagWorldProgress.xpFor(4);
    expect(w.techBlocker(engine), contains('Конный завод'));
    w.research('stud');
    expect(w.techBlocker(engine), contains('доставок'));
    w.deliveries = 30;
    expect(w.techBlocker(engine), isNull);
  });

  test('a young company gets small contracts near its start', () {
    final w = MagWorld.start();
    final f = w.map.startFarm;
    final near =
        (w.map.industries
                .where((i) => i.accepts.isNotEmpty && !i.spec.stores)
                .toList()
              ..sort((a, b) => a.distanceTo(f).compareTo(b.distanceTo(f))))
            .take(6)
            .map((i) => i.id)
            .toSet();
    for (var k = 0; k < 10; k++) {
      final c = w.contracts.first;
      expect(near, contains(c.to));
      expect(c.amount, lessThanOrEqualTo(12 + 18 + w.level * 2));
      w.money += 150;
      w.replaceContract(c.id);
    }
  });

  test('cart upgrades work; saves keep carts; old companies keep trucks', () {
    final w = MagWorld.start()..money = 50000;
    final cart = w.vehicles.values.single;
    final load = w.capacityOf(cart);
    expect(w.upgrade(cart.id, MagUpgrade.body), isNull);
    expect(w.capacityOf(cart), greaterThan(load));
    firstDelivery(w, MagRoad.dirt);
    w.step(321);
    final saved = jsonEncode(w.toJson());
    final b = magWorldFromJson(jsonDecode(saved) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), saved);
    expect(b.vehicles.values.single.model, 'cart');
    for (final f in ['v1', 'v2', 'v3']) {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/magistrali_save_$f.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final old = magWorldFromJson(raw);
      expect(old.motorUnlocked, isTrue, reason: f);
      expect(old.vehicles.values.every((v) => !v.spec.horse), isTrue);
      old.money = 100000;
      expect(old.buyTruck('pickup'), isNull);
    }
  });
}
