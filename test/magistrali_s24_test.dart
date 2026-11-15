import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S24 (1.96): the credit rating, bonds, insurance, cruise liners;
/// saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test('the rating follows debt; in a living world it sets loan terms', () {
    final w = motorStart()..money = 50000;
    final calm = w.rating;
    expect(MagWorldCredit.ratings, contains(calm));
    expect(w.ratingInterest, 1); // a test world: usual terms
    w.debt = w.companyValue * 2;
    expect(
      MagWorldCredit.ratings.indexOf(w.rating),
      greaterThan(MagWorldCredit.ratings.indexOf(calm)),
    );
    w.livingWorld = true;
    expect(w.ratingInterest, greaterThan(1));
    w.debt = 0;
    expect(w.ratingInterest, lessThanOrEqualTo(1));
    expect(w.loanLimit, greaterThan(0));
  });

  test('bonds: money now, coupons monthly, the sum back at the end', () {
    final w = motorStart()..money = 2000000;
    final money = w.money;
    expect(w.issueBond(25000), isNull);
    expect(w.money, money + 25000);
    expect(w.bondsOwed, 25000);
    expect(reload(w).bonds.single.amount, 25000);
    final rate = w.bonds.single.rate;
    w.step(MagRules.ticksPerDay * MagRules.daysPerMonth);
    expect(
      w.months.any((m) => (m.expense['coupons'] ?? 0) > 0) ||
          (w.month.expense['coupons'] ?? 0) > 0,
      isTrue,
    );
    expect(rate, greaterThan(0));
    w.step(MagRules.ticksPerDay * MagRules.bondDays);
    expect(w.bonds, isEmpty);
    expect(w.issueBond(w.companyValue * 10), contains('Рынок'));
  });

  test('insurance: a premium; disasters mended in a day and paid for', () {
    final w = motorStart()..money = 500000;
    expect(w.setInsured(true), isNull);
    expect(w.insured, isTrue);
    expect(reload(w).insured, isTrue);
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    w.buildRoad(plan);
    final c = plan.cells[2];
    w.damaged[c] = w.tick + 6 * MagRules.ticksPerDay;
    expect(w.repairPrice(c), 0);
    expect(w.setInsured(false), isNull);
    expect(w.repairPrice(c), greaterThan(0));
  });

  test('a cruise liner: people only, the most comfort, needs tourism', () {
    final m = MagRules.truck('liner')!;
    expect(m.water, isTrue);
    expect(m.passengers, isTrue);
    expect(m.comfort, 1.6);
    final w = MagWorld.start()
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(14);
    w.techs.addAll(['stud', 'shipping']);
    expect(w.buyTruck('liner'), contains('Туризм'));
    w.techs.add('tourism');
    expect(w.buyTruck('liner'), isNull);
    final v = w.vehicles.values.last;
    expect(w.canCarry(v, MagCargo.passengers), isTrue);
    expect(w.canCarry(v, MagCargo.oil), isFalse);
    expect(w.canCarry(v, MagCargo.grain), isFalse);
  });

  test('insured, the weather’s damage is paid and mended in a day', () {
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
    expect(w.setInsured(true), isNull);
    var paid = 0;
    for (var d = 0; d < 150 && paid == 0; d++) {
      w.step(MagRules.ticksPerDay);
      paid =
          w.months.fold(0, (s, m) => s + (m.income['insurance_payout'] ?? 0)) +
          (w.month.income['insurance_payout'] ?? 0);
    }
    expect(paid, greaterThan(0));
    for (final until in w.damaged.values) {
      expect(until - w.tick, lessThanOrEqualTo(MagRules.ticksPerDay));
    }
  });
}
